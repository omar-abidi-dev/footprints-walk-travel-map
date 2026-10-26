import Foundation
import CoreLocation
import MapKit

nonisolated struct TrackPoint: Hashable, Sendable, Codable {
    var latitude: Double
    var longitude: Double
    var altitude: Double
    var timestamp: TimeInterval

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Packs points as raw doubles: compact and fast to decode.
    static func pack(_ points: [TrackPoint]) -> Data {
        var raw = [Double]()
        raw.reserveCapacity(points.count * 4)
        for p in points { raw += [p.latitude, p.longitude, p.altitude, p.timestamp] }
        return raw.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    static func unpack(_ data: Data) -> [TrackPoint] {
        let count = data.count / MemoryLayout<Double>.size
        guard count >= 4 else { return [] }
        var raw = [Double](repeating: 0, count: count)
        _ = raw.withUnsafeMutableBytes { data.copyBytes(to: $0) }
        return stride(from: 0, to: count - count % 4, by: 4).map {
            TrackPoint(latitude: raw[$0], longitude: raw[$0 + 1], altitude: raw[$0 + 2], timestamp: raw[$0 + 3])
        }
    }
}

nonisolated enum Geo {
    struct Box { var minLat, maxLat, minLon, maxLon: Double }

    static func boundingBox(_ coords: [CLLocationCoordinate2D]) -> Box {
        guard let first = coords.first else { return Box(minLat: 0, maxLat: 0, minLon: 0, maxLon: 0) }
        var b = Box(minLat: first.latitude, maxLat: first.latitude, minLon: first.longitude, maxLon: first.longitude)
        for c in coords {
            b.minLat = min(b.minLat, c.latitude); b.maxLat = max(b.maxLat, c.latitude)
            b.minLon = min(b.minLon, c.longitude); b.maxLon = max(b.maxLon, c.longitude)
        }
        return b
    }

    static func region(fitting coords: [CLLocationCoordinate2D], padding: Double = 1.4, minSpan: Double = 0.006) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        let b = boundingBox(coords)
        let center = CLLocationCoordinate2D(latitude: (b.minLat + b.maxLat) / 2, longitude: (b.minLon + b.maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: min(170, max(minSpan, (b.maxLat - b.minLat) * padding)),
            longitudeDelta: min(350, max(minSpan, (b.maxLon - b.minLon) * padding))
        )
        return MKCoordinateRegion(center: center, span: span)
    }

    static func distance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func pathLength(_ coords: [CLLocationCoordinate2D]) -> Double {
        zip(coords, coords.dropFirst()).reduce(0) { $0 + distance($1.0, $1.1) }
    }

    /// Ramer–Douglas–Peucker simplification with a tolerance in meters.
    static func simplify(_ coords: [CLLocationCoordinate2D], tolerance: Double) -> [CLLocationCoordinate2D] {
        guard coords.count > 2 else { return coords }
        let lat0 = coords[0].latitude * .pi / 180
        let mPerDegLat = 111_320.0
        let mPerDegLon = 111_320.0 * cos(lat0)
        let pts = coords.map { (x: $0.longitude * mPerDegLon, y: $0.latitude * mPerDegLat) }
        var keep = [Bool](repeating: false, count: coords.count)
        keep[0] = true; keep[coords.count - 1] = true
        var stack: [(Int, Int)] = [(0, coords.count - 1)]
        while let (s, e) = stack.popLast() {
            guard e > s + 1 else { continue }
            let a = pts[s], b = pts[e]
            let dx = b.x - a.x, dy = b.y - a.y
            let len = hypot(dx, dy)
            var maxD = 0.0, idx = s
            for i in (s + 1)..<e {
                // Closed loops have start ≈ end: fall back to distance from that point.
                let d = len < 1
                    ? hypot(pts[i].x - a.x, pts[i].y - a.y)
                    : abs(dy * pts[i].x - dx * pts[i].y + b.x * a.y - b.y * a.x) / len
                if d > maxD { maxD = d; idx = i }
            }
            if maxD > tolerance {
                keep[idx] = true
                stack.append((s, idx)); stack.append((idx, e))
            }
        }
        return coords.enumerated().compactMap { keep[$0.offset] ? $0.element : nil }
    }

    /// ~150 m grid cell used for the "explored" metric.
    static func cellKey(_ c: CLLocationCoordinate2D) -> Int64 {
        let size = 0.00135
        let y = Int64((c.latitude / size).rounded(.down))
        let x = Int64((c.longitude / size).rounded(.down))
        return y &* 1_000_000 &+ x
    }

    /// Approximate km² for one explored cell.
    static let cellAreaKm2 = 0.15 * 0.15

    static func boxesIntersect(_ walk: Box, _ region: MKCoordinateRegion) -> Bool {
        let rMinLat = region.center.latitude - region.span.latitudeDelta / 2
        let rMaxLat = region.center.latitude + region.span.latitudeDelta / 2
        let rMinLon = region.center.longitude - region.span.longitudeDelta / 2
        let rMaxLon = region.center.longitude + region.span.longitudeDelta / 2
        return walk.maxLat >= rMinLat && walk.minLat <= rMaxLat && walk.maxLon >= rMinLon && walk.minLon <= rMaxLon
    }
}

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
