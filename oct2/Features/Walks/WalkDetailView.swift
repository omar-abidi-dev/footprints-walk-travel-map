import SwiftUI
import MapKit
import SwiftData
import Charts

struct WalkDetailView: View {
    @Bindable var walk: Walk

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(AppModel.self) private var app
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var pinned: [Place] = []
    @State private var shareImage: UIImage?
    @State private var selectedPlace: Place?

    private var points: [TrackPoint] { RouteCache.shared.points(for: walk) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                RouteMapPreview(coordinates: RouteCache.shared.displayCoordinates(for: walk), interactive: true)
                    .frame(height: 300)
                    .clipShape(.rect(cornerRadius: 28, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(walk.displayTitle)
                        .font(.largeTitle.weight(.bold))
                        .fontDesign(.rounded)
                    Text("\(Fmt.day(walk.startDate)) · \(Fmt.time(walk.startDate))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let place = walk.locality ?? walk.regionName {
                        Text("\(Flag.emoji(walk.countryCode)) \(place)")
                            .font(.subheadline.weight(.semibold))
                    }
                }

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10), GridItem(.flexible())], spacing: 10) {
                    StatTile(value: Fmt.distance(walk.distance, metric: metric), label: "Distance", symbol: "point.bottomleft.forward.to.point.topright.scurvepath.fill", tint: Theme.teal)
                    StatTile(value: Fmt.duration(walk.movingDuration), label: "Time", symbol: "stopwatch.fill", tint: Theme.ocean)
                    StatTile(value: Fmt.pace(distance: walk.distance, duration: walk.movingDuration, metric: metric), label: "Pace \(Fmt.paceUnit(metric: metric))", symbol: "speedometer", tint: Theme.violet)
                    StatTile(value: Fmt.elevation(walk.elevationGain, metric: metric), label: "Climb", symbol: "mountain.2.fill", tint: Theme.moss)
                    StatTile(value: "\(Int(walk.distance / 0.76).formatted())", label: "Steps (est.)", symbol: "shoeprints.fill", tint: Theme.coral)
                    StatTile(value: String(format: "%.0f", walk.movingDuration / 60 * 4.2), label: "kcal (est.)", symbol: "flame.fill", tint: Theme.amber)
                }

                if let profile = elevationProfile, profile.count > 4 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Elevation").font(.headline)
                        Chart(profile, id: \.0) { item in
                            AreaMark(x: .value("Distance", item.0), y: .value("Altitude", item.1))
                                .foregroundStyle(LinearGradient(colors: [Theme.moss.opacity(0.5), Theme.moss.opacity(0.05)], startPoint: .top, endPoint: .bottom))
                                .interpolationMethod(.catmullRom)
                            LineMark(x: .value("Distance", item.0), y: .value("Altitude", item.1))
                                .foregroundStyle(Theme.moss)
                                .interpolationMethod(.catmullRom)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .chartXAxisLabel(metric ? "km" : "mi")
                        .frame(height: 140)
                    }
                    .card()
                }

                if !walk.note.isEmpty {
                    Text(walk.note).frame(maxWidth: .infinity, alignment: .leading).card()
                }

                if let data = walk.photoData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 240)
                        .frame(maxWidth: .infinity)
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                }

                if !pinned.isEmpty {
                    SectionHeader(title: "Pinned on this walk")
                    VStack(spacing: 0) {
                        ForEach(pinned) { p in
                            Button { selectedPlace = p } label: { PlaceRow(place: p) }
                                .buttonStyle(.plain)
                            if p.id != pinned.last?.id { Divider().padding(.leading, 68) }
                        }
                    }
                    .card(padding: 12)
                }
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let shareImage {
                    ShareLink(item: Image(uiImage: shareImage), preview: SharePreview(walk.displayTitle, image: Image(uiImage: shareImage))) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(walk.isFavorite ? "Unfavorite" : "Favorite", systemImage: walk.isFavorite ? "heart.slash" : "heart") {
                        walk.isFavorite.toggle()
                    }
                    Button("Edit", systemImage: "pencil") { showEdit = true }
                    Button("Show on map", systemImage: "map") {
                        dismiss()
                        if let region = Geo.region(fitting: RouteCache.shared.displayCoordinates(for: walk), padding: 1.4) {
                            app.showOnMap(region: region)
                        }
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showEdit) { WalkEditSheet(walk: walk) }
        .sheet(item: $selectedPlace) { p in
            NavigationStack { PlaceDetailView(place: p) }
        }
        .confirmationDialog("Delete this walk?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(walk)
                try? context.save()
                dismiss()
            }
        }
        .task(id: walk.id) {
            let id = walk.id
            pinned = (try? context.fetch(FetchDescriptor<Place>(predicate: #Predicate { $0.walkID == id }, sortBy: [SortDescriptor(\.firstVisit)]))) ?? []
            shareImage = await renderShareCard()
        }
    }

    /// (distance in display units, altitude) pairs, downsampled.
    private var elevationProfile: [(Double, Double)]? {
        let pts = points
        guard pts.count > 4 else { return nil }
        let alts = pts.map(\.altitude)
        guard (alts.max() ?? 0) - (alts.min() ?? 0) > 2 else { return nil }
        let unit = metric ? 1000.0 : 1609.344
        var out: [(Double, Double)] = []
        var dist = 0.0
        let step = max(1, pts.count / 120)
        for i in pts.indices {
            if i > 0 { dist += Geo.distance(pts[i - 1].coordinate, pts[i].coordinate) }
            if i % step == 0 { out.append((dist / unit, metric ? pts[i].altitude : pts[i].altitude * 3.28084)) }
        }
        return out
    }

    private func renderShareCard() async -> UIImage? {
        guard let map = await RouteSnapshotter.shared.image(for: walk, size: CGSize(width: 360, height: 300), dark: scheme == .dark) else { return nil }
        let card = WalkShareCard(walk: walk, map: map, metric: metric)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Instagram-ready summary card.
struct WalkShareCard: View {
    let walk: Walk
    let map: UIImage
    let metric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(uiImage: map).resizable().frame(width: 360, height: 300)
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "shoeprints.fill")
                    Text("FOOTPRINTS").tracking(2)
                }
                .font(.caption.weight(.heavy))
                .foregroundStyle(.white.opacity(0.85))
                Text(walk.displayTitle).font(.title2.weight(.bold)).foregroundStyle(.white)
                HStack(spacing: 22) {
                    stat(Fmt.distance(walk.distance, metric: metric), "Distance")
                    stat(Fmt.duration(walk.movingDuration), "Time")
                    stat(Fmt.pace(distance: walk.distance, duration: walk.movingDuration, metric: metric), "Pace")
                }
                Text("\(Flag.emoji(walk.countryCode)) \(walk.locality ?? "") · \(Fmt.day(walk.startDate))")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
            .frame(width: 360, alignment: .leading)
            .background(LinearGradient(colors: [Theme.teal, Theme.ocean, Theme.violet], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .clipShape(.rect(cornerRadius: 28))
    }

    private func stat(_ v: String, _ l: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(v).font(.headline.weight(.bold)).fontDesign(.rounded).foregroundStyle(.white)
            Text(l).font(.caption2).foregroundStyle(.white.opacity(0.75))
        }
    }
}

struct WalkEditSheet: View {
    @Bindable var walk: Walk
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var note = ""
    @State private var photoData: Data?
    @State private var colorHex: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 12) {
                        TextField("Title", text: $title, prompt: Text(Walk.defaultTitle(for: walk.startDate)))
                            .font(.title3.weight(.semibold))
                        Divider()
                        TextField("Note", text: $note, axis: .vertical).lineLimit(3...10)
                    }
                    .card()
                    PhotoPickerCard(photoData: $photoData, colorHex: $colorHex, prompt: "Add a cover photo")
                }
                .padding()
            }
            .background(Theme.canvas)
            .navigationTitle("Edit walk")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel", role: .cancel) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        walk.title = title
                        walk.note = note
                        walk.photoData = photoData
                        walk.photoColorHex = colorHex
                        dismiss()
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.coral)
                }
            }
            .onAppear {
                title = walk.title; note = walk.note
                photoData = walk.photoData; colorHex = walk.photoColorHex
            }
        }
    }
}

// MARK: - Rows shared by Journal and detail screens

struct WalkRow: View {
    let walk: Walk
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric
    @State private var snapshot: UIImage?

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let snapshot {
                    Image(uiImage: snapshot).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Theme.teal.opacity(0.25), Theme.ocean.opacity(0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Image(systemName: "figure.walk").foregroundStyle(Theme.ocean)
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(.rect(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(walk.displayTitle).font(.headline).lineLimit(1)
                    if walk.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.rose) }
                }
                Text("\(Fmt.shortDay(walk.startDate)) · \(Fmt.time(walk.startDate))\(walk.locality.map { " · \($0)" } ?? "")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.distance(walk.distance, metric: metric))
                    .font(.subheadline.weight(.bold))
                    .fontDesign(.rounded)
                    .foregroundStyle(Theme.ocean)
                Text(Fmt.longDuration(walk.movingDuration))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(.rect)
        .task(id: "\(walk.id)-\(scheme == .dark)") {
            snapshot = await RouteSnapshotter.shared.image(for: walk, size: CGSize(width: 112, height: 112), dark: scheme == .dark)
        }
    }
}

struct PlaceRow: View {
    let place: Place

    var body: some View {
        HStack(spacing: 14) {
            Thumb(image: ThumbnailCache.shared.image(id: place.id, data: place.photoData, side: 56),
                  symbol: place.category.symbol, tint: place.tint)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(place.displayName).font(.headline).lineLimit(1)
                    if place.isFavorite { Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.rose) }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if place.visitCount > 1 {
                Text("×\(place.visitCount)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(place.tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(place.tint.opacity(0.12), in: .capsule)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }

    private var subtitle: String {
        var parts = [Fmt.shortDay(place.firstVisit)]
        if !place.placeLine.isEmpty { parts.append("\(Flag.emoji(place.countryCode)) \(place.placeLine)") }
        return parts.joined(separator: " · ")
    }
}
