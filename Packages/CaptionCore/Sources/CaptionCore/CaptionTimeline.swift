import Foundation

/// A later decode whose text cannot be placed safely without rewriting an
/// already-confirmed cue. Retain and show it separately; never merge these into
/// a primary SRT without an explicit user choice.
public struct CaptionAlternative: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID { caption.id }
    public let caption: CaptionSegment
    public let overlappingCaptionIDs: [UUID]
    public let reason: String
    public init(caption: CaptionSegment, overlappingCaptionIDs: [UUID], reason: String) {
        self.caption = caption
        self.overlappingCaptionIDs = overlappingCaptionIDs
        self.reason = reason
    }
}

public struct CaptionTimelineUpdate: Sendable {
    public var inserted: [CaptionSegment] = []
    public var duplicateCount = 0
    public var alternatives: [CaptionAlternative] = []
    /// The caller must surface the capacity limit or persist these elsewhere.
    /// The timeline never silently evicts earlier transcript text.
    public var unretained: [CaptionSegment] = []
    public var ignoredInvalidCount = 0
    public init() {}
}

/// Reconciles immutable source-time cues across repeated media seeks.
///
/// First-confirmed coverage wins. Fully covered identical text is redundant.
/// New text at one edge is kept only when an exact suffix/prefix match proves
/// which characters are duplicated. We never divide text by a time ratio:
/// without token timing that would silently remove or misplace unique words.
/// Ambiguous revisions/overlaps remain visible as alternative records instead.
public struct CaptionTimeline: Sendable {
    public private(set) var cues: [CaptionSegment] = []
    public private(set) var alternatives: [CaptionAlternative] = []
    public let maximumCues: Int
    public let maximumAlternatives: Int
    private var retainedIDs: Set<UUID> = []

    public init(maximumCues: Int = 10_000, maximumAlternatives: Int = 1_000) {
        self.maximumCues = max(1, maximumCues)
        self.maximumAlternatives = max(0, maximumAlternatives)
    }

    public mutating func reset() {
        cues.removeAll(keepingCapacity: true)
        alternatives.removeAll(keepingCapacity: true)
        retainedIDs.removeAll(keepingCapacity: true)
    }

    @discardableResult public mutating func insert(_ incoming: [CaptionSegment]) -> CaptionTimelineUpdate {
        var update = CaptionTimelineUpdate()
        for original in incoming.sorted(by: { $0.start < $1.start }) {
            guard original.isFinal, original.start.isFinite, original.end.isFinite,
                  original.start >= 0, original.end > original.start,
                  !original.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                update.ignoredInvalidCount += 1
                continue
            }
            if retainedIDs.contains(original.id) { update.duplicateCount += 1; continue }
            let overlaps = cues.filter { $0.start < original.end && $0.end > original.start }
            var candidate = original
            if !overlaps.isEmpty {
                let normalized = Self.normalized(original.text)
                let existingText = Self.normalized(overlaps.map(\.text).joined())
                if uncoveredRanges(in: original.start..<original.end).isEmpty,
                   !normalized.isEmpty, existingText.contains(normalized) {
                    update.duplicateCount += 1
                    continue
                }
                var safelyTrimmed = false
                if overlaps.count == 1, let prior = overlaps.first {
                    if prior.start <= original.start && prior.end < original.end {
                        let trimmed = CaptionReconciler.removingOverlap(previous: prior.text, next: original.text)
                        if trimmed != original.text {
                            candidate.text = trimmed; candidate.start = prior.end
                            safelyTrimmed = true
                        }
                    } else if original.start < prior.start && original.end <= prior.end,
                              let trimmed = Self.removingSuffixOverlap(original.text, followedBy: prior.text) {
                        candidate.text = trimmed; candidate.end = prior.start
                        safelyTrimmed = true
                    }
                }
                if safelyTrimmed && Self.normalized(candidate.text).isEmpty {
                    update.duplicateCount += 1
                    continue
                }
                if !safelyTrimmed {
                    let alternative = CaptionAlternative(
                        caption: original, overlappingCaptionIDs: overlaps.map(\.id),
                        reason: "重播辨識與已確認字幕重疊；保留完整新結果，避免刪除原有文字。"
                    )
                    if alternatives.count < maximumAlternatives {
                        alternatives.append(alternative)
                        retainedIDs.insert(original.id)
                        update.alternatives.append(alternative)
                    } else { update.unretained.append(original) }
                    continue
                }
            }
            if cues.count < maximumCues {
                cues.append(candidate)
                cues.sort { $0.start < $1.start }
                retainedIDs.insert(original.id)
                update.inserted.append(candidate)
            } else { update.unretained.append(original) }
        }
        return update
    }

    /// The current cached subtitle can be shown immediately after a seek.
    public func caption(at time: Double) -> CaptionSegment? {
        guard time.isFinite else { return nil }
        return cues.first { $0.start <= time && time < $0.end }
    }

    /// Optional ingestion optimization. These are *caption* intervals, not
    /// proof of a word boundary. Reset the streaming buffer when skipping a
    /// covered interval, and always keep the original source-time offset.
    public func uncoveredRanges(in range: Range<Double>) -> [Range<Double>] {
        guard range.lowerBound.isFinite, range.upperBound.isFinite,
              range.lowerBound < range.upperBound else { return [] }
        var cursor = range.lowerBound
        var result: [Range<Double>] = []
        for cue in cues where cue.end > range.lowerBound && cue.start < range.upperBound {
            if cue.start > cursor { result.append(cursor..<min(cue.start, range.upperBound)) }
            cursor = max(cursor, cue.end)
            if cursor >= range.upperBound { break }
        }
        if cursor < range.upperBound { result.append(cursor..<range.upperBound) }
        return result
    }

    private static func normalized(_ text: String) -> String {
        text.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func removingSuffixOverlap(_ text: String, followedBy following: String) -> String? {
        let indices = text.indices.filter { text[$0].isLetter || text[$0].isNumber }
        let before = normalized(text)
        let after = normalized(following)
        let limit = min(200, before.count, after.count)
        guard limit >= 3 else { return nil }
        for count in stride(from: limit, through: 3, by: -1) {
            if before.suffix(count) == after.prefix(count) {
                if count >= indices.count { return "" }
                let cut = indices[indices.count - count]
                return String(text[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }
}
