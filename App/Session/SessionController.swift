import AVFoundation
import CaptionCore
import Foundation
import Observation
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum CaptionSource: String, CaseIterable, Identifiable {
    case media = "本機媒體"
    #if os(macOS)
    case system = "系統音訊"
    #endif
    var id: String { rawValue }
}

enum SessionPhase: Equatable {
    case idle, loading, running, pausing, paused, seeking, stopping, failed
}

@MainActor @Observable
final class SessionController {
    private struct LoadedConfiguration: Equatable {
        let modelURL: URL
        let requestedGPU: Bool
    }
    let models: ModelStore
    let media = MediaController()
    let preferences: AppPreferences
    var source: CaptionSource = .media {
        didSet { defaults.set(source.rawValue, forKey: "captionSource") }
    }
    private var selectedLanguageCode: String
    var language: String {
        get { selectedLanguageCode }
        set {
            let code = SourceLanguageCatalog.validatedCode(newValue)
            selectedLanguageCode = code
            defaults.set(code, forKey: Self.languagePreferenceKey)
        }
    }
    private static let languagePreferenceKey = "sourceLanguageCode"
    private(set) var phase: SessionPhase = .idle
    private(set) var status = "選擇模型與音訊來源，開始產生原文字幕。"
    private(set) var errorMessage: String?
    private(set) var captions: [CaptionSegment] = []
    private(set) var alternatives: [CaptionAlternative] = []
    private(set) var partial: CaptionSegment?
    private(set) var metrics = TranscriptionMetrics()
    private(set) var level: Float = 0
    private(set) var trimmedHistory = false
    private(set) var inputDroppedSeconds: Double = 0
    private(set) var activeBackend = "尚未載入"
    var useGPU = true
    var overlayVisible = false {
        didSet {
            #if os(macOS)
            if overlayVisible { panel.show(content: FloatingCaptionView(session: self)) }
            else { panel.hide() }
            #endif
        }
    }
    var clickThrough = false {
        didSet {
            #if os(macOS)
            panel.setClickThrough(clickThrough)
            #endif
        }
    }
    var alwaysOnTop = true {
        didSet {
            #if os(macOS)
            panel.setAlwaysOnTop(alwaysOnTop)
            #endif
        }
    }
    @ObservationIgnored let engine: WhisperEngine
    @ObservationIgnored let transcriber: StreamingTranscriber
    @ObservationIgnored private var eventTask: Task<Void, Never>?
    @ObservationIgnored private var sourceTask: Task<Void, Never>?
    @ObservationIgnored private var captureTask: Task<Void, Never>?
    @ObservationIgnored private let audioSession = PlaybackAudioSession()
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var stopTask: Task<Void, Never>?
    @ObservationIgnored private var loadedConfiguration: LoadedConfiguration?
    @ObservationIgnored private var isImporting = false
    @ObservationIgnored private var timeline = CaptionTimeline()
    @ObservationIgnored private var sessionStart = ProcessInfo.processInfo.systemUptime
    @ObservationIgnored private let defaults: UserDefaults
    #if os(iOS)
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    let pictureInPicture = CaptionPictureInPictureController()
    private(set) var isPreparingPictureInPicture = false
    @ObservationIgnored private var pictureInPictureRequestedGPU: Bool?
    @ObservationIgnored private var pictureInPicturePreparation: UUID?
    #endif
    #if os(macOS)
    @ObservationIgnored private var lastAudio = Date()
    @ObservationIgnored var capture: any SystemAudioCapturing = MacSystemAudioCapture()
    @ObservationIgnored let panel = CaptionPanelController()
    let captionScope: CaptionScopePreferences
    let foregroundMonitor = ForegroundContextMonitor()
    private(set) var scopeWaiting = false
    @ObservationIgnored private var scopeArmed = false
    @ObservationIgnored private var scopeRevoked = false
    @ObservationIgnored private var foregroundContext: ForegroundContext?
    @ObservationIgnored private var monitorsForeground = true
    #endif

    var isWaitingForScope: Bool {
        #if os(macOS)
        source == .system && (scopeWaiting || (scopeArmed && scopeRevoked))
        #else
        false
        #endif
    }

    var canStart: Bool {
        !isImporting && !media.isLoading && [.idle, .paused, .failed].contains(phase) && hasReadyModel &&
        (source != .media || media.isReady)
    }
    var hasReadyModel: Bool { models.selectedModel.map { models.state(for: $0).isInstalled } == true }
    var modelReadinessMessage: String {
        guard let model = models.selectedModel else { return "先下載並選擇一個模型，建議從 Base 開始。" }
        switch models.state(for: model) {
        case .verifying: return "正在驗證 \(model.name) 的完整性，完成後可開始字幕。"
        case .downloading: return "\(model.name) 正在下載，請在模型管理查看進度。"
        case .failed, .notInstalled: return "選擇的模型尚不可用。請到模型管理檢查、重新下載或切換模型。"
        case .installed: return "模型已就緒。"
        }
    }
    var isBusy: Bool { isImporting || media.isLoading || [.loading, .pausing, .seeking, .stopping].contains(phase) }
    var isPlaybackPaused: Bool {
        phase == .paused || (phase == .running && source == .media && !media.isPlaying)
    }
    var stageCaption: CaptionSegment? {
        if isWaitingForScope { return nil }
        if let partial { return partial }
        if source == .media {
            return captions.last { $0.start <= media.currentTime && $0.end + 2 >= media.currentTime }
        }
        return captions.last
    }

    func displayText(for caption: CaptionSegment) -> String {
        CaptionDisplayFilter.text(caption.text, language: language, hideFillers: preferences.hideFillerWords)
    }

    var displayStageText: String { stageCaption.map { displayText(for: $0) } ?? "" }

    init(models: ModelStore? = nil, defaults: UserDefaults = .standard, monitorForeground: Bool = true) {
        self.defaults = defaults
        preferences = AppPreferences(defaults: defaults)
        #if os(macOS)
        source = CaptionSource(rawValue: defaults.string(forKey: "captionSource") ?? "") ?? .system
        captionScope = CaptionScopePreferences(defaults: defaults)
        monitorsForeground = monitorForeground
        #endif
        selectedLanguageCode = SourceLanguageCatalog.validatedCode(defaults.string(forKey: Self.languagePreferenceKey))
        self.models = models ?? ModelStore(defaults: defaults)
        engine = WhisperEngine()
        transcriber = StreamingTranscriber(engine: engine)
        let stream = transcriber.taggedEvents
        eventTask = Task { [weak self] in
            for await envelope in stream {
                guard let self, envelope.generation == self.transcriber.currentGeneration else { continue }
                self.receive(envelope.event)
            }
        }
        #if os(macOS)
        captionScope.onChange = { [weak self] in self?.scopeSettingsChanged() }
        scopeSettingsChanged()
        #endif
        #if os(iOS)
        observeLifecycle()
        pictureInPicture.bind(snapshot: { [weak self] in
            guard let self else { return .init(text: "", status: "字幕已停止", isReady: false, isPlaying: false, currentTime: 0, duration: 0) }
            return .init(text: self.displayStageText,
                         status: self.isBusy ? "正在準備字幕…" : self.phase == .running ? "等待語音…" : "字幕已暫停",
                         isReady: self.media.isReady, isPlaying: self.media.isPlaying,
                         currentTime: self.media.currentTime, duration: self.media.duration,
                         fontScale: self.preferences.fontSize / 32)
        }, setPlaying: { [weak self] playing in
            guard let self else { return }
            if playing {
                if self.phase == .running { self.media.play() }
                else { await self.start() }
            } else { await self.pause() }
        }, skip: { [weak self] interval in
            guard let self else { return }
            await self.seek(to: min(self.media.duration, max(0, self.media.currentTime + interval)))
        }, didStop: { [weak self] in
            await self?.pictureInPictureEnded()
        })
        #endif
    }

    #if os(iOS)
    private func observeLifecycle() {
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                await self?.stop()
                self?.report("裝置記憶體不足，已停止辨識並釋放模型。請改用 tiny 或 base，並關閉其他 App。")
            }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? NSNumber,
                  AVAudioSession.InterruptionType(rawValue: value.uintValue) == .began else { return }
            Task { @MainActor in
                guard let self, self.phase == .running else { return }
                await self.pause()
                self.status = "音訊已中斷。準備好後按繼續。"
            }
        })
        lifecycleObservers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.backgrounded() }
        })
    }
    #endif

    func report(_ message: String) { errorMessage = message; status = message }

    #if os(macOS)
    private var scopeAllowsAudio: Bool {
        captionScope.allows(bundleIdentifier: foregroundContext?.appBundleIdentifier,
                            url: foregroundContext?.pageURL)
    }

    private var scopeWaitingMessage: String {
        if captionScope.applications.isEmpty && captionScope.websites.isEmpty {
            return "已啟用自動字幕。請在設定加入指定 App 或網站，目前保持暫停。"
        }
        if let context = foregroundContext,
           ForegroundContextMonitor.supportedBrowsers.contains(where: { $0.id == context.appBundleIdentifier }),
           !captionScope.websites.isEmpty, context.pageState != .available {
            return "自動暫停：\(context.pageState.message)切換到指定 App 或可辨識的網站後會繼續。"
        }
        return "自動暫停：目前不在指定 App 或網站。切換到指定範圍後會繼續。"
    }

    private func scopeSettingsChanged() {
        foregroundMonitor.readsBrowserURL = captionScope.mode == .selected && !captionScope.websites.isEmpty
        if monitorsForeground {
            if captionScope.mode == .selected {
                foregroundMonitor.start { [weak self] context in self?.updateForegroundContext(context) }
            } else {
                foregroundMonitor.stop()
                foregroundContext = nil
            }
        }
        reconcileScopeSoon()
    }

    // An explicit context entry point also lets regression checks drive foreground
    // changes without controlling the user's actual applications or permissions.
    func updateForegroundContext(_ context: ForegroundContext) {
        foregroundContext = context
        reconcileScopeSoon()
    }

    private func reconcileScopeSoon() {
        guard scopeArmed, source == .system else { return }
        if !scopeAllowsAudio {
            if phase == .running || phase == .loading { scopeRevoked = true }
            partial = nil; level = 0
        }
        Task { [weak self] in await self?.reconcileScope() }
    }

    private func reconcileScope() async {
        guard scopeArmed, source == .system else { return }
        if !scopeAllowsAudio || scopeRevoked {
            if phase == .running { await suspendForScope() }
            else if phase == .paused, scopeWaiting { status = scopeWaitingMessage }
            // A loading start checks the latest context before starting capture
            // and again before feeding PCM. Do not race its capture.start().
        } else if phase == .paused, scopeWaiting {
            await start()
        }
    }

    private func suspendForScope() async {
        guard scopeArmed, source == .system, phase == .running || phase == .loading else { return }
        let token = UUID()
        generation = token
        scopeWaiting = true
        phase = .pausing
        partial = nil
        level = 0
        status = scopeWaitingMessage
        sourceTask?.cancel(); sourceTask = nil
        captureTask?.cancel(); captureTask = nil
        engine.cancel()
        await capture.stop()
        guard generation == token else { return }
        // Discard the unconfirmed tail at a scope boundary; do not transcribe
        // queued audio after the foreground has become disallowed.
        await transcriber.stop(unloadModel: false)
        guard generation == token else { return }
        phase = .paused
        scopeRevoked = false
        if !scopeArmed {
            scopeWaiting = false
            status = "已手動暫停。按繼續後才會依指定範圍自動啟用。"
            return
        }
        status = scopeWaitingMessage
        await reconcileScope()
    }
    #endif

    func openMedia(_ url: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        await stop()
        do {
            try await media.open(url)
            source = .media
            await clearHistory()
            errorMessage = nil
            status = "媒體已就緒。選擇語言並開始字幕。"
        } catch { report(error.localizedDescription) }
    }

    func selectModel(_ model: WhisperModel) async {
        await stop()
        do { try models.select(model); errorMessage = nil; status = "已選擇 \(model.name)。" }
        catch { report(error.localizedDescription) }
    }

    func changeSource(_ newSource: CaptionSource) async {
        await stop()
        source = newSource
        await clearHistory()
    }

    func togglePlayback() async {
        if isWaitingForScope { await pause(); return }
        if phase == .running {
            if isPlaybackPaused { media.play() }
            else { await pause() }
        } else { await start() }
    }

    func start() async {
        guard canStart, let model = models.selectedModel else { return }
        #if os(macOS)
        if source == .system {
            if !scopeArmed && preferences.autoShowOverlay && !overlayVisible && NSApp != nil { overlayVisible = true }
            scopeArmed = true
            scopeRevoked = false
            guard scopeAllowsAudio else {
                scopeWaiting = true
                partial = nil
                phase = .paused
                errorMessage = nil
                status = scopeWaitingMessage
                return
            }
            scopeWaiting = false
        }
        #endif
        let token = UUID()
        generation = token
        phase = .loading
        errorMessage = nil
        status = "正在載入 \(model.name)…"
        models.setInUse(model.id)
        do {
            if models.physicalMemoryBytes < model.estimatedMemoryBytes + 512 * 1_048_576 {
                throw SessionError.insufficientMemory
            }
            let modelURL = try models.modelURL(for: model)
            let requested = LoadedConfiguration(modelURL: modelURL, requestedGPU: useGPU)
            let loadedURL = await engine.loadedModelURL
            guard generation == token else { return }
            if loadedConfiguration != requested || loadedURL != modelURL {
                // Pause retains the context. Rebuilding it on every Continue
                // needlessly reloads weights and reallocates inference buffers.
                try await engine.load(modelURL: modelURL, useGPU: requested.requestedGPU)
                guard generation == token else { return }
                loadedConfiguration = requested
            }
            activeBackend = await engine.usingGPU ? "Metal + Accelerate" : "CPU + Accelerate"
            guard generation == token else { return }
            #if os(macOS)
            if source == .system, !scopeAllowsAudio || scopeRevoked { await suspendForScope(); return }
            #endif
            await transcriber.start(language: SourceLanguageCatalog.engineLanguage(for: language))
            guard generation == token else { return }
            if source == .media {
                if media.currentTime >= media.duration - 0.05 {
                    await media.seek(to: 0)
                    guard generation == token else { return }
                }
                try await media.reader.reset(at: media.currentTime)
                guard generation == token else { return }
                await transcriber.reset()
                guard generation == token else { return }
                try await audioSession.activate()
                guard generation == token else { return }
                media.play()
                phase = .running
                launchMediaFeed(token: token)
            } else {
                #if os(macOS)
                guard scopeAllowsAudio, !scopeRevoked else { await suspendForScope(); return }
                let offset = ProcessInfo.processInfo.systemUptime - sessionStart
                let chunks = try await capture.start(onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token,
                              self.phase == .running || self.phase == .loading else { return }
                        await self.stop()
                        self.report(message)
                    }
                })
                guard generation == token else { return }
                phase = .running
                guard scopeAllowsAudio, !scopeRevoked else { await suspendForScope(); return }
                let priorDropped = inputDroppedSeconds
                captureTask = Task { [weak self] in
                    for await chunk in chunks {
                        guard let self, !Task.isCancelled, self.generation == token, self.phase == .running else { return }
                        guard self.scopeAllowsAudio, !self.scopeWaiting, !self.scopeRevoked else { continue }
                        self.inputDroppedSeconds = priorDropped + chunk.droppedAudioSeconds
                        self.updateLevel(chunk.samples)
                        await self.transcriber.append(samples: chunk.samples, at: chunk.start + offset)
                    }
                }
                launchWatchdog(token: token)
                #endif
            }
            status = "正在聆聽，等待語音…"
        } catch {
            guard generation == token else { return }
            await stop()
            phase = .failed
            report(error.localizedDescription)
        }
    }

    func pause() async {
        #if os(macOS)
        scopeArmed = false
        if scopeWaiting, phase == .pausing { return }
        scopeRevoked = false
        if scopeWaiting, phase == .paused {
            scopeWaiting = false
            status = "已手動暫停。按繼續後才會依指定範圍自動啟用。"
            return
        }
        #endif
        guard phase == .running else { return }
        let token = generation
        phase = .pausing
        let feeding = sourceTask
        sourceTask = nil
        captureTask?.cancel(); captureTask = nil
        media.pause()
        if source == .media {
            // Let any read already in progress finish feeding its PCM. Cancelling
            // here could consume a reader block without appending it to ASR.
            await feeding?.value
            guard generation == token else { return }
            do { try await feedPlayedMedia(until: media.player.currentTime().seconds, token: token) }
            catch {
                guard generation == token else { return }
                await stop()
                report(error.localizedDescription)
                return
            }
        } else { feeding?.cancel() }
        guard generation == token else { return }
        #if os(macOS)
        await capture.stop()
        guard generation == token else { return }
        #endif
        await transcriber.finish()
        guard generation == token else { return }
        generation = UUID()
        phase = .paused
        level = 0
        status = "已暫停。模型仍保留；停止可釋放記憶體。"
    }

    func stop() async {
        #if os(iOS)
        pictureInPicturePreparation = nil
        isPreparingPictureInPicture = false
        restorePictureInPicturePreferences()
        #endif
        #if os(macOS)
        scopeArmed = false
        scopeWaiting = false
        scopeRevoked = false
        #endif
        if let stopTask { await stopTask.value; return }
        generation = UUID()
        phase = .stopping
        sourceTask?.cancel(); sourceTask = nil
        captureTask?.cancel(); captureTask = nil
        media.pause()
        engine.cancel()
        let cleanup = Task {
            #if os(macOS)
            await capture.stop()
            #endif
            await transcriber.stop(unloadModel: true)
            loadedConfiguration = nil
            await audioSession.deactivate()
            models.setInUse(nil)
            activeBackend = "尚未載入"
            partial = nil; level = 0
            phase = .idle
            status = "已停止並釋放模型。字幕歷史可匯出。"
        }
        stopTask = cleanup
        await cleanup.value
        stopTask = nil
        #if os(iOS)
        pictureInPicture.stop()
        await pictureInPictureEnded()
        #endif
    }

    func clearHistory() async {
        await transcriber.reset()
        timeline.reset()
        captions = []; partial = nil; trimmedHistory = false
        alternatives = []
        sessionStart = ProcessInfo.processInfo.systemUptime
        metrics = TranscriptionMetrics()
        inputDroppedSeconds = 0
    }

    func seek(to time: Double) async {
        guard source == .media else { await media.seek(to: time); return }
        let wasRunning = phase == .running
        let priorPhase = phase
        guard !isBusy else { return }
        let token = UUID()
        generation = token
        phase = .seeking
        sourceTask?.cancel()
        media.pause()
        await transcriber.reset()
        guard generation == token else { return }
        partial = nil
        await media.seek(to: time)
        guard generation == token else { return }
        do { try await media.reader.reset(at: media.currentTime) }
        catch {
            guard generation == token else { return }
            phase = .paused
            report(error.localizedDescription)
            return
        }
        guard generation == token else { return }
        if wasRunning {
            await transcriber.start(language: SourceLanguageCatalog.engineLanguage(for: language))
            guard generation == token else { return }
            phase = .running
            media.play()
            launchMediaFeed(token: token)
        } else { phase = priorPhase }
    }

    #if os(iOS)
    func startFloatingCaptions() async {
        guard media.isReady, hasReadyModel, !isBusy, !isPreparingPictureInPicture,
              UIApplication.shared.applicationState == .active,
              !pictureInPicture.isActive, !pictureInPicture.isStarting else { return }
        let request = UUID()
        pictureInPicturePreparation = request
        isPreparingPictureInPicture = true
        defer {
            if pictureInPicturePreparation == request {
                pictureInPicturePreparation = nil
                isPreparingPictureInPicture = false
            }
        }
        pictureInPictureRequestedGPU = useGPU
        if phase == .running { await pause() }
        guard pictureInPicturePreparation == request else { return }
        guard UIApplication.shared.applicationState == .active else { await stop(); return }
        // A real media session may continue in PiP; Metal inference may not.
        useGPU = false
        await start()
        guard pictureInPicturePreparation == request else { return }
        guard UIApplication.shared.applicationState == .active else { await stop(); return }
        guard phase == .running, loadedConfiguration?.requestedGPU == false else {
            await pictureInPictureEnded()
            return
        }
        media.player.audiovisualBackgroundPlaybackPolicy = .continuesIfPossible
        pictureInPicture.refresh()
        if !pictureInPicture.start() {
            report(pictureInPicture.status)
            await pictureInPictureEnded()
        }
    }

    private func pictureInPictureEnded() async {
        pictureInPicturePreparation = nil
        isPreparingPictureInPicture = false
        restorePictureInPicturePreferences()
        if UIApplication.shared.applicationState == .background, phase != .idle, phase != .stopping {
            await stop()
            status = "子母畫面已關閉，背景字幕已停止。"
        }
    }

    private func restorePictureInPicturePreferences() {
        media.player.audiovisualBackgroundPlaybackPolicy = .pauses
        if let requested = pictureInPictureRequestedGPU { useGPU = requested }
        pictureInPictureRequestedGPU = nil
    }

    private func backgrounded() async {
        guard phase != .idle && phase != .failed else { return }
        if (pictureInPicture.isActive || pictureInPicture.isStarting),
           source == .media, loadedConfiguration?.requestedGPU == false,
           phase == .running || phase == .paused { return }
        await stop()
        status = "App 已進入背景，字幕已停止並釋放模型。返回後可繼續播放辨識。"
    }
    #endif

    private func launchMediaFeed(token: UUID) {
        sourceTask?.cancel()
        sourceTask = Task { [weak self] in
            guard let self else { return }
            var previousTime = self.media.currentTime
            var previousJump = self.media.jumpSerial
            var previousTick = ProcessInfo.processInfo.systemUptime
            var previousRate = self.media.player.rate
            var playerPaused = false
            var lastMovement = Date()
            while !Task.isCancelled, self.generation == token, self.phase == .running {
                let now = self.media.player.currentTime().seconds
                let tick = ProcessInfo.processInfo.systemUptime
                // A delayed UI tick or faster playback is normal clock progress,
                // not a seek. Compare source advance against actual elapsed time.
                let allowedAdvance = max(0.35, (tick - previousTick) * Double(max(1, abs(previousRate), abs(self.media.player.rate))) + 0.2)
                guard now.isFinite else {
                    await self.stop()
                    self.report("無法讀取播放時間，請重新匯入媒體。")
                    return
                }
                do {
                    // AVPlayer can emit timeJumped at EOF. That is not a user seek:
                    // resetting here would abort the last inference and lose its text.
                    if now >= self.media.duration - 0.001 {
                        if now - previousTime > allowedAdvance {
                            // An explicit native seek to EOF must not transcribe the
                            // skipped remainder as though the user had listened to it.
                            // The timeJumped notification may arrive after this tick.
                            await self.transcriber.reset()
                            guard !Task.isCancelled, self.generation == token else { return }
                            try await self.media.reader.reset(at: now)
                            guard !Task.isCancelled, self.generation == token else { return }
                            self.partial = nil
                        }
                        try await self.feedPlayedMedia(until: self.media.duration, token: token)
                        await self.transcriber.finish()
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.media.pause()
                        self.phase = .paused
                        self.level = 0
                        self.status = "播放結束。可匯出字幕，或停止以釋放模型。"
                        return
                    }
                    // VideoPlayer's native transport can seek too. Invalidate old audio/results.
                    if self.media.jumpSerial != previousJump || now < previousTime - 0.15 || now - previousTime > allowedAdvance {
                        previousJump = self.media.jumpSerial
                        await self.transcriber.reset()
                        guard !Task.isCancelled, self.generation == token else { return }
                        try await self.media.reader.reset(at: now)
                        guard !Task.isCancelled, self.generation == token else { return }
                        self.partial = nil
                    }
                    if self.media.player.rate > 0 {
                        if playerPaused {
                            await self.transcriber.start(language: SourceLanguageCatalog.engineLanguage(for: self.language))
                            guard !Task.isCancelled, self.generation == token else { return }
                            playerPaused = false
                        }
                        for block in try await self.media.reader.read(until: now) {
                            guard !Task.isCancelled, self.generation == token else { return }
                            self.updateLevel(block.samples)
                            await self.transcriber.append(samples: block.samples, at: block.start)
                        }
                        if abs(now - previousTime) > 0.001 { lastMovement = Date() }
                        else if Date().timeIntervalSince(lastMovement) > 8 {
                            self.status = "播放尚未提供音訊。請檢查媒體是否可播放或受內容保護。"
                        }
                    } else if !playerPaused, self.phase == .running {
                        // Drain the final played interval before flushing the utterance.
                        try await self.feedPlayedMedia(until: self.media.player.currentTime().seconds, token: token)
                        guard !Task.isCancelled, self.generation == token else { return }
                        await self.transcriber.pause()
                        playerPaused = true
                        self.status = "播放已暫停，字幕會在繼續播放後恢復。"
                    }
                    if let failure = self.media.player.currentItem?.error { throw failure }
                    previousTime = now
                    previousTick = tick
                    previousRate = self.media.player.rate
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError { return }
                catch {
                    guard !Task.isCancelled, self.generation == token else { return }
                    await self.stop()
                    self.report(error.localizedDescription)
                    return
                }
            }
        }
    }

    private func feedPlayedMedia(until time: Double, token: UUID) async throws {
        while true {
            guard !Task.isCancelled, generation == token else { throw CancellationError() }
            let blocks = try await media.reader.read(until: time)
            guard !Task.isCancelled, generation == token else { throw CancellationError() }
            if blocks.isEmpty { return }
            for block in blocks {
                await transcriber.append(samples: block.samples, at: block.start)
                guard !Task.isCancelled, generation == token else { throw CancellationError() }
            }
        }
    }

    #if os(macOS)
    private func launchWatchdog(token: UUID) {
        lastAudio = Date()
        sourceTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                guard let self, self.generation == token, self.phase == .running else { return }
                if Date().timeIntervalSince(self.lastAudio) > 6 {
                    self.status = "尚未收到音訊。請播放內容並確認螢幕與系統音訊錄製權限；受保護內容可能無法擷取。"
                }
            }
        }
    }
    #endif

    private func updateLevel(_ samples: [Float]) {
        #if os(macOS)
        lastAudio = Date()
        #endif
        guard !samples.isEmpty else { return }
        level = min(1, sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)) * 8)
    }

    private func receive(_ event: TranscriptionEvent) {
        guard phase != .stopping else { return }
        #if os(macOS)
        // Reject queued results immediately on a foreground change, before the
        // asynchronous capture / inference teardown finishes.
        if source == .system, scopeWaiting || (scopeArmed && (!scopeAllowsAudio || scopeRevoked)) { return }
        #endif
        switch event {
        case .partial(let caption): partial = caption
        case .confirmed(let additions):
            let update = timeline.insert(additions)
            captions = timeline.cues
            alternatives = timeline.alternatives
            if !update.unretained.isEmpty {
                trimmedHistory = true
                Task {
                    await self.stop()
                    self.report("字幕記錄已達容量上限，已停止辨識。請先匯出，再清除歷史以繼續。")
                }
            }
        case .metrics(let value): metrics = value
        case .status(let state):
            if case .failed(let message) = state {
                guard phase != .idle, phase != .stopping else { return }
                report(message)
                let token = generation
                Task {
                    guard self.generation == token else { return }
                    await self.stop()
                    self.phase = .failed
                    self.report(message)
                }
                return
            }
            guard phase == .running else { return }
            switch state {
            case .processing: status = "正在辨識原文…"
            case .listening: status = "正在聆聽…"
            case .noAudio: status = "目前沒有偵測到足夠的語音訊號。請確認音量與播放內容。"
            default: break
            }
        }
    }

    isolated deinit {
        #if os(macOS)
        foregroundMonitor.stop()
        #endif
        eventTask?.cancel(); sourceTask?.cancel(); captureTask?.cancel()
        #if os(iOS)
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
        #endif
    }
}

enum SessionError: LocalizedError {
    case insufficientMemory
    var errorDescription: String? { "裝置記憶體不足以安全載入此模型。請改用 tiny、base 或 small。" }
}
