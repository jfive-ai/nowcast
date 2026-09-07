import XCTest

final class URLCanonicalizerTests: XCTestCase {
    private func url(_ text: String) throws -> URL { try XCTUnwrap(URL(string: text)) }
    func testTrackingParametersAndFragmentsAreRemoved() throws {
        let input = try url("https://www.example.com/story/?utm_source=x&fbclid=y&gclid=z&id=42#comments")
        XCTAssertEqual(URLCanonicalizer.canonicalize(input).absoluteString, "https://example.com/story?id=42")
    }
    func testMobileHostCaseAndDefaultPortNormalize() throws {
        XCTAssertEqual(URLCanonicalizer.canonicalize(try url("HTTPS://M.EXAMPLE.COM:443/story/")).absoluteString, "https://example.com/story")
    }
    func testYouTubeShareFormsHaveTheSameHash() throws {
        let short = try url("https://youtu.be/abc?t=30&si=share")
        let long = try url("https://www.youtube.com/watch?v=abc&t=50&feature=share")
        XCTAssertEqual(URLCanonicalizer.hash(short), URLCanonicalizer.hash(long))
    }
    func testMeaningfulQueryAndNondefaultPortRemain() throws {
        XCTAssertEqual(URLCanonicalizer.canonicalize(try url("https://example.com:8443/?id=42")).absoluteString, "https://example.com:8443/?id=42")
        XCTAssertNotEqual(URLCanonicalizer.hash(try url("https://example.com/?id=1")), URLCanonicalizer.hash(try url("https://example.com/?id=2")))
    }
    func testCanonicalizationIsIdempotent() throws {
        let once = URLCanonicalizer.canonicalize(try url("https://www.example.com:443/article/?utm_medium=mail"))
        XCTAssertEqual(URLCanonicalizer.canonicalize(once), once)
    }
}
