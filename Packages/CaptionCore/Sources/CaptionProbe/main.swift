import Foundation
import AVFoundation
import CaptionCore
import Darwin

/// Instrument the public engine boundary, without changing core scheduling.
private actor MeasuredEngine: SpeechRecognizing {
    nonisolated let engine: WhisperEngine
    private var calls: [[String: Double]] = []
    private let origin: Double
    init(engine: WhisperEngine, origin: Double) { self.engine = engine; self.origin = origin }
    func transcribe(samples: [Float], language: String?) async throws -> [RecognitionSegment] {
        let began = ProcessInfo.processInfo.systemUptime
        do {
            let result = try await engine.transcribe(samples: samples, language: language)
            calls.append(["startSeconds": began - origin,
                          "durationSeconds": ProcessInfo.processInfo.systemUptime - began,
                          "audioSeconds": Double(samples.count) / 16_000, "succeeded": 1])
            return result
        } catch {
            calls.append(["startSeconds": began - origin,
                          "durationSeconds": ProcessInfo.processInfo.systemUptime - began,
                          "audioSeconds": Double(samples.count) / 16_000, "succeeded": 0])
            throw error
        }
    }
    nonisolated func cancel() { engine.cancel() }
    func unload() async { await engine.unload() }
    func measurements() -> [[String: Double]] { calls }
}

/// Development-only audit harness. The apps do not launch this executable.
@main struct CaptionProbe {
    private struct StreamSummary {
        var captions: [CaptionSegment] = []
        var partialCount = 0
        var firstPartialSeconds: Double?
        var maximumFinalDelaySeconds = 0.0
        var maximumInferenceSeconds = 0.0
        var droppedAudioSeconds = 0.0
        var firstSubtitleSeconds: Double?
        var lastConfirmedSeconds: Double?
        var updates: [[String: Any]] = []
        var errors: [String] = []
    }

    /// Fixed benchmark-only energy proxy. This is deliberately independent of
    /// the product VAD, so a VAD tuning change cannot move the measurement goal.
    /// It is not a human-annotated phonetic boundary or an accuracy claim.
    static func energyBounds(_ samples: [Float]) -> (first: Double?, last: Double?) {
        var first: Double?, last: Double?
        var runStart = 0, runCount = 0
        for offset in stride(from: 0, to: samples.count, by: 320) {
            let end = min(offset + 320, samples.count)
            let rms = sqrt(samples[offset..<end].reduce(0.0) { $0 + Double($1 * $1) } / Double(end - offset))
            if rms >= 0.006 {
                if runCount == 0 { runStart = offset }
                runCount += 1
                if runCount >= 3 {
                    if first == nil { first = Double(runStart) / 16_000 }
                    last = Double(end) / 16_000
                }
            } else { runCount = 0 }
        }
        return (first, last)
    }
    static func main() async {
        let args = CommandLine.arguments
        func value(_ key: String) -> String? {
            guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
            return args[index + 1]
        }
        guard let model = value("--model"), let audio = value("--audio") else {
            print("Usage: CaptionProbe --model /path/ggml-tiny.bin --audio /path/audio.wav [--language ja|fr|auto] [--cpu] [--stream] [--repeat 1] [--srt /path/out.srt]")
            exit(2)
        }
        do {
            let engine = WhisperEngine()
            let started = Date()
            try await engine.load(modelURL: URL(fileURLWithPath: model), useGPU: !args.contains("--cpu"))
            let loadSeconds = Date().timeIntervalSince(started)
            let file = try AVAudioFile(forReading: URL(fileURLWithPath: audio))
            let normalizer = PCMNormalizer()
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 16_384) else {
                throw WhisperEngineError.invalidAudio
            }
            var samples: [Float] = []
            while file.framePosition < file.length {
                try file.read(into: buffer)
                samples += try normalizer.convert(buffer)
            }
            let language = value("--language") ?? "auto"
            if args.contains("--cancel-check") {
                let part = Array(samples.prefix(25 * 16_000))
                let job = Task { try await engine.transcribe(samples: part, language: language) }
                try await Task.sleep(nanoseconds: 1_000_000)
                job.cancel(); engine.cancel()
                var cancelled = false
                do { _ = try await job.value } catch is CancellationError { cancelled = true }
                await engine.unload()
                let unloaded = await engine.loadedModelURL == nil
                try await engine.load(modelURL: URL(fileURLWithPath: model), useGPU: !args.contains("--cpu"))
                let retried = try await engine.transcribe(samples: part, language: language)
                await engine.unload()
                let result: [String: Any] = ["cancellationObserved": cancelled, "unloadedAfterCancellation": unloaded,
                                            "retrySegmentCount": retried.count, "retryText": retried.map(\.text).joined(separator: " ")]
                print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                if !cancelled || !unloaded || retried.isEmpty { exit(1) }
                return
            }
            var captions: [CaptionSegment] = []
            var streamSummary: StreamSummary?
            let repeatCount = max(1, min(100, Int(value("--repeat") ?? "1") ?? 1))
            var memoryPeaks: [Int] = []
            let inferenceStarted = ProcessInfo.processInfo.systemUptime
            let measuredEngine = MeasuredEngine(engine: engine, origin: inferenceStarted)
            var maximumFeedLateness = 0.0
            let energy = energyBounds(samples)
            if args.contains("--stream") {
                let stream = StreamingTranscriber(engine: measuredEngine)
                let consumer = Task { () -> StreamSummary in
                    var collected = StreamSummary()
                    for await event in stream.events {
                        let now = ProcessInfo.processInfo.systemUptime - inferenceStarted
                        switch event {
                        case .confirmed(let batch):
                            collected.captions += batch
                            if !batch.isEmpty {
                                if collected.firstSubtitleSeconds == nil { collected.firstSubtitleSeconds = now }
                                collected.lastConfirmedSeconds = now
                                collected.updates.append(["kind": "confirmed", "wallSeconds": now,
                                    "segments": batch.map { ["start": $0.start, "end": $0.end, "text": $0.text] }])
                            }
                            if let end = batch.last?.end {
                                collected.maximumFinalDelaySeconds = max(collected.maximumFinalDelaySeconds, now - end)
                            }
                        case .partial(.some(let caption)):
                            collected.partialCount += 1
                            if collected.firstPartialSeconds == nil { collected.firstPartialSeconds = now }
                            if collected.firstSubtitleSeconds == nil { collected.firstSubtitleSeconds = now }
                            collected.updates.append(["kind": "partial", "wallSeconds": now,
                                "start": caption.start, "end": caption.end, "text": caption.text])
                        case .status(.stopped): return collected
                        case .status(.failed(let reason)): collected.errors.append(reason)
                        case .metrics(let metrics):
                            collected.droppedAudioSeconds = max(collected.droppedAudioSeconds, metrics.droppedAudioSeconds)
                            collected.maximumInferenceSeconds = max(collected.maximumInferenceSeconds, metrics.inferenceSeconds)
                        default: break
                        }
                    }
                    return collected
                }
                await stream.start(language: language)
                for repetition in 0..<repeatCount {
                    for offset in stride(from: 0, to: samples.count, by: 3200) {
                        let end = min(offset + 3200, samples.count)
                        // Deliver only audio whose END has already been played.
                        // The old harness delivered 200 ms of future audio, making
                        // subtitle latency look artificially shorter. Absolute
                        // monotonic deadlines also avoid accumulating sleep drift.
                        let due = inferenceStarted + Double(repetition * samples.count + end) / 16_000
                        let remaining = due - ProcessInfo.processInfo.systemUptime
                        if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                        maximumFeedLateness = max(maximumFeedLateness, ProcessInfo.processInfo.systemUptime - due)
                        await stream.append(samples: Array(samples[offset..<end]), at: Double(repetition * samples.count + offset) / 16_000)
                    }
                    var snapshot = rusage(); getrusage(RUSAGE_SELF, &snapshot)
                    memoryPeaks.append(snapshot.ru_maxrss)
                }
                await stream.finish()
                streamSummary = await consumer.value
                captions = streamSummary!.captions
            } else {
                // Files are decoded in bounded windows, never handed whole to whisper.
                for offset in stride(from: 0, to: samples.count, by: 25 * 16_000) {
                    let part = Array(samples[offset..<min(samples.count, offset + 25 * 16_000)])
                    let segments = try await measuredEngine.transcribe(samples: part, language: language)
                    captions += segments.map { .init(start: $0.start + Double(offset) / 16_000,
                                                     end: $0.end + Double(offset) / 16_000, text: $0.text) }
                }
            }
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let calls = await measuredEngine.measurements()
            var result: [String: Any] = [
                "benchmarkVersion": 2,
                "engine": "whisper.cpp 1.9.5 / b5454",
                "language": language,
                "gpuRequested": !args.contains("--cpu"),
                "gpuLoaded": await engine.usingGPU,
                "loadSeconds": loadSeconds,
                "audioSeconds": Double(samples.count) / 16_000 * Double(args.contains("--stream") ? repeatCount : 1),
                "inferenceWallSeconds": ProcessInfo.processInfo.systemUptime - inferenceStarted,
                "inferenceCallCount": calls.count,
                "inferenceTotalSeconds": calls.reduce(0) { $0 + ($1["durationSeconds"] ?? 0) },
                "inferenceTotalAudioSeconds": calls.reduce(0) { $0 + ($1["audioSeconds"] ?? 0) },
                "inferenceCalls": calls,
                "peakResidentBytes": usage.ru_maxrss,
                "segments": captions.map { ["start": $0.start, "end": $0.end, "text": $0.text] }
            ]
            if let summary = streamSummary {
                let partialTimes = summary.updates.filter { $0["kind"] as? String == "partial" }.compactMap { $0["wallSeconds"] as? Double }
                let intervals = zip(partialTimes, partialTimes.dropFirst()).map { $1 - $0 }
                let lastEnergy = energy.last.map { $0 + Double(repeatCount - 1) * Double(samples.count) / 16_000 }
                result["streaming"] = [
                    "chunkSeconds": 0.2,
                    "delivery": "At or after each source chunk end, paced by systemUptime; model loaded before playback clock",
                    "energyBoundaryMethod": "20 ms RMS >= 0.006 for 3 consecutive frames; fixed benchmark-only speech-energy proxy, not human annotation",
                    "speechEnergyOnsetSeconds": energy.first.map { $0 as Any } ?? NSNull(),
                    "speechEnergyEndSeconds": lastEnergy.map { $0 as Any } ?? NSNull(),
                    "partialCount": summary.partialCount,
                    "firstPartialSeconds": summary.firstPartialSeconds.map { $0 as Any } ?? NSNull(),
                    "firstSubtitleSeconds": summary.firstSubtitleSeconds.map { $0 as Any } ?? NSNull(),
                    "speechEnergyToFirstSubtitleSeconds": summary.firstSubtitleSeconds.flatMap { first in energy.first.map { first - $0 } }.map { $0 as Any } ?? NSNull(),
                    "lastConfirmedSeconds": summary.lastConfirmedSeconds.map { $0 as Any } ?? NSNull(),
                    "speechEnergyEndToLastConfirmedSeconds": summary.lastConfirmedSeconds.flatMap { final in lastEnergy.map { final - $0 } }.map { $0 as Any } ?? NSNull(),
                    "lastConfirmedAfterEOFSeconds": summary.lastConfirmedSeconds.map { $0 - Double(samples.count) / 16_000 * Double(repeatCount) as Any } ?? NSNull(),
                    "partialUpdateIntervalsSeconds": intervals,
                    "maximumFeedLatenessSeconds": maximumFeedLateness,
                    "maximumFinalDelaySeconds": summary.maximumFinalDelaySeconds,
                    "maximumInferenceSeconds": summary.maximumInferenceSeconds,
                    "droppedAudioSeconds": summary.droppedAudioSeconds,
                    "repeatCount": repeatCount,
                    "peakResidentBytesAfterEachRepeat": memoryPeaks,
                    "updates": summary.updates,
                    "errors": summary.errors
                ]
            }
            let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            print(String(decoding: json, as: UTF8.self))
            if let output = value("--srt") { try CaptionExporter.srt(captions).write(toFile: output, atomically: true, encoding: .utf8) }
            await engine.unload()
            if streamSummary?.errors.isEmpty == false { exit(1) }
        } catch {
            fputs("CaptionProbe: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
