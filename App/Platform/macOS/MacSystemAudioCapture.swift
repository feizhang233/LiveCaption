#if os(macOS)
import AVFoundation
import CaptionCore
import CoreGraphics
import ScreenCaptureKit

/// Captures other applications through Apple's ScreenCaptureKit. No loopback driver.
/// A fresh sink owns each session; conversion and delivery run on its serial queue.
@MainActor
protocol SystemAudioCapturing: AnyObject {
    func start(onError: @escaping @Sendable (String) -> Void) async throws -> AsyncStream<CapturedAudioChunk>
    func stop() async
}

@MainActor
final class MacSystemAudioCapture: SystemAudioCapturing {
    enum CaptureError: LocalizedError {
        case alreadyRunning, noDisplay, permission(String), start(String)
        var errorDescription: String? {
            switch self {
            case .alreadyRunning: "系統音訊擷取已在執行。"
            case .noDisplay: "找不到可擷取的顯示器。請接上顯示器後重試。"
            case .permission(let detail): "請在系統設定 → 隱私權與安全性 → 螢幕與系統音訊錄製中允許 Live Caption，然後重新開啟 App。\n\(detail)"
            case .start(let detail): "無法開始系統音訊擷取：\(detail)"
            }
        }
    }

    private var stream: SCStream?
    private var sink: AudioSink?
    private var starting = false
    private var generation: UInt64 = 0

    func start(
        onError: @escaping @Sendable (String) -> Void
    ) async throws -> AsyncStream<CapturedAudioChunk> {
        guard stream == nil, !starting else { throw CaptureError.alreadyRunning }
        starting = true
        generation &+= 1
        let expectedGeneration = generation
        defer { starting = false }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                throw CaptureError.permission(error.localizedDescription)
            }
            throw CaptureError.start(error.localizedDescription)
        }
        try Task.checkCancellation()
        guard expectedGeneration == generation else { throw CancellationError() }
        guard let display = content.displays.first else { throw CaptureError.noDisplay }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        // ScreenCaptureKit's filter is display based, but no video output is retained.
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 3
        configuration.showsCursor = false

        let ingress = CapturedAudioIngress { [weak self] in
            Task { @MainActor in
                guard let self, self.generation == expectedGeneration else { return }
                await self.stop()
            }
        }
        let sink = AudioSink(ingress: ingress, onError: onError)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: sink)
        try stream.addStreamOutput(sink, type: .audio, sampleHandlerQueue: sink.queue)
        // Drain tiny video frames to avoid ScreenCaptureKit's missing-output warning.
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        self.sink = sink
        self.stream = stream
        do {
            try await stream.startCapture()
            try Task.checkCancellation()
            guard expectedGeneration == generation else { throw CancellationError() }
            return ingress.stream
        } catch {
            await sink.deactivate()
            try? await stream.stopCapture()
            if expectedGeneration == generation {
                self.stream = nil
                self.sink = nil
            }
            throw error
        }
    }

    func stop() async {
        generation &+= 1
        let oldStream = stream
        let oldSink = sink
        stream = nil
        sink = nil
        await oldSink?.deactivate()
        try? await oldStream?.stopCapture()
    }
}

private final class AudioSink: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "app.livecaption.system-audio", qos: .userInitiated)
    private let ingress: CapturedAudioIngress
    private let onError: @Sendable (String) -> Void
    // All mutable state below is confined to queue.
    private var active = true
    private let normalizer = SystemAudioNormalizer()
    private var reportedConversionError = false

    init(ingress: CapturedAudioIngress, onError: @escaping @Sendable (String) -> Void) {
        self.ingress = ingress
        self.onError = onError
    }

    func deactivate() async {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                active = false
                normalizer.reset()
                ingress.finish()
                continuation.resume()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        let message = error.localizedDescription
        queue.async { [self] in
            guard active else { return }
            active = false
            onError("系統音訊已中斷：\(message)。請確認錄製權限及播放來源後重試。")
            ingress.finish()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard active, type == .audio, sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        autoreleasepool {
            do {
                if let result = try normalizer.convert(sampleBuffer) {
                    if !ingress.yield(samples: result.samples, at: result.start) {
                        active = false
                        normalizer.reset()
                    }
                }
            }
            catch {
                guard !reportedConversionError else { return }
                reportedConversionError = true
                onError("無法轉換系統音訊：\(error.localizedDescription)")
            }
        }
    }

}

/// Samples and their original session-relative time survive queue shedding.
/// The cumulative drop counter is read at consumption time, so the last queued
/// chunk also reports drops that occurred after that chunk was constructed.
struct CapturedAudioChunk: Sendable {
    let samples: [Float]
    let start: Double
    fileprivate let dropCounter: CaptureDropCounter
    var droppedAudioSeconds: Double { dropCounter.seconds }
}

fileprivate final class CaptureDropCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: Int64 = 0
    var seconds: Double { lock.lock(); defer { lock.unlock() }; return Double(frames) / 16_000 }
    func recordYield(_ body: () -> AsyncStream<CapturedAudioChunk>.Continuation.YieldResult) -> Bool {
        // Serialize accounting with readers: a consumer cannot observe a just-
        // yielded chunk before the corresponding overflow has been counted.
        lock.lock()
        defer { lock.unlock() }
        switch body() {
        case .enqueued: return true
        case .dropped(let dropped): frames += Int64(dropped.samples.count); return true
        case .terminated: return false
        @unknown default: return false
        }
    }
}

/// At most eight audio chunks can wait for the single async consumer. No task is
/// created per audio callback; slower consumers receive recent audio with gaps.
final class CapturedAudioIngress: @unchecked Sendable {
    let stream: AsyncStream<CapturedAudioChunk>
    private let continuation: AsyncStream<CapturedAudioChunk>.Continuation
    private let dropCounter = CaptureDropCounter()

    init(onTermination: @escaping @Sendable () -> Void = {}) {
        let pair = AsyncStream<CapturedAudioChunk>.makeStream(bufferingPolicy: .bufferingNewest(8))
        stream = pair.stream
        continuation = pair.continuation
        continuation.onTermination = { _ in onTermination() }
    }

    /// False means the consumer terminated; the caller must release audio state.
    @discardableResult
    func yield(samples: [Float], at start: Double) -> Bool {
        dropCounter.recordYield {
            continuation.yield(CapturedAudioChunk(samples: samples, start: start, dropCounter: dropCounter))
        }
    }

    func finish() { continuation.finish() }
    deinit { continuation.finish() }
}

/// Testable adapter between ScreenCaptureKit sample buffers and the shared PCM
/// normalizer. This type does not access screen content or trigger permissions.
final class SystemAudioNormalizer {
    struct Block { let samples: [Float]; let start: Double }
    private let normalizer = PCMNormalizer()
    private var sourceFormat: AVAudioFormat?
    private var basePTS: Double?
    private var chunkOrigin = 0.0
    private var outputFrames: Int64 = 0
    private var expectedInputPTS: Double?
    private var nextOutputTime = 0.0

    func reset() {
        normalizer.reset()
        sourceFormat = nil; basePTS = nil; chunkOrigin = 0
        outputFrames = 0; expectedInputPTS = nil; nextOutputTime = 0
    }

    func convert(_ sampleBuffer: CMSampleBuffer) throws -> Block? {
        guard sampleBuffer.isValid, CMSampleBufferDataIsReady(sampleBuffer) else { return nil }
        guard let description = sampleBuffer.formatDescription else { throw WhisperEngineError.invalidAudio }
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        let count = CMSampleBufferGetNumSamples(sampleBuffer)
        guard count > 0 else { return nil }
        guard count < 480_000, format.sampleRate > 0,
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { throw WhisperEngineError.invalidAudio }
        input.frameLength = AVAudioFrameCount(count)
        let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(count), into: input.mutableAudioBufferList)
        guard copyStatus == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(copyStatus))
        }

        let pts = sampleBuffer.presentationTimeStamp.seconds
        guard pts.isFinite else { throw WhisperEngineError.invalidAudio }
        if basePTS == nil { basePTS = pts }
        let changedFormat = sourceFormat != format
        let discontinuity = expectedInputPTS.map { abs(pts - $0) > 0.05 } ?? false
        if sourceFormat == nil || changedFormat || discontinuity {
            normalizer.reset()
            sourceFormat = format
            // Keep forward gaps; a restarted source clock must never rewind the session.
            chunkOrigin = max(nextOutputTime, pts - (basePTS ?? pts))
            outputFrames = 0
        }
        expectedInputPTS = pts + Double(count) / format.sampleRate
        let samples = try normalizer.convert(input)
        guard !samples.isEmpty else { return nil }
        let start = chunkOrigin + Double(outputFrames) / 16_000
        outputFrames += Int64(samples.count)
        nextOutputTime = start + Double(samples.count) / 16_000
        return Block(samples: samples, start: start)
    }
}
#endif
