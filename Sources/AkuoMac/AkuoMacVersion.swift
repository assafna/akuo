import AkuoCore

public enum AkuoMacVersion {
    public static let current = AkuoCoreVersion.current
    public static let build = AkuoCoreVersion.build

    public static var packagingIdentity: String {
        "\(current)\t\(build)"
    }
}
