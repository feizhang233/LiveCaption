import XCTest
@testable import CaptionCore

final class CaptionDisplayFilterTests: XCTestCase {
    private func filtered(_ text: String, _ language: String?) -> String {
        CaptionDisplayFilter.text(text, language: language, hideFillers: true)
    }

    func testDisabledFilterPreservesExactText() {
        let text = "  Um,\nえっと、嗯， euh…  "
        XCTAssertEqual(CaptionDisplayFilter.text(text, language: "en", hideFillers: false), text)
    }

    func testInitialHesitationsInSupportedLanguages() {
        XCTAssertEqual(filtered("Um, I agree.", "en"), "I agree.")
        XCTAssertEqual(filtered("Uhh… we can start.", "en-US"), "we can start.")
        XCTAssertEqual(filtered("Euh, je suis prêt.", "fr"), "je suis prêt.")
        XCTAssertEqual(filtered("えっと、今日は晴れです。", "ja"), "今日は晴れです。")
        XCTAssertEqual(filtered("あのー、次は何ですか？", "ja"), "次は何ですか？")
        XCTAssertEqual(filtered("嗯，我們走吧。", "zh-Hant"), "我們走吧。")
        XCTAssertEqual(filtered("呃，我们走吧。", "zh_Hans"), "我们走吧。")
    }

    func testFillerOnlyCueBecomesEmptyWithoutExposingAnOlderCue() {
        for (text, language) in [("Um, uh...", "en"), ("Euh… heu.", "fr"), ("えー、えっと。", "ja"), ("嗯，呃……", "zh")] {
            XCTAssertEqual(filtered(text, language), "", text)
        }
    }

    func testDoesNotDeleteMeaningfulWordsOrEmbeddedParticles() {
        let cases = [
            ("Well, I like the right answer.", "en"),
            ("The human opened an umbrella in Durham.", "en"),
            ("Une heure de bonheur, alors on continue.", "fr"),
            ("はい、あの人はまあまあ元気です。", "ja"),
            ("うん、そうだね。", "ja"),
            ("えっと書いてあります。", "ja"),
            ("啊，你不去嗎？那個就是答案吧。", "zh"),
            ("佢唔去。", "zh"),
            ("呃逆是一種症狀。", "zh")
        ]
        for (text, language) in cases { XCTAssertEqual(filtered(text, language), text) }
    }

    func testQuotedTermsAndCompoundsRemainIntact() {
        for text in ["“um” is a hesitation.", "Say 'uh' again.", "The um-pah rhythm.", "(um) is in the transcript."] {
            XCTAssertEqual(filtered(text, "en"), text)
        }
        XCTAssertEqual(filtered("「えっと」は間投詞です。", "ja"), "「えっと」は間投詞です。")
    }

    func testMiddleAndTrailingFillersKeepWordAndSentenceBoundaries() {
        XCTAssertEqual(filtered("We um agree.", "en"), "We agree.")
        XCTAssertEqual(filtered("I, um, agree.", "en"), "I agree.")
        XCTAssertEqual(filtered("Done. Um, Next.", "en"), "Done. Next.")
        XCTAssertEqual(filtered("I agree, um.", "en"), "I agree.")
        XCTAssertEqual(filtered("Choices: uh, red or blue.", "en"), "Choices: red or blue.")
        XCTAssertEqual(filtered("Je suis, euh, prêt.", "fr"), "Je suis prêt.")
        XCTAssertEqual(filtered("今日は、えっと、晴れです。", "ja"), "今日は晴れです。")
        XCTAssertEqual(filtered("我想，嗯，我們走吧。", "zh"), "我想我們走吧。")
    }

    func testUnknownAndAutomaticLanguagesPreservePotentiallyMeaningfulWords() {
        let text = "um die Ecke"
        for language: String? in [nil, "auto", "de", "", "ar"] {
            XCTAssertEqual(filtered(text, language), text)
        }
        XCTAssertEqual(filtered("えっと、続けます。", "en"), "えっと、続けます。")
    }

    func testRepeatedFilteringIsStableAndPunctuationOnlyInputIsUntouched() {
        let once = filtered("Um, I, uh, agree, um.", "en")
        XCTAssertEqual(filtered(once, "en"), once)
        XCTAssertEqual(filtered("！？…", "ja"), "！？…")
        XCTAssertEqual(filtered("", "en"), "")
    }
}
