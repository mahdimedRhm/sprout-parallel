import AppKit
import SwiftUI

enum Theme {
    static let bg = Color(hex: 0x0B0F14)
    static let bar = Color(hex: 0x0E141B)
    static let sidebar = Color(hex: 0x0A0E12)
    static let selection = Color(hex: 0x12202B)
    static let selectionEdge = Color(hex: 0x1D3A4A)
    static let border = Color(hex: 0x1F2A36)
    static let logBg = Color(hex: 0x070A0D)
    static let green = Color(hex: 0x39FFA0)
    static let amber = Color(hex: 0xFFCC66)
    static let red = Color(hex: 0xFF6B6B)
    static let cyan = Color(hex: 0x56D4FF)
    static let violet = Color(hex: 0xC792EA)
    static let muted = Color(hex: 0x6B7A8C)
    static let text = Color(hex: 0xC9D1D9)
    static let bright = Color(hex: 0xE6EDF3)

    private static let hasJetBrainsMono = NSFont(name: "JetBrainsMono-Regular", size: 12) != nil

    static func mono(_ size: CGFloat = 12, weight: Font.Weight = .regular) -> Font {
        hasJetBrainsMono
            ? .custom("JetBrains Mono", size: size).weight(weight)
            : .system(size: size, weight: weight, design: .monospaced)
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1)
    }
}
