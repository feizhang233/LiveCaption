#if os(iOS)
import AVFoundation
import AVKit
import Observation
import UIKit

/// Displays captions for the app's real local-media playback using system PiP.
/// This controller neither captures other apps nor creates a background audio source.
@MainActor
@Observable
final class CaptionPictureInPictureController: NSObject {
    struct Snapshot {
        var text: String
        var status: String
        var isReady: Bool
        var isPlaying: Bool
        var currentTime: Double
        var duration: Double
        var fontScale: Double = 1
    }

    private(set) var isSupported = false
    private(set) var isPossible = false
    private(set) var isActive = false
    private(set) var isStarting = false
    private(set) var status = "播放本機媒體後，可開啟浮動字幕"

    @ObservationIgnored let surface = CaptionPictureInPictureSurface()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var possibilityObservation: NSKeyValueObservation?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var startTimeout: Task<Void, Never>?
    @ObservationIgnored private var snapshotProvider: (() -> Snapshot)?
    @ObservationIgnored private var setPlaying: ((Bool) async -> Void)?
    @ObservationIgnored private var skip: ((Double) async -> Void)?
    @ObservationIgnored private var didStop: (() async -> Void)?
    @ObservationIgnored private var wantsPictureInPicture = false
    @ObservationIgnored private var lastFrameText: String?
    @ObservationIgnored private var lastFontScale: Double = 1
    @ObservationIgnored private var lastPlaying = false
    @ObservationIgnored private var lastDuration: Double = 0
    // AVKit may ask synchronous playback questions off the main actor.
    nonisolated private let playback = CaptionPiPPlaybackState()

    override init() {
        super.init()
        isSupported = AVPictureInPictureController.isPictureInPictureSupported()
        var timebase: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr,
              let timebase else {
            isSupported = false
            status = "無法建立浮動字幕的播放時鐘"
            return
        }
        CMTimebaseSetTime(timebase, time: .zero)
        CMTimebaseSetRate(timebase, rate: 0)
        surface.displayLayer.controlTimebase = timebase
        surface.displayLayer.videoGravity = .resizeAspect
        surface.backgroundColor = .black
        surface.accessibilityLabel = "浮動字幕預覽"
        surface.onWindowChanged = { [weak self] in self?.updateRefreshLoop() }
        // Inline caption rendering works even in an environment without PiP
        // (including some simulator runtimes); it does not imply PiP support.
        render(text: "播放本機媒體後，字幕會顯示在這裡", fontScale: 1, time: .zero)
        guard isSupported else {
            status = "這個裝置環境不支援畫中畫字幕"
            return
        }
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: surface.displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        self.controller = controller
        controller.delegate = self
        controller.canStartPictureInPictureAutomaticallyFromInline = false
        // The real finite media timeline and transport callbacks remain available.
        controller.requiresLinearPlayback = false
        possibilityObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { [weak self] _, change in
            let possible = change.newValue ?? false
            Task { @MainActor [weak self] in self?.isPossible = possible }
        }
    }

    /// The owner supplies the same caption and transport used by the main player.
    /// didStop also runs when a requested start fails or times out.
    func bind(snapshot: @escaping () -> Snapshot,
              setPlaying: @escaping (Bool) async -> Void,
              skip: @escaping (Double) async -> Void,
              didStop: @escaping () async -> Void) {
        snapshotProvider = snapshot
        self.setPlaying = setPlaying
        self.skip = skip
        self.didStop = didStop
        refresh()
    }

    /// Returns whether a request was submitted; only didStart proves success.
    @discardableResult
    func start() -> Bool {
        guard let controller, isSupported else { return false }
        guard !isActive, !isStarting else { return true }
        guard let snapshot = snapshotProvider?(), snapshot.isReady, snapshot.isPlaying else {
            status = "請先播放本機媒體，再開啟浮動字幕"
            return false
        }
        refresh()
        guard surface.window != nil, controller.isPictureInPicturePossible else {
            status = "系統尚未準備好畫中畫，請保持字幕預覽可見並再試一次"
            return false
        }
        wantsPictureInPicture = true
        isStarting = true
        status = "正在開啟浮動字幕…"
        updateRefreshLoop()
        controller.startPictureInPicture()
        startTimeout?.cancel()
        startTimeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(8)) } catch { return }
            guard let self, self.isStarting, !self.isActive else { return }
            self.finish(message: "系統未能開啟畫中畫，請返回 App 後重試")
            self.controller?.stopPictureInPicture()
        }
        return true
    }

    func stop() {
        let wasStarting = isStarting
        wantsPictureInPicture = false
        isStarting = false
        startTimeout?.cancel()
        startTimeout = nil
        controller?.stopPictureInPicture()
        if !isActive {
            status = "浮動字幕已關閉"
            updateRefreshLoop()
            if wasStarting { notifyStopped() }
        }
    }

    /// Also callable after an immediate settings, caption, or transport change.
    func refresh() {
        guard let snapshot = snapshotProvider?() else { return }
        let duration = snapshot.duration.isFinite ? max(0, snapshot.duration) : 0
        let time = snapshot.currentTime.isFinite ? min(max(0, snapshot.currentTime), duration) : 0
        let ready = snapshot.isReady && duration > 0
        let playing = ready && snapshot.isPlaying
        playback.update(ready: ready, playing: playing, duration: duration)
        let mediaTime = CMTime(seconds: time, preferredTimescale: 16_000)
        if let timebase = surface.displayLayer.controlTimebase {
            let clockTime = CMTimebaseGetTime(timebase).seconds
            if !clockTime.isFinite || abs(clockTime - time) > 0.5 || lastPlaying != playing {
                // Flush obsolete queued frames after seeks or pause/resume.
                surface.displayLayer.sampleBufferRenderer.flush()
                lastFrameText = nil
                CMTimebaseSetTime(timebase, time: mediaTime)
            }
            CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
        }
        if lastPlaying != playing || lastDuration != duration {
            lastPlaying = playing
            lastDuration = duration
            controller?.invalidatePlaybackState()
        }
        let text = snapshot.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let frameText = !text.isEmpty ? text : (ready ? (snapshot.status.isEmpty ? "等待語音…" : snapshot.status) : "播放本機媒體後，字幕會顯示在這裡")
        let scale = snapshot.fontScale.isFinite ? min(max(snapshot.fontScale, 0.75), 1.5) : 1
        guard frameText != lastFrameText || scale != lastFontScale || surface.displayLayer.sampleBufferRenderer.status == .failed else { return }
        if render(text: frameText, fontScale: scale, time: mediaTime) {
            lastFrameText = frameText
            lastFontScale = scale
        }
    }

    private func updateRefreshLoop() {
        let needed = surface.window != nil || isActive || isStarting
        guard needed else {
            refreshTask?.cancel()
            refreshTask = nil
            return
        }
        refresh()
        guard refreshTask == nil else { return }
        // Caption updates continue while the main SwiftUI view is in background.
        // Runtime comes only from actual media playback and system PiP.
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                self.refresh()
            }
        }
    }

    private func finish(message: String) {
        let shouldNotify = isActive || isStarting || wantsPictureInPicture
        isActive = false
        isStarting = false
        wantsPictureInPicture = false
        startTimeout?.cancel()
        startTimeout = nil
        status = message
        updateRefreshLoop()
        if shouldNotify { notifyStopped() }
    }

    private func notifyStopped() {
        guard let didStop else { return }
        Task { await didStop() }
    }

    @discardableResult
    private func render(text: String, fontScale: Double, time: CMTime) -> Bool {
        let renderer = surface.displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData else { return false }
        let width = 960, height = 540
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer,
              CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else { return false }
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            return false
        }
        context.setFillColor(UIColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        UIGraphicsPushContext(context)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let bounds = CGRect(x: 48, y: 60, width: 864, height: 420)
        var fontSize = CGFloat(60 * fontScale)
        var caption: NSAttributedString
        var measured: CGRect
        repeat {
            caption = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: fontSize, weight: .semibold), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            measured = caption.boundingRect(with: CGSize(width: bounds.width, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            fontSize -= 2
        } while measured.height > bounds.height && fontSize >= 24
        let textHeight = min(measured.height, bounds.height)
        caption.draw(with: CGRect(x: bounds.minX, y: bounds.midY - textHeight / 2, width: bounds.width, height: textHeight), options: [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine], context: nil)
        UIGraphicsPopContext()
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description) == noErr,
              let description else { return false }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return false }
        // A paused player must still be able to repaint an edited caption/style.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true), CFArrayGetCount(attachments) > 0 {
            let dictionary = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
            CFDictionarySetValue(dictionary, Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(), Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
        }
        renderer.enqueue(sample)
        return true
    }

    isolated deinit {
        refreshTask?.cancel()
        startTimeout?.cancel()
        controller?.delegate = nil
        controller?.stopPictureInPicture()
    }
}

private final class CaptionPiPPlaybackState: @unchecked Sendable {
    private let lock = NSLock()
    private var ready = false
    private var playing = false
    private var duration: Double = 0

    func update(ready: Bool, playing: Bool, duration: Double) {
        lock.lock(); defer { lock.unlock() }
        self.ready = ready; self.playing = playing; self.duration = duration
    }

    var isPaused: Bool { lock.lock(); defer { lock.unlock() }; return !playing }
    var timeRange: CMTimeRange {
        lock.lock(); defer { lock.unlock() }
        return ready ? CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 16_000)) : .invalid
    }
}

@MainActor
final class CaptionPictureInPictureSurface: UIView {
    var onWindowChanged: (() -> Void)?
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
    override func didMoveToWindow() { super.didMoveToWindow(); onWindowChanged?() }
}

extension CaptionPictureInPictureController: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isActive = true
            self.isStarting = false
            self.startTimeout?.cancel()
            self.startTimeout = nil
            guard self.wantsPictureInPicture else {
                self.controller?.stopPictureInPicture()
                return
            }
            self.status = "浮動字幕已開啟，可切換到其他 App"
            self.updateRefreshLoop()
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in self?.finish(message: "浮動字幕已關閉") }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in self?.finish(message: "無法開啟浮動字幕：\(message)") }
    }

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        // No private foregrounding API; the OS brings back the existing scene.
        Task { @MainActor [weak self] in completionHandler(self?.surface.window != nil) }
    }
}

extension CaptionPictureInPictureController: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.setPlaying?(playing)
            self.refresh()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { playback.timeRange }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { playback.isPaused }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) {
        let seconds = skipInterval.seconds
        Task { @MainActor [weak self] in
            if let self, seconds.isFinite {
                await self.skip?(seconds)
                self.refresh()
            }
            completion()
        }
    }
}
#endif
