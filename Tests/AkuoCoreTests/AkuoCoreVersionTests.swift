import XCTest
@testable import AkuoCore

final class AkuoCoreVersionTests: XCTestCase {
    // Production mutation caught: changing the authoritative candidate version
    // or build identity away from the approved Unreleased values.
    func testCurrentCandidateIdentityIsPointFourBuildSeventeen() {
        XCTAssertEqual(AkuoCoreVersion.current, "0.4.0")
        XCTAssertEqual(AkuoCoreVersion.build, "17")
    }
}
