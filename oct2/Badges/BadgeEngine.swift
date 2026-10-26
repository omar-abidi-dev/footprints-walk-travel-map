import Foundation
import SwiftUI
import CoreLocation

struct RegionProgress: Identifiable {
    let atlas: CountryAtlas
    /// regionID → (first visit, number of footprints)
    let visited: [String: (first: Date, count: Int)]
    var id: String { atlas.code }
    var count: Int { visited.count }
    var total: Int { atlas.regions.count }
    var fraction: Double { total == 0 ? 0 : Double(count) / Double(total) }
}

struct ContinentProgress: Identifiable {
    let continent: WorldCatalog.Continent
    let visited: Int
    var id: String { continent.id }
    var fraction: Double { Double(visited) / Double(max(continent.countries.count, 1)) }
}

struct Achievement: Identifiable {
    enum Tier: Int { case locked, bronze, silver, gold }

    let id: String
    let title: String
    let symbol: String
    let unit: String
    let thresholds: [Double]   // bronze, silver, gold
    let value: Double

    var tier: Tier {
        if value >= thresholds[2] { return .gold }
        if value >= thresholds[1] { return .silver }
        if value >= thresholds[0] { return .bronze }
        return .locked
    }

    var nextThreshold: Double? { thresholds.first { value < $0 } }

    var progressToNext: Double {
        guard let next = nextThreshold else { return 1 }
        let prev = thresholds.last { $0 <= value } ?? 0
        return (value - prev) / max(next - prev, 0.0001)
    }

    var tierColors: [Color] {
        switch tier {
        case .locked: [Color(.systemGray4), Color(.systemGray3)]
        case .bronze: [Color(hex: 0xE8A06A), Theme.bronze]
        case .silver: [Color(hex: 0xE6ECF2), Theme.silver]
        case .gold: [Color(hex: 0xFFE27A), Theme.gold]
        }
    }

    func label(_ v: Double) -> String {
        let n = v.rounded() == v ? "\(Int(v))" : String(format: "%.1f", v)
        return unit.isEmpty ? n : "\(n) \(unit)"
    }
}

struct WeekBucket: Identifiable {
    let start: Date
    let meters: Double
    var id: Date { start }
}

struct RegionRank: Identifiable {
    let id: String
    let name: String
    let countryCode: String?
    let count: Int
}

/// Everything derived from the user's footprints, computed in one pass.
struct FootprintStats {
    var totalDistance: Double = 0
    var totalDuration: TimeInterval = 0
    var walkCount = 0
    var placeCount = 0
    var photoCount = 0
    var countries: [String: Date] = [:]
    var regionProgress: [RegionProgress] = []
    var continents: [ContinentProgress] = []
    var achievements: [Achievement] = []
    var exploredCells = 0
    var longestWalk: Double = 0
    var currentStreak = 0
    var bestStreak = 0
    var activeDays: [Date: Int] = [:]
    var weeks: [WeekBucket] = []
    var topRegions: [RegionRank] = []
    var firstDate: Date?

    var regionsVisited: Int { regionProgress.reduce(0) { $0 + $1.count } }
    var exploredKm2: Double { Double(exploredCells) * Geo.cellAreaKm2 }

    var xp: Int {
        Int(totalDistance / 100) + placeCount * 10 + regionsVisited * 60 + countries.count * 150 + walkCount * 15
    }

    /// Levels grow quadratically: level n needs 250·n² xp.
    var level: Int { Int((Double(xp) / 250).squareRoot()) + 1 }
    var levelProgress: Double {
        let lo = 250 * Double((level - 1) * (level - 1))
        let hi = 250 * Double(level * level)
        return (Double(xp) - lo) / max(hi - lo, 1)
    }

    var levelTitle: String {
        switch level {
        case 1: "Wanderer"
        case 2...3: "Stroller"
        case 4...5: "Pathfinder"
        case 6...8: "Trailblazer"
        case 9...12: "Voyager"
        case 13...18: "Cartographer"
        default: "Legend"
        }
    }
}

enum BadgeEngine {
    static func compute(places: [Place], walks: [Walk], now: Date = .now) -> FootprintStats {
        var s = FootprintStats()
        let cal = Calendar.current

        s.walkCount = walks.count
        s.placeCount = places.count
        s.photoCount = places.filter { $0.photoData != nil }.count + walks.filter { $0.photoData != nil }.count

        var regionVisits: [String: [String: (first: Date, count: Int)]] = [:]
        var regionCounts: [String: RegionRank] = [:]
        var cells = Set<Int64>()
        var days: [Date: Int] = [:]
        var earlyBird = 0, nightOwl = 0

        func record(country: String?, regionID: String?, regionName: String?, locality: String?, date: Date, weight: Int) {
            if let country {
                s.countries[country] = min(s.countries[country] ?? date, date)
            }
            if let regionID, let country {
                var map = regionVisits[country, default: [:]]
                let existing = map[regionID]
                map[regionID] = (min(existing?.first ?? date, date), (existing?.count ?? 0) + weight)
                regionVisits[country] = map
            }
            let key = regionID ?? locality.map { "\(country ?? "")|\($0)" }
            if let key {
                let name = regionName ?? locality ?? key
                let prev = regionCounts[key]?.count ?? 0
                regionCounts[key] = RegionRank(id: key, name: name, countryCode: country, count: prev + weight)
            }
            days[cal.startOfDay(for: date), default: 0] += 1
            s.firstDate = min(s.firstDate ?? date, date)
        }

        for p in places {
            record(country: p.countryCode, regionID: p.regionID, regionName: p.regionName, locality: p.locality, date: p.firstVisit, weight: p.visitCount)
            cells.insert(Geo.cellKey(p.coordinate))
        }

        var weekly: [Date: Double] = [:]
        for w in walks {
            record(country: w.countryCode, regionID: w.regionID, regionName: w.regionName, locality: w.locality, date: w.startDate, weight: 1)
            s.totalDistance += w.distance
            s.totalDuration += w.movingDuration
            s.longestWalk = max(s.longestWalk, w.distance)
            for c in RouteCache.shared.displayCoordinates(for: w) { cells.insert(Geo.cellKey(c)) }
            if let wk = cal.dateInterval(of: .weekOfYear, for: w.startDate)?.start { weekly[wk, default: 0] += w.distance }
            let hour = cal.component(.hour, from: w.startDate)
            if hour < 7 { earlyBird += 1 }
            if hour >= 21 { nightOwl += 1 }
        }
        s.exploredCells = cells.count
        s.activeDays = days

        // Last 12 weeks, oldest first.
        if let thisWeek = cal.dateInterval(of: .weekOfYear, for: now)?.start {
            s.weeks = (0..<12).reversed().compactMap { offset in
                guard let start = cal.date(byAdding: .weekOfYear, value: -offset, to: thisWeek) else { return nil }
                return WeekBucket(start: start, meters: weekly[start] ?? 0)
            }
        }

        // Streaks over active days.
        let sortedDays = days.keys.sorted()
        var run = 0, best = 0
        var prev: Date?
        for d in sortedDays {
            if let p = prev, cal.dateComponents([.day], from: p, to: d).day == 1 { run += 1 } else { run = 1 }
            best = max(best, run)
            prev = d
        }
        s.bestStreak = best
        let today = cal.startOfDay(for: now)
        var cursor = days[today] != nil ? today : cal.date(byAdding: .day, value: -1, to: today)!
        while days[cursor] != nil {
            s.currentStreak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }

        s.regionProgress = RegionCatalog.atlases.map { RegionProgress(atlas: $0, visited: regionVisits[$0.code] ?? [:]) }
            .sorted { ($0.count > 0 ? 0 : 1, -$0.fraction) < ($1.count > 0 ? 0 : 1, -$1.fraction) }

        let visitedCountries = Set(s.countries.keys)
        s.continents = WorldCatalog.continents.map {
            ContinentProgress(continent: $0, visited: $0.countries.intersection(visitedCountries).count)
        }

        s.topRegions = regionCounts.values.sorted { $0.count > $1.count }.prefix(5).map { $0 }

        let km = s.totalDistance / 1000
        s.achievements = [
            Achievement(id: "first", title: "First Steps", symbol: "shoeprints.fill", unit: "walks", thresholds: [1, 10, 50], value: Double(s.walkCount)),
            Achievement(id: "distance", title: "Distance", symbol: "figure.walk", unit: "km", thresholds: [10, 100, 500], value: km.rounded()),
            Achievement(id: "marathon", title: "Long Haul", symbol: "flag.checkered", unit: "km", thresholds: [5, 10, 21], value: (s.longestWalk / 100).rounded() / 10),
            Achievement(id: "places", title: "Collector", symbol: "mappin.and.ellipse", unit: "places", thresholds: [10, 50, 200], value: Double(s.placeCount)),
            Achievement(id: "countries", title: "Globetrotter", symbol: "globe.europe.africa.fill", unit: "countries", thresholds: [2, 5, 15], value: Double(s.countries.count)),
            Achievement(id: "regions", title: "Regional Hero", symbol: "map.fill", unit: "regions", thresholds: [3, 10, 30], value: Double(s.regionsVisited)),
            Achievement(id: "streak", title: "On a Roll", symbol: "flame.fill", unit: "days", thresholds: [3, 7, 30], value: Double(s.bestStreak)),
            Achievement(id: "photos", title: "Memory Keeper", symbol: "camera.fill", unit: "photos", thresholds: [5, 25, 100], value: Double(s.photoCount)),
            Achievement(id: "explorer", title: "Explorer", symbol: "square.grid.3x3.fill", unit: "km²", thresholds: [1, 10, 50], value: (s.exploredKm2 * 10).rounded() / 10),
            Achievement(id: "early", title: "Early Bird", symbol: "sunrise.fill", unit: "walks", thresholds: [1, 5, 20], value: Double(earlyBird)),
            Achievement(id: "night", title: "Night Owl", symbol: "moon.stars.fill", unit: "walks", thresholds: [1, 5, 20], value: Double(nightOwl)),
            Achievement(id: "continents", title: "Continental", symbol: "globe", unit: "continents", thresholds: [2, 4, 6], value: Double(s.continents.filter { $0.visited > 0 }.count))
        ]
        return s
    }
}
