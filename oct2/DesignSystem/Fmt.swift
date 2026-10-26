import Foundation

/// Formatting helpers. `metric` is passed explicitly so views react to the units toggle.
enum Fmt {
    static let metricKey = "useMetric"
    static var defaultMetric: Bool { Locale.current.measurementSystem != .us }

    static func distance(_ meters: Double, metric: Bool) -> String {
        let p = distanceParts(meters, metric: metric)
        return "\(p.value) \(p.unit)"
    }

    static func distanceParts(_ meters: Double, metric: Bool) -> (value: String, unit: String) {
        if metric {
            if meters < 1000 { return ("\(Int(meters.rounded()))", "m") }
            let km = meters / 1000
            return (km >= 100 ? String(format: "%.0f", km) : String(format: "%.2f", km), "km")
        } else {
            let miles = meters / 1609.344
            if miles < 0.1 { return ("\(Int((meters * 3.28084).rounded()))", "ft") }
            return (miles >= 100 ? String(format: "%.0f", miles) : String(format: "%.2f", miles), "mi")
        }
    }

    /// Big totals (e.g. "1,284 km").
    static func compactDistance(_ meters: Double, metric: Bool) -> String {
        let v = metric ? meters / 1000 : meters / 1609.344
        let unit = metric ? "km" : "mi"
        if v < 10 { return String(format: "%.1f %@", v, unit) }
        return "\(Int(v.rounded()).formatted()) \(unit)"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    static func longDuration(_ seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        let h = s / 3600, m = (s % 3600) / 60
        if h == 0 { return "\(m) min" }
        return "\(h)h \(m)m"
    }

    static func pace(distance: Double, duration: TimeInterval, metric: Bool) -> String {
        let unitMeters = metric ? 1000.0 : 1609.344
        guard distance > 20, duration > 0 else { return "–" }
        let secPerUnit = duration / (distance / unitMeters)
        guard secPerUnit.isFinite, secPerUnit < 60 * 60 else { return "–" }
        let m = Int(secPerUnit) / 60, s = Int(secPerUnit) % 60
        return String(format: "%d'%02d\"", m, s)
    }

    static func paceUnit(metric: Bool) -> String { metric ? "/km" : "/mi" }

    static func elevation(_ meters: Double, metric: Bool) -> String {
        metric ? "\(Int(meters.rounded())) m" : "\(Int((meters * 3.28084).rounded())) ft"
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    static func shortDay(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
