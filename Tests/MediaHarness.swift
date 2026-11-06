import AVFoundation
import Foundation

enum MediaCheckFailure: Error, CustomStringConvertible {
    case failed(String)
    var description: String { switch self { case .failed(let message): message } }
}

@main struct MediaHarness {
    @MainActor static func main() async throws {
        guard CommandLine.arguments.count > 1 else {
            throw MediaCheckFailure.failed("Supply a real audio file path")
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        let reader = MediaPCMReader()
        let duration = try await reader.open(url: url)
        try require(duration > 4, "Fixture must be at least four seconds")
        try require(try await reader.read(until: 0).isEmpty, "Must not emit audio before playback")
        let first = try await reader.read(until: 0.2)
        let firstCount = first.reduce(0) { $0 + $1.samples.count }
        try require((3_180...3_200).contains(firstCount), "0.2s should emit approximately 3,200 mono 16kHz samples, got \(firstCount)")
        try checkBlocks(first, lower: 0, upper: 0.2)
        try require(try await reader.read(until: 0.2).isEmpty, "Fixed playback time must not advance the decoder")

        var total = firstCount
        for tick in 3...30 {
            let time = Double(tick) / 10
            let blocks = try await reader.read(until: time)
            try checkBlocks(blocks, lower: 0, upper: time)
            try require(blocks.reduce(0) { $0 + $1.samples.count } <= 8_000, "Bounded read must be at most 0.5s")
            total += blocks.reduce(0) { $0 + $1.samples.count }
        }
        try require(abs(total - 48_000) <= 2, "Three seconds should contain 48,000 mono samples; got \(total)")
        print("PASS: mono 16 kHz decoding, no future audio, 0.5-second bound, stationary playhead")

        try await reader.reset(at: 1.5)
        let backward = try await reader.read(until: 1.8)
        try checkBlocks(backward, lower: 1.5, upper: 1.8)
        try require(backward.first.map { abs($0.start - 1.5) < 0.001 } == true, "Backward seek must reset to media timeline")
        try await reader.reset(at: 3.25)
        let forward = try await reader.read(until: 3.5)
        try checkBlocks(forward, lower: 3.25, upper: 3.5)
        try require(forward.first.map { abs($0.start - 3.25) < 0.001 } == true, "Forward seek must reset to media timeline")
        await reader.close()
        try require(try await reader.read(until: duration).isEmpty, "Closed reader emits no audio")
        print("PASS: forward/backward seek timestamps and close")

        _ = try await reader.open(url: url)
        let hugeTime = try await reader.read(until: Double.greatestFiniteMagnitude)
        try require(!hugeTime.isEmpty && hugeTime.reduce(0) { $0 + $1.samples.count } <= 8_000,
                    "Huge finite playback times must remain bounded without Int overflow")
        do {
            _ = try await reader.open(url: URL(fileURLWithPath: "/tmp/live-caption-reader-missing-\(UUID().uuidString).wav"))
            throw MediaCheckFailure.failed("Missing reader source must fail")
        } catch is MediaCheckFailure { throw MediaCheckFailure.failed("Missing reader source did not fail") }
        catch {
            try require(try await reader.read(until: duration).isEmpty, "Failed source replacement must not retain old audio")
        }
        print("PASS: failed reader replacement discards old PCM; huge finite time stays bounded")

        var interruptedOpenCount = 0
        for _ in 0..<16 {
            let candidate = MediaPCMReader()
            var completed = false
            let opening = Task { () -> Result<Double, Error> in
                defer { completed = true }
                do { return .success(try await candidate.open(url: url)) }
                catch { return .failure(error) }
            }
            let deadline = Date().addingTimeInterval(5)
            while !completed {
                if await candidate.isOpening { break }
                try require(Date() < deadline, "Opening must start before close-race test")
                await Task.yield()
            }
            if await candidate.isOpening { interruptedOpenCount += 1 }
            await candidate.close()
            _ = await opening.value
            try require(try await candidate.read(until: 0.2).isEmpty,
                        "An open completion after close must not resurrect its reader")
        }
        try require(interruptedOpenCount > 0, "Regression must actually interrupt at least one in-flight asset open")
        let cancelledReader = MediaPCMReader()
        let cancelledOpening = Task { try await cancelledReader.open(url: url) }
        cancelledOpening.cancel()
        do {
            _ = try await cancelledOpening.value
            throw MediaCheckFailure.failed("Pre-cancelled reader open must not succeed")
        } catch is CancellationError { }
        try require(try await cancelledReader.read(until: 0.2).isEmpty, "Cancelled open emits no audio")
        print("PASS: close invalidates in-flight opens (\(interruptedOpenCount) observed); pre-cancelled open stays closed")

        let controller = MediaController()
        controller.player.isMuted = true
        try await controller.open(url)
        try require(controller.isReady && !controller.isLoading, "Opening should reach ready state")
        controller.play()
        try await waitUntil(timeout: 12) { controller.player.currentTime().seconds >= 0.3 }
        controller.pause()
        let pausedAt = controller.player.currentTime().seconds
        try await Task.sleep(for: .milliseconds(450))
        let afterPause = controller.player.currentTime().seconds
        try require(abs(afterPause - pausedAt) < 0.02, "AVPlayer time must remain stationary on pause")
        try require(!controller.isPlaying, "Pause state must be visible")
        await controller.seek(to: 2)
        try require(abs(controller.currentTime - 2) < 0.001, "Explicit seek should update playback position")
        controller.play()
        try await waitUntil(timeout: 12) { controller.player.currentTime().seconds > 2.2 }
        controller.pause()
        print("PASS: actual muted AVPlayer playback, pause stability, seek and resume")

        do {
            try await controller.open(URL(fileURLWithPath: "/tmp/live-caption-no-such-audio-\(UUID().uuidString).wav"))
            throw MediaCheckFailure.failed("Missing media must fail")
        } catch is MediaCheckFailure { throw MediaCheckFailure.failed("Missing media did not fail") }
        catch {
            try require(!controller.isReady && !controller.isLoading, "Failed import must not remain ready/loading")
            try require(controller.duration == 0 && controller.currentTime == 0 && !controller.isPlaying,
                        "Failed import must clear the previous duration, playhead, and playing state")
            controller.play()
            await controller.seek(to: 2)
            try require(!controller.isPlaying && controller.currentTime == 0, "An empty player cannot play or seek")
            print("PASS: failed media import clears ready/loading state (\(error.localizedDescription))")
        }

        var disposable: MediaController? = MediaController()
        try await disposable!.open(url)
        let retainedPlayer = disposable!.player
        retainedPlayer.isMuted = true
        disposable = nil
        await Task.yield()
        try require(retainedPlayer.currentItem == nil && retainedPlayer.rate == 0,
                    "Releasing a controller must detach its player before releasing file access")
        print("PASS: controller disposal closes a player retained by a native display surface")
        print("All media checks passed. Fixture: \(url.lastPathComponent), duration \(duration)s")
    }

    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw MediaCheckFailure.failed(message) }
    }
    static func checkBlocks(_ blocks: [MediaPCMBlock], lower: Double, upper: Double) throws {
        for block in blocks {
            try require(!block.samples.isEmpty && block.samples.allSatisfy(\.isFinite), "Samples must be finite")
            try require(block.start >= lower - 1 / 16_000, "Block begins before requested seek")
            let end = block.start + Double(block.samples.count) / 16_000
            try require(end <= upper + 1 / 16_000, "Block ends after playback time: \(end) > \(upper)")
        }
    }
    @MainActor static func waitUntil(timeout: TimeInterval, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { throw MediaCheckFailure.failed("AVPlayer did not advance before timeout") }
            try await Task.sleep(for: .milliseconds(50))
        }
    }
}
