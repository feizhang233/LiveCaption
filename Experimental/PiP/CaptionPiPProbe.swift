import AVFoundation
import AVKit
import Combine
import UIKit

/// Public-API rendering experiment, independent from Whisper and the production app.
/// The delegate's didStart callback is the only evidence of a successful PiP start.
@MainActor
final class CaptionPiPProbe: NSObject, ObservableObject {
    @Published private(set) var state = "尚未啟動畫中畫"
    @Published private(set) var active = false
    let surface = ProbeVideoSurface()
    private var controller: AVPictureInPictureController?
    // AVKit's Objective-C delegate requirements do not encode actor isolation.
    // Synchronous playback queries use this lock; UIKit/rendering stays on main.
    nonisolated private let playback = ProbePlaybackFlag()
    private var appliedPlaying = true
    private var wantsPictureInPicture = false

    override init() {
        super.init()
        guard AVPictureInPictureController.isPictureInPictureSupported() else {
            state = "這個裝置環境不支援畫中畫"
            return
        }
        var timebase: CMTimebase?
        guard CMTimebaseCreateWithSourceClock(allocator: kCFAllocatorDefault, sourceClock: CMClockGetHostTimeClock(), timebaseOut: &timebase) == noErr,
              let timebase else {
            state = "無法建立畫中畫播放時鐘"
            return
        }
        CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
        CMTimebaseSetRate(timebase, rate: 1)
        surface.displayLayer.controlTimebase = timebase
        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: surface.displayLayer, playbackDelegate: self)
        controller = AVPictureInPictureController(contentSource: source)
        controller?.delegate = self
        controller?.requiresLinearPlayback = true
        // No private KVC properties and no automatic/background activation.
        render(text: "本機收音診斷\n尚未產生辨識字幕")
    }

    func start() {
        guard let controller else { return }
        guard !wantsPictureInPicture, !controller.isPictureInPictureActive else { return }
        guard controller.isPictureInPicturePossible else {
            state = "系統尚未允許啟動畫中畫；保持預覽可見後重試。"
            return
        }
        wantsPictureInPicture = true
        state = "正在請求畫中畫"
        controller.startPictureInPicture()
    }

    func stop() {
        wantsPictureInPicture = false
        controller?.stopPictureInPicture()
    }

    private func applyPlaybackState() {
        let playing = playback.isPlaying
        guard appliedPlaying != playing else { return }
        appliedPlaying = playing
        if let timebase = surface.displayLayer.controlTimebase {
            if playing {
                // This is a live diagnostic display: resume at the current host
                // time instead of queuing frames behind a paused playback clock.
                surface.displayLayer.sampleBufferRenderer.flush()
                CMTimebaseSetTime(timebase, time: CMClockGetTime(CMClockGetHostTimeClock()))
            }
            CMTimebaseSetRate(timebase, rate: playing ? 1 : 0)
        }
        controller?.invalidatePlaybackState()
    }

    func render(text: String) {
        guard playback.isPlaying else { return }
        let renderer = surface.displayLayer.sampleBufferRenderer
        if renderer.status == .failed { renderer.flush() }
        guard renderer.isReadyForMoreMediaData else { return }
        let width = 960
        let height = 540
        var pixelBuffer: CVPixelBuffer?
        let attributes: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, attributes as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pixelBuffer else { state = "無法建立畫中畫影格"; return }
        guard CVPixelBufferLockBaseAddress(pixelBuffer, []) == kCVReturnSuccess else {
            state = "無法鎖定畫中畫影格記憶體"
            return
        }
        if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) {
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(context)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributed = NSAttributedString(string: text, attributes: [.font: UIFont.systemFont(ofSize: 40, weight: .medium), .foregroundColor: UIColor.white, .paragraphStyle: paragraph])
            attributed.draw(with: CGRect(x: 40, y: 100, width: width - 80, height: height - 140), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
            UIGraphicsPopContext()
        } else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            state = "無法繪製畫中畫影格"
            return
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        var description: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &description) == noErr, let description else { return }
        var timing = CMSampleTimingInfo(duration: CMTime(seconds: 1, preferredTimescale: 600), presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample) == noErr, let sample else { return }
        renderer.enqueue(sample)
    }
}

private final class ProbePlaybackFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var playing = true
    var isPlaying: Bool { lock.lock(); defer { lock.unlock() }; return playing }
    func set(_ value: Bool) { lock.lock(); playing = value; lock.unlock() }
}

@MainActor
final class ProbeVideoSurface: UIView {
    override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }
    var displayLayer: AVSampleBufferDisplayLayer { layer as! AVSampleBufferDisplayLayer }
}

extension CaptionPiPProbe: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            active = true
            guard wantsPictureInPicture else {
                state = "正在停止畫中畫"
                controller?.stopPictureInPicture()
                return
            }
            state = "畫中畫已啟動；背景推論仍未驗證"
        }
    }
    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            active = false
            wantsPictureInPicture = false
            state = "畫中畫已停止"
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor [weak self] in
            guard let self else { return }
            active = false
            wantsPictureInPicture = false
            state = "畫中畫啟動失敗：\(message)"
        }
    }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false) // This probe never promises to foreground the host.
    }
}

extension CaptionPiPProbe: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        playback.set(playing)
        Task { @MainActor [weak self] in self?.applyPlaybackState() }
    }
    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange { CMTimeRange(start: .zero, duration: .positiveInfinity) }
    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool { !playback.isPlaying }
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}
    nonisolated func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion: @escaping () -> Void) { completion() }
}
