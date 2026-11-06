import AppKit
import AVFoundation
import CaptionCore
import Foundation

/// Runs the actual App coordinator, AVPlayer, AVAssetReader, model integrity
/// scanner and whisper.cpp. No mock recognizer, screen recording, or UI window.
@main struct SessionHarness {
    @MainActor static func main() async {
        do {
            let report = try await run()
            print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch {
            let report: [String: Any] = ["passed": false, "error": error.localizedDescription]
            if let data = try? JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            exit(1)
        }
    }

    @MainActor static func run() async throws -> [String: Any] {
        let args = CommandLine.arguments
        guard args.count == 4 || args.count == 5 else {
            throw Failure("Usage: session-checks MODEL.bin AUDIO_OR_VIDEO TEMP_DIRECTORY [ja|fr]")
        }
        let language = args.count == 5 ? args[4] : "ja"
        let initialPauseTarget = language == "fr" ? 4.5 : 2.5
        let modelURL = URL(fileURLWithPath: args[1])
        let audioURL = URL(fileURLWithPath: args[2])
        let directory = URL(fileURLWithPath: args[3], isDirectory: true).appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let tiny = WhisperModel.catalog.first { $0.id == "tiny" }!
        try FileManager.default.copyItem(at: modelURL, to: directory.appendingPathComponent(tiny.fileName))
        let suite = "LiveCaption.SessionHarness.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelStore(storageURL: directory, defaults: defaults)
        try await waitUntil("SHA-256 model scan", seconds: 12) { store.state(for: tiny).isInstalled }
        try store.select(tiny)
        let session = SessionController(models: store, defaults: defaults)
        session.useGPU = false // Deterministic CPU path; Metal separately tested by CaptionProbe.
        session.language = language
        session.media.player.isMuted = true
        await session.openMedia(audioURL)
        try check(session.media.isReady && session.media.duration > 8, "Real audio must open with readable duration")
        try check(session.canStart, "Verified selected model and open media must enable Start")

        var startCallSeconds: [Double] = []
        let coldStart = ContinuousClock.now
        await session.start()
        startCallSeconds.append(elapsed(since: coldStart))
        try check(session.phase == .running, "Start failed: \(session.errorMessage ?? session.status)")
        try await waitUntil("Playback before delayed polling tick", seconds: 8) {
            session.media.player.currentTime().seconds >= 0.5
        }
        let generationBeforeDelayedTick = session.transcriber.currentGeneration
        // Test-only: simulate a delayed UI executor, while AVPlayer keeps playing.
        // This must not be interpreted as a seek that discards already-played audio.
        usleep(1_400_000)
        try await Task.sleep(for: .milliseconds(250))
        try check(session.transcriber.currentGeneration == generationBeforeDelayedTick,
                  "Normal playback during a delayed tick must not reset the transcription generation")
        try await waitUntil("AVPlayer advancing during real recognition", seconds: 15) {
            session.media.player.currentTime().seconds >= initialPauseTarget
        }
        await session.pause()
        try check(session.phase == .paused && session.media.player.rate == 0, "Pause must suspend the player and finish its transition")
        let pauseTime = session.media.player.currentTime().seconds
        let unreadPlayedTail = try await session.media.reader.read(until: pauseTime)
        try check(unreadPlayedTail.isEmpty,
                  "Pause must feed every played PCM sample before finalizing (unread \(unreadPlayedTail.reduce(0) { $0 + $1.samples.count }) samples)")
        try await waitUntil("Final caption after pause", seconds: 8) { !session.captions.isEmpty }
        let firstPass = session.captions
        try check(firstPass.allSatisfy { !$0.text.isEmpty && $0.end <= pauseTime + 0.15 }, "Initial confirmed text must use the played source timeline")
        try await Task.sleep(for: .milliseconds(350))
        try check(abs(session.media.player.currentTime().seconds - pauseTime) < 0.03, "Paused playback time must remain fixed")

        let generationBeforeSeek = session.transcriber.currentGeneration
        await session.seek(to: 1)
        try check(session.phase == .paused, "Seeking while paused must not start playback")
        try check(abs(session.media.currentTime - 1) < 0.05, "Seek must land on source time 1 second")
        try check(session.transcriber.currentGeneration > generationBeforeSeek, "Seek must invalidate old inference/event generation")
        let firstResume = ContinuousClock.now
        await session.start()
        startCallSeconds.append(elapsed(since: firstResume))
        try check(session.phase == .running, "Resume after seek failed: \(session.errorMessage ?? session.status)")
        try await waitUntil("Resumed player reaching later source audio", seconds: 15) {
            session.media.player.currentTime().seconds >= 7.4
        }
        await session.pause()
        try await waitUntil("Confirmed replay result", seconds: 8) {
            session.captions.count > firstPass.count || !session.alternatives.isEmpty
        }
        for original in firstPass {
            try check(session.captions.contains(original), "Seeking into a cue must preserve all earlier unique text")
        }
        for pair in zip(session.captions, session.captions.dropFirst()) {
            try check(pair.0.end <= pair.1.start, "Primary captions must remain nonoverlapping after replay")
        }
        let replayPass = session.captions
        let alternativeCount = session.alternatives.count
        let srt = CaptionExporter.srt(replayPass)
        try check(!srt.isEmpty && srt.contains(" --> "), "Real confirmed text must export as SRT")
        try check(session.metrics.audioSeconds > 0 && session.metrics.inferenceSeconds > 0, "Actual model inference metrics must be observed")

        // Exercise the native transport path, bypassing SessionController.seek.
        let secondResume = ContinuousClock.now
        await session.start()
        startCallSeconds.append(elapsed(since: secondResume))
        let generationBeforeNativeSeek = session.transcriber.currentGeneration
        await session.media.player.seek(to: CMTime(seconds: 0.75, preferredTimescale: 16_000), toleranceBefore: .zero, toleranceAfter: .zero)
        try await waitUntil("Native AVPlayer seek invalidation", seconds: 5) {
            session.transcriber.currentGeneration > generationBeforeNativeSeek
        }
        try await waitUntil("Playback after native seek", seconds: 6) { session.media.player.currentTime().seconds > 2.2 }
        session.media.player.pause()
        let nativePausedAt = session.media.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(450))
        let unreadNativePause = try await session.media.reader.read(until: nativePausedAt)
        try check(unreadNativePause.isEmpty, "Native transport pause must drain every played PCM sample")
        try check(session.isPlaybackPaused, "Session controls must reflect a native player pause")
        await session.togglePlayback()
        try check(session.media.player.rate > 0 && session.phase == .running,
                  "Continue after native pause must resume playback with one action")

        try await waitUntil("Clean end of media", seconds: 15) { session.phase == .paused || session.phase == .failed }
        try check(session.phase == .paused && session.errorMessage == nil,
                  "EOF must flush and pause without decoding error: \(session.errorMessage ?? session.status)")
        try check(session.media.player.currentTime().seconds >= session.media.duration - 0.1,
                  "EOF must correspond to the actual source duration")
        let eofTime = session.media.player.currentTime().seconds
        let allEOFResults = session.captions + session.alternatives.map(\.caption)
        let eofMaximumCueEnd = allEOFResults.map(\.end).max() ?? 0
        try check(eofMaximumCueEnd > (replayPass.map(\.end).max() ?? 0) + 0.2,
                  "EOF must flush newly played tail audio instead of cancelling its final inference")
        try check(session.metrics.audioSeconds > 0 && session.metrics.inferenceSeconds > 0,
                  "EOF must retain final inference metrics instead of resetting them")
        try check(allEOFResults.allSatisfy { $0.text.contains { $0.isLetter || $0.isNumber } },
                  "Quiet audio must not produce punctuation-only captions")

        let eofResume = ContinuousClock.now
        await session.start()
        startCallSeconds.append(elapsed(since: eofResume))
        try check(session.phase == .running && session.media.player.currentTime().seconds < 1,
                  "Start at EOF must automatically seek to the beginning")
        try await waitUntil("Automatic replay after EOF", seconds: 5) {
            session.media.player.currentTime().seconds > 0.25 && session.media.player.currentTime().seconds < 2
        }
        let restartedAtSourceSeconds = session.media.player.currentTime().seconds

        // Jump straight over unplayed audio to EOF. This is a seek, not natural
        // completion: draining the reader here would transcribe skipped content.
        try await waitUntil("Playback before direct EOF seek", seconds: 4) {
            session.media.player.currentTime().seconds >= 0.8
        }
        await session.clearHistory()
        let beforeDirectEOF = session.media.player.currentTime().seconds
        let skippedSourceSeconds = session.media.duration - beforeDirectEOF
        let generationBeforeDirectEOF = session.transcriber.currentGeneration
        await session.media.player.seek(to: CMTime(seconds: session.media.duration, preferredTimescale: 16_000),
                                        toleranceBefore: .zero, toleranceAfter: .zero)
        try await waitUntil("Direct native seek to EOF", seconds: 5) {
            session.phase == .paused || session.phase == .failed
        }
        try check(session.phase == .paused && session.errorMessage == nil, "Direct EOF seek must pause cleanly")
        try check(session.transcriber.currentGeneration > generationBeforeDirectEOF,
                  "Direct EOF seek must invalidate skipped audio (generation \(generationBeforeDirectEOF)→\(session.transcriber.currentGeneration), \(session.captions.count) captions, \(session.metrics.audioSeconds) inferred audio seconds)")
        try check(session.captions.isEmpty && session.alternatives.isEmpty && session.partial == nil,
                  "Direct EOF seek must not transcribe or retain skipped content")
        try check(session.metrics.audioSeconds == 0 && session.metrics.inferenceSeconds == 0,
                  "Direct EOF seek must not run inference on the skipped remainder")

        await session.clearHistory()
        await session.stop()
        try await Task.sleep(for: .milliseconds(700))
        try check(session.phase == .idle, "Stop must finish in idle")
        try check(session.captions.isEmpty && session.alternatives.isEmpty && session.partial == nil,
                  "Clear plus stop must not be repopulated by late inference events")
        let modelAfterStop = await session.engine.loadedModelURL
        try check(modelAfterStop == nil && store.activeModelID == nil, "Stop must release model ownership and its C context")

        let restartAfterStop = ContinuousClock.now
        await session.start()
        startCallSeconds.append(elapsed(since: restartAfterStop))
        let reloadedModel = await session.engine.loadedModelURL
        try check(session.phase == .running && reloadedModel != nil,
                  "Starting after Stop must reload the released context")
        await session.stop()

        // A failed import must not leave a misleading ready player.
        await session.openMedia(URL(fileURLWithPath: args[3]).appendingPathComponent("missing.wav"))
        try check(!session.media.isReady && session.errorMessage != nil, "Unreadable media must expose a real failure state")
        await session.stop()
        await session.media.reader.close()
        session.media.player.replaceCurrentItem(with: nil)

        return [
            "passed": true,
            "model": tiny.id,
            "modelSHA256": tiny.sha256,
            "input": audioURL.lastPathComponent,
            "language": language,
            "cpuInference": true,
            "mutedPlayback": true,
            "startCallSeconds": startCallSeconds,
            "pausedAtSourceSeconds": pauseTime,
            "firstPass": firstPass.map(cue),
            "replayPrimary": replayPass.map(cue),
            "replayAlternativeCount": alternativeCount,
            "cleanEOFSourceSeconds": eofTime,
            "EOFMaximumCueEnd": eofMaximumCueEnd,
            "autoRestartSourceSeconds": restartedAtSourceSeconds,
            "nativeSeekToEOFSkippedSeconds": skippedSourceSeconds,
            "nativeSeekToEOFConfirmedCount": 0,
            "exportedSRT": srt,
            "checked": ["verified model selection", "AVPlayer/AVAssetReader real source-time feed", "delayed polling tick preserves audio generation", "pause drains all played PCM", "pause clock", "explicit seek", "resume", "immutable earlier history", "disjoint SRT", "native AVPlayer seek", "native transport pause drains all played PCM", "clean EOF with flushed tail and retained metrics", "no punctuation-only captions", "automatic replay at EOF", "native direct EOF seek skips unplayed audio", "clear/stop stale-event rejection", "model unload", "released context reloads after Stop", "unreadable import"]
        ]
    }

    private static func cue(_ cue: CaptionSegment) -> [String: Any] {
        ["start": cue.start, "end": cue.end, "text": cue.text]
    }
    private static func elapsed(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
    @MainActor private static func waitUntil(_ label: String, seconds: Double, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { throw Failure("Timed out: \(label)") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
    private static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw Failure(message) }
    }
    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
