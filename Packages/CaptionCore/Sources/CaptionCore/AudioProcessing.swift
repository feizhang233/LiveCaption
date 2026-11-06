import Foundation
import AVFoundation

/// Reuses AVAudioConverter's anti-aliasing resampler rather than decimating samples.
/// Confine an instance to the serial audio-capture queue that owns it.
public final class PCMNormalizer {
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
    public init() {}
    public func reset() { converter = nil; inputFormat = nil }
    public func convert(_ buffer: AVAudioPCMBuffer) throws -> [Float] {
        if inputFormat != buffer.format {
            inputFormat = buffer.format
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
            converter?.downmix = true
        }
        guard let converter else { throw WhisperEngineError.invalidAudio }
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * 16_000 / buffer.format.sampleRate) + 256)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { throw WhisperEngineError.invalidAudio }
        var consumed: AVAudioFrameCount = 0
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { requested, outStatus in
            guard consumed < buffer.frameLength else { outStatus.pointee = .noDataNow; return nil }
            let count = min(AVAudioFrameCount(requested), buffer.frameLength - consumed)
            guard let slice = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: count) else {
                outStatus.pointee = .noDataNow; return nil
            }
            slice.frameLength = count
            let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
            let destination = UnsafeMutableAudioBufferListPointer(slice.mutableAudioBufferList)
            let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
            for channel in 0..<source.count {
                if let from = source[channel].mData, let to = destination[channel].mData {
                    memcpy(to, from.advanced(by: Int(consumed) * bytesPerFrame), Int(count) * bytesPerFrame)
                }
            }
            consumed += count
            outStatus.pointee = .haveData
            return slice
        }
        if let error { throw error }
        guard status != .error, let channel = output.floatChannelData?[0] else { throw WhisperEngineError.invalidAudio }
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }
}

struct SpeechWindow: Sendable {
    var samples: [Float]
    var start: Double
    var isFinal: Bool
    var end: Double { start + Double(samples.count) / 16_000 }
}

/// Lightweight acoustic VAD: 20 ms energy frames, adaptive silence floor,
/// 250 ms preroll, 600 ms hangover. It is deliberately NOT claimed as a neural
/// speech/music classifier. Music and very quiet speech remain a QA limitation.
struct SpeechWindowBuilder {
    // Only provisional timing is shortened. Final VAD/overlap boundaries stay
    // unchanged so a faster preview does not sacrifice transcription context.
    private static let firstPartialSamples = 16_000
    private static let partialStrideSamples = 12_800
    private(set) var active: [Float] = []
    private var preRoll: [Float] = []
    private var start = 0.0
    private var noiseFloor = 0.00001
    private var silenceSamples = 0
    private var lastPartialCount = 0
    private var hasNewSpeech = false
    private var pending: [Float] = []
    private var pendingStart = 0.0
    private var expectedNext: Double?
    private(set) var silentSeconds = 0.0

    mutating func reset() { self = SpeechWindowBuilder() }

    mutating func append(_ samples: [Float], at time: Double, emitPartials: Bool = true) -> [SpeechWindow] {
        guard time.isFinite, !samples.isEmpty else { return [] }
        var windows: [SpeechWindow] = []
        if let expectedNext, abs(time - expectedNext) > 0.15 {
            if let final = flush() { windows.append(final) }
            preRoll.removeAll(keepingCapacity: true); pending.removeAll(keepingCapacity: true)
        }
        expectedNext = time + Double(samples.count) / 16_000
        if pending.isEmpty { pendingStart = time }
        // Oversized callers cannot make the ring grow without bound.
        for offset in stride(from: 0, to: samples.count, by: 320) {
            let stop = min(samples.count, offset + 320)
            pending.append(contentsOf: samples[offset..<stop])
            while pending.count >= 320 {
                let frame = Array(pending.prefix(320))
                pending.removeFirst(320)
                windows.append(contentsOf: process(frame, at: pendingStart, emitPartials: emitPartials))
                pendingStart += 0.02
            }
        }
        return windows
    }

    private mutating func process(_ frame: [Float], at time: Double, emitPartials: Bool) -> [SpeechWindow] {
        let rms = sqrt(frame.reduce(0.0) { $0 + Double($1 * $1) } / Double(frame.count))
        // Digital/media audio can be very quiet even when intelligible. A fixed
        // 0.004 gate rejected an actual French FLEURS clip (max RMS 0.00266).
        let voiced = rms > max(0.0001, min(0.018, noiseFloor * 3.5))
        if !voiced { noiseFloor = 0.97 * noiseFloor + 0.03 * rms }
        silentSeconds = voiced ? 0 : silentSeconds + 0.02
        var output: [SpeechWindow] = []
        if active.isEmpty {
            if voiced {
                start = max(0, time - Double(preRoll.count) / 16_000)
                active = preRoll; active.append(contentsOf: frame)
                preRoll.removeAll(keepingCapacity: true)
                hasNewSpeech = true; silenceSamples = 0
            } else {
                preRoll.append(contentsOf: frame)
                if preRoll.count > 4_000 { preRoll.removeFirst(preRoll.count - 4_000) }
            }
        } else {
            active.append(contentsOf: frame)
            if voiced { silenceSamples = 0; hasNewSpeech = true }
            else { silenceSamples += frame.count }
            if silenceSamples >= 9_600 {
                if let final = flushActive() { output.append(final) }
            } else if active.count >= 160_000 {
                output.append(SpeechWindow(samples: active, start: start, isFinal: true))
                let overlap = Array(active.suffix(12_800))
                start += Double(active.count - overlap.count) / 16_000
                active = overlap
                lastPartialCount = overlap.count
                hasNewSpeech = false
            } else if emitPartials && active.count >= Self.firstPartialSamples &&
                        (lastPartialCount == 0 || active.count - lastPartialCount >= Self.partialStrideSamples) {
                output.append(SpeechWindow(samples: active, start: start, isFinal: false))
                lastPartialCount = active.count
            }
        }
        return output
    }

    mutating func flush() -> SpeechWindow? {
        if !pending.isEmpty && !active.isEmpty { active.append(contentsOf: pending) }
        pending.removeAll(keepingCapacity: true)
        expectedNext = nil
        return flushActive()
    }

    private mutating func flushActive() -> SpeechWindow? {
        let final: SpeechWindow? = hasNewSpeech && active.count >= 3_200
            ? SpeechWindow(samples: active, start: start, isFinal: true) : nil
        active.removeAll(keepingCapacity: true)
        silenceSamples = 0; lastPartialCount = 0; hasNewSpeech = false
        return final
    }
}
