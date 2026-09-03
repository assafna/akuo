import XCTest
import AkuoCore
@testable import AkuoMac

final class AkuoMacVersionTests: XCTestCase {
    // Production mutation caught: duplicating or drifting either runtime identity
    // value in AkuoMac instead of deriving both values from AkuoCore.
    func testMacCandidateIdentityBridgesCoreIdentity() {
        XCTAssertEqual(AkuoMacVersion.current, AkuoCoreVersion.current)
        XCTAssertEqual(AkuoMacVersion.build, AkuoCoreVersion.build)
        XCTAssertEqual(AkuoMacVersion.sourceRevision, AkuoSourceRevision.current)
    }
}
