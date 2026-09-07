import XCTest

final class BriefDiffTests: XCTestCase {
    func testIdenticalClustersContinue() {
        let item = cluster(headline: "Ethereum ETF inflows surge")
        let result = BriefDiff.diff(current: [item], prior: [item])
        XCTAssertEqual(result.continuingClusters.count, 1)
        XCTAssertTrue(result.newClusters.isEmpty)
        XCTAssertTrue(result.droppedClusters.isEmpty)
    }
    func testReorderedHeadlinesContinue() {
        let result = BriefDiff.diff(current: [cluster("new", headline: "Surging ETH ETF flows")], prior: [cluster("old", headline: "ETH ETF flows surge")])
        XCTAssertEqual(result.continuingClusters.count, 1)
    }
    func testUnrelatedClusterIsNewAndOldOneDrops() {
        let result = BriefDiff.diff(current: [cluster("new", headline: "Volcano eruption closes airports")], prior: [cluster("old", headline: "Ethereum staking rewards increase")])
        XCTAssertEqual(result.newClusters.map(\.id), ["new"])
        XCTAssertEqual(result.droppedClusters.map(\.id), ["old"])
    }
    func testEachPriorClusterMatchesAtMostOnce() {
        let result = BriefDiff.diff(current: [cluster("one", headline: "Mars rover finds water"), cluster("two", headline: "Mars rover finds water")], prior: [cluster("old", headline: "Mars rover finds water")])
        XCTAssertEqual(result.continuingClusters.count, 1)
        XCTAssertEqual(result.newClusters.count, 1)
    }
    func testEmptyInputsAndInitialBrief() {
        XCTAssertNil(BriefDiff.renderMarkdown(BriefDiff.diff(current: [], prior: [])))
        XCTAssertEqual(BriefDiff.diff(current: [cluster()], prior: []).newClusters.count, 1)
        XCTAssertEqual(BriefDiff.diff(current: [], prior: [cluster()]).droppedClusters.count, 1)
    }
}
