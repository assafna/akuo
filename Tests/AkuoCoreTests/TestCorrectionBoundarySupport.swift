@testable import AkuoCore

extension CompletedWord {
    init(
        token: String,
        boundary: String,
        keyStrokes: [ObservedKeyStroke] = [],
        physicalTraceIntegrity: PhysicalTraceIntegrity = .unavailable
    ) {
        let validatedBoundary: CorrectionBoundary?
        if boundary.isEmpty {
            validatedBoundary = nil
        } else {
            validatedBoundary = CorrectionBoundary(
                text: boundary,
                keyCode: Self.testBoundaryKeyCode(for: boundary)
            )
            precondition(validatedBoundary != nil, "Unsupported test correction boundary")
        }
        self.init(
            token: token,
            boundary: validatedBoundary,
            keyStrokes: keyStrokes,
            physicalTraceIntegrity: physicalTraceIntegrity
        )
    }

    private static func testBoundaryKeyCode(for text: String) -> Int {
        switch text {
        case " ": 49
        case "\r", "\n": 36
        case "\u{3}": 76
        default: -1
        }
    }
}
