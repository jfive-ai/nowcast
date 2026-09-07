import XCTest

final class SourceReliabilityTests: XCTestCase {
    private func reliability(_ score: Int) -> SourceReliability {
        .init(host: "example.com", mentions: 0, thumbsUp: 0, thumbsDown: 0, hallucinations: 0, score: score)
    }
    func testUnratedSourceStartsNeutral() {
        XCTAssertEqual(SourceReliability.formula(mentions: 0, thumbsUp: 0, thumbsDown: 0, hallucinations: 0), 50)
    }
    func testBandBoundaries() {
        XCTAssertEqual(reliability(39).band, .watch)
        XCTAssertEqual(reliability(40).band, .mixed)
        XCTAssertEqual(reliability(69).band, .mixed)
        XCTAssertEqual(reliability(70).band, .ok)
    }
    func testOutlyingFeedbackIsClamped() {
        XCTAssertEqual(SourceReliability.formula(mentions: 1, thumbsUp: 1000, thumbsDown: 0, hallucinations: 0), 100)
        XCTAssertEqual(SourceReliability.formula(mentions: 1, thumbsUp: 0, thumbsDown: 1000, hallucinations: 0), 0)
    }
    func testHallucinationPenaltyExceedsThumbsDown() {
        let down = SourceReliability.formula(mentions: 5, thumbsUp: 0, thumbsDown: 1, hallucinations: 0)
        let hallucination = SourceReliability.formula(mentions: 5, thumbsUp: 0, thumbsDown: 0, hallucinations: 1)
        XCTAssertLessThan(hallucination, down)
    }
}
