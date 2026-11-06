import AVFoundation
import Foundation
import ReplayKit

/// Diagnostic target only. Records a bounded eight-second PCM ring to an App Group.
/// It does not run Whisper, open a network connection or claim to wake its host app.
final class SampleHandler: RPBroadcastSampleHandler {
    private let lock = NSLock()
    private var writer: ProbeRingWriter?
    private var converter: ProbeAudioConverter?
    private var active = false
    private var videoBuffers: UInt64 = 0
    private var appAudioBuffers: UInt64 = 0
    private var micAudioBuffers: UInt64 = 0
    private var conversionFailures: UInt64 = 0

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        var failure: Error?
        lock.lock()
        do {
            active = false
            videoBuffers = 0; appAudioBuffers = 0; micAudioBuffers = 0; conversionFailures = 0
            writer = try ProbeRingWriter()
            converter = ProbeAudioConverter()
            active = true
            try writer?.writeStatus(state: "capturing", video: 0, app: 0, mic: 0, failures: 0)
        } catch {
            active = false
            converter = nil
            try? writer?.eraseAudio()
            writer = nil
            failure = error
        }
        lock.unlock()
        // A framework callback may reenter the handler: never call it while
        // holding the state lock, and do not depend on broadcastFinished for cleanup.
        if let failure { finishBroadcastWithError(failure) }
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        var failure: Error?
        lock.lock()
        guard active, let writer else { lock.unlock(); return }
        do {
            switch sampleBufferType {
            case .video: videoBuffers &+= 1 // Do not retain or encode video.
            case .audioMic: micAudioBuffers &+= 1 // Do not record the microphone.
            case .audioApp:
                appAudioBuffers &+= 1
                try autoreleasepool {
                    guard let result = try converter?.convert(sampleBuffer) else { return }
                    try writer.append(samples: result.samples, at: result.start)
                }
            @unknown default: break
            }
            if (videoBuffers + appAudioBuffers + micAudioBuffers) % 30 == 1 {
                try writer.writeStatus(state: "capturing", video: videoBuffers, app: appAudioBuffers, mic: micAudioBuffers, failures: conversionFailures)
            }
        } catch {
            conversionFailures &+= 1
            try? writer.writeStatus(state: "error: \(error.localizedDescription)", video: videoBuffers, app: appAudioBuffers, mic: micAudioBuffers, failures: conversionFailures)
            active = false
            converter = nil
            try? writer.eraseAudio()
            self.writer = nil
            failure = error
        }
        lock.unlock()
        if let failure { finishBroadcastWithError(failure) }
    }

    override func broadcastPaused() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        try? writer?.writeStatus(state: "paused", video: videoBuffers, app: appAudioBuffers, mic: micAudioBuffers, failures: conversionFailures)
    }

    override func broadcastResumed() {
        lock.lock()
        defer { lock.unlock() }
        guard writer != nil else { return }
        converter = ProbeAudioConverter()
        writer?.discardPartialChunk()
        active = true
    }

    override func broadcastFinished() {
        lock.lock()
        defer { lock.unlock() }
        active = false
        try? writer?.eraseAudio()
        try? writer?.writeStatus(state: "finished", video: videoBuffers, app: appAudioBuffers, mic: micAudioBuffers, failures: conversionFailures)
        converter = nil
        writer = nil
    }
}

final class ProbeAudioConverter {
    struct Output { var samples: [Float]; var start: Double }
    private var converter: AVAudioConverter?
    private var previousFormat: AVAudioFormat?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    private var expectedInputPTS: Double?
    private var originPTS = 0.0
    private var outputFrames: Int64 = 0
    private var nextOutputTime = 0.0

    func convert(_ sample: CMSampleBuffer) throws -> Output? {
        guard sample.isValid, CMSampleBufferDataIsReady(sample), let description = sample.formatDescription else { return nil }
        let count = CMSampleBufferGetNumSamples(sample)
        let format = AVAudioFormat(cmAudioFormatDescription: description)
        // Reject an unexpectedly large buffer instead of retaining unbounded audio.
        guard count > 0, format.sampleRate > 0, count <= Int(format.sampleRate),
              let input = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)) else { return nil }
        input.frameLength = AVAudioFrameCount(count)
        let result = CMSampleBufferCopyPCMDataIntoAudioBufferList(sample, at: 0, frameCount: Int32(count), into: input.mutableAudioBufferList)
        guard result == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(result)) }
        let pts = sample.presentationTimeStamp.seconds
        guard pts.isFinite else { return nil }
        let discontinuity = expectedInputPTS.map { abs(pts - $0) > 0.05 } ?? false
        if previousFormat != format || converter == nil || discontinuity {
            converter = AVAudioConverter(from: format, to: outputFormat)
            converter?.primeMethod = .none
            converter?.downmix = true
            previousFormat = format
            originPTS = max(nextOutputTime, pts)
            outputFrames = 0
        }
        expectedInputPTS = pts + Double(count) / format.sampleRate
        guard let converter, let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(ceil(Double(count) * 16_000 / format.sampleRate)) + 64) else { return nil }
        var consumed: AVAudioFrameCount = 0
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { requested, status in
            guard consumed < input.frameLength else { status.pointee = .noDataNow; return nil }
            let frames = min(AVAudioFrameCount(requested), input.frameLength - consumed)
            guard let slice = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { status.pointee = .noDataNow; return nil }
            slice.frameLength = frames
            let source = UnsafeMutableAudioBufferListPointer(input.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(slice.mutableAudioBufferList)
            let bytesPerFrame = Int(format.streamDescription.pointee.mBytesPerFrame)
            for channel in 0..<source.count {
                if let from = source[channel].mData, let to = destination[channel].mData {
                    memcpy(to, from.advanced(by: Int(consumed) * bytesPerFrame), Int(frames) * bytesPerFrame)
                }
            }
            consumed += frames
            status.pointee = .haveData
            return slice
        }
        if let error { throw error }
        guard status != .error, output.frameLength > 0, let samples = output.floatChannelData?[0] else { return nil }
        let start = originPTS + Double(outputFrames) / 16_000
        outputFrames += Int64(output.frameLength)
        nextOutputTime = originPTS + Double(outputFrames) / 16_000
        return Output(samples: Array(UnsafeBufferPointer(start: samples, count: Int(output.frameLength))), start: start)
    }
}

final class ProbeRingWriter {
    struct Packet: Codable {
        let sequence: UInt64
        let sessionID: UUID
        let presentationTime: Double
        let sampleRate: Int
        let samples: [Float]
    }
    struct Status: Codable {
        let sessionID: UUID
        let state: String
        let updatedAt: Date
        let sequence: UInt64
        let videoBuffers: UInt64
        let appAudioBuffers: UInt64
        let micAudioBuffers: UInt64
        let failures: UInt64
    }
    private let directory: URL
    private let sessionID = UUID()
    private var sequence: UInt64 = 0
    private var pending: [Float] = []
    private var start = 0.0
    private let encoder = JSONEncoder()
    private let writingOptions: Data.WritingOptions
    private let slotCount: UInt64 = 32
    private let chunkFrames = 4_000

    /// An explicit directory is only used by the offline diagnostic regression harness.
    init(directory testDirectory: URL? = nil, writingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUnlessOpen]) throws {
        self.writingOptions = writingOptions
        if let testDirectory {
            directory = testDirectory
        } else {
            guard let group = Bundle.main.object(forInfoDictionaryKey: "LiveCaptionAppGroup") as? String,
                  !group.isEmpty,
                  let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
                throw NSError(domain: "LiveCaption.BroadcastProbe", code: 1, userInfo: [NSLocalizedDescriptionKey: "診斷廣播需要主 App 與擴充使用同一個已簽署的 App Group。"])
            }
            directory = container.appendingPathComponent("BroadcastProbe", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try mutableDirectory.setResourceValues(values)
        try eraseAudio()
    }

    func append(samples: [Float], at presentationTime: Double) throws {
        guard presentationTime.isFinite else { return }
        if pending.isEmpty { start = presentationTime }
        // Never merge across a real gap/overlap. The converter may restart after
        // a 50 ms source discontinuity, so a 100 ms tolerance would corrupt PTS.
        else if abs(presentationTime - (start + Double(pending.count) / 16_000)) > 1.0 / 16_000 {
            pending.removeAll(keepingCapacity: true)
            start = presentationTime
        }
        pending.append(contentsOf: samples)
        while pending.count >= chunkFrames {
            let packet = Packet(sequence: sequence, sessionID: sessionID, presentationTime: start, sampleRate: 16_000, samples: Array(pending.prefix(chunkFrames)))
            let data = try encoder.encode(packet)
            let url = directory.appendingPathComponent("slot-\(sequence % slotCount).json")
            try data.write(to: url, options: writingOptions)
            pending.removeFirst(chunkFrames)
            start += Double(chunkFrames) / 16_000
            sequence &+= 1
        }
    }

    func discardPartialChunk() { pending.removeAll(keepingCapacity: true) }
    func eraseAudio() throws {
        pending.removeAll(keepingCapacity: false)
        for index in 0..<slotCount {
            let url = directory.appendingPathComponent("slot-\(index).json")
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
    func writeStatus(state: String, video: UInt64, app: UInt64, mic: UInt64, failures: UInt64) throws {
        let status = Status(sessionID: sessionID, state: state, updatedAt: Date(), sequence: sequence, videoBuffers: video, appAudioBuffers: app, micAudioBuffers: mic, failures: failures)
        try encoder.encode(status).write(to: directory.appendingPathComponent("status.json"), options: .atomic)
    }
}
