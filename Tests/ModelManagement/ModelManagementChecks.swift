import CryptoKit
import Foundation

enum CheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let value): value } }
}

@main struct ModelManagementChecks {
    @MainActor static func main() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live-caption-model-checks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("real integrity fixture".utf8)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let fixture = WhisperModel(id: "fixture", name: "Fixture", fileBytes: Int64(data.count),
                                   estimatedMemoryBytes: 0, recommendedRAMBytes: 0, sha256: digest)
        let file = root.appendingPathComponent(fixture.fileName)
        try data.write(to: file)
        try ModelIntegrity.verify(file, expectedBytes: fixture.fileBytes, sha256: digest)
        try expectFailure("wrong size is rejected") {
            try ModelIntegrity.verify(file, expectedBytes: 123, sha256: digest)
        }
        try expectFailure("wrong hash is rejected") {
            try ModelIntegrity.verify(file, expectedBytes: fixture.fileBytes, sha256: String(repeating: "0", count: 64))
        }
        let link = root.appendingPathComponent("linked.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)
        try expectFailure("symlinks are rejected") {
            try ModelIntegrity.verify(link, expectedBytes: fixture.fileBytes, sha256: digest)
        }
        print("PASS: streamed SHA-256, size rejection, checksum rejection, symlink rejection")

        let suite = "live-caption-checks-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let second = WhisperModel(id: "second", name: "Second", fileBytes: fixture.fileBytes,
                                  estimatedMemoryBytes: 0, recommendedRAMBytes: 0, sha256: digest)
        try data.write(to: root.appendingPathComponent(second.fileName))
        let store = ModelStore(storageURL: root, defaults: defaults, models: [fixture, second])
        // This happens synchronously, before the startup scanner Task can execute.
        try require(store.state(for: fixture) == .verifying && store.state(for: second) == .verifying,
                    "All existing models must be reserved for verification before init returns")
        store.download(second)
        try require(store.state(for: second) == .verifying && !store.canCancel(second),
                    "Immediate download must not bypass a queued startup integrity scan")
        try expectFailure("queued startup verification locks deletion") { try store.delete(second) }
        try await waitUntil(timeout: 10) { store.state(for: fixture).isInstalled && store.state(for: second).isInstalled }
        print("PASS: synchronous startup reservations prevent download/delete races for all queued models")
        try store.select(fixture)
        try require(store.selectedID == fixture.id, "selected model must persist")
        store.setInUse(fixture.id)
        try expectFailure("loaded model cannot be deleted") { try store.delete(fixture) }
        store.setInUse(nil)
        try store.delete(fixture)
        try require(store.selectedID == nil, "deleting selection must clear it")
        try require(!FileManager.default.fileExists(atPath: file.path), "delete must remove weights")
        try expectFailure("unverified model cannot load") { _ = try store.modelURL(for: fixture) }
        print("PASS: startup verification, selection, in-use deletion lock, deletion clears selection")

        var corrupted = data
        corrupted[0] = 0
        try corrupted.write(to: file)
        let invalidStore = ModelStore(storageURL: root, defaults: defaults, models: [fixture])
        try await waitUntil(timeout: 10) {
            if case .failed = invalidStore.state(for: fixture) { true } else { false }
        }
        try expectFailure("corrupt installed file cannot load") { _ = try invalidStore.modelURL(for: fixture) }
        print("PASS: existing corrupt model is not marked installed")

        let dangling = WhisperModel(id: "dangling", name: "Dangling", fileBytes: fixture.fileBytes,
                                    estimatedMemoryBytes: 0, recommendedRAMBytes: 0, sha256: digest)
        let danglingURL = root.appendingPathComponent(dangling.fileName)
        try FileManager.default.createSymbolicLink(at: danglingURL, withDestinationURL: root.appendingPathComponent("missing-target"))
        let danglingStore = ModelStore(storageURL: root, defaults: defaults, models: [dangling])
        try require(danglingStore.hasStoredFile(dangling), "Broken symbolic links still occupy the model filename")
        try await waitUntil(timeout: 10) {
            if case .failed = danglingStore.state(for: dangling) { true } else { false }
        }
        try danglingStore.delete(dangling)
        try require(!danglingStore.hasStoredFile(dangling), "Delete must remove a dangling model link so retry can install")
        print("PASS: dangling model links are rejected and removable instead of blocking retries")

        let blockedStorage = root.appendingPathComponent("not-a-directory")
        try data.write(to: blockedStorage)
        let blockedStore = ModelStore(storageURL: blockedStorage, defaults: defaults, models: [fixture])
        try require(blockedStore.storageError != nil, "A file used as model directory must expose storage failure")
        blockedStore.download(fixture)
        try require(!blockedStore.isBusy && !blockedStore.canCancel(fixture),
                    "Unavailable storage must not start a network transfer")
        if case .failed = blockedStore.state(for: fixture) { }
        else { throw CheckFailure.failed("Unavailable storage must preserve actionable failure state") }
        print("PASS: storage initialization failure prevents a pointless download")

        if CommandLine.arguments.contains("--network") {
            let networkDirectory = URL(fileURLWithPath: "/tmp/live-caption-verification-models", isDirectory: true)
            let actual = ModelStore(storageURL: networkDirectory, defaults: defaults)
            let tiny = WhisperModel.catalog.first { $0.id == "tiny" }!
            let networkFile = networkDirectory.appendingPathComponent(tiny.fileName)
            if FileManager.default.fileExists(atPath: networkFile.path) {
                try await waitUntil(timeout: 20) { actual.state(for: tiny).isInstalled }
                print("Existing verified tiny retained: \(networkFile.path)")
            } else {
                actual.download(tiny)
                try await Task.sleep(for: .milliseconds(150))
                try require(actual.state(for: tiny).isBusy, "first download should be active before cancellation")
                actual.cancel(tiny)
                try require(actual.state(for: tiny) == .notInstalled, "cancel must remove usable state immediately")
                try require(!FileManager.default.fileExists(atPath: networkFile.path), "cancel must not publish a model")
                // Immediate retry deliberately overlaps teardown to exercise operation-ID protection.
                actual.download(tiny)
                var reportedProgress = -1
                try await waitUntil(timeout: 600) {
                    switch actual.state(for: tiny) {
                    case .failed(let error): throw CheckFailure.failed(error)
                    case .downloading(let progress):
                        let tenth = Int(progress * 10)
                        if tenth != reportedProgress { print("Tiny download \(tenth * 10)%"); reportedProgress = tenth }
                    default: break
                    }
                    return actual.state(for: tiny).isInstalled
                }
                print("PASS: actual URLSession cancel, immediate retry, SHA-256 verification, atomic installation")
            }
            try actual.select(tiny)
            print("VERIFIED_MODEL=\(try actual.modelURL(for: tiny).path)")
            print("SHA256=\(tiny.sha256)")
        }
        print("All model-management checks passed.")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw CheckFailure.failed(message) }
    }
    static func expectFailure(_ name: String, operation: () throws -> Void) throws {
        do { try operation() } catch { return }
        throw CheckFailure.failed(name)
    }
    @MainActor static func waitUntil(timeout: TimeInterval, condition: () throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while try !condition() {
            if Date() >= deadline { throw CheckFailure.failed("Timed out after \(timeout) seconds") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}
