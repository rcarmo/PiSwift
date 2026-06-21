import Foundation

#if os(macOS)
import AppKit
import Collaboration
#else
import UIKit
#endif

struct ShellUserProfile {
    var displayName: String

    #if os(macOS)
    var image: NSImage?
    #else
    var image: UIImage?
    #endif

    static let current = load()

    private static func load() -> ShellUserProfile {
        #if os(macOS)
        let userName = NSUserName()
        let identity = CBIdentity(name: userName, authority: CBIdentityAuthority.default())
        let fullName = clean(identity?.fullName) ?? clean(NSFullUserName()) ?? userName
        return ShellUserProfile(displayName: fullName, image: identity?.image)
        #else
        let userName = NSUserName()
        let fullName = clean(NSFullUserName()) ?? userName
        return ShellUserProfile(displayName: fullName, image: nil)
        #endif
    }

    private static func clean(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
