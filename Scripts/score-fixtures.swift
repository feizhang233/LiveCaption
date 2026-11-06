// Development audit only; the apps do not execute this script.
// swift Scripts/score-fixtures.swift /path/to/fixtures.json Verification/engine
import Foundation

func distance<T: Equatable>(_ reference: [T], _ hypothesis: [T]) -> Int {
    var row = Array(0...hypothesis.count)
    for (i, left) in reference.enumerated() {
        var next = Array(repeating: 0, count: hypothesis.count + 1)
        next[0] = i + 1
        for (j, right) in hypothesis.enumerated() {
            next[j + 1] = min(next[j] + 1, row[j + 1] + 1, row[j] + (left == right ? 0 : 1))
        }
        row = next
    }
    return row.last ?? 0
}
func characters(_ text: String) -> [Character] {
    Array(text.lowercased().filter { $0.isLetter || $0.isNumber })
}
func words(_ text: String) -> [String] {
    text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
}
let args = CommandLine.arguments
guard args.count >= 3 else { fatalError("Pass fixture manifest and results directory [--language code]...") }
let allFixtures = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
var selectedLanguages: Set<String> = []
var argumentIndex = 3
while argumentIndex < args.count {
    guard args[argumentIndex] == "--language", argumentIndex + 1 < args.count else { fatalError("Expected --language code") }
    selectedLanguages.insert(args[argumentIndex + 1])
    argumentIndex += 2
}
let knownLanguages = Set(allFixtures.compactMap { $0["language"] as? String })
guard selectedLanguages.isSubset(of: knownLanguages) else { fatalError("Unknown fixture language") }
let manifest = allFixtures.filter { selectedLanguages.isEmpty || selectedLanguages.contains($0["language"] as! String) }
var report: [[String: Any]] = []
for fixture in manifest {
    let name = URL(fileURLWithPath: fixture["path"] as! String).deletingPathExtension().lastPathComponent
    let url = URL(fileURLWithPath: args[2]).appendingPathComponent(name + ".json")
    let result = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let hypothesis = (result["segments"] as! [[String: Any]]).map { $0["text"] as! String }.joined(separator: " ")
    let reference = fixture["transcription"] as! String
    let language = fixture["language"] as! String
    let characterMetric = language.hasPrefix("ja") || language.hasPrefix("cmn") || language.hasPrefix("zh")
    let edits = characterMetric ? distance(characters(reference), characters(hypothesis)) : distance(words(reference), words(hypothesis))
    let count = characterMetric ? characters(reference).count : words(reference).count
    var row: [String: Any] = [
        "fixture": name,
        "metric": characterMetric ? "CER" : "WER",
        "edits": edits,
        "referenceUnits": count,
        "errorRate": Double(edits) / Double(max(1, count)),
        "reference": reference,
        "hypothesis": hypothesis,
        "normalization": "Lowercase; Japanese/Chinese letters/numbers only (no simplified/traditional conversion); English/French split on all non-letter/non-number characters. Accents retained; no number-word conversion."
    ]
    if language.hasPrefix("cmn") || language.hasPrefix("zh") {
        // Diagnostic only: preserve the raw character score and actual captions.
        // Script variants are a separate issue from recognition substitutions.
        let transform = StringTransform("Traditional-Simplified")
        if let foldedReference = reference.applyingTransform(transform, reverse: false),
           let foldedHypothesis = hypothesis.applyingTransform(transform, reverse: false) {
            let foldedCount = characters(foldedReference).count
            let foldedEdits = distance(characters(foldedReference), characters(foldedHypothesis))
            row["simplifiedScriptDiagnostic"] = [
                "metric": "CER", "edits": foldedEdits, "referenceUnits": foldedCount,
                "errorRate": Double(foldedEdits) / Double(max(1, foldedCount)),
                "normalization": "Same character normalization plus Foundation ICU Traditional-Simplified applied to both texts; diagnostic only, raw score and captions unchanged."
            ] as [String: Any]
        }
    }
    report.append(row)
}
print(String(decoding: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
