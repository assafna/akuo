public struct CorrectionBoundary: Equatable, Sendable {
    public let text: String
    public let keyCode: Int

    public init?(text: String, keyCode: Int) {
        switch (keyCode, text) {
        case (49, " "), (36, "\r"), (36, "\n"), (76, "\u{3}"):
            self.text = text
            self.keyCode = keyCode
        default:
            return nil
        }
    }
}
