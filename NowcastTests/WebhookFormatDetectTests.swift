import XCTest

final class WebhookFormatDetectTests: XCTestCase {
    func testKnownProviderHosts() {
        XCTAssertEqual(WebhookFormat.detect(from: "https://hooks.slack.com/services/a"), .slack)
        XCTAssertEqual(WebhookFormat.detect(from: "https://discord.com/api/webhooks/a"), .discord)
        XCTAssertEqual(WebhookFormat.detect(from: "https://discordapp.com/api/webhooks/a"), .discord)
    }
    func testGenericAndMalformedURLs() {
        XCTAssertEqual(WebhookFormat.detect(from: "https://example.com/hook"), .generic)
        XCTAssertEqual(WebhookFormat.detect(from: "not a URL"), .generic)
        XCTAssertEqual(WebhookFormat.detect(from: ""), .generic)
    }
}
