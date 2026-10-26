import Foundation
import UIKit
import MapKit
import SwiftUI

/// Decoded routes are immutable once saved, so they are cached by walk id.
final class RouteCache {
    static let shared = RouteCache()

    private var full: [UUID: [TrackPoint]] = [:]
    private var display: [UUID: [CLLocationCoordinate2D]] = [:]

    func points(for walk: Walk) -> [TrackPoint] {
        if let cached = full[walk.id] { return cached }
        let pts = TrackPoint.unpack(walk.routeData)
        full[walk.id] = pts
        return pts
    }

    /// Simplified coordinates for drawing on maps.
    func displayCoordinates(for walk: Walk) -> [CLLocationCoordinate2D] {
        if let cached = display[walk.id] { return cached }
        let coords = Geo.simplify(points(for: walk).map(\.coordinate), tolerance: 6)
        display[walk.id] = coords
        return coords
    }

    func removeAll() {
        full.removeAll()
        display.removeAll()
    }
}

final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, UIImage>()

    func image(id: UUID, data: Data?, side: CGFloat) -> UIImage? {
        guard let data else { return nil }
        let key = "\(id.uuidString)-\(Int(side))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let scale = UITraitCollection.current.displayScale
        let px = side * max(scale, 2)
        guard let img = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: px, height: px * aspect(data))) else { return nil }
        cache.setObject(img, forKey: key)
        return img
    }

    private func aspect(_ data: Data) -> CGFloat {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat, w > 0 else { return 1 }
        // Thumbnails fill a square, so make the short side cover `side`.
        return w > h ? 1 : h / w
    }

    func removeAll() { cache.removeAllObjects() }
}

/// Renders static map images with a route drawn on top (used for journal rows and share cards).
/// Uses Apple's snapshotter, or web tiles (OpenStreetMap / Esri) when that style is chosen or Apple's map is unavailable.
final class RouteSnapshotter {
    static let shared = RouteSnapshotter()
    private let cache = NSCache<NSString, UIImage>()

    func image(for walk: Walk, size: CGSize, dark: Bool) async -> UIImage? {
        let style = MapStyleChoice(rawValue: UserDefaults.standard.string(forKey: "mapStyle") ?? "") ?? .standard
        let key = "\(walk.id.uuidString)-\(Int(size.width))x\(Int(size.height))-\(dark)-\(style.rawValue)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        let coords = RouteCache.shared.displayCoordinates(for: walk)
        guard let region = Geo.region(fitting: coords, padding: 1.5, minSpan: 0.004) else { return nil }

        var base: (UIImage, (CLLocationCoordinate2D) -> CGPoint)?
        if style.tileTemplate == nil {
            base = await appleBase(region: region, size: size, dark: dark)
        }
        if base == nil {
            let template = (style.tileTemplate ?? MapStyleChoice.street.tileTemplate)!
            base = await TileCompositor.render(region: region, size: size, template: template)
        }
        guard let (baseImage, project) = base else { return nil }

        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            baseImage.draw(in: CGRect(origin: .zero, size: size))
            Self.drawRoute(coords.map(project), size: size, in: ctx.cgContext)
        }
        cache.setObject(image, forKey: key)
        return image
    }

    private func appleBase(region: MKCoordinateRegion, size: CGSize, dark: Bool) async -> (UIImage, (CLLocationCoordinate2D) -> CGPoint)? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        options.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
        options.pointOfInterestFilter = .excludingAll
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return nil }
        return (snapshot.image, { snapshot.point(for: $0) })
    }

    private static func drawRoute(_ pts: [CGPoint], size: CGSize, in cg: CGContext) {
        guard pts.count > 1 else { return }
        let path = CGMutablePath()
        path.addLines(between: pts)
        cg.setLineCap(.round)
        cg.setLineJoin(.round)

        cg.addPath(path)
        cg.setLineWidth(max(4, size.width / 40))
        cg.setStrokeColor(UIColor.white.withAlphaComponent(0.9).cgColor)
        cg.strokePath()

        cg.saveGState()
        cg.addPath(path)
        cg.setLineWidth(max(2.5, size.width / 70))
        cg.replacePathWithStrokedPath()
        cg.clip()
        let colors = [UIColor(Theme.teal).cgColor, UIColor(Theme.ocean).cgColor, UIColor(Theme.violet).cgColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.5, 1]) {
            let loop = hypot(pts[0].x - pts[pts.count - 1].x, pts[0].y - pts[pts.count - 1].y) < 8
            let a = loop ? CGPoint.zero : pts[0]
            let b = loop ? CGPoint(x: size.width, y: size.height) : pts[pts.count - 1]
            cg.drawLinearGradient(gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        cg.restoreGState()

        let s = pts[0]
        let dot = max(6, size.width / 24)
        cg.setFillColor(UIColor.white.cgColor)
        cg.fillEllipse(in: CGRect(x: s.x - dot / 2 - 1.5, y: s.y - dot / 2 - 1.5, width: dot + 3, height: dot + 3))
        cg.setFillColor(UIColor(Theme.teal).cgColor)
        cg.fillEllipse(in: CGRect(x: s.x - dot / 2, y: s.y - dot / 2, width: dot, height: dot))
    }
}

/// Stitches web-mercator tiles into a static image for a region.
enum TileCompositor {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpAdditionalHeaders = ["User-Agent": "Footprints/1.0 (iOS; \(Bundle.main.bundleIdentifier ?? "footprints"))"]
        config.urlCache = URLCache(memoryCapacity: 16 << 20, diskCapacity: 128 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// World pixel coordinates at zoom `z` (256-px tiles).
    private static func pixel(_ c: CLLocationCoordinate2D, z: Int) -> CGPoint {
        let scale = 256.0 * pow(2.0, Double(z))
        let lat = max(min(c.latitude, 85.0511), -85.0511) * .pi / 180
        let x = (c.longitude + 180) / 360 * scale
        let y = (1 - log(tan(lat) + 1 / cos(lat)) / .pi) / 2 * scale
        return CGPoint(x: x, y: y)
    }

    static func render(region: MKCoordinateRegion, size: CGSize, template: String) async -> (UIImage, (CLLocationCoordinate2D) -> CGPoint)? {
        let scale: CGFloat = 2   // tiles are drawn at half size for crispness
        let outPx = CGSize(width: size.width * scale, height: size.height * scale)
        let nw = CLLocationCoordinate2D(latitude: region.center.latitude + region.span.latitudeDelta / 2,
                                        longitude: region.center.longitude - region.span.longitudeDelta / 2)
        let se = CLLocationCoordinate2D(latitude: region.center.latitude - region.span.latitudeDelta / 2,
                                        longitude: region.center.longitude + region.span.longitudeDelta / 2)
        var z = 18
        while z > 1 {
            let a = pixel(nw, z: z), b = pixel(se, z: z)
            if abs(b.x - a.x) <= outPx.width && abs(b.y - a.y) <= outPx.height { break }
            z -= 1
        }
        let center = pixel(region.center, z: z)
        let origin = CGPoint(x: center.x - outPx.width / 2, y: center.y - outPx.height / 2)
        let maxTile = 1 << z
        let x0 = Int(floor(origin.x / 256)), x1 = Int(floor((origin.x + outPx.width) / 256))
        let y0 = max(0, Int(floor(origin.y / 256))), y1 = min(maxTile - 1, Int(floor((origin.y + outPx.height) / 256)))
        guard x1 - x0 < 8, y1 - y0 < 8 else { return nil }

        var tiles: [(Int, Int, UIImage)] = []
        await withTaskGroup(of: (Int, Int, UIImage?).self) { group in
            for tx in x0...x1 {
                for ty in y0...y1 {
                    let wrapped = ((tx % maxTile) + maxTile) % maxTile
                    let urlString = template
                        .replacingOccurrences(of: "{z}", with: "\(z)")
                        .replacingOccurrences(of: "{x}", with: "\(wrapped)")
                        .replacingOccurrences(of: "{y}", with: "\(ty)")
                    guard let url = URL(string: urlString) else { continue }
                    group.addTask {
                        let data = try? await session.data(from: url).0
                        return (tx, ty, data.flatMap { UIImage(data: $0) })
                    }
                }
            }
            for await (tx, ty, img) in group { if let img { tiles.append((tx, ty, img)) } }
        }
        guard !tiles.isEmpty else { return nil }

        let image = UIGraphicsImageRenderer(size: size).image { _ in
            for (tx, ty, img) in tiles {
                let rect = CGRect(x: (CGFloat(tx) * 256 - origin.x) / scale, y: (CGFloat(ty) * 256 - origin.y) / scale,
                                  width: 256 / scale, height: 256 / scale)
                img.draw(in: rect)
            }
        }
        let project: (CLLocationCoordinate2D) -> CGPoint = { c in
            let p = pixel(c, z: z)
            return CGPoint(x: (p.x - origin.x) / scale, y: (p.y - origin.y) / scale)
        }
        return (image, project)
    }
}
