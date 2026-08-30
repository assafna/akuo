import XCTest
@testable import AkuoCore

final class AkuoCoreVersionTests: XCTestCase {
    func testCurrentVersionIsPointTwo() {
        XCTAssertEqual(AkuoCoreVersion.current, "0.2.0")
    }
}
