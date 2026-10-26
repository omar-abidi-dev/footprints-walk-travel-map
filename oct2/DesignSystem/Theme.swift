import SwiftUI
import UIKit

/// Central palette for Footprints: warm "sunrise" for places, cool "trail" for walks.
enum Theme {
    static let coral = Color(hex: 0xFF5A36)
    static let amber = Color(hex: 0xFFAE34)
    static let teal = Color(hex: 0x10B5A4)
    static let ocean = Color(hex: 0x2F7CF6)
    static let violet = Color(hex: 0x7C5CFA)
    static let rose = Color(hex: 0xF43F72)
    static let moss = Color(hex: 0x4FAE3C)
    static let gold = Color(hex: 0xF5B700)
    static let silver = Color(hex: 0x9AA7B8)
    static let bronze = Color(hex: 0xC4733B)

    static let sunrise = LinearGradient(colors: [coral, amber], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let trail = LinearGradient(colors: [teal, ocean, violet], startPoint: .leading, endPoint: .trailing)
    static let trailColors: [Color] = [teal, ocean, violet]

    static let card = Color(uiColor: .secondarySystemGroupedBackground)
    static let canvas = Color(uiColor: .systemGroupedBackground)

    /// A soft mesh used behind hero cards. Pass 9 colors (3×3 grid).
    static func mesh(_ colors: [Color]) -> MeshGradient {
        let c = (0..<9).map { colors[$0 % max(colors.count, 1)] }
        return MeshGradient(
            width: 3, height: 3,
            points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.55, 0.45], [1, 0.5],
                [0, 1], [0.5, 1], [1, 1]
            ],
            colors: c
        )
    }

    static let heroMesh: [Color] = [
        coral, amber, Color(hex: 0xFFD27A),
        rose, coral, amber,
        violet, rose, coral
    ]

    static let worldMesh: [Color] = [
        teal, ocean, Color(hex: 0x6EE7F9),
        ocean, violet, teal,
        violet, ocean, Color(hex: 0x34D399)
    ]
}

extension Color {
    nonisolated init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    nonisolated init?(hexString: String?) {
        guard var s = hexString?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(hex: v)
    }
}

extension View {
    /// Rounded grouped-style card.
    func card(padding: CGFloat = 16, radius: CGFloat = 22) -> some View {
        self
            .padding(padding)
            .background(Theme.card, in: .rect(cornerRadius: radius, style: .continuous))
    }
}
