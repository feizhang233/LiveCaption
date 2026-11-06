import XCTest
import AVFoundation
@testable import CaptionCore

final class CaptionCoreTests: XCTestCase {
    func testSRTUsesSourceTimelineAndOmitsUnconfirmed() {
        let captions = [
            CaptionSegment(start: 65.432, end: 67.100, text: "日本語です。"),
            CaptionSegment(start: 5.250, end: 7.5, text: "Bonjour."),
            CaptionSegment(start: 8, end: 9, text: "pending", isFinal: false)
        ]
        XCTAssertEqual(CaptionExporter.srt(captions), "1\n00:00:05,250 --> 00:00:07,500\nBonjour.\n\n2\n00:01:05,432 --> 00:01:07,100\n日本語です。\n")
    }

    func testOverlapRemovalSupportsJapaneseAndFrench() {
        XCTAssertEqual(CaptionReconciler.removingOverlap(previous: "今日はいい天気です。", next: "いい天気です。散歩しましょう。"), "散歩しましょう。")
        XCTAssertEqual(CaptionReconciler.removingOverlap(previous: "Bonjour, tout le monde.", next: "Tout le monde. Comment allez-vous ?"), "Comment allez-vous ?")
        // Two-character repeats have no safe enough evidence to delete.
        XCTAssertEqual(CaptionReconciler.removingOverlap(previous: "はい", next: "はい、わかりました"), "はい、わかりました")
    }

    func testQuietAudioPunctuationDoesNotBecomePartialOrFinalSubtitle() {
        var reconciler = CaptionReconciler()
        let punctuation = ["...", "…", "！？", "「 」", "♪♫", " \n"]
        for text in punctuation {
            XCTAssertFalse(TranscriptText.containsSpokenContent(text))
            let output = [RecognitionSegment(start: 0, end: 2, text: text)]
            XCTAssertTrue(reconciler.confirm(output, windowStart: 10, windowEnd: 12).isEmpty)
            XCTAssertNil(reconciler.provisional(output, windowStart: 10, windowEnd: 12, id: UUID()))
        }
        for text in ["はい。", "Ça va ?", "你好。", "2026", "123,45"] {
            XCTAssertTrue(TranscriptText.containsSpokenContent(text), "Keep genuine text and numbers in every script")
            XCTAssertEqual(reconciler.confirm([.init(start: 0, end: 2, text: text)], windowStart: 20, windowEnd: 22).first?.text, text)
            reconciler.reset()
        }
    }

    func testIdenticalSentenceLaterInMediaIsRetained() {
        var reconciler = CaptionReconciler()
        let first = reconciler.confirm([.init(start: 0, end: 2, text: "Bonjour.")], windowStart: 0, windowEnd: 3)
        let later = reconciler.confirm([.init(start: 0, end: 2, text: "Bonjour.")], windowStart: 30, windowEnd: 33)
        XCTAssertEqual(first.count, 1); XCTAssertEqual(later.count, 1)
        XCTAssertEqual(later.first?.start, 30)
    }

    func testFullyOverlappingFinalIsNotRepeated() {
        var reconciler = CaptionReconciler()
        _ = reconciler.confirm([.init(start: 0, end: 4, text: "今日はいい天気です。")], windowStart: 10, windowEnd: 14)
        let second = reconciler.confirm([.init(start: 0, end: 1, text: "いい天気です。"), .init(start: 1, end: 3, text: "散歩しましょう。")], windowStart: 13, windowEnd: 16)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second.first?.start, 14)
        XCTAssertEqual(second.first?.text, "散歩しましょう。")
    }

    func testSilenceDoesNotSubmitInference() {
        var builder = SpeechWindowBuilder()
        for second in 0..<30 {
            XCTAssertTrue(builder.append(Array(repeating: 0, count: 16_000), at: Double(second)).isEmpty)
        }
        XCTAssertNil(builder.flush())
        XCTAssertGreaterThan(builder.silentSeconds, 29)
    }

    func testQuietSpeechEnergyIsNotRejectedByFixedLoudnessGate() {
        var builder = SpeechWindowBuilder()
        _ = builder.append(Array(repeating: 0, count: 16_000), at: 0)
        _ = builder.append(Array(repeating: 0.0007, count: 16_000), at: 1)
        let finals = builder.append(Array(repeating: 0, count: 16_000), at: 2).filter(\.isFinal)
        XCTAssertEqual(finals.count, 1)
        XCTAssertLessThanOrEqual(finals[0].start, 1)
    }

    func testSpeechWindowsStayBoundedAndOverlap() {
        var builder = SpeechWindowBuilder()
        var finals: [SpeechWindow] = []
        for second in 0..<35 {
            let result = builder.append(Array(repeating: 0.08, count: 16_000), at: Double(second))
            finals += result.filter(\.isFinal)
            XCTAssertLessThanOrEqual(builder.active.count, 160_000)
        }
        XCTAssertEqual(finals.count, 3)
        XCTAssertEqual(finals[0].start, 0, accuracy: 0.001)
        XCTAssertEqual(finals[1].start, 9.2, accuracy: 0.001)
        XCTAssertLessThanOrEqual(finals.map { $0.samples.count }.max()!, 160_000)
    }

    func testFirstPreviewAtOneSecondThenEightHundredMillisecondCadence() {
        var builder = SpeechWindowBuilder()
        XCTAssertTrue(builder.append(Array(repeating: 0.08, count: 15_680), at: 0).isEmpty)
        let first = builder.append(Array(repeating: 0.08, count: 320), at: 0.98)
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(first[0].isFinal)
        XCTAssertEqual(first[0].end, 1, accuracy: 0.0001)
        XCTAssertTrue(builder.append(Array(repeating: 0.08, count: 12_480), at: 1).isEmpty)
        let second = builder.append(Array(repeating: 0.08, count: 320), at: 1.78)
        XCTAssertEqual(second.count, 1)
        XCTAssertEqual(second[0].end, 1.8, accuracy: 0.0001)
    }

    func testSkippingBusyPreviewsPreservesEveryFinalSampleAndBoundary() {
        var eager = SpeechWindowBuilder()
        var busy = SpeechWindowBuilder()
        var eagerFinals: [SpeechWindow] = []
        var busyFinals: [SpeechWindow] = []
        // Cross the maximum window, its overlap, silence hangover, and a new
        // utterance. Preview scheduling must never change the final audio.
        for frame in 0..<900 {
            let value: Float = (frame >= 610 && frame < 680) ? 0 : Float(frame % 13 + 1) * 0.01
            let samples = Array(repeating: value, count: 320)
            eagerFinals += eager.append(samples, at: Double(frame) * 0.02).filter(\.isFinal)
            let output = busy.append(samples, at: Double(frame) * 0.02, emitPartials: false)
            XCTAssertTrue(output.allSatisfy(\.isFinal))
            busyFinals += output
        }
        if let final = eager.flush() { eagerFinals.append(final) }
        if let final = busy.flush() { busyFinals.append(final) }
        XCTAssertEqual(eagerFinals.count, 3)
        XCTAssertEqual(eagerFinals.count, busyFinals.count)
        for (eager, busy) in zip(eagerFinals, busyFinals) {
            XCTAssertEqual(eager.start, busy.start)
            XCTAssertEqual(eager.samples, busy.samples)
        }
    }

    func testVADPrerollAndHangoverKeepSourceTimes() {
        var builder = SpeechWindowBuilder()
        _ = builder.append(Array(repeating: 0, count: 16_000), at: 100)
        _ = builder.append(Array(repeating: 0.1, count: 16_000), at: 101)
        let finals = builder.append(Array(repeating: 0, count: 16_000), at: 102).filter(\.isFinal)
        XCTAssertEqual(finals.count, 1)
        XCTAssertEqual(finals[0].start, 100.75, accuracy: 0.001)
        XCTAssertEqual(finals[0].end, 102.6, accuracy: 0.021)
    }

    func testResetAfterSeekHasNoPriorAudio() {
        var builder = SpeechWindowBuilder()
        _ = builder.append(Array(repeating: 0.1, count: 16_000), at: 100)
        builder.reset()
        _ = builder.append(Array(repeating: 0.1, count: 16_000), at: 12)
        let final = builder.flush()
        XCTAssertEqual(final?.start, 12)
        XCTAssertEqual(final?.samples.count, 16_000)
    }

    func testInvalidModelFailsTruthfully() async {
        let engine = WhisperEngine()
        do {
            try await engine.load(modelURL: URL(fileURLWithPath: "/does/not/exist"))
            XCTFail("Missing models must not become available")
        } catch { XCTAssertTrue(error is WhisperEngineError) }
    }

    func testSeekInvalidatesInFlightOutput() async throws {
        let stream = StreamingTranscriber(engine: DelayedTestRecognizer())
        let collector = Task { () -> [CaptionSegment] in
            var result: [CaptionSegment] = []
            for await event in stream.events {
                if case .confirmed(let batch) = event { result += batch }
                if case .status(.stopped) = event { break }
            }
            return result
        }
        await stream.start(language: "ja")
        await stream.append(samples: Array(repeating: 0.1, count: 32_000), at: 100)
        try await Task.sleep(nanoseconds: 20_000_000)
        await stream.reset(at: 10)
        await stream.append(samples: Array(repeating: 0.1, count: 32_000), at: 10)
        await stream.finish()
        let captions = await collector.value
        XCTAssertFalse(captions.isEmpty)
        XCTAssertTrue(captions.allSatisfy { $0.start >= 10 && $0.end <= 12 })
    }

    func testSlowInferenceReportsDroppedAudioAndDoesNotAccumulateQueue() async {
        let stream = StreamingTranscriber(engine: DelayedTestRecognizer())
        let collector = Task { () -> Double in
            var dropped = 0.0
            for await event in stream.events {
                if case .metrics(let metrics) = event { dropped = max(dropped, metrics.droppedAudioSeconds) }
                if case .status(.stopped) = event { break }
            }
            return dropped
        }
        await stream.start(language: "fr")
        for second in 0..<60 {
            await stream.append(samples: Array(repeating: 0.1, count: 16_000), at: Double(second))
        }
        await stream.finish()
        let dropped = await collector.value
        XCTAssertGreaterThan(dropped, 0)
        XCTAssertLessThan(dropped, 60)
    }

    func testEngineLanguageListIsFromPinnedRuntime() {
        XCTAssertNotNil(WhisperEngine.supportedLanguages["ja"])
        XCTAssertNotNil(WhisperEngine.supportedLanguages["fr"])
        XCTAssertGreaterThan(WhisperEngine.supportedLanguages.count, 90)
    }

    func testBufferedEventsAreTaggedForRejectionAfterSeek() async {
        let stream = StreamingTranscriber(engine: DelayedTestRecognizer())
        await stream.start(language: "ja")
        await stream.reset(at: 10)
        var iterator = stream.taggedEvents.makeAsyncIterator()
        let obsolete = await iterator.next()
        XCTAssertEqual(obsolete?.generation, 0)
        XCTAssertEqual(stream.currentGeneration, 1)
        XCTAssertNotEqual(obsolete?.generation, stream.currentGeneration)
        let current = await iterator.next()
        XCTAssertEqual(current?.generation, stream.currentGeneration)
        await stream.stop()
    }

    func testStereoRightChannelIsMixedAndResampled() throws {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 2, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!
        buffer.frameLength = 44_100
        for i in 0..<44_100 {
            buffer.floatChannelData![0][i] = 0
            buffer.floatChannelData![1][i] = Float(sin(Double(i) * 2 * .pi * 440 / 44_100)) * 0.2
        }
        let samples = try PCMNormalizer().convert(buffer)
        XCTAssertEqual(samples.count, 16_000, accuracy: 32)
        XCTAssertGreaterThan(samples.map(abs).max() ?? 0, 0.02, "Do not lose speech present only in the right channel")
    }
}

/// Scheduling-only fixture; never used by either app or real-audio probes.
private actor DelayedTestRecognizer: SpeechRecognizing {
    nonisolated func cancel() {}
    func unload() {}
    func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment] {
        try await Task.sleep(nanoseconds: 150_000_000)
        return [.init(start: 0, end: Double(samples.count) / 16_000, text: "scheduler test")]
    }
}
