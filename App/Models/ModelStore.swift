import Foundation
import Observation

@MainActor @Observable
final class ModelStore {
    let models: [WhisperModel]
    private(set) var states: [String: ModelInstallState] = [:]
    private(set) var selectedID: String?
    private(set) var activeModelID: String?
    private(set) var availableDiskBytes: Int64?
    private(set) var storageError: String?
    let physicalMemoryBytes = ProcessInfo.processInfo.physicalMemory
    let storageURL: URL

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var operations: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var operationIDs: [String: UUID] = [:]
    @ObservationIgnored private var scanTask: Task<Void, Never>?
    private static let selectionKey = "livecaption.selectedModel"

    var selectedModel: WhisperModel? { models.first { $0.id == selectedID } }
    var isBusy: Bool { states.values.contains(where: \.isBusy) }
    var formattedAvailableSpace: String {
        availableDiskBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "無法讀取"
    }

    init(storageURL: URL? = nil, defaults: UserDefaults = .standard,
         models: [WhisperModel] = WhisperModel.catalog) {
        self.models = models
        self.defaults = defaults
        self.storageURL = storageURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LiveCaption/Models", isDirectory: true)
        let savedID = defaults.string(forKey: Self.selectionKey)
        self.selectedID = models.contains(where: { $0.id == savedID }) ? savedID : nil
        for model in models { states[model.id] = .notInstalled }
        do {
            try FileManager.default.createDirectory(at: self.storageURL, withIntermediateDirectories: true)
            var excluded = self.storageURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try excluded.setResourceValues(values)
            // Downloads never survive as "installed" after a crash. Clear only our own staging files.
            let staging = self.storageURL.appendingPathComponent("Downloads", isDirectory: true)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            for file in try FileManager.default.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil)
                where file.pathExtension == "partial" {
                try? FileManager.default.removeItem(at: file)
            }
            refreshStorage()
            // Reserve every existing file before init returns. Otherwise a caller
            // can start a new download before the startup Task gets its first turn.
            let existing = models.filter {
                Self.itemExists(at: self.storageURL.appendingPathComponent($0.fileName))
            }
            for model in existing {
                states[model.id] = .verifying
                operationIDs[model.id] = UUID()
            }
            scanTask = Task { [weak self] in await self?.validateExistingFiles(existing) }
        } catch {
            storageError = "無法建立模型儲存區：\(error.localizedDescription)"
        }
    }

    func state(for model: WhisperModel) -> ModelInstallState { states[model.id] ?? .notInstalled }
    func hasStoredFile(_ model: WhisperModel) -> Bool {
        Self.itemExists(at: storageURL.appendingPathComponent(model.fileName))
    }
    func canCancel(_ model: WhisperModel) -> Bool { operations[model.id] != nil }

    func refreshStorage() {
        do {
            let values = try storageURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey,
                                                                 .volumeAvailableCapacityKey])
            availableDiskBytes = values.volumeAvailableCapacityForImportantUsage
                ?? values.volumeAvailableCapacity.map(Int64.init)
        } catch { availableDiskBytes = nil }
    }

    /// Root coordinator locks the ID before loading; clears it on failure or after unloading.
    func setInUse(_ id: String?) { activeModelID = id }

    func select(_ model: WhisperModel) throws {
        guard activeModelID == nil || activeModelID == model.id else { throw ModelStoreError.inUse }
        guard state(for: model).isInstalled else { throw ModelStoreError.notInstalled }
        selectedID = model.id
        defaults.set(model.id, forKey: Self.selectionKey)
    }

    func modelURL(for model: WhisperModel) throws -> URL {
        guard state(for: model).isInstalled else { throw ModelStoreError.notInstalled }
        let url = storageURL.appendingPathComponent(model.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            states[model.id] = .failed("模型檔案已遺失，請重新下載。")
            throw ModelStoreError.notInstalled
        }
        return url
    }

    func download(_ model: WhisperModel) {
        guard models.contains(model), !state(for: model).isInstalled else { return }
        if let storageError { states[model.id] = .failed(storageError); return }
        guard activeModelID != model.id else { states[model.id] = .failed(ModelStoreError.inUse.localizedDescription); return }
        guard !isBusy else { return }
        refreshStorage()
        guard let available = availableDiskBytes else {
            states[model.id] = .failed(ModelStoreError.spaceUnavailable.localizedDescription)
            return
        }
        // Keep 256 MiB for filesystem operations and the rest of the app.
        let required = model.fileBytes + 256 * 1_048_576
        guard available >= required else {
            states[model.id] = .failed(ModelStoreError.insufficientSpace(required: required, available: available).localizedDescription)
            return
        }
        let operationID = UUID()
        operationIDs[model.id] = operationID
        states[model.id] = .downloading(progress: 0)
        let temporary = storageURL.appendingPathComponent("Downloads/\(operationID.uuidString).partial")
        operations[model.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                try? FileManager.default.removeItem(at: temporary)
                if self.operationIDs[model.id] == operationID {
                    self.operations[model.id] = nil
                    self.operationIDs[model.id] = nil
                }
                self.refreshStorage()
            }
            do {
                let downloader = ModelDownload(destination: temporary, expectedBytes: model.fileBytes) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.operationIDs[model.id] == operationID,
                              case .downloading = self.states[model.id] else { return }
                        self.states[model.id] = .downloading(progress: progress)
                    }
                }
                let url = try await downloader.run(url: model.downloadURL)
                try Task.checkCancellation()
                guard self.operationIDs[model.id] == operationID else { return }
                self.states[model.id] = .verifying
                let verification = Task.detached(priority: .utility) {
                    try ModelIntegrity.verify(url, expectedBytes: model.fileBytes, sha256: model.sha256)
                }
                try await withTaskCancellationHandler {
                    try await verification.value
                } onCancel: { verification.cancel() }
                try Task.checkCancellation()
                guard self.operationIDs[model.id] == operationID else { return }
                let destination = self.storageURL.appendingPathComponent(model.fileName)
                if Self.itemExists(at: destination) {
                    // Any previous file here failed validation; it was never available to the engine.
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: url, to: destination)
                self.states[model.id] = .installed
            } catch {
                guard self.operationIDs[model.id] == operationID else { return }
                let networkError = error as NSError
                if error is CancellationError || (networkError.domain == NSURLErrorDomain && networkError.code == NSURLErrorCancelled) {
                    self.states[model.id] = .notInstalled
                } else {
                    self.states[model.id] = .failed(error.localizedDescription)
                }
            }
        }
    }

    func cancel(_ model: WhisperModel) {
        guard let task = operations[model.id] else { return }
        // Invalidate progress/completion first. A retry cannot receive an old transfer's callbacks.
        operationIDs[model.id] = nil
        operations[model.id] = nil
        states[model.id] = .notInstalled
        task.cancel()
    }

    func delete(_ model: WhisperModel) throws {
        guard activeModelID != model.id else { throw ModelStoreError.inUse }
        guard !state(for: model).isBusy else { throw ModelStoreError.busy }
        let url = storageURL.appendingPathComponent(model.fileName)
        if Self.itemExists(at: url) { try FileManager.default.removeItem(at: url) }
        states[model.id] = .notInstalled
        if selectedID == model.id {
            selectedID = nil
            defaults.removeObject(forKey: Self.selectionKey)
        }
        refreshStorage()
    }

    private func validateExistingFiles(_ existing: [WhisperModel]) async {
        defer { scanTask = nil; refreshStorage() }
        for model in existing {
            let url = storageURL.appendingPathComponent(model.fileName)
            guard let operationID = operationIDs[model.id], operations[model.id] == nil else { continue }
            do {
                try await Task.detached(priority: .utility) {
                    try ModelIntegrity.verify(url, expectedBytes: model.fileBytes, sha256: model.sha256)
                }.value
                guard operationIDs[model.id] == operationID else { continue }
                states[model.id] = .installed
            } catch {
                guard operationIDs[model.id] == operationID else { continue }
                states[model.id] = .failed(error.localizedDescription)
            }
            operationIDs[model.id] = nil
        }
    }

    private static func itemExists(at url: URL) -> Bool {
        // fileExists follows symlinks and returns false for a dangling one.
        // The link still occupies the filename and must be rejected/removable.
        FileManager.default.fileExists(atPath: url.path)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
