import Foundation

/// Whisper can emit punctuation during quiet audio. These are not words and
/// must not become subtitle cues. Unicode letters retain all supported scripts.
enum TranscriptText {
    static func containsSpokenContent(_ text: String) -> Bool {
        text.contains { $0.isLetter || $0.isNumber }
    }
}

public struct RecognitionSegment: Sendable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String
    public init(start: Double, end: Double, text: String) {
        self.start = start; self.end = end; self.text = text
    }
}

public struct CaptionSegment: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var start: Double
    public var end: Double
    public var text: String
    public var isFinal: Bool
    public init(id: UUID = UUID(), start: Double, end: Double, text: String, isFinal: Bool = true) {
        self.id = id; self.start = start; self.end = end; self.text = text; self.isFinal = isFinal
    }
}

public enum CaptionExporter {
    /// Only confirmed text is exported; a pending hypothesis is not a subtitle.
    public static func txt(_ captions: [CaptionSegment]) -> String {
        sorted(captions).map(\.text).joined(separator: "\n")
    }
    public static func srt(_ captions: [CaptionSegment]) -> String {
        sorted(captions).enumerated().map { i, caption in
            "\(i + 1)\n\(timestamp(caption.start)) --> \(timestamp(max(caption.start + 0.001, caption.end)))\n\(caption.text)\n"
        }.joined(separator: "\n")
    }
    private static func sorted(_ captions: [CaptionSegment]) -> [CaptionSegment] {
        captions.filter { $0.isFinal && $0.start.isFinite && $0.end.isFinite && !$0.text.isEmpty }
            .sorted { $0.start < $1.start }
    }
    public static func timestamp(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "00:00:00,000" }
        // Multiplying an arbitrary finite media timestamp by 1000 can overflow
        // Double or Int64. Only bounded remainders are ever converted to Int.
        var wholeSeconds = floor(seconds)
        var milliseconds = Int(((seconds - wholeSeconds) * 1000).rounded())
        if milliseconds == 1000 { wholeSeconds += 1; milliseconds = 0 }
        let hours = floor(wholeSeconds / 3600)
        let remainder = wholeSeconds.truncatingRemainder(dividingBy: 3600)
        let minutes = Int(floor(remainder / 60))
        let remainingSeconds = Int(remainder.truncatingRemainder(dividingBy: 60))
        return String(format: "%02.0f:%02d:%02d,%03d", hours, minutes, remainingSeconds, milliseconds)
    }
}

public enum TranscriptionStatus: Sendable, Equatable {
    case idle, listening, processing, paused, noAudio, stopped
    case failed(String)
}

public struct TranscriptionMetrics: Sendable, Equatable {
    public var inferenceSeconds: Double
    public var audioSeconds: Double
    public var droppedAudioSeconds: Double
    public init(inferenceSeconds: Double = 0, audioSeconds: Double = 0, droppedAudioSeconds: Double = 0) {
        self.inferenceSeconds = inferenceSeconds
        self.audioSeconds = audioSeconds
        self.droppedAudioSeconds = droppedAudioSeconds
    }
}

public enum TranscriptionEvent: Sendable {
    case partial(CaptionSegment?)
    /// Incremental batch; append these UUIDs once, never replace history with this array.
    case confirmed([CaptionSegment])
    case status(TranscriptionStatus)
    case metrics(TranscriptionMetrics)
}

public struct GenerationTaggedEvent: Sendable {
    public var generation: UInt64
    public var event: TranscriptionEvent
    public init(generation: UInt64, event: TranscriptionEvent) {
        self.generation = generation; self.event = event
    }
}
