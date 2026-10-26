import Foundation
import SwiftData
import CoreLocation

/// A pre-geocoded demo journey so the app looks alive on first launch / in the simulator.
enum SampleData {
    private struct Spot {
        let name: String, lat: Double, lon: Double, cat: PlaceCategory
        let cc: String, region: String?, city: String, daysAgo: Int, hex: String?
    }

    private static let spots: [Spot] = [
        Spot(name: "Dolores Park", lat: 37.7596, lon: -122.4269, cat: .nature, cc: "US", region: "US-CA", city: "San Francisco", daysAgo: 3, hex: "#4FAE3C"),
        Spot(name: "Ferry Building", lat: 37.7955, lon: -122.3937, cat: .food, cc: "US", region: "US-CA", city: "San Francisco", daysAgo: 5, hex: nil),
        Spot(name: "Twin Peaks", lat: 37.7544, lon: -122.4477, cat: .viewpoint, cc: "US", region: "US-CA", city: "San Francisco", daysAgo: 9, hex: "#2F7CF6"),
        Spot(name: "Sightglass Coffee", lat: 37.7770, lon: -122.4085, cat: .coffee, cc: "US", region: "US-CA", city: "San Francisco", daysAgo: 12, hex: nil),
        Spot(name: "Central Park", lat: 40.7812, lon: -73.9665, cat: .nature, cc: "US", region: "US-NY", city: "New York", daysAgo: 40, hex: nil),
        Spot(name: "The High Line", lat: 40.7480, lon: -74.0048, cat: .viewpoint, cc: "US", region: "US-NY", city: "New York", daysAgo: 41, hex: "#7C5CFA"),
        Spot(name: "Pike Place Market", lat: 47.6097, lon: -122.3422, cat: .food, cc: "US", region: "US-WA", city: "Seattle", daysAgo: 70, hex: nil),
        Spot(name: "Zion Narrows", lat: 37.3047, lon: -112.9475, cat: .nature, cc: "US", region: "US-UT", city: "Springdale", daysAgo: 120, hex: "#C4733B"),
        Spot(name: "Shibuya Crossing", lat: 35.6595, lon: 139.7005, cat: .culture, cc: "JP", region: "JP-13", city: "Tokyo", daysAgo: 150, hex: "#F43F72"),
        Spot(name: "Fushimi Inari", lat: 34.9671, lon: 135.7727, cat: .culture, cc: "JP", region: "JP-26", city: "Kyoto", daysAgo: 154, hex: "#FF5A36"),
        Spot(name: "Dotonbori", lat: 34.6687, lon: 135.5013, cat: .food, cc: "JP", region: "JP-27", city: "Osaka", daysAgo: 156, hex: nil),
        Spot(name: "Nara Park", lat: 34.6851, lon: 135.8430, cat: .nature, cc: "JP", region: "JP-29", city: "Nara", daysAgo: 155, hex: nil),
        Spot(name: "Bukchon Hanok Village", lat: 37.5826, lon: 126.9830, cat: .culture, cc: "KR", region: "KR-11", city: "Seoul", daysAgo: 200, hex: nil),
        Spot(name: "Haeundae Beach", lat: 35.1587, lon: 129.1604, cat: .nature, cc: "KR", region: "KR-26", city: "Busan", daysAgo: 203, hex: "#10B5A4"),
        Spot(name: "Taipei 101", lat: 25.0340, lon: 121.5645, cat: .viewpoint, cc: "TW", region: "TW-TPE", city: "Taipei", daysAgo: 230, hex: nil),
        Spot(name: "Jiufen Old Street", lat: 25.1092, lon: 121.8452, cat: .food, cc: "TW", region: "TW-NWT", city: "Ruifang", daysAgo: 231, hex: "#FFAE34"),
        Spot(name: "Jemaa el-Fna", lat: 31.6258, lon: -7.9891, cat: .culture, cc: "MA", region: "MA-07", city: "Marrakesh", daysAgo: 280, hex: "#E07A3F"),
        Spot(name: "Hassan II Mosque", lat: 33.6084, lon: -7.6326, cat: .culture, cc: "MA", region: "MA-06", city: "Casablanca", daysAgo: 284, hex: nil),
        Spot(name: "Chefchaouen Medina", lat: 35.1688, lon: -5.2636, cat: .viewpoint, cc: "MA", region: "MA-01", city: "Chefchaouen", daysAgo: 286, hex: "#3B82F6"),
        Spot(name: "Canal Saint-Martin", lat: 48.8722, lon: 2.3655, cat: .coffee, cc: "FR", region: "FR-IDF", city: "Paris", daysAgo: 320, hex: nil),
        Spot(name: "Calanques", lat: 43.2140, lon: 5.4400, cat: .nature, cc: "FR", region: "FR-PAC", city: "Marseille", daysAgo: 324, hex: "#10B5A4"),
        Spot(name: "Stanley Park", lat: 49.3043, lon: -123.1443, cat: .nature, cc: "CA", region: "CA-BC", city: "Vancouver", daysAgo: 95, hex: nil),
        Spot(name: "Arthur's Seat", lat: 55.9441, lon: -3.1618, cat: .viewpoint, cc: "GB", region: "GB-SCT", city: "Edinburgh", daysAgo: 340, hex: "#7C5CFA"),
        Spot(name: "LX Factory", lat: 38.7036, lon: -9.1785, cat: .shopping, cc: "PT", region: nil, city: "Lisbon", daysAgo: 300, hex: nil)
    ]

    private struct Route { let lat: Double, lon: Double, cc: String, region: String?, city: String, km: Double, daysAgo: Int, hour: Int }

    private static let routes: [Route] = [
        Route(lat: 37.7694, lon: -122.4862, cc: "US", region: "US-CA", city: "San Francisco", km: 5.2, daysAgo: 0, hour: 7),
        Route(lat: 37.8024, lon: -122.4058, cc: "US", region: "US-CA", city: "San Francisco", km: 3.4, daysAgo: 1, hour: 18),
        Route(lat: 37.7596, lon: -122.4269, cc: "US", region: "US-CA", city: "San Francisco", km: 2.1, daysAgo: 2, hour: 12),
        Route(lat: 37.7749, lon: -122.4194, cc: "US", region: "US-CA", city: "San Francisco", km: 4.0, daysAgo: 3, hour: 6),
        Route(lat: 37.8080, lon: -122.4177, cc: "US", region: "US-CA", city: "San Francisco", km: 6.8, daysAgo: 6, hour: 9),
        Route(lat: 37.7544, lon: -122.4477, cc: "US", region: "US-CA", city: "San Francisco", km: 3.0, daysAgo: 9, hour: 17),
        Route(lat: 37.7880, lon: -122.4075, cc: "US", region: "US-CA", city: "San Francisco", km: 2.6, daysAgo: 13, hour: 21),
        Route(lat: 37.8199, lon: -122.4783, cc: "US", region: "US-CA", city: "San Francisco", km: 8.1, daysAgo: 20, hour: 8),
        Route(lat: 37.7700, lon: -122.4500, cc: "US", region: "US-CA", city: "San Francisco", km: 4.4, daysAgo: 27, hour: 7),
        Route(lat: 40.7812, lon: -73.9665, cc: "US", region: "US-NY", city: "New York", km: 7.3, daysAgo: 40, hour: 10),
        Route(lat: 40.7061, lon: -73.9969, cc: "US", region: "US-NY", city: "New York", km: 3.9, daysAgo: 41, hour: 19),
        Route(lat: 47.6205, lon: -122.3493, cc: "US", region: "US-WA", city: "Seattle", km: 5.0, daysAgo: 70, hour: 15),
        Route(lat: 49.3043, lon: -123.1443, cc: "CA", region: "CA-BC", city: "Vancouver", km: 10.4, daysAgo: 95, hour: 9),
        Route(lat: 35.6764, lon: 139.6993, cc: "JP", region: "JP-13", city: "Tokyo", km: 6.2, daysAgo: 150, hour: 11),
        Route(lat: 35.0116, lon: 135.7681, cc: "JP", region: "JP-26", city: "Kyoto", km: 9.5, daysAgo: 154, hour: 6),
        Route(lat: 37.5796, lon: 126.9770, cc: "KR", region: "KR-11", city: "Seoul", km: 5.7, daysAgo: 200, hour: 16),
        Route(lat: 25.0330, lon: 121.5654, cc: "TW", region: "TW-TPE", city: "Taipei", km: 4.8, daysAgo: 230, hour: 20),
        Route(lat: 31.6295, lon: -7.9811, cc: "MA", region: "MA-07", city: "Marrakesh", km: 3.6, daysAgo: 280, hour: 18),
        Route(lat: 48.8584, lon: 2.2945, cc: "FR", region: "FR-IDF", city: "Paris", km: 12.0, daysAgo: 320, hour: 8),
        Route(lat: 55.9533, lon: -3.1883, cc: "GB", region: "GB-SCT", city: "Edinburgh", km: 6.0, daysAgo: 340, hour: 13)
    ]

    static func load(into context: ModelContext) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)

        for s in spots {
            let date = cal.date(byAdding: .day, value: -s.daysAgo, to: today)!.addingTimeInterval(Double(10 + s.daysAgo % 8) * 3600)
            let p = Place(name: s.name, coordinate: .init(latitude: s.lat, longitude: s.lon), date: date, category: s.cat, source: .sample)
            p.photoColorHex = s.hex
            p.countryCode = s.cc
            p.regionID = s.region
            p.regionName = RegionCatalog.region(id: s.region)?.name
            p.locality = s.city
            p.visitCount = 1 + s.name.count % 4
            p.isFavorite = s.daysAgo % 3 == 0
            p.geocodeState = GeocodeState.done
            context.insert(p)
        }

        var rng = SeededRandom(seed: 42)
        for r in routes {
            let start = cal.date(byAdding: .day, value: -r.daysAgo, to: today)!.addingTimeInterval(Double(r.hour) * 3600 + 900)
            let pts = loop(center: .init(latitude: r.lat, longitude: r.lon), km: r.km, start: start, rng: &rng)
            let dist = Geo.pathLength(pts.map(\.coordinate))
            let duration = dist / 1.35
            let w = Walk(title: "", points: pts, start: start,
                         end: start.addingTimeInterval(duration), distance: dist, movingDuration: duration,
                         elevationGain: Double(rng.next(in: 8...140)), source: .sample)
            w.countryCode = r.cc
            w.regionID = r.region
            w.regionName = RegionCatalog.region(id: r.region)?.name
            w.locality = r.city
            w.geocodeState = GeocodeState.done
            context.insert(w)
        }
        try? context.save()
    }

    /// A wobbly closed loop of roughly `km` length.
    private static func loop(center: CLLocationCoordinate2D, km: Double, start: Date, rng: inout SeededRandom) -> [TrackPoint] {
        let radius = km * 1000 / (2 * .pi) / 1.15
        let n = max(60, Int(km * 45))
        let phase = rng.next(in: 0...6.28), wobble = rng.next(in: 0.08...0.22), lobes = Double(Int(rng.next(in: 2...5)))
        let mLat = 111_320.0, mLon = 111_320.0 * cos(center.latitude * .pi / 180)
        let step = km * 1000 / 1.35 / Double(n)
        return (0...n).map { i in
            let t = Double(i) / Double(n) * 2 * .pi
            let r = radius * (1 + wobble * sin(lobes * t + phase) + 0.04 * sin(9 * t))
            let x = r * cos(t + phase) * 1.2, y = r * sin(t + phase) * 0.85
            return TrackPoint(latitude: center.latitude + y / mLat, longitude: center.longitude + x / mLon,
                              altitude: 20 + 15 * sin(t * 2), timestamp: start.timeIntervalSince1970 + Double(i) * step)
        }
    }
}

struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func next(in range: ClosedRange<Double>) -> Double {
        range.lowerBound + Double(next() >> 11) / Double(1 << 53) * (range.upperBound - range.lowerBound)
    }
}
