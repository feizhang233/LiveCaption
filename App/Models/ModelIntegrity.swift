import CryptoKit
import Foundation

enum ModelIntegrity {
    /// Reads only one MiB at a time. Call on a detached task, never the UI executor.
    nonisolated static func verify(_ url: URL, expectedBytes: Int64, sha256: String) throws {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw ModelStoreError.invalidFile
        }
        let actual = Int64(values.fileSize ?? -1)
        guard actual == expectedBytes else {
            throw ModelStoreError.wrongSize(expected: expectedBytes, actual: actual)
        }
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let data = try file.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hash.update(data: data)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard digest == sha256.lowercased() else { throw ModelStoreError.checksumMismatch }
        try Task.checkCancellation()
    }
}
