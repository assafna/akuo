import XCTest
@testable import AkuoCore

final class AkuoCoreVersionTests: XCTestCase {
    func testInitialVersionIsPointOne() {
        XCTAssertEqual(AkuoCoreVersion.current, "0.1.0")
    }
}
