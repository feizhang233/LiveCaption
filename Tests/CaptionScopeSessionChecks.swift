import AppKit
import CaptionCore
import Foundation

/// Uses the real coordinator, integrity scanner and Whisper context, with a
/// controlled audio adapter. It does not capture the user's audio or change focus.
@main struct CaptionScopeSessionChecks {
    @MainActor static func main() async {
        do {
            let report = try await run()
            print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
        } catch {
            print("FAIL: \(error.localizedDescription)")
            exit(1)
        }
    }

    @MainActor private static func run() async throws -> [String: Any] {
        guard CommandLine.arguments.count == 3 else { throw Failure("Usage: scope-session-checks MODEL.bin TEMP_DIRECTORY") }
        let temporary = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
        let modelsDirectory = temporary.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        let tiny = WhisperModel.catalog.first { $0.id == "tiny" }!
        try FileManager.default.copyItem(at: URL(fileURLWithPath: CommandLine.arguments[1]),
                                        to: modelsDirectory.appendingPathComponent(tiny.fileName))
        let suite = "LiveCaption.ScopeSessionChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ModelStore(storageURL: modelsDirectory, defaults: defaults)
        try await waitUntil("verified model", seconds: 15) { store.state(for: tiny).isInstalled }
        try store.select(tiny)
        let session = SessionController(models: store, defaults: defaults, monitorForeground: false)
        let capture = ControlledCapture()
        session.capture = capture
        session.source = .system
        session.useGPU = false
        let allowedApp = ForegroundContext(appBundleIdentifier: "com.example.Player", appName: "Player", pageState: .notSupported)
        let otherApp = ForegroundContext(appBundleIdentifier: "com.example.Editor", appName: "Editor", pageState: .notSupported)
        func page(_ string: String?, state: BrowserPageState = .available) -> ForegroundContext {
            ForegroundContext(appBundleIdentifier: "com.apple.Safari", appName: "Safari", pageURL: string.flatMap(URL.init(string:)), pageState: state)
        }
        var assertions = 0
        func check(_ condition: Bool, _ label: String) throws {
            assertions += 1
            guard condition else { throw Failure(label) }
        }

        // Arming an empty allowlist must not request capture or load the model.
        session.captionScope.mode = .selected
        session.updateForegroundContext(otherApp)
        await session.start()
        try check(session.phase == .paused && session.isWaitingForScope, "Empty selected scope should wait")
        try check(capture.startCount == 0 && !capture.isRunning, "Waiting must not request capture")
        let emptyModel = await session.engine.loadedModelURL
        try check(emptyModel == nil && store.activeModelID == nil, "Waiting must not load or lock the model")
        await session.pause()
        try check(!session.isWaitingForScope && session.phase == .paused, "Manual pause disarms waiting")
        session.captionScope.addApplication(id: allowedApp.appBundleIdentifier!, name: allowedApp.appName!)
        session.updateForegroundContext(allowedApp)
        await settle()
        try check(capture.startCount == 0 && session.phase == .paused, "Allowed context cannot revive a manual pause")
        session.captionScope.mode = .always
        await settle()
        try check(capture.startCount == 0 && session.phase == .paused, "Changing mode cannot revive a manual pause")

        session.captionScope.mode = .selected
        session.updateForegroundContext(otherApp)
        await session.start()
        try check(session.isWaitingForScope, "Explicit start arms waiting again")
        await session.stop()
        session.updateForegroundContext(allowedApp)
        await settle()
        try check(session.phase == .idle && !session.isWaitingForScope && capture.startCount == 0,
                  "Stop disarms waiting and prevents later automatic start")

        // Continuous mode captures with a real loaded context, regardless of focus.
        session.captionScope.mode = .always
        session.updateForegroundContext(otherApp)
        await session.start()
        try check(session.phase == .running && capture.isRunning && capture.startCount == 1, "Always mode starts system capture")
        let loadedModel = await session.engine.loadedModelURL
        try check(loadedModel != nil && store.activeModelID == tiny.id, "Running capture owns the real verified model")
        capture.emitBurst(chunks: 32)
        try await waitUntil("accepted controlled audio") { session.inputDroppedSeconds > 0 }
        try check(session.inputDroppedSeconds > 0, "Allowed controlled audio reaches session feed")
        session.updateForegroundContext(allowedApp)
        session.captionScope.mode = .selected
        await settle()
        try check(capture.startCount == 1 && session.phase == .running, "Already allowed scope does not restart capture")
        let generationBeforePause = session.transcriber.currentGeneration
        session.updateForegroundContext(otherApp)
        try check(session.isWaitingForScope && session.stageCaption == nil, "Scope revocation immediately hides live captions")
        try await waitUntil("automatic scope pause") { session.phase == .paused && session.isWaitingForScope }
        try check(!capture.isRunning, "Automatic pause stops capture")
        let retainedModel = await session.engine.loadedModelURL
        try check(retainedModel == loadedModel && store.activeModelID == tiny.id, "Automatic pause retains model ownership for resume")
        try check(session.transcriber.currentGeneration > generationBeforePause, "Automatic pause invalidates pending inference events")
        session.updateForegroundContext(allowedApp)
        try await waitUntil("automatic app resume") { session.phase == .running && capture.startCount == 2 }
        try check(capture.isRunning && !session.isWaitingForScope, "Returning to selected app resumes automatically")

        // Same browser, new tabs/URLs: host/subdomain allowed; unlisted or unknown denied.
        try session.captionScope.addWebsite("example.com")
        session.updateForegroundContext(page("https://example.com/watch"))
        session.updateForegroundContext(page("https://video.example.com/movie"))
        await settle()
        try check(session.phase == .running && capture.startCount == 2, "Allowed website and subdomain keep capture running")
        session.updateForegroundContext(page("https://unlisted.test/movie"))
        try await waitUntil("unlisted browser page pause") { session.phase == .paused && session.isWaitingForScope }
        try check(!capture.isRunning && session.stageCaption == nil, "Changing only the active page suspends capture and stage")
        let stoppedForPage = capture.stopCount
        session.updateForegroundContext(page(nil, state: .permissionDenied))
        await settle()
        try check(session.phase == .paused && session.isWaitingForScope && capture.stopCount == stoppedForPage,
                  "Unreadable page stays paused without repeated teardown")
        session.updateForegroundContext(page("https://example.com/return"))
        try await waitUntil("allowed browser page resume") { session.phase == .running && capture.startCount == 3 }
        try check(!session.isWaitingForScope, "Returning to allowed page resumes")

        // Do not coalesce a deny→allow pair into uninterrupted audio: there was
        // an actual unauthorized interval even if no async task ran between them.
        let priorGeneration = session.transcriber.currentGeneration
        let priorStarts = capture.startCount
        let priorStops = capture.stopCount
        let priorDropped = session.inputDroppedSeconds
        session.updateForegroundContext(page("https://unlisted.test"))
        session.updateForegroundContext(page("https://example.com"))
        capture.emitBurst(chunks: 64)
        try check(session.isWaitingForScope, "Same-turn deny then allow keeps revocation latched")
        try await waitUntil("latched scope restart") { session.phase == .running && capture.startCount == priorStarts + 1 }
        try check(capture.stopCount == priorStops + 1, "Latched revocation tears down the previous capture exactly once")
        try check(session.transcriber.currentGeneration > priorGeneration, "Latched revocation invalidates prior generation")
        try check(session.inputDroppedSeconds == priorDropped, "Audio queued across revoked boundary is not fed")

        // A manual pause while automatic capture teardown is awaiting completion
        // disarms the later resume even if focus returns before teardown ends.
        capture.holdStops = true
        session.updateForegroundContext(otherApp)
        try await waitUntil("held automatic pause") { session.phase == .pausing && capture.pendingStops > 0 }
        await session.pause()
        session.updateForegroundContext(allowedApp)
        let startsBeforeManualDisarm = capture.startCount
        capture.releaseStops()
        try await waitUntil("manual pause wins") { session.phase == .paused && !session.isWaitingForScope }
        await settle()
        try check(capture.startCount == startsBeforeManualDisarm && !capture.isRunning, "Manual pause during automatic teardown prevents resume")
        try check(session.status.contains("手動暫停"), "Manual disarm exposes a manual-pause status")
        await session.start()
        try check(session.phase == .running && capture.startCount == startsBeforeManualDisarm + 1, "Explicit start re-arms after manual disarm")

        // Stop during an automatic transition must own final state and unload.
        capture.holdStops = true
        session.updateForegroundContext(otherApp)
        try await waitUntil("automatic teardown before stop") { session.phase == .pausing && capture.pendingStops > 0 }
        let stopTask = Task { await session.stop() }
        try await waitUntil("Stop joins in-progress teardown") { session.phase == .stopping && capture.pendingStops == 2 }
        session.updateForegroundContext(allowedApp)
        let startsBeforeStop = capture.startCount
        capture.releaseStops()
        await stopTask.value
        await settle()
        try check(session.phase == .idle && !session.isWaitingForScope && !capture.isRunning, "Stop wins against automatic pause/resume")
        let releasedModel = await session.engine.loadedModelURL
        try check(releasedModel == nil && store.activeModelID == nil, "Stop releases real model after overlapping pause")
        try check(capture.startCount == startsBeforeStop, "Late allowed focus cannot revive stopped session")

        // Revoke during an async capture start; the same-turn allow cannot
        // authorize the older capture's queued buffers or skip its teardown.
        capture.holdStarts = true
        let startTask = Task { await session.start() }
        try await waitUntil("held capture start", seconds: 15) { session.phase == .loading && capture.pendingStarts == 1 }
        let startsDuringLoad = capture.startCount
        let stopsDuringLoad = capture.stopCount
        session.updateForegroundContext(otherApp)
        session.updateForegroundContext(allowedApp)
        try check(session.isWaitingForScope, "Revocation during capture start is latched")
        capture.releaseStarts()
        await startTask.value
        try await waitUntil("fresh capture after loading revocation") { session.phase == .running && capture.startCount == startsDuringLoad + 1 }
        try check(capture.stopCount == stopsDuringLoad + 1 && capture.isRunning, "Revoked loading capture is torn down before fresh resume")
        await session.stop()
        try check(session.phase == .idle && !capture.isRunning, "Final cleanup leaves session stopped")

        return ["passed": true, "assertions": assertions, "model": tiny.id, "modelSHA256": tiny.sha256,
                "captureStarts": capture.startCount, "captureStops": capture.stopCount,
                "realModel": true, "capture": "controlled silent PCM adapter; no actual system audio captured",
                "checked": ["empty allowlist waits without capture/model", "manual pause disarms automatic start", "stop disarms waiting",
                            "always captures", "app switch stops/resumes", "model retained across automatic pause", "browser tab and unknown URL gating",
                            "same-turn revoke/allow requires teardown", "stale audio rejected", "manual pause during automatic teardown",
                            "stop during automatic teardown", "revocation during capture start"]]
    }

    @MainActor private static func waitUntil(_ label: String, seconds: Double = 5, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() > deadline { throw Failure("Timed out: \(label)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(120))
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}

@MainActor private final class ControlledCapture: SystemAudioCapturing {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var isRunning = false
    var holdStarts = false
    var holdStops = false
    private var revision = 0
    private var starts: [CheckedContinuation<Void, Never>] = []
    private var stops: [CheckedContinuation<Void, Never>] = []
    private var audio: CapturedAudioIngress?
    var pendingStarts: Int { starts.count }
    var pendingStops: Int { stops.count }

    func start(onError: @escaping @Sendable (String) -> Void) async throws -> AsyncStream<CapturedAudioChunk> {
        startCount += 1
        revision += 1
        let expected = revision
        if holdStarts { await withCheckedContinuation { starts.append($0) } }
        guard revision == expected else { throw CancellationError() }
        isRunning = true
        let ingress = CapturedAudioIngress()
        audio = ingress
        return ingress.stream
    }

    func stop() async {
        stopCount += 1
        revision += 1
        isRunning = false
        audio?.finish()
        audio = nil
        if holdStops { await withCheckedContinuation { stops.append($0) } }
    }

    func emitBurst(chunks: Int) {
        for index in 0..<chunks {
            audio?.yield(samples: Array(repeating: 0, count: 1_600), at: Double(index) / 10)
        }
    }

    func releaseStarts() {
        holdStarts = false
        let waiting = starts
        starts.removeAll()
        waiting.forEach { $0.resume() }
    }

    func releaseStops() {
        holdStops = false
        let waiting = stops
        stops.removeAll()
        waiting.forEach { $0.resume() }
    }
}
