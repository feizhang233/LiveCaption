import AVFoundation
import Foundation

/// Offline checks for the exact ScreenCaptureKit buffer adapter. This executable
/// never requests screen-recording access and does not instantiate SCStream.
@main
struct PlatformAudioHarness {
    static func main() async throws {
        let normalizer = SystemAudioNormalizer()
        var sampleCount = 0
        var lastEnd = 0.0
        var energy = 0.0
        for index in 0..<1_000 {
            let sample = try makeSample(rate: 48_000, channels: 2, count: 4_800, at: 10 + Double(index) * 0.1)
            guard let block = try normalizer.convert(sample) else { fatalError("Missing converted PCM") }
            check(abs(block.start - lastEnd) < 1.0 / 16_000, "Continuous samples must have continuous timestamps")
            sampleCount += block.samples.count
            energy += block.samples.reduce(0) { $0 + Double($1 * $1) }
            lastEnd = block.start + Double(block.samples.count) / 16_000
        }
        check(abs(sampleCount - 1_600_000) < 640, "48 kHz stereo 100-second stream must stay within 40 ms of input; received \(sampleCount) frames")
        check(energy / Double(sampleCount) > 0.001, "Conversion must preserve non-silent audio")

        let gap = try normalizer.convert(makeSample(rate: 48_000, channels: 2, count: 4_800, at: 110.25))!
        check(abs(gap.start - 100.25) < 0.001, "Forward PTS gap must remain in caption timeline")
        let afterGap = gap.start + Double(gap.samples.count) / 16_000
        let rewind = try normalizer.convert(makeSample(rate: 48_000, channels: 2, count: 4_800, at: 8))!
        check(rewind.start >= afterGap, "Source clock reset must not rewind captions")

        normalizer.reset()
        let mono = try normalizer.convert(makeSample(rate: 44_100, channels: 1, count: 4_410, at: 100))!
        check(abs(mono.start) < 0.001 && abs(mono.samples.count - 1_600) < 640, "Fresh session and 44.1 kHz conversion")
        let changed = try normalizer.convert(makeSample(rate: 16_000, channels: 1, count: 1_600, at: 100.1))!
        check(changed.start >= mono.start + Double(mono.samples.count) / 16_000, "Format change must not rewind output")
        check(changed.samples.count == 1_600, "16 kHz mono must preserve frame count")
        normalizer.reset()
        let rightOnly = try normalizer.convert(makeSample(rate: 16_000, channels: 2, count: 1_600, at: 0, silentFirstChannel: true))!
        check(rightOnly.samples.reduce(0.0) { $0 + Double($1 * $1) } / Double(rightOnly.samples.count) > 0.0001, "Right-channel-only dialogue must survive downmix")
        let termination = TerminationFlag()
        let ingress = CapturedAudioIngress { termination.set() }
        for index in 0..<20 { ingress.yield(samples: [Float](repeating: Float(index), count: 160), at: Double(index) * 0.01) }
        ingress.finish()
        var received: [CapturedAudioChunk] = []
        for await chunk in ingress.stream { received.append(chunk) }
        check(received.count == 8, "Ingress must retain exactly eight newest chunks")
        check(received.first?.samples.first == 12 && received.last?.samples.first == 19, "Ingress must shed oldest audio")
        check(abs((received.first?.start ?? 0) - 0.12) < 0.0001, "Shedding must preserve original timestamps")
        check(abs((received.last?.droppedAudioSeconds ?? 0) - 0.12) < 0.0001, "Cumulative dropped audio must include last overflow")
        check(termination.value && !ingress.yield(samples: [0], at: 1), "Finished ingress must terminate and reject future audio")
        let cancelled = TerminationFlag()
        let cancelledIngress = CapturedAudioIngress { cancelled.set() }
        let consumer = Task { for await _ in cancelledIngress.stream {} }
        consumer.cancel()
        await consumer.value
        check(cancelled.value && !cancelledIngress.yield(samples: [0], at: 1), "Consumer cancellation must terminate capture ingress")
        try checkProbeAudioAndRing()
        for screen in [CGRect(x: 0, y: 40, width: 1280, height: 680), CGRect(x: -1920, y: -900, width: 1920, height: 1080)] {
            for size in [CGSize(width: 760, height: 170), CGSize(width: 4000, height: 4000)] {
                let frame = CaptionPanelPlacement.frame(size: size, on: screen)
                check(screen.contains(frame), "Restored panel must fit inside the target visible frame, including an oversized panel")
                check(frame.minY >= screen.minY + 16 && frame.maxY <= screen.maxY - 16,
                      "Panel placement must preserve both vertical margins on smaller/negative-origin displays")
                let saved = CGRect(origin: CGPoint(x: screen.minX - 200, y: screen.minY + 100), size: size)
                let restored = CaptionPanelPlacement.restoredFrame(saved, on: screen)
                check(screen.contains(restored), "A partially visible saved panel must be resized and moved fully onto its display")
            }
        }
        print("PASS: ScreenCaptureKit PCM adapter — stereo downmix, 48/44.1/16 kHz conversion, continuous PTS, forward gaps, source-clock rewind and reset; bounded newest-8 ingress, overflow accounting and termination; ReplayKit probe converter and bounded 32-slot ring with gap/overlap timestamps; panel placement on smaller and negative-origin screens. No UI or recording permission requested.")
    }

    static func checkProbeAudioAndRing() throws {
        let converter = ProbeAudioConverter()
        var frames = 0
        var nextStart = 100.0
        var energy = 0.0
        for index in 0..<100 {
            let sample = try makeSample(rate: 48_000, channels: 2, count: 4_800, at: 100 + Double(index) * 0.1, silentFirstChannel: true)
            guard let block = try converter.convert(sample) else { fatalError("Probe converter lost valid audio") }
            check(abs(block.start - nextStart) < 1.0 / 16_000, "Probe converter must preserve a continuous source timeline")
            frames += block.samples.count
            energy += block.samples.reduce(0) { $0 + Double($1 * $1) }
            nextStart = block.start + Double(block.samples.count) / 16_000
        }
        check(abs(frames - 160_000) < 640 && energy / Double(frames) > 0.0001,
              "Probe converter must retain right-channel speech and the full 10-second duration")
        let gapBlock = try converter.convert(makeSample(rate: 48_000, channels: 2, count: 4_800, at: 110.06))!
        check(abs(gapBlock.start - 110.06) < 1.0 / 16_000, "Probe converter must preserve a 60 ms input gap")
        let rewind = try converter.convert(makeSample(rate: 16_000, channels: 1, count: 1600, at: 1))!
        check(rewind.start >= gapBlock.start + Double(gapBlock.samples.count) / 16_000,
              "Probe output must not rewind after a clock or format reset")

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("live-caption-probe-ring-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        // Synthetic test payloads use ordinary atomic files: encrypted iOS file
        // protection and locked-device availability require a separate device test.
        let writer = try ProbeRingWriter(directory: directory, writingOptions: .atomic)
        let decoder = JSONDecoder()
        func packet(_ slot: Int) throws -> ProbeRingWriter.Packet {
            try decoder.decode(ProbeRingWriter.Packet.self, from: Data(contentsOf: directory.appendingPathComponent("slot-\(slot).json")))
        }
        try writer.append(samples: [Float](repeating: 1, count: 2_000), at: 10)
        try writer.append(samples: [Float](repeating: 2, count: 4_000), at: 10.185)
        let afterGap = try packet(0)
        check(abs(afterGap.presentationTime - 10.185) < 0.000001 && afterGap.samples.allSatisfy { $0 == 2 },
              "A 60 ms gap must discard the partial prefix instead of timestamping unrelated audio as continuous")
        try writer.append(samples: [Float](repeating: 3, count: 2_000), at: 20)
        try writer.append(samples: [Float](repeating: 4, count: 4_000), at: 20.045)
        let afterOverlap = try packet(1)
        check(abs(afterOverlap.presentationTime - 20.045) < 0.000001 && afterOverlap.samples.allSatisfy { $0 == 4 },
              "A source overlap must not concatenate partial packets with misleading timestamps")
        try writer.append(samples: [Float](repeating: 5, count: 2_000), at: 30)
        try writer.append(samples: [Float](repeating: 6, count: 2_000), at: 30.125)
        let continuous = try packet(2)
        check(continuous.presentationTime == 30 && continuous.samples.first == 5 && continuous.samples.last == 6,
              "Truly continuous partial buffers must be assembled in source order")
        for index in 0..<40 {
            try writer.append(samples: [Float](repeating: Float(index), count: 4_000), at: 40 + Double(index) * 0.25)
        }
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("slot-") }
        check(urls.count == 32, "Diagnostic PCM storage must remain bounded to 32 slots")
        let packets = try urls.map { try decoder.decode(ProbeRingWriter.Packet.self, from: Data(contentsOf: $0)) }
        check(packets.map(\.sequence).min() == 11 && packets.map(\.sequence).max() == 42,
              "The ring must retain only the most recent eight seconds")
        check(packets.allSatisfy { $0.samples.count == 4_000 && $0.sessionID == afterGap.sessionID },
              "Each ring packet must have a fixed payload bound and the same session identity")
        try writer.eraseAudio()
        let remainingFiles = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        check(remainingFiles.isEmpty,
              "Finishing a diagnostic broadcast must remove its audio")
    }

    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }

    static func makeSample(rate: Double, channels: AVAudioChannelCount, count: AVAudioFrameCount, at seconds: Double, silentFirstChannel: Bool = false) throws -> CMSampleBuffer {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: channels, interleaved: false)!
        let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: count)!
        pcm.frameLength = count
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(count) { pcm.floatChannelData![channel][frame] = silentFirstChannel && channel == 0 ? 0 : 0.2 * Float(sin(2 * .pi * 440 * Double(frame) / rate)) }
        }
        var description: CMAudioFormatDescription?
        let formatResult = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &description)
        guard formatResult == noErr, let description else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(formatResult)) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: Int32(rate)), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48_000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let sampleResult = CMSampleBufferCreate(allocator: kCFAllocatorDefault, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil, formatDescription: description, sampleCount: Int(count), sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample)
        guard sampleResult == noErr, let sample else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(sampleResult)) }
        let dataResult = CMSampleBufferSetDataBufferFromAudioBufferList(sample, blockBufferAllocator: kCFAllocatorDefault, blockBufferMemoryAllocator: kCFAllocatorDefault, flags: 0, bufferList: pcm.audioBufferList)
        guard dataResult == noErr else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(dataResult)) }
        CMSampleBufferSetDataReady(sample)
        return sample
    }
}

private final class TerminationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var terminated = false
    func set() { lock.lock(); terminated = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return terminated }
}
