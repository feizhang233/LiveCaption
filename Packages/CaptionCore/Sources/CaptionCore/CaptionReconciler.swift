import Foundation

/// Final captions are immutable. Only text in an overlapping audio window may be
/// deduplicated; identical words spoken later in a film must remain in history.
struct CaptionReconciler {
    private var last: CaptionSegment?
    mutating func reset() { last = nil }

    mutating func confirm(_ segments: [RecognitionSegment], windowStart: Double, windowEnd: Double) -> [CaptionSegment] {
        var output: [CaptionSegment] = []
        for segment in segments {
            var text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
            var start = max(windowStart, windowStart + segment.start)
            let end = min(windowEnd, windowStart + segment.end)
            guard end > start, TranscriptText.containsSpokenContent(text) else { continue }
            if let previous = last, windowStart < previous.end {
                if end <= previous.end { continue }
                if start < previous.end {
                    text = Self.removingOverlap(previous: previous.text, next: text)
                    start = max(start, previous.end)
                }
            }
            guard TranscriptText.containsSpokenContent(text), end > start else { continue }
            let caption = CaptionSegment(start: start, end: end, text: text)
            output.append(caption); last = caption
        }
        return output
    }

    func provisional(_ segments: [RecognitionSegment], windowStart: Double, windowEnd: Double, id: UUID) -> CaptionSegment? {
        var copy = self
        let fresh = copy.confirm(segments, windowStart: windowStart, windowEnd: windowEnd)
        guard let first = fresh.first, let end = fresh.last?.end else { return nil }
        return CaptionSegment(id: id, start: first.start, end: end,
                              text: fresh.map(\.text).joined(separator: " "), isFinal: false)
    }

    static func removingOverlap(previous: String, next: String) -> String {
        let previousChars = previous.lowercased().filter { $0.isLetter || $0.isNumber }
        let indices = next.indices.filter { next[$0].isLetter || next[$0].isNumber }
        let nextChars = String(indices.map { next[$0] }).lowercased()
        let limit = min(200, previousChars.count, nextChars.count)
        guard limit >= 3 else { return next }
        for count in stride(from: limit, through: 3, by: -1) {
            if previousChars.suffix(count) == nextChars.prefix(count) {
                if count >= indices.count { return "" }
                return String(next[indices[count]...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return next
    }
}
