import Foundation
import SwiftData
import CoreLocation

/// Parses Google Timeline exports. Supports:
///  • On-device export (2024+): `{ "semanticSegments": [...] }`
///  • Older iOS export: top-level array of `{ visit | activity | timelinePath }`
///  • Takeout Semantic Location History: `{ "timelineObjects": [...] }`
nonisolated struct TimelineParser {
    struct Visit: Sendable {
        var latitude: Double
        var longitude: Double
        var start: Date
        var end: Date
        var name: String?
        var semanticType: String?
        var count = 1
    }

    struct Path: Sendable {
        var points: [TrackPoint]
        var start: Date
        var end: Date
        var distance: Double
    }

    struct Result: Sendable {
        var visits: [Visit]
        var walks: [Path]
        var rawVisitCount: Int
    }

    enum ParseError: LocalizedError {
        case unrecognized
        case rawRecordsOnly
        var errorDescription: String? {
            switch self {
            case .unrecognized: "This file doesn't look like a Google Timeline export."
            case .rawRecordsOnly: "Records.json only contains raw GPS pings. Export “Timeline” (or Semantic Location History) instead."
            }
        }
    }

    private struct Activity { var start: Date; var end: Date; var from: CLLocationCoordinate2D?; var to: CLLocationCoordinate2D?; var distance: Double; var type: String }

    private let isoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let iso = ISO8601DateFormatter()

    func parse(_ data: Data) throws -> Result {
        let json = try JSONSerialization.jsonObject(with: data)
        var visits: [Visit] = []
        var activities: [Activity] = []
        var pathPoints: [TrackPoint] = []
        var takeoutWalks: [Path] = []

        if let root = json as? [String: Any], let segments = root["semanticSegments"] as? [[String: Any]] {
            parseSegments(segments, &visits, &activities, &pathPoints)
        } else if let segments = json as? [[String: Any]] {
            parseSegments(segments, &visits, &activities, &pathPoints)
        } else if let root = json as? [String: Any], let objects = root["timelineObjects"] as? [[String: Any]] {
            parseTakeout(objects, &visits, &takeoutWalks)
        } else if let root = json as? [String: Any], root["locations"] != nil {
            throw ParseError.rawRecordsOnly
        } else {
            throw ParseError.unrecognized
        }

        // Join on-foot activities with the path points recorded during them.
        pathPoints.sort { $0.timestamp < $1.timestamp }
        var walks = takeoutWalks
        for a in activities where Self.isOnFoot(a.type) {
            let lo = a.start.timeIntervalSince1970, hi = a.end.timeIntervalSince1970
            var pts = slice(pathPoints, from: lo, to: hi)
            if let f = a.from { pts.insert(TrackPoint(latitude: f.latitude, longitude: f.longitude, altitude: 0, timestamp: lo), at: 0) }
            if let t = a.to { pts.append(TrackPoint(latitude: t.latitude, longitude: t.longitude, altitude: 0, timestamp: hi)) }
            guard pts.count >= 2 else { continue }
            let dist = a.distance > 0 ? a.distance : Geo.pathLength(pts.map(\.coordinate))
            guard dist >= 150 else { continue }
            walks.append(Path(points: pts, start: a.start, end: a.end, distance: dist))
        }

        let raw = visits.count
        return Result(visits: Self.cluster(visits), walks: walks, rawVisitCount: raw)
    }

    // MARK: Formats

    private func parseSegments(_ segments: [[String: Any]], _ visits: inout [Visit], _ activities: inout [Activity], _ path: inout [TrackPoint]) {
        for seg in segments {
            guard let start = date(seg["startTime"]) else { continue }
            let end = date(seg["endTime"]) ?? start

            if let visit = seg["visit"] as? [String: Any], let top = visit["topCandidate"] as? [String: Any] {
                let loc = top["placeLocation"]
                let coordString = (loc as? [String: Any])?["latLng"] as? String ?? loc as? String
                if let c = coordString.flatMap(latLng) {
                    visits.append(Visit(latitude: c.latitude, longitude: c.longitude, start: start, end: end,
                                        name: (loc as? [String: Any])?["name"] as? String,
                                        semanticType: top["semanticType"] as? String))
                }
            } else if let act = seg["activity"] as? [String: Any] {
                let type = ((act["topCandidate"] as? [String: Any])?["type"] as? String) ?? ""
                activities.append(Activity(start: start, end: end,
                                           from: point(act["start"]), to: point(act["end"]),
                                           distance: number(act["distanceMeters"]) ?? 0, type: type))
            } else if let tp = seg["timelinePath"] as? [[String: Any]] {
                for p in tp {
                    guard let c = (p["point"] as? String).flatMap(latLng) else { continue }
                    let t: Date
                    if let d = date(p["time"]) { t = d }
                    else if let off = number(p["durationMinutesOffsetFromStartTime"]) { t = start.addingTimeInterval(off * 60) }
                    else { t = start }
                    path.append(TrackPoint(latitude: c.latitude, longitude: c.longitude, altitude: 0, timestamp: t.timeIntervalSince1970))
                }
            }
        }
    }

    private func parseTakeout(_ objects: [[String: Any]], _ visits: inout [Visit], _ walks: inout [Path]) {
        for obj in objects {
            if let pv = obj["placeVisit"] as? [String: Any],
               let loc = pv["location"] as? [String: Any],
               let lat = number(loc["latitudeE7"]), let lon = number(loc["longitudeE7"]) {
                let dur = pv["duration"] as? [String: Any]
                let start = date(dur?["startTimestamp"]) ?? Date(timeIntervalSince1970: (number(dur?["startTimestampMs"]) ?? 0) / 1000)
                let end = date(dur?["endTimestamp"]) ?? start
                visits.append(Visit(latitude: lat / 1e7, longitude: lon / 1e7, start: start, end: end,
                                    name: loc["name"] as? String, semanticType: loc["semanticType"] as? String))
            } else if let seg = obj["activitySegment"] as? [String: Any] {
                let type = seg["activityType"] as? String ?? ""
                guard Self.isOnFoot(type) else { continue }
                let dur = seg["duration"] as? [String: Any]
                guard let start = date(dur?["startTimestamp"]) else { continue }
                let end = date(dur?["endTimestamp"]) ?? start
                var coords: [CLLocationCoordinate2D] = []
                if let s = e7(seg["startLocation"]) { coords.append(s) }
                if let wps = (seg["waypointPath"] as? [String: Any])?["waypoints"] as? [[String: Any]] {
                    coords += wps.compactMap { w in
                        guard let la = number(w["latE7"]), let lo = number(w["lngE7"]) else { return nil }
                        return CLLocationCoordinate2D(latitude: la / 1e7, longitude: lo / 1e7)
                    }
                } else if let raw = (seg["simplifiedRawPath"] as? [String: Any])?["points"] as? [[String: Any]] {
                    coords += raw.compactMap { w in
                        guard let la = number(w["latE7"]), let lo = number(w["lngE7"]) else { return nil }
                        return CLLocationCoordinate2D(latitude: la / 1e7, longitude: lo / 1e7)
                    }
                }
                if let e = e7(seg["endLocation"]) { coords.append(e) }
                guard coords.count >= 2 else { continue }
                let span = end.timeIntervalSince(start) / Double(max(coords.count - 1, 1))
                let pts = coords.enumerated().map { i, c in
                    TrackPoint(latitude: c.latitude, longitude: c.longitude, altitude: 0, timestamp: start.timeIntervalSince1970 + span * Double(i))
                }
                let dist = number(seg["distance"]) ?? Geo.pathLength(coords)
                guard dist >= 150 else { continue }
                walks.append(Path(points: pts, start: start, end: end, distance: dist))
            }
        }
    }

    // MARK: Helpers

    static func isOnFoot(_ type: String) -> Bool {
        let t = type.lowercased()
        return t.contains("walk") || t.contains("run") || t.contains("hik") || t.contains("foot")
    }

    /// Merges visits within ~120 m into one place with a visit count.
    static func cluster(_ visits: [Visit]) -> [Visit] {
        let cell = 0.0012
        var grid: [Int64: [Int]] = [:]
        var out: [Visit] = []
        func key(_ y: Int64, _ x: Int64) -> Int64 { y &* 10_000_000 &+ x }
        for v in visits.sorted(by: { $0.start < $1.start }) {
            let y = Int64((v.latitude / cell).rounded(.down)), x = Int64((v.longitude / cell).rounded(.down))
            var merged = false
            search: for dy in Int64(-1)...1 {
                for dx in Int64(-1)...1 {
                    for idx in grid[key(y + dy, x + dx)] ?? [] {
                        let o = out[idx]
                        if Geo.distance(.init(latitude: o.latitude, longitude: o.longitude), .init(latitude: v.latitude, longitude: v.longitude)) < 120 {
                            out[idx].count += 1
                            out[idx].end = max(o.end, v.end)
                            if out[idx].name == nil { out[idx].name = v.name }
                            merged = true
                            break search
                        }
                    }
                }
            }
            if !merged {
                grid[key(y, x), default: []].append(out.count)
                out.append(v)
            }
        }
        return out
    }

    private func slice(_ pts: [TrackPoint], from lo: TimeInterval, to hi: TimeInterval) -> [TrackPoint] {
        var l = 0, h = pts.count
        while l < h { let m = (l + h) / 2; if pts[m].timestamp < lo { l = m + 1 } else { h = m } }
        var out: [TrackPoint] = []
        var i = l
        while i < pts.count, pts[i].timestamp <= hi { out.append(pts[i]); i += 1 }
        return out
    }

    private func date(_ any: Any?) -> Date? {
        guard let s = any as? String else { return nil }
        return isoFrac.date(from: s) ?? iso.date(from: s)
    }

    private func number(_ any: Any?) -> Double? {
        if let n = any as? NSNumber { return n.doubleValue }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private func e7(_ any: Any?) -> CLLocationCoordinate2D? {
        guard let d = any as? [String: Any], let la = number(d["latitudeE7"]), let lo = number(d["longitudeE7"]) else { return nil }
        return CLLocationCoordinate2D(latitude: la / 1e7, longitude: lo / 1e7)
    }

    private func point(_ any: Any?) -> CLLocationCoordinate2D? {
        if let s = any as? String { return latLng(s) }
        if let d = any as? [String: Any], let s = d["latLng"] as? String { return latLng(s) }
        return nil
    }

    /// Accepts "geo:48.85,2.35" and "48.8566°, 2.3522°".
    private func latLng(_ s: String) -> CLLocationCoordinate2D? {
        let cleaned = s.replacingOccurrences(of: "geo:", with: "").replacingOccurrences(of: "°", with: "")
        let parts = cleaned.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let la = Double(parts[0]), let lo = Double(parts[1]),
              abs(la) <= 90, abs(lo) <= 180 else { return nil }
        return CLLocationCoordinate2D(latitude: la, longitude: lo)
    }
}

struct ImportSummary {
    var newPlaces = 0
    var mergedVisits = 0
    var walks = 0
    var rawVisits = 0
}

enum TimelineImporter {
    /// Parses off the main thread, then merges into SwiftData.
    static func importFile(at url: URL, into context: ModelContext) async throws -> ImportSummary {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        let parsed = try await Task.detached(priority: .userInitiated) { try TimelineParser().parse(data) }.value

        var summary = ImportSummary(rawVisits: parsed.rawVisitCount)
        let existing = (try? context.fetch(FetchDescriptor<Place>())) ?? []

        for v in parsed.visits {
            let coord = CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude)
            if let match = existing.first(where: { abs($0.latitude - v.latitude) < 0.002 && abs($0.longitude - v.longitude) < 0.002 && Geo.distance($0.coordinate, coord) < 100 }) {
                match.visitCount += v.count
                match.firstVisit = min(match.firstVisit, v.start)
                match.lastVisit = max(match.lastVisit, v.end)
                summary.mergedVisits += v.count
                continue
            }
            let category: PlaceCategory = switch v.semanticType?.uppercased() {
            case "HOME", "INFERRED_HOME": .home
            case "WORK", "INFERRED_WORK": .work
            default: .other
            }
            let place = Place(name: v.name ?? (category == .other ? "" : category.title), coordinate: coord, date: v.start, category: category, source: .imported)
            place.lastVisit = v.end
            place.visitCount = v.count
            context.insert(place)
            summary.newPlaces += 1
        }

        let existingWalkStarts = Set(((try? context.fetch(FetchDescriptor<Walk>())) ?? []).map { Int($0.startDate.timeIntervalSince1970) })
        for w in parsed.walks where !existingWalkStarts.contains(Int(w.start.timeIntervalSince1970)) {
            let walk = Walk(title: Walk.defaultTitle(for: w.start), points: w.points, start: w.start, end: w.end,
                            distance: w.distance, movingDuration: w.end.timeIntervalSince(w.start), source: .imported)
            context.insert(walk)
            summary.walks += 1
        }
        try context.save()
        return summary
    }
}
