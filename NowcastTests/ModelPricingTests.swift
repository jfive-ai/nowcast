import XCTest

final class ModelPricingTests: XCTestCase {
    func testLongestPrefixWinsIgnoringCase() {
        XCTAssertEqual(ModelPricing.entry(forModel: "GPT-4O-MINI-2024")?.prefix, "gpt-4o-mini")
        XCTAssertEqual(ModelPricing.entry(forModel: "gpt-4o-2024")?.prefix, "gpt-4o")
    }
    func testUnknownModelIsNotReportedAsFree() {
        XCTAssertNil(ModelPricing.entry(forModel: "unlisted-model"))
        XCTAssertNil(ModelPricing.cost(forModel: "unlisted-model", usage: .init(promptTokens: 10, completionTokens: 20)))
    }
    func testInputAndOutputCostAreBothCounted() throws {
        let cost = try XCTUnwrap(ModelPricing.cost(forModel: "gpt-4o-mini", usage: .init(promptTokens: 1_000_000, completionTokens: 2_000_000)))
        XCTAssertEqual(cost, 1.35, accuracy: 0.000001)
    }
    func testLocalModelAndZeroUsageAreFree() {
        XCTAssertEqual(ModelPricing.cost(forModel: "llama3", usage: .init(promptTokens: 200, completionTokens: 100)), 0)
        XCTAssertEqual(ModelPricing.cost(forModel: "gpt-4o", usage: .init(promptTokens: 0, completionTokens: 0)), 0)
    }
    func testEstimateMultipliesCallsAndClampsNegativeCallCount() {
        XCTAssertEqual(ModelPricing.estimate(model: "gpt-4o", calls: 2, avgPromptTokens: 1_000_000, avgCompletionTokens: 0), 5)
        XCTAssertEqual(ModelPricing.estimate(model: "gpt-4o", calls: -1, avgPromptTokens: 100, avgCompletionTokens: 100), 0)
    }
}
