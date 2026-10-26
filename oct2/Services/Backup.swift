import Foundation
import SwiftUI
import SwiftData
import CoreLocation
import UniformTypeIdentifiers

nonisolated struct BackupPayload: Codable, Sendable {
    struct PlaceDTO: Codable, Sendable {
        var id: UUID, name: String, latitude: Double, longitude: Double
        var firstVisit: Date, lastVisit: Date, visitCount: Int, note: String
        var photo: Data?, photoColorHex: String?, category: String, source: String, isFavorite: Bool
        var countryCode: String?, regionID: String?, regionName: String?, locality: String?, address: String?
        var walkID: UUID?
    }

    struct WalkDTO: Codable, Sendable {
        var id: UUID, title: String, note: String, startDate: Date, endDate: Date
        var distance: Double, movingDuration: Double, elevationGain: Double
        var route: Data, photo: Data?, photoColorHex: String?, source: String, isFavorite: Bool
        var countryCode: String?, regionID: String?, regionName: String?, locality: String?
    }

    var version = 1
    var exportedAt = Date()
    var places: [PlaceDTO]
    var walks: [WalkDTO]
}

nonisolated struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let d = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = d
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum BackupService {
    static func export(context: ModelContext) throws -> BackupDocument {
        let places = try context.fetch(FetchDescriptor<Place>())
        let walks = try context.fetch(FetchDescriptor<Walk>())
        let payload = BackupPayload(
            places: places.map {
                .init(id: $0.id, name: $0.name, latitude: $0.latitude, longitude: $0.longitude,
                      firstVisit: $0.firstVisit, lastVisit: $0.lastVisit, visitCount: $0.visitCount, note: $0.note,
                      photo: $0.photoData, photoColorHex: $0.photoColorHex, category: $0.categoryRaw, source: $0.sourceRaw,
                      isFavorite: $0.isFavorite, countryCode: $0.countryCode, regionID: $0.regionID, regionName: $0.regionName,
                      locality: $0.locality, address: $0.address, walkID: $0.walkID)
            },
            walks: walks.map {
                .init(id: $0.id, title: $0.title, note: $0.note, startDate: $0.startDate, endDate: $0.endDate,
                      distance: $0.distance, movingDuration: $0.movingDuration, elevationGain: $0.elevationGain,
                      route: $0.routeData, photo: $0.photoData, photoColorHex: $0.photoColorHex, source: $0.sourceRaw,
                      isFavorite: $0.isFavorite, countryCode: $0.countryCode, regionID: $0.regionID,
                      regionName: $0.regionName, locality: $0.locality)
            }
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return BackupDocument(data: try encoder.encode(payload))
    }

    /// Restores records that aren't already present. Returns (places, walks) added.
    static func restore(from url: URL, into context: ModelContext) throws -> (Int, Int) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let payload = try decoder.decode(BackupPayload.self, from: Data(contentsOf: url))

        let placeIDs = Set(try context.fetch(FetchDescriptor<Place>()).map(\.id))
        let walkIDs = Set(try context.fetch(FetchDescriptor<Walk>()).map(\.id))
        var addedPlaces = 0, addedWalks = 0

        for d in payload.places where !placeIDs.contains(d.id) {
            let p = Place(name: d.name, coordinate: .init(latitude: d.latitude, longitude: d.longitude), date: d.firstVisit,
                          category: PlaceCategory(rawValue: d.category) ?? .other, source: RecordSource(rawValue: d.source) ?? .manual)
            p.id = d.id
            p.lastVisit = d.lastVisit; p.visitCount = d.visitCount; p.note = d.note
            p.photoData = d.photo; p.photoColorHex = d.photoColorHex; p.isFavorite = d.isFavorite
            p.countryCode = d.countryCode; p.regionID = d.regionID; p.regionName = d.regionName
            p.locality = d.locality; p.address = d.address; p.walkID = d.walkID
            p.geocodeState = d.countryCode == nil ? GeocodeState.pending : GeocodeState.done
            context.insert(p)
            addedPlaces += 1
        }
        for d in payload.walks where !walkIDs.contains(d.id) {
            let w = Walk(id: d.id, title: d.title, points: TrackPoint.unpack(d.route), start: d.startDate, end: d.endDate,
                         distance: d.distance, movingDuration: d.movingDuration, elevationGain: d.elevationGain,
                         source: RecordSource(rawValue: d.source) ?? .walk)
            w.note = d.note; w.photoData = d.photo; w.photoColorHex = d.photoColorHex; w.isFavorite = d.isFavorite
            w.countryCode = d.countryCode; w.regionID = d.regionID; w.regionName = d.regionName; w.locality = d.locality
            w.geocodeState = d.countryCode == nil ? GeocodeState.pending : GeocodeState.done
            context.insert(w)
            addedWalks += 1
        }
        try context.save()
        return (addedPlaces, addedWalks)
    }
}
