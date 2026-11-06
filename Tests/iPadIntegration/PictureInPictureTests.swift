import AVFoundation
import AVKit
import UIKit
import XCTest
@testable import LiveCaption

/// Transport and renderer regressions. Delegate callbacks below are explicitly
/// simulated; these tests do not prove real-device background PiP/inference.
final class PictureInPictureTests: XCTestCase {
    @MainActor
    func testStartRequiresPlayingLocalMediaAndVisiblePreview() {
        let subject = CaptionPictureInPictureController()
        var snapshot = snapshot(ready: false, playing: false)
        subject.bind(snapshot: { snapshot }, setPlaying: { _ in }, skip: { _ in }, didStop: {})
        XCTAssertFalse(subject.start())
        snapshot.isReady = true
        XCTAssertFalse(subject.start(), "Paused local media must not create a background session")
        snapshot.isPlaying = true
        XCTAssertFalse(subject.start(), "An unattached preview must not start PiP")
        XCTAssertFalse(subject.isStarting)
        XCTAssertFalse(subject.isActive)
    }

    @MainActor
    func testPlaybackQueriesFollowFiniteMediaTimeline() {
        let subject = CaptionPictureInPictureController()
        let delegateController = controller(for: subject)
        var snapshot = snapshot(ready: true, playing: true)
        subject.bind(snapshot: { snapshot }, setPlaying: { _ in }, skip: { _ in }, didStop: {})
        let range = subject.pictureInPictureControllerTimeRangeForPlayback(delegateController)
        XCTAssertEqual(range.start.seconds, 0)
        XCTAssertEqual(range.duration.seconds, 120)
        XCTAssertFalse(subject.pictureInPictureControllerIsPlaybackPaused(delegateController))
        snapshot.currentTime = 72
        snapshot.isPlaying = false
        subject.refresh()
        XCTAssertTrue(subject.pictureInPictureControllerIsPlaybackPaused(delegateController))
        if let timebase = subject.surface.displayLayer.controlTimebase {
            XCTAssertEqual(CMTimebaseGetTime(timebase).seconds, 72, accuracy: 0.01,
                           "Seeking must move the PiP clock to the actual media position")
        }
        snapshot.isReady = false
        subject.refresh()
        XCTAssertFalse(subject.pictureInPictureControllerTimeRangeForPlayback(delegateController).isValid,
                       "No imported media must be reported as no playable content")
    }

    @MainActor
    func testTransportActionsReachPlaybackOwner() async {
        let subject = CaptionPictureInPictureController()
        let delegateController = controller(for: subject)
        var snapshot = snapshot(ready: true, playing: true)
        let paused = expectation(description: "pause forwarded")
        let skipped = expectation(description: "seek completed")
        subject.bind(snapshot: { snapshot }, setPlaying: { playing in
            snapshot.isPlaying = playing
            XCTAssertFalse(playing)
            paused.fulfill()
        }, skip: { seconds in
            XCTAssertEqual(seconds, -15)
            snapshot.currentTime += seconds
        }, didStop: {})
        subject.pictureInPictureController(delegateController, setPlaying: false)
        await fulfillment(of: [paused], timeout: 2)
        XCTAssertTrue(subject.pictureInPictureControllerIsPlaybackPaused(delegateController))
        subject.pictureInPictureController(delegateController, skipByInterval: CMTime(seconds: -15, preferredTimescale: 600)) {
            skipped.fulfill()
        }
        await fulfillment(of: [skipped], timeout: 2)
        XCTAssertEqual(snapshot.currentTime, 15)
    }

    @MainActor
    func testLateStartFailureClearsStateAndNotifiesOwnerOnce() async throws {
        let subject = CaptionPictureInPictureController()
        let delegateController = controller(for: subject)
        var cleanupCount = 0
        subject.bind(snapshot: { self.snapshot(ready: true, playing: true) }, setPlaying: { _ in }, skip: { _ in }, didStop: { cleanupCount += 1 })
        subject.stop()
        // A platform callback can arrive after the user cancels a pending start.
        subject.pictureInPictureControllerDidStartPictureInPicture(delegateController)
        try await Task.sleep(for: .milliseconds(50))
        subject.pictureInPictureController(delegateController, failedToStartPictureInPictureWithError: NSError(domain: "PiPTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "test failure"]))
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertFalse(subject.isActive)
        XCTAssertFalse(subject.isStarting)
        XCTAssertEqual(cleanupCount, 1)
        subject.pictureInPictureControllerDidStopPictureInPicture(delegateController)
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(cleanupCount, 1, "Late stop must not trigger a second background cleanup")
    }

    @MainActor
    func testCaptionFrameRepaintsWhilePlaybackIsPaused() async throws {
        let subject = CaptionPictureInPictureController()
        var snapshot = snapshot(ready: true, playing: false)
        subject.bind(snapshot: { snapshot }, setPlaying: { _ in }, skip: { _ in }, didStop: {})
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let host = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 640, height: 360)
        window.rootViewController = host
        window.isHidden = false
        host.view.addSubview(subject.surface)
        subject.surface.frame = host.view.bounds
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(300))
        let initialPixels = try XCTUnwrap(subject.surface.displayLayer.sampleBufferRenderer.displayedPixelBuffer())
        let initialChecksum = try pixelChecksum(initialPixels)
        snapshot.text = "字幕在暫停時仍可更新\n日本語の字幕も表示できます"
        snapshot.fontScale = 1.5
        subject.refresh()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotEqual(subject.surface.displayLayer.sampleBufferRenderer.status, .failed)
        let pixels = try XCTUnwrap(subject.surface.displayLayer.sampleBufferRenderer.displayedPixelBuffer())
        XCTAssertNotEqual(try pixelChecksum(pixels), initialChecksum,
                          "A paused display must replace the previous caption image")
        XCTAssertEqual(CVPixelBufferGetWidth(pixels), 960)
        XCTAssertEqual(CVPixelBufferGetHeight(pixels), 540)
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(pixels)
        var brightPixels = 0
        for row in Swift.stride(from: 0, to: 540, by: 4) {
            for column in Swift.stride(from: 0, to: 960, by: 4) {
                if base[row * stride + column * 4] > 160 { brightPixels += 1 }
            }
        }
        XCTAssertGreaterThan(brightPixels, 100, "The displayed frame must contain visible caption glyphs")
    }

    @MainActor
    private func controller(for subject: CaptionPictureInPictureController) -> AVPictureInPictureController {
        AVPictureInPictureController(contentSource: .init(sampleBufferDisplayLayer: AVSampleBufferDisplayLayer(), playbackDelegate: subject))
    }

    private func snapshot(ready: Bool, playing: Bool) -> CaptionPictureInPictureController.Snapshot {
        .init(text: "即時字幕", status: "等待語音…", isReady: ready, isPlaying: playing, currentTime: 30, duration: 120)
    }

    private func pixelChecksum(_ pixels: CVPixelBuffer) throws -> UInt64 {
        CVPixelBufferLockBaseAddress(pixels, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixels, .readOnly) }
        let base = try XCTUnwrap(CVPixelBufferGetBaseAddress(pixels)).assumingMemoryBound(to: UInt8.self)
        let count = CVPixelBufferGetHeight(pixels) * CVPixelBufferGetBytesPerRow(pixels)
        var result: UInt64 = 14_695_981_039_346_656_037
        for index in Swift.stride(from: 0, to: count, by: 16) {
            result = (result ^ UInt64(base[index])) &* 1_099_511_628_211
        }
        return result
    }
}
