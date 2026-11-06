// Development-only, no third-party dependencies.
// swift Verification/latency/compare.swift Verification/latency
import Foundation
import AVFoundation

let directory = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Verification/latency")
func read(_ path: String) throws -> Any {
    try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(path)))
}
func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? 0 }
func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    guard !sorted.isEmpty else { return 0 }
    return sorted.count % 2 == 0 ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2 : sorted[sorted.count / 2]
}
// Recompute the same lower fixed threshold for both versions. Raw probe v2
// recorded a 0.006 diagnostic threshold that misses the quiet French fixture;
// these source-derived bounds preserve the actual timing runs unchanged.
func speechBounds(_ audioURL: URL) throws -> (first: Double, last: Double) {
    let file = try AVAudioFile(forReading: audioURL)
    precondition(file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1)
    let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
    try file.read(into: buffer)
    let samples = Array(UnsafeBufferPointer(start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
    var first: Double?, last: Double?, runStart = 0, count = 0
    for offset in stride(from: 0, to: samples.count, by: 320) {
        let end = min(offset + 320, samples.count)
        let rms = sqrt(samples[offset..<end].reduce(0.0) { $0 + Double($1 * $1) } / Double(end - offset))
        if rms >= 0.0002 {
            if count == 0 { runStart = offset }
            count += 1
            if count >= 3 {
                if first == nil { first = Double(runStart) / 16_000 }
                last = Double(end) / 16_000
            }
        } else { count = 0 }
    }
    precondition(first != nil && last != nil, "Energy boundary unavailable; do not invent a speech-relative latency")
    return (first!, last!)
}
let fixtureDirectory = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "/tmp/live-caption-verification-audio")
var report: [[String: Any]] = []
for fixture in ["ja_jp-0", "ja_jp-1", "fr_fr-0", "fr_fr-1"] {
    let bounds = try speechBounds(fixtureDirectory.appendingPathComponent(fixture + ".wav"))
    var item: [String: Any] = ["fixture": fixture,
        "speechEnergyMethod": "Source-derived fixed 20 ms RMS >= 0.0002 for 3 consecutive frames; same bounds for both runs; not a human annotation",
        "speechEnergyOnsetSeconds": bounds.first, "speechEnergyEndSeconds": bounds.last]
    var finalSegments: [Data] = []
    for phase in ["baseline", "optimized"] {
        let result = try read("\(phase)/\(fixture).json") as! [String: Any]
        let streaming = result["streaming"] as! [String: Any]
        precondition(number(result["benchmarkVersion"]) == 2, "Only corrected causal measurements may be compared")
        precondition(result["gpuLoaded"] as? Bool == true, "This comparison requires actual Metal inference")
        precondition((streaming["errors"] as? [String])?.isEmpty == true, "Failed inference cannot be scored as a latency win")
        precondition(streaming["firstSubtitleSeconds"] is NSNumber && streaming["lastConfirmedSeconds"] is NSNumber,
                     "Missing subtitle events must not become zero-second latency")
        finalSegments.append(try JSONSerialization.data(withJSONObject: result["segments"]!, options: [.sortedKeys]))
        let allUpdates = streaming["updates"] as! [[String: Any]]
        let updates = allUpdates.filter { $0["kind"] as? String == "partial" }
        var changed: [Double] = [], previous: String?
        for update in updates {
            let text = update["text"] as? String
            if text != previous { changed.append(number(update["wallSeconds"])); previous = text }
        }
        let changedIntervals = zip(changed, changed.dropFirst()).map { $1 - $0 }
        let accuracy = (try read("\(phase)/accuracy.json") as! [[String: Any]]).first { $0["fixture"] as? String == fixture }!
        item[phase] = [
            "firstSubtitleKind": allUpdates.first?["kind"] ?? NSNull(),
            "firstPartialText": updates.first?["text"] ?? NSNull(),
            "lastPartialText": updates.last?["text"] ?? NSNull(),
            "firstSubtitleFromFileStartSeconds": streaming["firstSubtitleSeconds"] ?? NSNull(),
            "firstSubtitleFromSpeechEnergySeconds": number(streaming["firstSubtitleSeconds"]) - bounds.first,
            "finalAfterSpeechEnergyEndSeconds": number(streaming["lastConfirmedSeconds"]) - bounds.last,
            "finalAfterEOFSeconds": streaming["lastConfirmedAfterEOFSeconds"] ?? NSNull(),
            "partialEventCount": streaming["partialCount"] ?? 0,
            "partialTextChangeCount": changed.count,
            "medianChangedPartialIntervalSeconds": changedIntervals.isEmpty ? NSNull() : median(changedIntervals) as Any,
            "maximumChangedPartialIntervalSeconds": changedIntervals.max().map { $0 as Any } ?? NSNull(),
            "inferenceCallCount": result["inferenceCallCount"] ?? 0,
            "inferenceTotalSeconds": result["inferenceTotalSeconds"] ?? 0,
            "maximumInferenceSeconds": streaming["maximumInferenceSeconds"] ?? 0,
            "droppedAudioSeconds": streaming["droppedAudioSeconds"] ?? 0,
            "maximumFeedLatenessSeconds": streaming["maximumFeedLatenessSeconds"] ?? 0,
            "peakResidentMiB": number(result["peakResidentBytes"]) / 1_048_576,
            "accuracy": accuracy
        ] as [String: Any]
    }
    let before = item["baseline"] as! [String: Any], after = item["optimized"] as! [String: Any]
    let firstBefore = number(before["firstSubtitleFromSpeechEnergySeconds"])
    let firstAfter = number(after["firstSubtitleFromSpeechEnergySeconds"])
    item["firstSubtitleReductionSeconds"] = firstBefore - firstAfter
    item["firstSubtitleReductionPercent"] = (firstBefore - firstAfter) / max(firstBefore, 0.001) * 100
    item["finalSegmentsIdentical"] = finalSegments[0] == finalSegments[1]
    report.append(item)
}
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
