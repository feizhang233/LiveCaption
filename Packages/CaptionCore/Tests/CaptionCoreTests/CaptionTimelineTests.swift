import XCTest
@testable import CaptionCore

final class CaptionTimelineTests: XCTestCase {
    func testSeekingIntoMiddleNeverDeletesEarlierUniqueWords() {
        var timeline = CaptionTimeline()
        let earlier = CaptionSegment(start: 10, end: 20, text: "Earlier unique words. Bonjour le monde.")
        timeline.insert([earlier])
        let replay = CaptionSegment(start: 15, end: 25, text: "A changed decoding with additional words.")
        let update = timeline.insert([replay])
        XCTAssertEqual(timeline.cues, [earlier])
        XCTAssertEqual(update.alternatives.map(\.caption), [replay])
        XCTAssertEqual(timeline.alternatives.first?.overlappingCaptionIDs, [earlier.id])
    }

    func testExactJapaneseBoundaryRetainsNewSuffixWithDisjointTime() {
        var timeline = CaptionTimeline()
        let original = CaptionSegment(start: 10, end: 20, text: "今日はいい天気です。")
        timeline.insert([original])
        timeline.insert([.init(start: 16, end: 25, text: "いい天気です。散歩しましょう。")])
        XCTAssertEqual(timeline.cues.count, 2)
        XCTAssertEqual(timeline.cues[0], original)
        XCTAssertEqual(timeline.cues[1].text, "散歩しましょう。")
        XCTAssertEqual(timeline.cues[1].start, 20)
        XCTAssertEqual(timeline.cues[1].end, 25)
        XCTAssertTrue(timeline.alternatives.isEmpty)
    }

    func testSeekingEarlierPreservesNewPrefixAndExistingWholeCue() {
        var timeline = CaptionTimeline()
        let original = CaptionSegment(start: 10, end: 20, text: "Bonjour le monde. Comment allez-vous ?")
        timeline.insert([original])
        timeline.insert([.init(start: 5, end: 15, text: "Une phrase avant. Bonjour le monde.")])
        XCTAssertEqual(timeline.cues.count, 2)
        XCTAssertEqual(timeline.cues[0].text, "Une phrase avant.")
        XCTAssertEqual(timeline.cues[0].start, 5)
        XCTAssertEqual(timeline.cues[0].end, 10)
        XCTAssertEqual(timeline.cues[1], original)
    }

    func testFullyCoveredDuplicateIsSkippedButRevisionIsRetained() {
        var timeline = CaptionTimeline()
        timeline.insert([.init(start: 0, end: 10, text: "Bonjour le monde.")])
        let duplicate = timeline.insert([.init(start: 2, end: 8, text: "Bonjour, le monde !")])
        XCTAssertEqual(duplicate.duplicateCount, 1)
        XCTAssertEqual(timeline.cues.count, 1)
        let revision = timeline.insert([.init(start: 2, end: 8, text: "Bonsoir les amis.")])
        XCTAssertEqual(revision.alternatives.count, 1)
        XCTAssertEqual(timeline.alternatives.first?.caption.text, "Bonsoir les amis.")
    }

    func testCueAcrossMultipleConfirmedIntervalsIsNotSplitByCharacterRatio() {
        var timeline = CaptionTimeline()
        let first = CaptionSegment(start: 10, end: 20, text: "First sentence.")
        let second = CaptionSegment(start: 30, end: 40, text: "Second sentence.")
        timeline.insert([first, second])
        let replay = CaptionSegment(start: 5, end: 45, text: "Prefix. First sentence. Middle. Second sentence. Suffix.")
        let update = timeline.insert([replay])
        XCTAssertEqual(timeline.cues, [first, second])
        XCTAssertEqual(update.alternatives.first?.caption, replay)
        XCTAssertEqual(timeline.uncoveredRanges(in: 5..<45), [5..<10, 20..<30, 40..<45])
    }

    func testNonoverlappingRepeatIsARealNewUtterance() {
        var timeline = CaptionTimeline()
        timeline.insert([.init(start: 0, end: 2, text: "はい、そうです。"), .init(start: 20, end: 22, text: "はい、そうです。")])
        XCTAssertEqual(timeline.cues.count, 2)
        XCTAssertEqual(timeline.caption(at: 21)?.start, 20)
        XCTAssertNil(timeline.caption(at: 2))
    }

    func testCapacityReturnsUnretainedWithoutEvictingEarlierText() {
        var timeline = CaptionTimeline(maximumCues: 1, maximumAlternatives: 1)
        let first = CaptionSegment(start: 0, end: 10, text: "Keep this text.")
        timeline.insert([first])
        let overflow = CaptionSegment(start: 20, end: 25, text: "New uncovered text.")
        XCTAssertEqual(timeline.insert([overflow]).unretained, [overflow])
        timeline.insert([.init(start: 3, end: 4, text: "Alternative one")])
        let alternativeOverflow = CaptionSegment(start: 5, end: 6, text: "Alternative two")
        XCTAssertEqual(timeline.insert([alternativeOverflow]).unretained, [alternativeOverflow])
        XCTAssertEqual(timeline.cues, [first])
        XCTAssertEqual(timeline.alternatives.count, 1)
    }

    func testPrimaryExportIsSortedAndDisjointAfterRepeatedSeeks() {
        var timeline = CaptionTimeline()
        timeline.insert([.init(start: 10, end: 20, text: "Bonjour le monde.")])
        timeline.insert([.init(start: 15, end: 25, text: "Bonjour le monde. Au revoir."),
                         .init(start: 2, end: 8, text: "Avant le voyage."),
                         .init(start: 12, end: 18, text: "Bonjour le monde."),
                         .init(start: 19, end: 24, text: "Un autre résultat.")])
        XCTAssertEqual(timeline.cues.map(\.start), [2, 10, 20])
        for pair in zip(timeline.cues, timeline.cues.dropFirst()) { XCTAssertLessThanOrEqual(pair.0.end, pair.1.start) }
        let srt = CaptionExporter.srt(timeline.cues)
        XCTAssertEqual(srt.components(separatedBy: "Bonjour le monde.").count - 1, 1)
        XCTAssertTrue(srt.contains("00:00:20,000 --> 00:00:25,000\nAu revoir."))
    }
}
