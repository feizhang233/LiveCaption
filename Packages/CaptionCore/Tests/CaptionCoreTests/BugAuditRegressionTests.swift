import XCTest
@testable import CaptionCore

final class BugAuditRegressionTests: XCTestCase {
    func testBriefNewCaptionAfterConfirmedBoundaryIsNotDropped() {
        var reconciler = CaptionReconciler()
        _ = reconciler.confirm([.init(start: 0, end: 1, text: "Bonjour.")], windowStart: 0, windowEnd: 1)
        let next = reconciler.confirm([.init(start: 0.21, end: 0.26, text: "Oui.")], windowStart: 0.8, windowEnd: 1.5)
        XCTAssertEqual(next.first?.text, "Oui.")
        XCTAssertEqual(next.first?.start ?? -1, 1.01, accuracy: 0.001)
    }

    func testRepeatedWordsAfterConfirmedBoundaryAreStillNewSpeech() {
        var reconciler = CaptionReconciler()
        _ = reconciler.confirm([.init(start: 0, end: 1, text: "Bonjour.")], windowStart: 0, windowEnd: 1)
        let next = reconciler.confirm([.init(start: 0.25, end: 0.7, text: "Bonjour.")], windowStart: 0.8, windowEnd: 1.5)
        XCTAssertEqual(next.first?.text, "Bonjour.")
        XCTAssertEqual(next.first?.start ?? -1, 1.05, accuracy: 0.001)
    }

    func testHugeFiniteTimestampDoesNotTrap() {
        let timestamp = CaptionExporter.timestamp(Double.greatestFiniteMagnitude)
        XCTAssertFalse(timestamp.isEmpty)
        XCTAssertFalse(timestamp.localizedCaseInsensitiveContains("inf"))
        XCTAssertFalse(timestamp.localizedCaseInsensitiveContains("nan"))
    }

    func testTimestampRoundingCarryAndInvalidValues() {
        XCTAssertEqual(CaptionExporter.timestamp(3599.9996), "01:00:00,000")
        XCTAssertEqual(CaptionExporter.timestamp(-1), "00:00:00,000")
        XCTAssertEqual(CaptionExporter.timestamp(.nan), "00:00:00,000")
        XCTAssertEqual(CaptionExporter.timestamp(.infinity), "00:00:00,000")
    }

    func testLateCancellationHandlerCannotCancelTheNextOperation() {
        let slot = EngineCancellationSlot()
        let earlier = slot.begin()
        slot.end(earlier)
        let current = slot.begin()
        // Reproduce a delayed onCancel closure from the previous task.
        earlier.cancel()
        XCTAssertTrue(earlier.isCancelled)
        XCTAssertFalse(current.isCancelled)
        // Late cleanup from that same task must not detach the active request.
        slot.end(earlier)
        slot.cancel()
        XCTAssertTrue(current.isCancelled)
        slot.end(current)
        let retry = slot.begin()
        XCTAssertFalse(retry.isCancelled)
        slot.end(retry)
    }

    func testFinalSupersedesInFlightPartial() async {
        let recognizer = ControlledAuditRecognizer()
        let stream = StreamingTranscriber(engine: recognizer)
        let gotFinal = expectation(description: "final delivered")
        let consumer = Task { () -> [String] in
            var text: [String] = []
            for await event in stream.events {
                if case .partial(let caption?) = event {
                    text.append(caption.text)
                }
                if case .confirmed(let captions) = event, captions.first?.text == "confirmed sentence" { gotFinal.fulfill() }
                if case .status(.stopped) = event { break }
            }
            return text
        }
        var requests = recognizer.requests.makeAsyncIterator()
        await stream.start(language: "fr")
        await stream.append(samples: Array(repeating: 0.1, count: 32_000), at: 0)
        _ = await requests.next() // First decode now definitely in flight.
        await stream.append(samples: Array(repeating: 0.1, count: 16_000), at: 2)
        await stream.pause() // The final supersedes the in-flight provisional job.
        await recognizer.completeNext(text: "obsolete hypothesis")
        _ = await requests.next()
        await recognizer.completeNext(text: "confirmed sentence")
        await fulfillment(of: [gotFinal], timeout: 2)
        await stream.stop(unloadModel: false)
        let delivered = await consumer.value
        XCTAssertEqual(delivered, [])
    }

    func testBusyInferenceStillPublishesPreviewThenUsesLatestAudio() async {
        let recognizer = ControlledAuditRecognizer()
        let stream = StreamingTranscriber(engine: recognizer)
        let gotFirst = expectation(description: "slow first preview is not starved")
        let gotLatest = expectation(description: "next idle preview uses accumulated audio")
        let consumer = Task { () -> [String] in
            var text: [String] = []
            for await event in stream.events {
                if case .partial(let caption?) = event {
                    text.append(caption.text)
                    if caption.text == "first available words" { gotFirst.fulfill() }
                    if caption.text == "latest available sentence" { gotLatest.fulfill() }
                }
                if case .status(.stopped) = event { break }
            }
            return text
        }
        var requests = recognizer.requests.makeAsyncIterator()
        await stream.start(language: "fr")
        await stream.append(samples: Array(repeating: 0.1, count: 16_000), at: 0)
        let firstRequest = await requests.next()
        XCTAssertEqual(firstRequest, 16_000)
        // Several cadence boundaries pass while the decoder is busy. Keeping a
        // replacement at each one used to discard every result on slow hardware.
        for frame in 0..<10 {
            await stream.append(samples: Array(repeating: 0.1, count: 3_200), at: 1 + Double(frame) * 0.2)
        }
        await recognizer.completeNext(text: "first available words")
        await fulfillment(of: [gotFirst], timeout: 2)
        await stream.append(samples: Array(repeating: 0.1, count: 320), at: 3)
        let latestRequest = await requests.next()
        XCTAssertEqual(latestRequest, 48_320, "Do not replay an older queued snapshot")
        await recognizer.completeNext(text: "latest available sentence")
        await fulfillment(of: [gotLatest], timeout: 2)
        await stream.stop(unloadModel: false)
        let delivered = await consumer.value
        XCTAssertEqual(delivered, ["first available words", "latest available sentence"])
    }
}

private actor ControlledAuditRecognizer: SpeechRecognizing {
    nonisolated let requests: AsyncStream<Int>
    private let requestContinuation: AsyncStream<Int>.Continuation
    private var pending: [(Int, CheckedContinuation<[RecognitionSegment], Error>)] = []
    init() {
        var continuation: AsyncStream<Int>.Continuation!
        requests = AsyncStream { continuation = $0 }
        requestContinuation = continuation
    }
    nonisolated func cancel() {}
    func unload() {}
    func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment] {
        try await withCheckedThrowingContinuation { continuation in
            pending.append((samples.count, continuation))
            requestContinuation.yield(samples.count)
        }
    }
    func completeNext(text: String) {
        guard !pending.isEmpty else { return }
        let (count, continuation) = pending.removeFirst()
        continuation.resume(returning: [.init(start: 0, end: Double(count) / 16_000, text: text)])
    }
}
