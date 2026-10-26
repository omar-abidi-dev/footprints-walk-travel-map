import SwiftUI
import UIKit

struct StatTile: View {
    let value: String
    let label: String
    let symbol: String
    var tint: Color = Theme.coral

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.15), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title3.weight(.bold))
                    .fontDesign(.rounded)
                    .contentTransition(.numericText())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14, radius: 20)
    }
}

struct ProgressRing: View {
    var progress: Double
    var lineWidth: CGFloat = 8
    var colors: [Color] = [Theme.coral, Theme.amber, Theme.coral]

    var body: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.002, min(progress, 1)))
                .stroke(
                    AngularGradient(colors: colors, center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
        .animation(.spring(duration: 0.8), value: progress)
    }
}

/// Pointy-top hexagon used for region tiles.
struct Hexagon: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let cx = rect.midX
        var p = Path()
        p.move(to: CGPoint(x: cx, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.25))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + h * 0.75))
        p.addLine(to: CGPoint(x: cx, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.75))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + h * 0.25))
        p.closeSubpath()
        _ = w
        return p
    }
}

/// The colored dot for a place on the map; shows the photo when there is one.
struct PlaceDot: View {
    let color: Color
    var image: UIImage?
    var symbol: String?
    var size: CGFloat = 22
    var selected = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(.circle)
            } else {
                Circle()
                    .fill(color.gradient)
                    .frame(width: size, height: size)
                if let symbol, size >= 26 {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.42, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
        }
        .overlay(Circle().stroke(.white, lineWidth: selected ? 3.5 : 2.5))
        .overlay(Circle().stroke(color, lineWidth: selected ? 2 : 0).padding(-4))
        .shadow(color: color.opacity(0.45), radius: selected ? 8 : 4, y: 2)
        .scaleEffect(selected ? 1.25 : 1)
        .animation(.spring(duration: 0.3), value: selected)
    }
}

nonisolated enum Flag {
    static func emoji(_ code: String?) -> String {
        guard let code, code.count == 2 else { return "🏳️" }
        let base: UInt32 = 127397
        var s = ""
        for scalar in code.uppercased().unicodeScalars {
            if let u = UnicodeScalar(base + scalar.value) { s.unicodeScalars.append(u) }
        }
        return s
    }

    static func name(_ code: String?) -> String {
        guard let code else { return "Unknown" }
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title3.weight(.bold)).fontDesign(.rounded)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct Chip: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol) }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(tint)
        .background(tint.opacity(0.12), in: .capsule)
    }
}

/// Small rounded thumbnail for a photo or a fallback symbol.
struct Thumb: View {
    let image: UIImage?
    var symbol: String = "photo"
    var tint: Color = Theme.coral
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Rectangle().fill(tint.gradient)
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.38, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(.rect(cornerRadius: size * 0.28, style: .continuous))
    }
}
