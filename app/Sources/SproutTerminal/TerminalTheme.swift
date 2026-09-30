import AppKit
import SwiftTerm

/// Sprout's palette applied to SwiftTerm.
public enum TerminalTheme {
    /// ANSI 0–15: normal then bright.
    public static let ansi: [UInt32] = [
        0x0B0F14, 0xFF6B6B, 0x39FFA0, 0xFFCC66, 0x56D4FF, 0xC792EA, 0x56D4FF, 0xC9D1D9,
        0x6B7A8C, 0xFF8A8A, 0x7CFFC0, 0xFFDD99, 0x8AE2FF, 0xDDB3F5, 0x8AE2FF, 0xE6EDF3,
    ]

    public static func apply(to view: TerminalView) {
        view.installColors(ansi.map(terminalColor))
        view.nativeBackgroundColor = nsColor(0x070A0D)
        view.nativeForegroundColor = nsColor(0xC9D1D9)
        view.caretColor = nsColor(0x39FFA0)
        view.selectedTextBackgroundColor = nsColor(0x1D3A4A)
        view.font = NSFont(name: "JetBrainsMono-Regular", size: 12)
            ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    public static func nsColor(_ hex: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1)
    }

    /// SwiftTerm colours are 16-bit per channel.
    static func terminalColor(_ hex: UInt32) -> SwiftTerm.Color {
        SwiftTerm.Color(
            red: UInt16((hex >> 16) & 0xFF) * 257,
            green: UInt16((hex >> 8) & 0xFF) * 257,
            blue: UInt16(hex & 0xFF) * 257)
    }
}
