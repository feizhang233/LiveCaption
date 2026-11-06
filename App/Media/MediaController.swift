import AVFoundation
import Foundation
import Observation

struct MediaPCMBlock: Sendable {
    let samples: [Float]
    let start: Double
}

enum MediaError: LocalizedError {
    case protectedContent, noAudio, importInProgress, decoding(String)
    var errorDescription: String? {
        switch self {
        case .protectedContent: return "此媒體受內容保護，無法擷取音訊。請使用可讀取的本機音訊或影片。"
        case .noAudio: return "此檔案沒有可讀取的音軌。請選擇另一個音訊或影片。"
        case .importInProgress: return "正在開啟另一個媒體，請等待完成後再選擇檔案。"
        case .decoding(let reason): return "音訊讀取失敗：\(reason)"
        }
    }
}

/// Decodes a bounded amount of local media. It never transcribes ahead of playback.
actor MediaPCMReader {
    private var asset: AVURLAsset?
    private var track: AVAssetTrack?
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    private var pending: MediaPCMBlock?
    private var duration: Double = 0
    private var loadingAsset: AVURLAsset?
    private var openRevision: UInt64 = 0
    var isOpening: Bool { loadingAsset != nil }

    func open(url: URL) async throws -> Double {
        try Task.checkCancellation()
        openRevision &+= 1
        let revision = openRevision
        loadingAsset?.cancelLoading()
        discardReader()
        let asset = AVURLAsset(url: url)
        loadingAsset = asset
        do {
            let protected = try await asset.load(.hasProtectedContent)
            try checkOpenRevision(revision)
            guard !protected else { throw MediaError.protectedContent }
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            try checkOpenRevision(revision)
            guard let track = tracks.first else { throw MediaError.noAudio }
            let seconds = try await asset.load(.duration).seconds
            try checkOpenRevision(revision)
            guard seconds.isFinite, seconds > 0 else { throw MediaError.decoding("媒體長度無效") }
            self.asset = asset
            self.track = track
            duration = seconds
            try reset(at: 0)
            loadingAsset = nil
            return seconds
        } catch {
            // close() or a newer open owns the reader now; an old completion
            // must neither resurrect the old source nor clear the new source.
            guard openRevision == revision else { throw CancellationError() }
            loadingAsset?.cancelLoading()
            loadingAsset = nil
            discardReader()
            throw error
        }
    }

    func reset(at time: Double) throws {
        reader?.cancelReading()
        reader = nil; output = nil; pending = nil
        guard let asset, let track else { return }
        guard time.isFinite else { throw MediaError.decoding("跳轉時間無效") }
        if time >= duration - 0.000_01 { return }
        let next = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ])
        output.alwaysCopiesSampleData = false
        guard next.canAdd(output) else { throw MediaError.noAudio }
        next.add(output)
        let start = min(max(0, time), duration)
        next.timeRange = CMTimeRange(start: CMTime(seconds: start, preferredTimescale: 16_000),
                                    duration: CMTime(seconds: max(0, duration - start), preferredTimescale: 16_000))
        guard next.startReading() else { throw MediaError.decoding(next.error?.localizedDescription ?? "無法啟動解碼") }
        reader = next
        self.output = output
    }

    func read(until time: Double) throws -> [MediaPCMBlock] {
        guard let reader, let output else { return [] }
        guard time.isFinite else { throw MediaError.decoding("播放時間無效") }
        if reader.status == .cancelled || (reader.status == .completed && pending == nil) { return [] }
        var blocks: [MediaPCMBlock] = []
        var total = 0
        // Maximum half a second per call. The next playback tick drains the rest.
        while total < 8_000 {
            let block: MediaPCMBlock
            if let saved = pending { block = saved; pending = nil }
            else {
                guard let buffer = output.copyNextSampleBuffer() else {
                    if reader.status == .failed { throw MediaError.decoding(reader.error?.localizedDescription ?? "解碼中斷") }
                    break
                }
                guard let data = CMSampleBufferGetDataBuffer(buffer) else { continue }
                let bytes = CMBlockBufferGetDataLength(data)
                guard bytes > 0, bytes <= 4 * 16_000 * 4, bytes % 4 == 0 else {
                    throw MediaError.decoding("音訊區塊格式或大小無效")
                }
                var samples = [Float](repeating: 0, count: bytes / 4)
                let result = samples.withUnsafeMutableBytes { raw in
                    CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: bytes, destination: raw.baseAddress!)
                }
                guard result == kCMBlockBufferNoErr else { throw MediaError.decoding("無法讀取 PCM") }
                let start = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
                guard start.isFinite else { throw MediaError.decoding("音訊時間戳無效") }
                block = MediaPCMBlock(samples: samples, start: start)
            }
            // Clamp in floating point before conversion; very large finite
            // times can overflow Int (or overflow the multiplication to infinity).
            let played = Int(min(Double(block.samples.count), max(0, time - block.start) * 16_000))
            let count = min(played, 8_000 - total)
            if count > 0 {
                blocks.append(MediaPCMBlock(samples: Array(block.samples.prefix(count)), start: block.start))
                total += count
            }
            if count < block.samples.count {
                pending = MediaPCMBlock(samples: Array(block.samples.dropFirst(count)), start: block.start + Double(count) / 16_000)
                break
            }
        }
        return blocks
    }

    func close() {
        openRevision &+= 1
        loadingAsset?.cancelLoading()
        loadingAsset = nil
        discardReader()
    }

    private func checkOpenRevision(_ revision: UInt64) throws {
        try Task.checkCancellation()
        guard revision == openRevision else { throw CancellationError() }
    }

    private func discardReader() {
        reader?.cancelReading()
        reader = nil; output = nil; pending = nil; asset = nil; track = nil
        duration = 0
    }
}

@MainActor @Observable
final class MediaController {
    let player = AVPlayer()
    let reader = MediaPCMReader()
    var title: String?
    var duration: Double = 0
    var currentTime: Double = 0
    var isPlaying = false
    var isLoading = false
    private(set) var jumpSerial: UInt64 = 0
    var isReady: Bool { title != nil }
    @ObservationIgnored private var scopedURL: URL?
    @ObservationIgnored private var hasScope = false
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var jumpObserver: NSObjectProtocol?
    @ObservationIgnored private var itemRevision: UInt64 = 0

    init() {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                // A queued callback may belong to an item that was just replaced.
                let time = self.player.currentTime().seconds
                self.currentTime = self.isReady && time.isFinite ? time : 0
                self.isPlaying = self.isReady && self.player.rate > 0
            }
        }
        jumpObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.timeJumpedNotification, object: nil, queue: .main) { [weak self] note in
            guard let item = note.object as? AVPlayerItem else { return }
            MainActor.assumeIsolated {
                guard let self, item === self.player.currentItem else { return }
                self.jumpSerial &+= 1
            }
        }
    }

    func open(_ url: URL) async throws {
        guard !isLoading else { throw MediaError.importInProgress }
        try Task.checkCancellation()
        isLoading = true
        defer { isLoading = false }
        itemRevision &+= 1
        player.pause()
        player.replaceCurrentItem(with: nil)
        title = nil; duration = 0; currentTime = 0; isPlaying = false
        await reader.close()
        if hasScope { scopedURL?.stopAccessingSecurityScopedResource() }
        scopedURL = url
        hasScope = url.startAccessingSecurityScopedResource()
        do {
            try Task.checkCancellation()
            duration = try await reader.open(url: url)
            try Task.checkCancellation()
            player.replaceCurrentItem(with: AVPlayerItem(url: url))
            title = url.lastPathComponent
            currentTime = 0
        } catch {
            // Release access only after every reader reference to the URL closes.
            await reader.close()
            if hasScope { url.stopAccessingSecurityScopedResource() }
            scopedURL = nil; hasScope = false
            title = nil; duration = 0; currentTime = 0; isPlaying = false
            throw error
        }
    }

    func play() {
        guard isReady, !isLoading, player.currentItem != nil else { isPlaying = false; return }
        player.play()
        isPlaying = true
    }
    func pause() { player.pause(); isPlaying = false }
    func seek(to time: Double) async {
        guard isReady, !isLoading, !Task.isCancelled, time.isFinite, let item = player.currentItem else { return }
        itemRevision &+= 1
        let revision = itemRevision
        let target = CMTime(seconds: min(max(0, time), duration), preferredTimescale: 16_000)
        let completed = await player.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
        guard completed, !Task.isCancelled, revision == itemRevision, player.currentItem === item else { return }
        currentTime = target.seconds
    }

    isolated deinit {
        player.pause()
        player.replaceCurrentItem(with: nil)
        if let observer { player.removeTimeObserver(observer) }
        if let jumpObserver { NotificationCenter.default.removeObserver(jumpObserver) }
        let reader = reader
        let url = scopedURL
        let wasScoped = hasScope
        Task {
            await reader.close()
            if wasScoped { url?.stopAccessingSecurityScopedResource() }
        }
    }
}
