import SwiftUI
import MapKit
import SwiftData

/// Adds a new place, or edits an existing one when `editing` is set.
struct AddPlaceSheet: View {
    var initialCoordinate: CLLocationCoordinate2D?
    var walkID: UUID?
    var editing: Place?
    var initialName: String?
    var initialCategory: PlaceCategory?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @State private var name = ""
    @State private var category: PlaceCategory = .other
    @State private var date = Date()
    @State private var note = ""
    @State private var favorite = false
    @State private var photoData: Data?
    @State private var photoColorHex: String?

    @State private var command: MapCommand?
    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue
    @State private var center: CLLocationCoordinate2D?
    @State private var cameraRegion: MKCoordinateRegion?
    @State private var isPanning = false

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var searching = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    searchField
                    if !results.isEmpty { resultsList }
                    mapPicker
                    detailsCard
                    categoryPicker
                    TextField("Memories, tips, who you were with…", text: $note, axis: .vertical)
                        .lineLimit(3...8)
                        .card()
                    PhotoPickerCard(photoData: $photoData, colorHex: $photoColorHex)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.canvas)
            .navigationTitle(editing == nil ? "New place" : "Edit place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .buttonStyle(.glassProminent)
                        .tint(Theme.coral)
                        .disabled(center == nil)
                }
            }
        }
        .onAppear(perform: load)
    }

    // MARK: Sections

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search for a place", text: $query)
                .submitLabel(.search)
                .onSubmit { Task { await search() } }
            if searching {
                ProgressView()
            } else if !query.isEmpty {
                Button { query = ""; results = [] } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .background(Theme.card, in: .capsule)
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(results.prefix(6).enumerated()), id: \.offset) { idx, item in
                Button { choose(item) } label: {
                    HStack(spacing: 12) {
                        let cat = Self.category(for: item.pointOfInterestCategory)
                        Image(systemName: cat.symbol)
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                            .background(cat.color.gradient, in: .circle)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? "Place").font(.subheadline.weight(.semibold))
                            if let addr = item.address?.shortAddress {
                                Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if idx < min(results.count, 6) - 1 { Divider() }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(Theme.card, in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var mapPicker: some View {
        ZStack {
            FootprintMap(
                style: MapStyleChoice(rawValue: styleRaw) ?? .standard,
                command: $command,
                onRegionChange: { region in
                    center = region.center
                    cameraRegion = region
                    isPanning = false
                },
                onRegionWillChange: { isPanning = true }
            )

            // Center pin (lifts while panning).
            VStack(spacing: 0) {
                PlaceDot(color: Color(hexString: photoColorHex) ?? category.color, symbol: category.symbol, size: 34)
                Rectangle().fill(.primary.opacity(0.6)).frame(width: 2, height: 12)
            }
            .offset(y: isPanning ? -30 : -22)
            .animation(.spring(duration: 0.25), value: isPanning)
            .allowsHitTesting(false)
        }
        .frame(height: 260)
        .clipShape(.rect(cornerRadius: 26, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Button {
                app.requestLocation()
                command = MapCommand(kind: .user)
            } label: {
                Image(systemName: "location.fill").font(.subheadline.weight(.semibold)).frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
            .padding(12)
        }
        .overlay(alignment: .topTrailing) {
            VStack(spacing: 0) {
                Button { command = MapCommand(kind: .zoomIn) } label: {
                    Image(systemName: "plus").font(.subheadline.weight(.semibold)).frame(width: 40, height: 40)
                }
                Divider().frame(width: 22)
                Button { command = MapCommand(kind: .zoomOut) } label: {
                    Image(systemName: "minus").font(.subheadline.weight(.semibold)).frame(width: 40, height: 40)
                }
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(12)
        }
        .overlay(alignment: .topLeading) {
            Text("Move the map to place the pin")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .glassEffect(.regular, in: .capsule)
                .padding(12)
        }
    }

    private var detailsCard: some View {
        VStack(spacing: 12) {
            TextField("Name (optional — we'll fill it in)", text: $name)
                .font(.title3.weight(.semibold))
            Divider()
            DatePicker("Visited", selection: $date, in: ...Date.now)
            Divider()
            Toggle(isOn: $favorite) {
                Label("Favorite", systemImage: "heart.fill").foregroundStyle(favorite ? Theme.rose : .primary)
            }
            .tint(Theme.rose)
        }
        .card()
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(PlaceCategory.allCases) { cat in
                    Button {
                        withAnimation(.snappy) { category = cat }
                    } label: {
                        Label(cat.title, systemImage: cat.symbol)
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(category == cat ? .white : cat.color)
                            .background(category == cat ? AnyShapeStyle(cat.color.gradient) : AnyShapeStyle(cat.color.opacity(0.12)), in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 2)
        }
        .scrollClipDisabled()
    }

    // MARK: Actions

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        if let p = editing {
            name = p.name; category = p.category; date = p.firstVisit; note = p.note
            favorite = p.isFavorite; photoData = p.photoData; photoColorHex = p.photoColorHex
            center = p.coordinate
            command = MapCommand(kind: .region(MKCoordinateRegion(center: p.coordinate, latitudinalMeters: 450, longitudinalMeters: 450)))
        } else if let c = initialCoordinate {
            center = c
            name = initialName ?? ""
            category = initialCategory ?? .other
            command = MapCommand(kind: .region(MKCoordinateRegion(center: c, latitudinalMeters: 450, longitudinalMeters: 450)))
        } else {
            command = MapCommand(kind: .user)
        }
    }

    private func search() async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        if let cameraRegion { request.region = cameraRegion }
        results = (try? await MKLocalSearch(request: request).start().mapItems) ?? []
    }

    private func choose(_ item: MKMapItem) {
        let c = item.location.coordinate
        command = MapCommand(kind: .region(MKCoordinateRegion(center: c, latitudinalMeters: 350, longitudinalMeters: 350)))
        center = c
        if name.isEmpty || results.contains(where: { $0.name == name }) { name = item.name ?? name }
        if category == .other { category = Self.category(for: item.pointOfInterestCategory) }
        results = []
        query = ""
    }

    private func save() {
        guard let center else { return }
        if let p = editing {
            if Geo.distance(p.coordinate, center) > 25 {
                p.latitude = center.latitude
                p.longitude = center.longitude
                p.geocodeState = GeocodeState.pending
            }
            p.name = name.trimmingCharacters(in: .whitespaces)
            p.category = category
            p.firstVisit = min(date, p.lastVisit)
            p.note = note
            p.isFavorite = favorite
            p.photoData = photoData
            p.photoColorHex = photoColorHex
        } else {
            let p = Place(name: name.trimmingCharacters(in: .whitespaces), coordinate: center, date: date,
                          category: category, source: walkID == nil ? .manual : .walk)
            p.note = note
            p.isFavorite = favorite
            p.photoData = photoData
            p.photoColorHex = photoColorHex
            p.walkID = walkID
            context.insert(p)
        }
        try? context.save()
        app.resolver.resolvePending(in: context)
        dismiss()
        if editing == nil { AdManager.shared.naturalBreak() }
    }

    static func category(for poi: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poi else { return .other }
        switch poi {
        case .restaurant, .bakery, .brewery, .winery, .foodMarket, .nightlife: return .food
        case .cafe: return .coffee
        case .park, .nationalPark, .beach, .campground, .marina: return .nature
        case .museum, .theater, .library, .university, .school, .castle, .landmark: return .culture
        case .store: return .shopping
        case .hotel: return .stay
        case .publicTransport, .airport, .evCharger, .gasStation, .parking: return .transit
        default: return .other
        }
    }
}
