import SwiftUI
import MapKit
import CoreLocation
import Observation

enum AppTab: Hashable {
    case map, journal, badges, profile
}

/// A request to move the map camera (e.g. "Show on map" from a detail screen).
struct MapFocus: Equatable {
    let id = UUID()
    let region: MKCoordinateRegion

    static func == (a: MapFocus, b: MapFocus) -> Bool { a.id == b.id }
}

@Observable
final class AppModel {
    let recorder = WalkRecorder()
    let resolver = RegionResolver()
    @ObservationIgnored let locationManager = CLLocationManager()

    var selectedTab: AppTab = .map
    var showRecorder = false
    var mapFocus: MapFocus?

    func requestLocation() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    var locationDenied: Bool {
        let s = locationManager.authorizationStatus
        return s == .denied || s == .restricted
    }

    var lastKnownCoordinate: CLLocationCoordinate2D? {
        recorder.currentLocation?.coordinate ?? locationManager.location?.coordinate
    }

    func startWalk() {
        requestLocation()
        recorder.start()
        showRecorder = true
    }

    func showOnMap(_ coordinate: CLLocationCoordinate2D, span: Double = 0.01) {
        mapFocus = MapFocus(region: MKCoordinateRegion(center: coordinate, span: .init(latitudeDelta: span, longitudeDelta: span)))
        selectedTab = .map
    }

    func showOnMap(region: MKCoordinateRegion) {
        mapFocus = MapFocus(region: region)
        selectedTab = .map
    }
}
