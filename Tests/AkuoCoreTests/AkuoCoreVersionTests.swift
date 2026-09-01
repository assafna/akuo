import XCTest
@testable import AkuoCore

final class AkuoCoreVersionTests: XCTestCase {
    func testCurrentVersionIsPointThree() {
        XCTAssertEqual(AkuoCoreVersion.current, "0.3.0")
    }
}
