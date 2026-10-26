import Foundation
import MapKit
import SwiftData
import Observation

struct GeoResult {
    var countryCode: String?
    var region: RegionDef?
    var locality: String?
    var address: String?
    var poiName: String?
}

/// Reverse-geocodes places and walks into country + region, politely throttled
/// so large Google Timeline imports don't hit MapKit's rate limit.
@Observable
final class RegionResolver {
    private(set) var remaining = 0
    private(set) var isRunning = false

    @ObservationIgnored private var cache: [String: GeoResult] = [:]
    @ObservationIgnored private var rerunRequested = false

    func lookup(_ coordinate: CLLocationCoordinate2D) async -> GeoResult? {
        let key = String(format: "%.3f,%.3f", coordinate.latitude, coordinate.longitude)
        if let hit = cache[key] { return hit }
        guard let request = MKReverseGeocodingRequest(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) else { return nil }
        request.preferredLocale = Locale(identifier: "en_US")
        guard let item = try? await request.mapItems.first else { return nil }

        let reps = item.addressRepresentations
        let country = reps?.region?.identifier
        let lines = [item.address?.fullAddress, reps?.cityWithContext(.full), reps?.cityName].compactMap { $0 }
        let result = GeoResult(
            countryCode: country,
            region: RegionCatalog.match(countryCode: country, addressLines: lines),
            locality: reps?.cityName,
            address: item.address?.shortAddress ?? item.address?.fullAddress,
            poiName: item.name
        )
        cache[key] = result
        return result
    }

    func apply(_ result: GeoResult?, to place: Place) {
        guard let result else { place.geocodeState = GeocodeState.failed; return }
        place.countryCode = result.countryCode
        place.regionID = result.region?.id
        place.regionName = result.region?.name
        place.locality = result.locality
        place.address = result.address
        if place.name.isEmpty { place.name = result.locality ?? result.poiName ?? "" }
        place.geocodeState = GeocodeState.done
    }

    func apply(_ result: GeoResult?, to walk: Walk) {
        guard let result else { walk.geocodeState = GeocodeState.failed; return }
        walk.countryCode = result.countryCode
        walk.regionID = result.region?.id
        walk.regionName = result.region?.name
        walk.locality = result.locality
        walk.geocodeState = GeocodeState.done
    }

    /// Resolves every pending record. Safe to call repeatedly; extra calls queue one more pass.
    func resolvePending(in context: ModelContext) {
        guard !isRunning else { rerunRequested = true; return }
        isRunning = true
        Task {
            repeat {
                rerunRequested = false
                await runPass(context)
            } while rerunRequested
            isRunning = false
            remaining = 0
        }
    }

    func retryFailed(in context: ModelContext) {
        let failedPlaces = (try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.geocodeState == 2 }))) ?? []
        let failedWalks = (try? context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { $0.geocodeState == 2 }))) ?? []
        failedPlaces.forEach { $0.geocodeState = GeocodeState.pending }
        failedWalks.forEach { $0.geocodeState = GeocodeState.pending }
        try? context.save()
        resolvePending(in: context)
    }

    private func runPass(_ context: ModelContext) async {
        let places = (try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.geocodeState == 0 }))) ?? []
        let walks = (try? context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { $0.geocodeState == 0 }))) ?? []
        remaining = places.count + walks.count
        var sinceSave = 0

        for place in places {
            guard place.modelContext != nil, !place.isDeleted else { remaining -= 1; continue }
            let wasCached = isCached(place.coordinate)
            apply(await lookup(place.coordinate), to: place)
            remaining -= 1
            sinceSave += 1
            if sinceSave >= 10 { try? context.save(); sinceSave = 0 }
            if !wasCached { try? await Task.sleep(for: .milliseconds(1100)) }
        }
        for walk in walks {
            guard walk.modelContext != nil, !walk.isDeleted else { remaining -= 1; continue }
            let coord = walk.startCoordinate
            let wasCached = isCached(coord)
            apply(await lookup(coord), to: walk)
            remaining -= 1
            if !wasCached { try? await Task.sleep(for: .milliseconds(1100)) }
        }
        try? context.save()
    }

    private func isCached(_ c: CLLocationCoordinate2D) -> Bool {
        cache[String(format: "%.3f,%.3f", c.latitude, c.longitude)] != nil
    }
}
