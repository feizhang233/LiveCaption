import AVFoundation
import CaptionCore
import Foundation
import Observation
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
    let preferences = AppPreferences()
    var source: CaptionSource = .media
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
    var overlayVisible = false
    var clickThrough = false
    var alwaysOnTop = true
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
    @ObservationIgnored private var lastAudio = Date()
    @ObservationIgnored private var lifecycleObservers: [NSObjectProtocol] = []
    @ObservationIgnored private let defaults: UserDefaults
    #if os(macOS)
    @ObservationIgnored let capture = MacSystemAudioCapture()
    @ObservationIgnored let panel = CaptionPanelController()
    #endif

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
        if let partial { return partial }
        if source == .media {
            return captions.last { $0.start <= media.currentTime && $0.end + 2 >= media.currentTime }
        }
        return captions.last
    }

    init(models: ModelStore? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        selectedLanguageCode = SourceLanguageCatalog.validatedCode(defaults.string(forKey: Self.languagePreferenceKey))
        self.models = models ?? ModelStore()
        engine = WhisperEngine()
        transcriber = StreamingTranscriber(engine: engine)
        let stream = transcriber.taggedEvents
        eventTask = Task { [weak self] in
            for await envelope in stream {
                guard let self, envelope.generation == self.transcriber.currentGeneration else { continue }
                self.receive(envelope.event)
            }
        }
        #if os(iOS)
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
        #endif
    }

    func report(_ message: String) { errorMessage = message; status = message }
    func clearError() { errorMessage = nil }

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
        if phase == .running {
            if isPlaybackPaused { media.play() }
            else { await pause() }
        } else { await start() }
    }

    func start() async {
        guard canStart, let model = models.selectedModel else { return }
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
            await transcriber.start(language: SourceLanguageCatalog.engineLanguage(for: language))
            guard generation == token else { return }
            if source == .media {
                if media.currentTime >= media.duration - 0.05 {
                    await media.seek(to: 0)
                    guard generation == token else { return }
                }
                try await media.reader.reset(at: media.currentTime)
                guard generation == token else { return }
                await transcriber.reset(at: media.currentTime)
                guard generation == token else { return }
                try await audioSession.activate()
                guard generation == token else { return }
                media.play()
                phase = .running
                launchMediaFeed(token: token)
            } else {
                #if os(macOS)
                let offset = ProcessInfo.processInfo.systemUptime - sessionStart
                let chunks = try await capture.start(onError: { [weak self] message in
                    Task { @MainActor in
                        guard let self, self.generation == token,
                              self.phase == .running || self.phase == .loading else { return }
                        await self.stop()
                        self.report(message)
                    }
                })
                guard generation == token else { await capture.stop(); return }
                phase = .running
                let priorDropped = inputDroppedSeconds
                captureTask = Task { [weak self] in
                    for await chunk in chunks {
                        guard let self, !Task.isCancelled, self.generation == token, self.phase == .running else { return }
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
    }

    func clearHistory() async {
        await transcriber.reset(at: source == .media ? media.currentTime : 0)
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
        await transcriber.reset(at: time)
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

    func backgrounded() async {
        #if os(iOS)
        guard phase != .idle && phase != .failed else { return }
        await stop()
        status = "App 已進入背景，字幕已停止並釋放模型。返回後可繼續播放辨識。"
        #endif
    }

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
                            await self.transcriber.reset(at: now)
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
                        await self.transcriber.reset(at: now)
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

    private func updateLevel(_ samples: [Float]) {
        lastAudio = Date()
        guard !samples.isEmpty else { return }
        level = min(1, sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)) * 8)
    }

    private func receive(_ event: TranscriptionEvent) {
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
        eventTask?.cancel(); sourceTask?.cancel(); captureTask?.cancel()
        for observer in lifecycleObservers { NotificationCenter.default.removeObserver(observer) }
    }
}

enum SessionError: LocalizedError {
    case insufficientMemory
    var errorDescription: String? { "裝置記憶體不足以安全載入此模型。請改用 tiny、base 或 small。" }
}
