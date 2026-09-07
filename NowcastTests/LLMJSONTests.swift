import XCTest

final class LLMJSONTests: XCTestCase {
    private struct Value: Decodable { let count: Int }
    func testRawFencedAndProseWrappedObjects() {
        for input in ["{\"count\":3}", "```JSON\n{\"count\":3}\n```", "Result: {\"count\":3} done"] {
            XCTAssertEqual(LLMJSON.decode(Value.self, from: input)?.count, 3)
        }
    }
    func testArrayAndMissingClosingFence() {
        XCTAssertEqual(LLMJSON.decode([Int].self, from: "Items: [1,2,3] done"), [1,2,3])
        XCTAssertEqual(LLMJSON.decode(Value.self, from: "```json\n{\"count\":4}")?.count, 4)
    }
    func testMalformedAndWrongShapeReturnNil() {
        XCTAssertNil(LLMJSON.decode(Value.self, from: "{\"count\":}"))
        XCTAssertNil(LLMJSON.decode(Value.self, from: "[1,2]"))
    }
}
