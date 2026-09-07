import XCTest

final class BigStoryScorerTests: XCTestCase {
    func testEmptyBriefHasNoHeadlineOrScore() {
        let result = BigStoryScorer.score(brief([]))
        XCTAssertEqual(result.score, 0)
        XCTAssertNil(result.headline)
    }
    func testIndependentHostsIncreaseScore() {
        let four = cluster(citations: ["https://a.com/1", "https://b.com/2", "https://c.com/3", "https://d.com/4"])
        XCTAssertEqual(BigStoryScorer.score(brief([four])).score, 4.5)
        XCTAssertEqual(BigStoryScorer.score(brief([cluster(citations: ["https://a.com/1", "https://a.com/2"])])).score, 1)
    }
    func testClaimCitationsCountButWWWAndCaseDoNotDuplicateHosts() {
        let item = cluster(citations: ["https://www.EXAMPLE.com/1", "not a URL"], claims: [.init(text: "Claim", citations: ["https://example.com/2", "https://other.com/3"])])
        XCTAssertEqual(BigStoryScorer.score(brief([item])).score, 2)
    }
    func testSmallHistoryUsesAbsoluteFloor() {
        XCTAssertFalse(BigStoryScorer.isBig(score: 4.9, comparison: []))
        XCTAssertTrue(BigStoryScorer.isBig(score: 5, comparison: []))
    }
    func testLongHistoryUsesPercentileAndRejectsZeroScore() {
        let prior = (1...10).map(Double.init)
        XCTAssertFalse(BigStoryScorer.isBig(score: 7, comparison: prior))
        XCTAssertTrue(BigStoryScorer.isBig(score: 8, comparison: prior))
        XCTAssertFalse(BigStoryScorer.isBig(score: 0, comparison: Array(repeating: 0, count: 10)))
    }
}
