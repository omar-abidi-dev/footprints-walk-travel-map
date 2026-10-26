import Foundation
import SwiftData
import SwiftUI
import CoreLocation

enum PlaceCategory: String, CaseIterable, Identifiable, Codable {
    case food, coffee, nature, viewpoint, culture, shopping, stay, home, work, transit, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .food: "Food"
        case .coffee: "Coffee"
        case .nature: "Nature"
        case .viewpoint: "Viewpoint"
        case .culture: "Culture"
        case .shopping: "Shopping"
        case .stay: "Stay"
        case .home: "Home"
        case .work: "Work"
        case .transit: "Transit"
        case .other: "Place"
        }
    }

    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .nature: "leaf.fill"
        case .viewpoint: "binoculars.fill"
        case .culture: "building.columns.fill"
        case .shopping: "bag.fill"
        case .stay: "bed.double.fill"
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .transit: "tram.fill"
        case .other: "mappin"
        }
    }

    var color: Color {
        switch self {
        case .food: Theme.coral
        case .coffee: Color(hex: 0xA0673A)
        case .nature: Theme.moss
        case .viewpoint: Theme.ocean
        case .culture: Theme.violet
        case .shopping: Theme.rose
        case .stay: Color(hex: 0x6366F1)
        case .home: Theme.amber
        case .work: Color(hex: 0x64748B)
        case .transit: Theme.teal
        case .other: Color(hex: 0xEF6C4A)
        }
    }
}

enum RecordSource: String, Codable {
    case manual, walk, imported, sample
}

/// Geocoding progress for a record (stored as Int for predicate friendliness).
enum GeocodeState {
    static let pending = 0
    static let done = 1
    static let failed = 2
}

@Model
final class Place {
    var id: UUID = UUID()
    var name: String = ""
    var latitude: Double = 0
    var longitude: Double = 0
    var firstVisit: Date = Date()
    var lastVisit: Date = Date()
    var visitCount: Int = 1
    var note: String = ""
    @Attribute(.externalStorage) var photoData: Data?
    var photoColorHex: String?
    var categoryRaw: String = PlaceCategory.other.rawValue
    var sourceRaw: String = RecordSource.manual.rawValue
    var isFavorite: Bool = false
    var countryCode: String?
    var regionID: String?
    var regionName: String?
    var locality: String?
    var address: String?
    var geocodeState: Int = GeocodeState.pending
    var walkID: UUID?

    init(
        name: String,
        coordinate: CLLocationCoordinate2D,
        date: Date = .now,
        category: PlaceCategory = .other,
        source: RecordSource = .manual
    ) {
        self.id = UUID()
        self.name = name
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.firstVisit = date
        self.lastVisit = date
        self.categoryRaw = category.rawValue
        self.sourceRaw = source.rawValue
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var source: RecordSource { RecordSource(rawValue: sourceRaw) ?? .manual }

    /// Photo-derived color when available, otherwise the category color.
    var tint: Color { Color(hexString: photoColorHex) ?? category.color }

    var displayName: String {
        if !name.isEmpty { return name }
        return locality ?? "Unnamed place"
    }

    var placeLine: String {
        [locality, regionName ?? (countryCode.map { Flag.name($0) })]
            .compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ", ")
    }
}
