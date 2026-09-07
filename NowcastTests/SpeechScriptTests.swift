import XCTest

final class SpeechScriptTests: XCTestCase {
    func testCodeAndStructuredFooterAreNotSpoken() {
        let input = "Hello\n```swift\nlet secret = 1\n```\nWorld\n<!-- briefing-json -->\n{\"hidden\":true}"
        XCTAssertEqual(SpeechScript.make(from: input), "Hello\nWorld")
    }
    func testHeadingsBulletsAndAbbreviationsBecomeSpeech() {
        XCTAssertEqual(SpeechScript.make(from: "## TL;DR\n- USD 10 vs. USD 5"), "Quick take.\nUS dollars 10 versus US dollars 5")
    }
    func testLinksRetainLabelsAndDropURLs() {
        XCTAssertEqual(SpeechScript.make(from: "Read [the report](https://example.com). https://example.org"), "Read the report.")
    }
    func testUnclosedCodeFenceDoesNotLeakCode() {
        XCTAssertEqual(SpeechScript.make(from: "Visible\n```\nnot spoken"), "Visible")
    }
}
