import AVFoundation
import CoreVideo
import Foundation

enum VideoFixtureError: Error, CustomStringConvertible {
    case failure(String)
    var description: String { switch self { case .failure(let message): message } }
}

/// Development-only fixture generator. The video is a neutral solid background;
/// all audio is the unchanged spoken content from the supplied real recording.
@main struct MakeVideoFixture {
    static func main() async throws {
        guard CommandLine.arguments.count == 3 else {
            throw VideoFixtureError.failure("Usage: make-video-fixture INPUT_AUDIO OUTPUT_MP4")
        }
        let audioURL = URL(fileURLWithPath: CommandLine.arguments[1])
        let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])
        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw VideoFixtureError.failure("Output already exists: \(outputURL.path)")
        }
        let audioAsset = AVURLAsset(url: audioURL)
        guard let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first else {
            throw VideoFixtureError.failure("Input contains no audio track")
        }
        let duration = try await audioAsset.load(.duration)
        guard duration.seconds.isFinite, duration.seconds > 0 else {
            throw VideoFixtureError.failure("Input duration is invalid")
        }
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("live-caption-neutral-video-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: scratch) }
        try await makeSilentVideo(at: scratch, duration: duration)

        let videoAsset = AVURLAsset(url: scratch)
        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first else {
            throw VideoFixtureError.failure("Generated fixture has no video track")
        }
        let composition = AVMutableComposition()
        guard let composedVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let composedAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw VideoFixtureError.failure("Cannot create composition tracks")
        }
        let range = CMTimeRange(start: .zero, duration: duration)
        try composedVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        try composedAudio.insertTimeRange(range, of: audioTrack, at: .zero)
        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoFixtureError.failure("Cannot create MP4 exporter")
        }
        exporter.shouldOptimizeForNetworkUse = true
        try await exporter.export(to: outputURL, as: .mp4)

        let result = AVURLAsset(url: outputURL)
        let actualDuration = try await result.load(.duration).seconds
        let actualVideoTracks = try await result.loadTracks(withMediaType: .video).count
        let actualAudioTracks = try await result.loadTracks(withMediaType: .audio).count
        guard actualVideoTracks == 1, actualAudioTracks == 1,
              abs(actualDuration - duration.seconds) < 0.1 else {
            throw VideoFixtureError.failure("Exported track count or duration is incorrect")
        }
        print("VIDEO_FIXTURE=\(outputURL.path)")
        print("SOURCE_AUDIO=\(audioURL.path)")
        print("DURATION_SECONDS=\(actualDuration)")
        print("TRACKS=1 native H.264 video + 1 original-speech audio track (AAC export)")
        print("VISUAL=640x360 neutral solid background; no rendered text or subtitles")
    }

    static func makeSilentVideo(at url: URL, duration: CMTime) async throws {
        let width = 640, height = 360
        let frameRate: Int32 = 24
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 250_000,
                AVVideoMaxKeyFrameIntervalKey: 48
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])
        guard writer.canAdd(input) else { throw VideoFixtureError.failure("Cannot encode H.264 video") }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? VideoFixtureError.failure("Cannot start video writer") }
        writer.startSession(atSourceTime: .zero)

        var pixelBuffer: CVPixelBuffer?
        let code = CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA,
                                       nil, &pixelBuffer)
        guard code == kCVReturnSuccess, let pixelBuffer else {
            throw VideoFixtureError.failure("Cannot allocate pixel buffer: \(code)")
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
            throw VideoFixtureError.failure("Cannot map pixel buffer")
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                bytes[i] = 61
                bytes[i + 1] = 50
                bytes[i + 2] = 36
                bytes[i + 3] = 255
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        let frames = Int(ceil(duration.seconds * Double(frameRate)))
        let deadline = Date().addingTimeInterval(60)
        for frame in 0..<frames {
            while !input.isReadyForMoreMediaData {
                if writer.status == .failed { throw writer.error ?? VideoFixtureError.failure("Video encoder failed") }
                guard Date() < deadline else { throw VideoFixtureError.failure("Video encoder timed out") }
                try await Task.sleep(for: .milliseconds(2))
            }
            guard adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: Int64(frame), timescale: frameRate)) else {
                throw writer.error ?? VideoFixtureError.failure("Cannot append video frame")
            }
        }
        writer.endSession(atSourceTime: duration)
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? VideoFixtureError.failure("Video writer did not complete") }
    }
}
