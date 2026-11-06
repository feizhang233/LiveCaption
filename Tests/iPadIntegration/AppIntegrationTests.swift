import AVFoundation
import NaturalLanguage
import UIKit
import XCTest
@testable import LiveCaption

/// Hosted integration tests: actual App coordinator, AVPlayer/AVAssetReader,
/// SHA-256 ModelStore verification, and the bundled whisper.cpp C engine.
/// Fixture transcripts are never read by the recognition path.
final class AppIntegrationTests: XCTestCase {
    @MainActor
    func testJapaneseRealAudioProducesJapaneseCaptions() async throws {
        try await runRealFixture(name: "ja_jp-0.wav", sourceLanguage: "ja", expectedLanguage: .japanese,
                                 checksAudioInterruption: true)
    }

    @MainActor
    func testFrenchRealAudioProducesFrenchCaptions() async throws {
        try await runRealFixture(name: "fr_fr-0.wav", sourceLanguage: "fr", expectedLanguage: .french)
    }

    @MainActor
    func testFrenchRealVideoProducesFrenchCaptions() async throws {
        try await runRealFixture(name: "fr-native-video.mp4", sourceLanguage: "fr", expectedLanguage: .french)
    }

    @MainActor
    func testEnglishRealAudioProducesEnglishCaptions() async throws {
        try await runRealFixture(name: "en_us-0.wav", sourceLanguage: "en", expectedLanguage: .english)
    }

    @MainActor
    func testMandarinRealAudioProducesChineseCaptions() async throws {
        try await runRealFixture(name: "cmn_hans_cn-0.wav", sourceLanguage: "zh", expectedLanguage: .simplifiedChinese)
    }

    @MainActor
    func testJapaneseAutomaticAccelerationProducesJapaneseCaptions() async throws {
        try await runRealFixture(name: "ja_jp-0.wav", sourceLanguage: "ja", expectedLanguage: .japanese,
                                 requestedUseGPU: true)
    }

    @MainActor
    private func runRealFixture(name: String, sourceLanguage: String, expectedLanguage: NLLanguage,
                                requestedUseGPU: Bool = false, checksAudioInterruption: Bool = false) async throws {
        let files = FileManager.default
        let applicationSupport = try XCTUnwrap(files.urls(for: .applicationSupportDirectory, in: .userDomainMask).first)
        let documents = try XCTUnwrap(files.urls(for: .documentDirectory, in: .userDomainMask).first)
        let tiny = try XCTUnwrap(WhisperModel.catalog.first { $0.id == "tiny" })
        let installedModel = applicationSupport.appendingPathComponent("LiveCaption/Models/\(tiny.fileName)")
        let fixture = documents.appendingPathComponent(name)
        try XCTSkipUnless(files.fileExists(atPath: installedModel.path),
                          "Seed the verified multilingual tiny model in the host App's Application Support/LiveCaption/Models.")
        try XCTSkipUnless(files.fileExists(atPath: fixture.path),
                          "Seed the licensed real-speech fixture \(name) in the host App's Documents folder.")

        let temporary = files.temporaryDirectory.appendingPathComponent("LiveCaption-iPad-Integration-\(UUID().uuidString)", isDirectory: true)
        let modelDirectory = temporary.appendingPathComponent("Models", isDirectory: true)
        try files.createDirectory(at: modelDirectory, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: temporary) }
        try files.copyItem(at: installedModel, to: modelDirectory.appendingPathComponent(tiny.fileName))
        let suite = "LiveCaption.iPadIntegration.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let models = ModelStore(storageURL: modelDirectory, defaults: defaults)
        try await waitUntil("model SHA-256 verification", timeout: 15,
                            diagnostic: { models.state(for: tiny).statusText }) {
            models.state(for: tiny).isInstalled
        }
        try models.select(tiny)
        let session = SessionController(models: models, defaults: defaults)
        session.useGPU = requestedUseGPU
        session.language = sourceLanguage
        session.media.player.isMuted = true

        do {
            await session.openMedia(fixture)
            XCTAssertNil(session.errorMessage, session.status)
            XCTAssertTrue(session.media.isReady, "Actual fixture must open")
            XCTAssertGreaterThan(session.media.duration, 8, "Fixture should include the full recorded utterance")
            XCTAssertTrue(session.canStart, "A verified selected model and open media must enable Start")
            let wallStart = Date()
            await session.start()
            XCTAssertEqual(session.phase, .running, session.errorMessage ?? session.status)
            XCTAssertEqual(models.activeModelID, tiny.id)
            let usingGPU = await session.engine.usingGPU
            if !requestedUseGPU {
                XCTAssertFalse(usingGPU, "The CPU tests explicitly disable GPU use")
            }
            if checksAudioInterruption {
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.ended.rawValue)])
                try await Task.sleep(for: .milliseconds(150))
                XCTAssertEqual(session.phase, .running, "An ended notification must not pause running playback")
                NotificationCenter.default.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: NSNumber(value: AVAudioSession.InterruptionType.began.rawValue)])
                try await waitUntil("audio interruption began pauses playback", timeout: 8,
                                    diagnostic: { session.status }) { session.phase == .paused }
                XCTAssertEqual(session.media.player.rate, 0)
                await session.start()
                XCTAssertEqual(session.phase, .running, "Playback must allow explicit resume after an interruption")
            }
            try await waitUntil("actual source playback reaching EOF", timeout: 35,
                                diagnostic: { "phase=\(session.phase), source=\(session.media.currentTime), status=\(session.status), error=\(session.errorMessage ?? "none")" }) {
                session.phase == .failed || (session.phase == .paused && session.media.player.currentTime().seconds >= session.media.duration - 0.15)
            }
            XCTAssertEqual(session.phase, .paused, session.errorMessage ?? session.status)
            XCTAssertNil(session.errorMessage, session.status)
            try await waitUntil("confirmed real inference result", timeout: 10,
                                diagnostic: { session.errorMessage ?? session.status }) {
                !session.captions.isEmpty || session.errorMessage != nil
            }
            XCTAssertNil(session.errorMessage, session.status)
            XCTAssertFalse(session.captions.isEmpty, "The real whisper.cpp path must emit confirmed text")
            XCTAssertGreaterThan(session.metrics.audioSeconds, 0, "Audio must reach the transcriber")
            XCTAssertGreaterThan(session.metrics.inferenceSeconds, 0, "The real C engine must execute inference")

            let text = session.captions.map(\.text).joined(separator: " ")
            let languageRecognizer = NLLanguageRecognizer()
            languageRecognizer.processString(text)
            let detected = languageRecognizer.dominantLanguage
            XCTAssertTrue(sourceLanguage == "zh" ? [NLLanguage.simplifiedChinese, .traditionalChinese].contains(detected ?? .undetermined) : detected == expectedLanguage,
                           "Output must stay in the source language; observed text: \(text)")
            for cue in session.captions {
                XCTAssertTrue(cue.isFinal)
                XCTAssertFalse(cue.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                XCTAssertTrue(cue.start.isFinite && cue.end.isFinite)
                XCTAssertGreaterThanOrEqual(cue.start, 0)
                XCTAssertGreaterThan(cue.end, cue.start)
                XCTAssertLessThanOrEqual(cue.end, session.media.duration + 0.15,
                                         "Caption times must stay on the played source timeline")
            }
            for pair in zip(session.captions, session.captions.dropFirst()) {
                XCTAssertLessThanOrEqual(pair.0.end, pair.1.start, "Primary subtitle cues must not overlap")
            }
            let sourceDuration = session.media.duration
            let report: [String: Any] = [
                "fixture": name,
                "model": tiny.id,
                "modelSHA256": tiny.sha256,
                "sourceLanguage": sourceLanguage,
                "detectedOutputLanguage": languageRecognizer.dominantLanguage?.rawValue ?? "none",
                "sourceDurationSeconds": sourceDuration,
                "wallSecondsIncludingPlayback": Date().timeIntervalSince(wallStart),
                "inferenceSeconds": session.metrics.inferenceSeconds,
                "processedAudioSeconds": session.metrics.audioSeconds,
                "droppedAudioSeconds": session.metrics.droppedAudioSeconds,
                "requestedUseGPU": requestedUseGPU,
                "usingGPU": usingGPU,
                "cpuInference": !usingGPU,
                "mutedPlayback": true,
                "device": UIDevice.current.model,
                "osVersion": UIDevice.current.systemVersion,
                "captions": session.captions.map { ["start": $0.start, "end": $0.end, "text": $0.text] as [String: Any] }
            ]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            let json = String(decoding: data, as: UTF8.self)
            let attachment = XCTAttachment(string: json)
            attachment.name = "real-inference-\(name)-\(requestedUseGPU ? "automatic-acceleration" : "cpu").json"
            attachment.lifetime = .keepAlways
            add(attachment)
            print("IPAD_REAL_INFERENCE \(json)")

            // Check a paused source seek without reusing stale partial captions.
            let oldGeneration = session.transcriber.currentGeneration
            await session.seek(to: 1)
            XCTAssertEqual(session.phase, .paused)
            XCTAssertEqual(session.media.currentTime, 1, accuracy: 0.05)
            XCTAssertGreaterThan(session.transcriber.currentGeneration, oldGeneration)
            XCTAssertNil(session.partial)
            let pausedTime = session.media.player.currentTime().seconds
            try await Task.sleep(for: .milliseconds(300))
            XCTAssertEqual(session.media.player.currentTime().seconds, pausedTime, accuracy: 0.03)

            await session.stop()
            XCTAssertEqual(session.phase, .idle)
            XCTAssertNil(models.activeModelID)
            let loadedModel = await session.engine.loadedModelURL
            XCTAssertNil(loadedModel, "Stop must release the whisper.cpp model context")
            await session.media.reader.close()
            session.media.player.replaceCurrentItem(with: nil)
        } catch {
            let attachment = XCTAttachment(string: "fixture=\(name) phase=\(session.phase) time=\(session.media.currentTime) status=\(session.status) error=\(session.errorMessage ?? "none")")
            attachment.name = "integration-failure-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            await session.stop()
            await session.media.reader.close()
            session.media.player.replaceCurrentItem(with: nil)
            throw error
        }
    }

    @MainActor
    private func waitUntil(_ label: String, timeout: TimeInterval,
                           diagnostic: () -> String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline {
                let message = "Timed out waiting for \(label): \(diagnostic())"
                XCTFail(message)
                throw IntegrationFailure(message: message)
            }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private struct IntegrationFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}
