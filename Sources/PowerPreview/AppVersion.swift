import Foundation

enum AppVersion {
    /// Keep in sync with Scripts/package-dmg.sh VERSION default.
    static let current = "0.2.2"

    static var display: String { current }

    static var marketing: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? current
    }
}
