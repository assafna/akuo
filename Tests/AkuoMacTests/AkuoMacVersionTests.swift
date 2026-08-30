import XCTest
@testable import AkuoMac

final class AkuoMacVersionTests: XCTestCase {
    func testMacVersionBridgesCoreVersion() {
        XCTAssertEqual(AkuoMacVersion.current, "0.1.0")
    }
}
