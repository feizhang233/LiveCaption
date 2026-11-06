import Foundation
import Metal
import os
import whisper

public protocol SpeechRecognizing: Actor {
    func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment]
    nonisolated func cancel()
    func unload() async
}

public enum WhisperEngineError: LocalizedError, Sendable {
    case modelMissing, modelLoadFailed, notLoaded, invalidAudio, inferenceFailed(Int32), unsupportedLanguage(String)
    case insufficientMemory
    public var errorDescription: String? {
        switch self {
        case .modelMissing: return "找不到模型檔案，請在模型管理重新下載。"
        case .modelLoadFailed: return "模型載入失敗。請釋放記憶體、選擇較小模型，或重新驗證模型。"
        case .notLoaded: return "請先選擇已下載的模型。"
        case .invalidAudio: return "音訊格式不正確：需要 16 kHz 單聲道音訊。"
        case .inferenceFailed(let code): return "本機辨識失敗（\(code)）。請停止後重試，或選擇較小模型。"
        case .unsupportedLanguage(let code): return "不支援來源語言：\(code)。"
        case .insufficientMemory: return "目前可用的 App 記憶體不足以安全載入此模型。請選擇較小模型或關閉其他 App 後重試。"
        }
    }
}

/// The C abort callback runs on engine worker threads. Its only shared state is lock protected.
final class EngineCancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var aborted = false
    func cancel() { lock.lock(); aborted = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return aborted }
}

/// Each operation owns its flag permanently. A late cancellation handler from
/// an earlier Task must never mutate the flag of a subsequent decode.
final class EngineCancellationSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var current: EngineCancellationFlag?
    func begin() -> EngineCancellationFlag {
        let flag = EngineCancellationFlag()
        lock.lock(); current = flag; lock.unlock()
        return flag
    }
    func end(_ flag: EngineCancellationFlag) {
        lock.lock(); defer { lock.unlock() }
        if current === flag { current = nil }
    }
    func cancel() {
        lock.lock(); let flag = current; lock.unlock()
        flag?.cancel()
    }
}

/// One actor owns one C context. Every load, decode and free is serialized off MainActor.
/// cancel() intentionally bypasses the actor so a synchronous C decode can be interrupted.
public actor WhisperEngine: SpeechRecognizing {
    /// Language codes/names come from the pinned engine, never a drifting list.
    public nonisolated static var supportedLanguages: [String: String] {
        var result: [String: String] = [:]
        for id in 0...whisper_lang_max_id() {
            if let code = whisper_lang_str(id), let name = whisper_lang_str_full(id) {
                result[String(cString: code)] = String(cString: name)
            }
        }
        return result
    }
    private var context: OpaquePointer?
    private nonisolated let cancellation = EngineCancellationSlot()
    public private(set) var loadedModelURL: URL?
    public private(set) var usingGPU = false
    public init() {}

    deinit { if let context { whisper_free(context) } }

    public nonisolated func cancel() { cancellation.cancel() }

    public func load(modelURL: URL, useGPU: Bool = true) async throws {
        try Task.checkCancellation()
        let flag = cancellation.begin()
        defer { cancellation.end(flag) }
        guard FileManager.default.fileExists(atPath: modelURL.path) else { throw WhisperEngineError.modelMissing }
        if let context { whisper_free(context); self.context = nil }
        loadedModelURL = nil; usingGPU = false
        #if os(iOS)
        // This is a conservative snapshot, not a promise that jetsam cannot occur.
        // It is intentionally separate from download/file-size checks.
        let fileBytes = (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let estimatedBytes = UInt64(Double(fileBytes) * 1.8) + 256 * 1024 * 1024
        let remaining = os_proc_available_memory()
        if remaining > 0 && estimatedBytes > UInt64(remaining) { throw WhisperEngineError.insufficientMemory }
        #endif
        var options = whisper_context_default_params()
        // Some restricted hosts enumerate Metal devices but deny allocations.
        // Upstream ggml asserts on failed GPU allocation, so probe before loading.
        let gpuAvailable = useGPU && Self.canAllocateMetalBuffer()
        options.use_gpu = gpuAvailable
        options.flash_attn = true
        if Task.isCancelled || flag.isCancelled { throw CancellationError() }
        var loaded = modelURL.path.withCString { whisper_init_from_file_with_params($0, options) }
        var gpu = gpuAvailable
        if loaded == nil && gpuAvailable && !flag.isCancelled && !Task.isCancelled {
            options.use_gpu = false
            loaded = modelURL.path.withCString { whisper_init_from_file_with_params($0, options) }
            gpu = false
        }
        if Task.isCancelled || flag.isCancelled {
            if let loaded { whisper_free(loaded) }
            throw CancellationError()
        }
        guard let loaded else { throw WhisperEngineError.modelLoadFailed }
        context = loaded
        loadedModelURL = modelURL
        usingGPU = gpu
    }

    private nonisolated static func canAllocateMetalBuffer() -> Bool {
        #if targetEnvironment(simulator)
        // Simulator Metal can pass a small allocation probe yet abort in ggml
        // when copying model weights. It is not the device's Metal backend.
        // Keep simulator inference on the tested CPU path explicitly.
        return false
        #else
        guard let device = MTLCreateSystemDefaultDevice() else { return false }
        guard device.recommendedMaxWorkingSetSize > 0 else { return false }
        return autoreleasepool { device.makeBuffer(length: 4 * 1024 * 1024, options: .storageModePrivate) != nil }
        #endif
    }

    public func unload() {
        if let context { whisper_free(context) }
        context = nil; loadedModelURL = nil; usingGPU = false
    }

    public func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment] {
        try Task.checkCancellation()
        let flag = cancellation.begin()
        defer { cancellation.end(flag) }
        guard let context else { throw WhisperEngineError.notLoaded }
        guard !samples.isEmpty, samples.count <= 30 * 16_000,
              samples.allSatisfy(\.isFinite) else { throw WhisperEngineError.invalidAudio }
        if let language, language != "auto", whisper_lang_id(language) < 0 {
            throw WhisperEngineError.unsupportedLanguage(language)
        }
        return try await withTaskCancellationHandler(operation: {
            var options = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            options.n_threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
            options.translate = false
            options.no_context = true
            options.no_timestamps = false
            options.single_segment = false
            options.print_special = false
            options.print_progress = false
            options.print_realtime = false
            options.print_timestamps = false
            options.suppress_blank = true
            options.suppress_nst = true
            options.temperature = 0
            options.temperature_inc = 0
            options.no_speech_thold = 0.6
            // detect_language=true only returns the language; "auto" with false transcribes.
            options.detect_language = false
            options.abort_callback_user_data = Unmanaged.passUnretained(flag).toOpaque()
            options.abort_callback = { pointer in
                guard let pointer else { return false }
                return Unmanaged<EngineCancellationFlag>.fromOpaque(pointer).takeUnretainedValue().isCancelled
            }
            let duration = Double(samples.count) / 16_000
            // whisper expects >= 1 second; pad short final speech without shifting its origin.
            let padded = samples.count < 16_000 ? samples + Array(repeating: 0, count: 16_000 - samples.count) : samples
            let code = (language ?? "auto").withCString { languagePointer in
                options.language = languagePointer
                return padded.withUnsafeBufferPointer { buffer in
                    whisper_full(context, options, buffer.baseAddress, Int32(buffer.count))
                }
            }
            if flag.isCancelled || Task.isCancelled { throw CancellationError() }
            guard code == 0 else { throw WhisperEngineError.inferenceFailed(code) }
            var result: [RecognitionSegment] = []
            for i in 0..<whisper_full_n_segments(context) {
                guard let textPointer = whisper_full_get_segment_text(context, i) else { continue }
                let text = String(cString: textPointer).trimmingCharacters(in: .whitespacesAndNewlines)
                let start = max(0, min(duration, Double(whisper_full_get_segment_t0(context, i)) * 0.01))
                let end = max(start, min(duration, Double(whisper_full_get_segment_t1(context, i)) * 0.01))
                if TranscriptText.containsSpokenContent(text) && end > start {
                    result.append(.init(start: start, end: end, text: text))
                }
            }
            return result
        }, onCancel: { flag.cancel() })
    }
}
