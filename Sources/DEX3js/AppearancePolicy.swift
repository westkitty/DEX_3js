import AppKit
import SwiftUI

enum DEXAppearance {
    static let colorScheme: ColorScheme = .dark

    static func applyToApplication() {
        NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
    }
}
