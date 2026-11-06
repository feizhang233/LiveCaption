import XCTest
@testable import CaptionCore

final class EnglishChineseTests: XCTestCase {
    func testPinnedEngineSupportsEnglishAndChineseAlongsideOtherLanguages() {
        let languages = WhisperEngine.supportedLanguages
        XCTAssertEqual(languages["en"], "english")
        XCTAssertEqual(languages["zh"], "chinese")
        XCTAssertNotNil(languages["ja"])
        XCTAssertNotNil(languages["fr"])
        XCTAssertGreaterThan(languages.count, 90, "Adding preferred choices must not narrow Whisper support")
    }

    func testEnglishOverlapKeepsNewWordsAndOriginalPunctuation() {
        var reconciler = CaptionReconciler()
        _ = reconciler.confirm([.init(start: 0, end: 3, text: "Welcome to the live lecture.")], windowStart: 0, windowEnd: 3)
        let next = reconciler.confirm(
            [.init(start: 0, end: 3, text: "The live lecture. Today we study acoustics — let's begin!")],
            windowStart: 2, windowEnd: 5)
        XCTAssertEqual(next.map(\.text), ["Today we study acoustics — let's begin!"])
        XCTAssertEqual(next.first?.start, 3)
    }

    func testChineseOverlapPreservesSimplifiedAndTraditionalScripts() {
        let examples = [
            ("我们正在观看没有字幕的影片。", "没有字幕的影片。现在开始辨识。", "现在开始辨识。"),
            ("我們正在觀看沒有字幕的影片。", "沒有字幕的影片。現在開始辨識。", "現在開始辨識。")
        ]
        for (previous, hypothesis, suffix) in examples {
            var reconciler = CaptionReconciler()
            _ = reconciler.confirm([.init(start: 0, end: 3, text: previous)], windowStart: 0, windowEnd: 3)
            let next = reconciler.confirm([.init(start: 0, end: 3, text: hypothesis)], windowStart: 2, windowEnd: 5)
            XCTAssertEqual(next.map(\.text), [suffix])
            XCTAssertEqual(next.first?.start, 3)
        }
        // Script conversion is not an overlap match: no unrequested rewrite.
        XCTAssertEqual(CaptionReconciler.removingOverlap(previous: "沒有字幕", next: "没有字幕，现在开始。"), "没有字幕，现在开始。")
    }

    func testLaterEnglishAndChineseRepetitionsAreNotDeleted() {
        for text in ["Yes, of course.", "当然可以。", "當然可以。"] {
            var reconciler = CaptionReconciler()
            _ = reconciler.confirm([.init(start: 0, end: 1, text: text)], windowStart: 0, windowEnd: 1)
            let later = reconciler.confirm([.init(start: 0, end: 1, text: text)], windowStart: 2, windowEnd: 3)
            XCTAssertEqual(later.first?.text, text)
            XCTAssertEqual(later.first?.start, 2)
        }
    }

    func testEnglishAndChineseExportRoundTripKeepsUnicodeAndSourceTimes() throws {
        let english = "It's a live caption — café, 2026."
        let chinese = "中文原文：简体与繁體並存，保留標點。"
        let captions = [
            CaptionSegment(start: 10.125, end: 12.5, text: chinese),
            CaptionSegment(start: 1.25, end: 3.75, text: english),
            CaptionSegment(start: 4, end: 5, text: "未確認 preview", isFinal: false)
        ]
        let expectedTXT = "\(english)\n\(chinese)"
        let expectedSRT = "1\n00:00:01,250 --> 00:00:03,750\n\(english)\n\n2\n00:00:10,125 --> 00:00:12,500\n\(chinese)\n"
        XCTAssertEqual(CaptionExporter.txt(captions), expectedTXT)
        XCTAssertEqual(CaptionExporter.srt(captions), expectedSRT)
        for text in [expectedTXT, expectedSRT] {
            let data = try XCTUnwrap(text.data(using: .utf8))
            XCTAssertEqual(String(data: data, encoding: .utf8), text)
        }
        XCTAssertTrue(TranscriptText.containsSpokenContent(english))
        XCTAssertTrue(TranscriptText.containsSpokenContent(chinese))
    }

    func testSchedulerForwardsEnglishChineseAndAutoWithoutRewritingText() async {
        for (language, text) in [("en", "Original English words."), ("zh", "原文中文字幕。"), (nil, "自動偵測仍保留原文。")] as [(String?, String)] {
            let engine = SourceLanguageTestRecognizer(text: text)
            let stream = StreamingTranscriber(engine: engine)
            let collector = Task { () -> [CaptionSegment] in
                var captions: [CaptionSegment] = []
                for await event in stream.events {
                    if case .confirmed(let batch) = event { captions += batch }
                    if case .status(.stopped) = event { break }
                }
                return captions
            }
            await stream.start(language: language)
            await stream.append(samples: Array(repeating: 0.1, count: 8_000), at: 20)
            await stream.finish()
            let forwarded = await engine.languages
            let captions = await collector.value
            XCTAssertEqual(forwarded, [language])
            XCTAssertEqual(captions.map(\.text), [text])
            XCTAssertEqual(captions.first?.start, 20)
            XCTAssertEqual(captions.first?.end, 20.5)
        }
    }
}

/// Scheduling-only fixture. Real EN/ZH recognition is validated separately
/// against the pinned model and human recordings; this does not simulate ASR.
private actor SourceLanguageTestRecognizer: SpeechRecognizing {
    let text: String
    var languages: [String?] = []
    init(text: String) { self.text = text }
    nonisolated func cancel() {}
    func unload() {}
    func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment] {
        languages.append(language)
        return [.init(start: 0, end: Double(samples.count) / 16_000, text: text)]
    }
}
