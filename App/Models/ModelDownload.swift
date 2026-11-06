import Foundation

/// URLSession writes directly to disk. No model-sized Data is held in memory.
/// Delegate callbacks use a serial OperationQueue; mutable transfer state is lock protected.
final class ModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let destination: URL
    private let expectedBytes: Int64
    private let onProgress: @Sendable (Double) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var downloadTask: URLSessionDownloadTask?
    private var session: URLSession?
    private var savedResult: Result<URL, Error>?
    private var cancelled = false
    private var exceededExpectedSize: Int64?

    init(destination: URL, expectedBytes: Int64, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.expectedBytes = expectedBytes
        self.onProgress = onProgress
    }

    func run(url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                start(url: url, continuation: continuation)
            }
        } onCancel: { self.cancel() }
    }

    private func start(url: URL, continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        if cancelled {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 24 * 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.waitsForConnectivity = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        queue.qualityOfService = .utility
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        self.session = session
        var request = URLRequest(url: url)
        request.setValue("LiveCaption/1.0", forHTTPHeaderField: "User-Agent")
        let task = session.downloadTask(with: request)
        self.downloadTask = task
        task.resume()
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let task = downloadTask
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // Compare against the pinned manifest, not an untrusted response header.
        onProgress(min(1, max(0, Double(totalBytesWritten) / Double(expectedBytes))))
        if totalBytesWritten > expectedBytes {
            lock.lock()
            exceededExpectedSize = totalBytesWritten
            lock.unlock()
            downloadTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        let result: Result<URL, Error>
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw ModelStoreError.badResponse((downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0)
            }
            // Move before this callback returns: URLSession removes its temporary file immediately.
            try FileManager.default.moveItem(at: location, to: destination)
            result = .success(destination)
        } catch {
            result = .failure(error)
        }
        lock.lock()
        savedResult = result
        lock.unlock()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let result: Result<URL, Error>
        if cancelled { result = .failure(CancellationError()) }
        else if let actual = exceededExpectedSize {
            result = .failure(ModelStoreError.wrongSize(expected: expectedBytes, actual: actual))
        }
        else if let error { result = .failure(error) }
        else { result = savedResult ?? .failure(ModelStoreError.invalidFile) }
        self.downloadTask = nil
        self.session = nil
        lock.unlock()
        if case .failure = result { try? FileManager.default.removeItem(at: destination) }
        continuation?.resume(with: result)
        session.finishTasksAndInvalidate()
    }
}
