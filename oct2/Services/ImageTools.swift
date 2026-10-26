import Foundation
import ImageIO
import UniformTypeIdentifiers
import CoreImage
import CoreImage.CIFilterBuiltins

/// Thread-safe image helpers (ImageIO + Core Image only, no UIKit).
nonisolated enum ImageTools {
    struct Prepared: Sendable {
        let jpeg: Data
        let colorHex: String?
    }

    /// Downscales a picked photo and extracts its representative color.
    static func prepare(_ data: Data, maxPixel: Int = 1600) -> Prepared? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }

        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Prepared(jpeg: out as Data, colorHex: representativeColor(cg))
    }

    /// Average color, nudged toward a vivid tone so map dots stay readable.
    static func representativeColor(_ image: CGImage) -> String? {
        let ci = CIImage(cgImage: image)
        let filter = CIFilter.areaAverage()
        filter.inputImage = ci
        filter.extent = ci.extent
        guard let output = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        let ctx = CIContext(options: [.workingColorSpace: NSNull()])
        ctx.render(output, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)

        let (h, s0, v0) = rgbToHsv(Double(px[0]) / 255, Double(px[1]) / 255, Double(px[2]) / 255)
        let s = min(1, max(0.45, s0 * 1.5))
        let v = min(0.92, max(0.55, v0 * 1.15))
        let (r, g, b) = hsvToRgb(h, s, v)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }

    private static func rgbToHsv(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
        var h = 0.0
        if d > 0 {
            if mx == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if mx == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, mx == 0 ? 0 : d / mx, mx)
    }

    private static func hsvToRgb(_ h: Double, _ s: Double, _ v: Double) -> (Double, Double, Double) {
        let i = Int(h * 6) % 6
        let f = h * 6 - Double(Int(h * 6))
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch i {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
