import Foundation
import SwiftData
import SwiftUI
import CoreLocation

@Model
final class Walk {
    var id: UUID = UUID()
    var title: String = ""
    var note: String = ""
    var startDate: Date = Date()
    var endDate: Date = Date()
    var distance: Double = 0
    var movingDuration: Double = 0
    var elevationGain: Double = 0
    @Attribute(.externalStorage) var routeData: Data = Data()
    @Attribute(.externalStorage) var photoData: Data?
    var photoColorHex: String?
    var minLat: Double = 0
    var maxLat: Double = 0
    var minLon: Double = 0
    var maxLon: Double = 0
    var sourceRaw: String = RecordSource.walk.rawValue
    var isFavorite: Bool = false
    var countryCode: String?
    var regionID: String?
    var regionName: String?
    var locality: String?
    var geocodeState: Int = GeocodeState.pending

    init(
        id: UUID = UUID(),
        title: String,
        points: [TrackPoint],
        start: Date,
        end: Date,
        distance: Double,
        movingDuration: Double,
        elevationGain: Double = 0,
        source: RecordSource = .walk
    ) {
        self.id = id
        self.title = title
        self.startDate = start
        self.endDate = end
        self.distance = distance
        self.movingDuration = movingDuration
        self.elevationGain = elevationGain
        self.sourceRaw = source.rawValue
        self.routeData = TrackPoint.pack(points)
        let box = Geo.boundingBox(points.map(\.coordinate))
        self.minLat = box.minLat
        self.maxLat = box.maxLat
        self.minLon = box.minLon
        self.maxLon = box.maxLon
    }

    var source: RecordSource { RecordSource(rawValue: sourceRaw) ?? .walk }

    var startCoordinate: CLLocationCoordinate2D {
        RouteCache.shared.points(for: self).first?.coordinate
            ?? CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    var displayTitle: String { title.isEmpty ? Walk.defaultTitle(for: startDate) : title }

    var tint: Color { Color(hexString: photoColorHex) ?? Theme.teal }

    static func defaultTitle(for date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<11: return "Morning walk"
        case 11..<14: return "Midday walk"
        case 14..<18: return "Afternoon walk"
        case 18..<22: return "Evening walk"
        default: return "Night walk"
        }
    }
}
