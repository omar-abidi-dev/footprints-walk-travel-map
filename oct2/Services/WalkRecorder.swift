import Foundation
import CoreLocation
import Observation

/// Everything needed to save a finished walk.
struct WalkDraft: Identifiable {
    let id: UUID
    let points: [TrackPoint]
    let start: Date
    let end: Date
    let distance: Double
    let movingDuration: TimeInterval
    let elevationGain: Double
}

/// Records a walk with `CLLocationUpdate.liveUpdates`, keeping the session alive in the background.
@Observable
final class WalkRecorder {
    enum State { case idle, recording, paused }

    private(set) var state: State = .idle
    private(set) var points: [TrackPoint] = []
    private(set) var distance: Double = 0
    private(set) var elevationGain: Double = 0
    private(set) var startDate: Date?
    private(set) var currentLocation: CLLocation?
    private(set) var walkID = UUID()
    private(set) var signalIsWeak = false

    private var accumulated: TimeInterval = 0
    private var segmentStart: Date?
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var backgroundSession: CLBackgroundActivitySession?
    @ObservationIgnored private var serviceSession: CLServiceSession?

    var isActive: Bool { state != .idle }

    func elapsed(at date: Date = .now) -> TimeInterval {
        accumulated + (segmentStart.map { date.timeIntervalSince($0) } ?? 0)
    }

    func start() {
        guard state == .idle else { return }
        reset()
        walkID = UUID()
        state = .recording
        startDate = .now
        segmentStart = .now
        serviceSession = CLServiceSession(authorization: .whenInUse)
        backgroundSession = CLBackgroundActivitySession()
        beginUpdates()
    }

    func pause() {
        guard state == .recording else { return }
        accumulated = elapsed()
        segmentStart = nil
        state = .paused
    }

    func resume() {
        guard state == .paused else { return }
        segmentStart = .now
        state = .recording
    }

    /// Stops recording and returns the draft (nil when nothing useful was captured).
    func finish() -> WalkDraft? {
        guard let startDate else { discard(); return nil }
        let draft = WalkDraft(
            id: walkID,
            points: points,
            start: startDate,
            end: .now,
            distance: distance,
            movingDuration: elapsed(),
            elevationGain: elevationGain
        )
        stop()
        return draft
    }

    func discard() {
        stop()
    }

    private func stop() {
        updatesTask?.cancel()
        updatesTask = nil
        backgroundSession?.invalidate()
        backgroundSession = nil
        serviceSession?.invalidate()
        serviceSession = nil
        reset()
        state = .idle
    }

    private func reset() {
        points = []
        distance = 0
        elevationGain = 0
        accumulated = 0
        segmentStart = nil
        startDate = nil
        signalIsWeak = false
    }

    private func beginUpdates() {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            do {
                for try await update in CLLocationUpdate.liveUpdates(.fitness) {
                    guard let self, !Task.isCancelled else { break }
                    if let location = update.location { self.ingest(location) }
                }
            } catch {
                // Updates end when cancelled or when authorization is revoked.
            }
        }
    }

    private func ingest(_ location: CLLocation) {
        currentLocation = location
        signalIsWeak = location.horizontalAccuracy < 0 || location.horizontalAccuracy > 50
        guard state == .recording, !signalIsWeak else { return }

        let point = TrackPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            altitude: location.altitude,
            timestamp: location.timestamp.timeIntervalSince1970
        )
        if let last = points.last {
            let d = Geo.distance(last.coordinate, point.coordinate)
            guard d >= 4 else { return }
            // Ignore teleports (GPS jumps faster than ~25 m/s).
            let dt = max(point.timestamp - last.timestamp, 0.5)
            guard d / dt < 25 else { return }
            distance += d
            let climb = point.altitude - last.altitude
            if location.verticalAccuracy > 0, climb > 0.4, climb < 25 { elevationGain += climb }
        }
        points.append(point)
    }
}
