import AppKit
import SwiftUI

@main struct AppearanceSmoke {
    static func main() {
        let app = NSApplication.shared
        DEXAppearance.applyToApplication()
        precondition(DEXAppearance.colorScheme == .dark, "DEX must force SwiftUI dark mode")
        precondition(app.appearance?.name == .darkAqua, "DEX must force AppKit dark Aqua before showing its window")
        print("PASS: SwiftUI and AppKit appearance policies are both dark")
    }
}
