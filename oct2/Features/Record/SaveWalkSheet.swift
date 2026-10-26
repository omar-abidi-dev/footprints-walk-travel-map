import SwiftUI
import MapKit
import SwiftData

struct SaveWalkSheet: View {
    let draft: WalkDraft
    var onDone: () -> Void

    @Environment(\.modelContext) private var context
    @Environment(AppModel.self) private var app
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    @State private var title = ""
    @State private var note = ""
    @State private var photoData: Data?
    @State private var photoColorHex: String?
    @State private var confirmDiscard = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    RouteMapPreview(coordinates: draft.points.map(\.coordinate))
                        .frame(height: 230)
                        .clipShape(.rect(cornerRadius: 26, style: .continuous))

                    HStack(spacing: 10) {
                        StatTile(value: Fmt.distance(draft.distance, metric: metric), label: "Distance", symbol: "point.bottomleft.forward.to.point.topright.scurvepath.fill", tint: Theme.teal)
                        StatTile(value: Fmt.duration(draft.movingDuration), label: "Time", symbol: "stopwatch.fill", tint: Theme.ocean)
                        StatTile(value: Fmt.pace(distance: draft.distance, duration: draft.movingDuration, metric: metric), label: "Pace \(Fmt.paceUnit(metric: metric))", symbol: "speedometer", tint: Theme.violet)
                    }

                    VStack(spacing: 12) {
                        TextField("Title", text: $title, prompt: Text(Walk.defaultTitle(for: draft.start)))
                            .font(.title3.weight(.semibold))
                        Divider()
                        TextField("How was it? Add a note…", text: $note, axis: .vertical)
                            .lineLimit(3...8)
                    }
                    .card()

                    PhotoPickerCard(photoData: $photoData, colorHex: $photoColorHex, prompt: "Add a cover photo")
                }
                .padding()
            }
            .background(Theme.canvas)
            .navigationTitle("Nice walk!")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard", role: .destructive) { confirmDiscard = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .tint(Theme.coral)
                }
            }
            .confirmationDialog("Discard this walk?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                Button("Discard walk", role: .destructive, action: onDone)
            }
        }
        .interactiveDismissDisabled()
    }

    private func save() {
        let walk = Walk(
            id: draft.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            points: draft.points,
            start: draft.start,
            end: draft.end,
            distance: draft.distance,
            movingDuration: draft.movingDuration,
            elevationGain: draft.elevationGain
        )
        walk.note = note
        walk.photoData = photoData
        walk.photoColorHex = photoColorHex
        context.insert(walk)
        try? context.save()
        app.resolver.resolvePending(in: context)
        onDone()
        AdManager.shared.naturalBreak()
    }
}

/// Map showing a route with start/finish markers (static or interactive).
struct RouteMapPreview: View {
    let coordinates: [CLLocationCoordinate2D]
    var interactive = false

    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue
    @State private var command: MapCommand?

    var body: some View {
        var pins: [MapPin] = []
        if let first = coordinates.first {
            pins.append(MapPin(id: "start", coordinate: first, color: UIColor(Theme.teal), symbol: "figure.walk"))
        }
        if let last = coordinates.last, coordinates.count > 1 {
            pins.append(MapPin(id: "finish", coordinate: last, color: UIColor(Theme.violet), symbol: "flag.checkered"))
        }
        return FootprintMap(
            route: coordinates,
            pins: pins,
            style: MapStyleChoice(rawValue: styleRaw) ?? .standard,
            interactive: interactive,
            showsUser: false,
            initialRegion: Geo.region(fitting: coordinates, padding: 1.6, minSpan: 0.004),
            command: $command
        )
        .overlay(alignment: .bottomTrailing) {
            if interactive {
                Button {
                    command = MapCommand(kind: .fit(coordinates))
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 38, height: 38)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(10)
                .accessibilityLabel("Fit route")
            }
        }
    }
}
