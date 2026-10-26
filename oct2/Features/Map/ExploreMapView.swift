import SwiftUI
import MapKit
import SwiftData

enum MapLayer: String, CaseIterable, Identifiable {
    case all = "Everything", places = "Places", walks = "Walks"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .all: "square.stack.3d.up.fill"
        case .places: "mappin.and.ellipse"
        case .walks: "point.bottomleft.forward.to.point.topright.scurvepath.fill"
        }
    }
}

enum TimeFilter: String, CaseIterable, Identifiable {
    case all = "All time", year = "Past year", month = "Past 30 days", week = "Past 7 days"
    var id: String { rawValue }
    var since: Date? {
        let cal = Calendar.current
        switch self {
        case .all: return nil
        case .year: return cal.date(byAdding: .year, value: -1, to: .now)
        case .month: return cal.date(byAdding: .day, value: -30, to: .now)
        case .week: return cal.date(byAdding: .day, value: -7, to: .now)
        }
    }
}

enum MapStyleChoice: String, CaseIterable, Identifiable {
    case standard, street, muted, satellite, hybrid, worldImagery
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Apple Maps"
        case .street: "Street (OpenStreetMap)"
        case .muted: "Apple Muted"
        case .satellite: "Apple Satellite"
        case .hybrid: "Apple Hybrid"
        case .worldImagery: "Satellite (Esri)"
        }
    }

    /// Raster tile template for web-tile styles (nil for Apple's own map).
    var tileTemplate: String? {
        switch self {
        case .street: "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
        case .worldImagery: "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}"
        default: nil
        }
    }

    var attribution: String? {
        switch self {
        case .street: "© OpenStreetMap contributors"
        case .worldImagery: "Imagery © Esri, Maxar, Earthstar Geographics"
        default: nil
        }
    }

    /// The web-tile style to use when Apple's map can't load.
    var fallback: MapStyleChoice {
        switch self {
        case .satellite, .hybrid: .worldImagery
        default: .street
        }
    }
    var symbol: String {
        switch self {
        case .standard: "map"
        case .street: "road.lanes"
        case .muted: "map.circle"
        case .satellite: "globe.americas"
        case .hybrid: "square.2.layers.3d"
        case .worldImagery: "globe.europe.africa.fill"
        }
    }
}

/// Live suggestions from MapKit as the user types.
@Observable
final class SearchCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var results: [MKLocalSearchCompletion] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest, .query]
    }

    func update(_ query: String, region: MKCoordinateRegion?) {
        if let region { completer.region = region }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            results = []
            completer.cancel()
        } else {
            completer.queryFragment = query
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { results = Array(completer.results.prefix(8)) }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

struct AddPlaceRequest: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D?
    var name: String?
    var category: PlaceCategory?
}

struct ExploreMapView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Place.firstVisit, order: .reverse) private var places: [Place]
    @Query(sort: \Walk.startDate, order: .reverse) private var walks: [Walk]
    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    @State private var command: MapCommand?
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var layer: MapLayer = .all
    @State private var timeFilter: TimeFilter = .all
    @State private var selectedPlace: Place?
    @State private var selectedWalk: Walk?
    @State private var addRequest: AddPlaceRequest?
    @State private var didPositionCamera = false
    @State private var toast: String?

    @State private var searchText = ""
    @FocusState private var searchFocused: Bool
    @State private var completer = SearchCompleter()
    @State private var searchResult: MKMapItem?
    @State private var searching = false

    private var style: MapStyleChoice { MapStyleChoice(rawValue: styleRaw) ?? .standard }

    private var shownPlaces: [Place] {
        guard layer != .walks else { return [] }
        guard let since = timeFilter.since else { return places }
        return places.filter { $0.lastVisit >= since }
    }

    private var shownWalks: [Walk] {
        guard layer != .places else { return [] }
        guard let since = timeFilter.since else { return walks }
        return walks.filter { $0.startDate >= since }
    }

    private var searchPins: [MapPin] {
        guard let item = searchResult else { return [] }
        let cat = AddPlaceSheet.category(for: item.pointOfInterestCategory)
        return [MapPin(id: "search-\(item.location.coordinate.latitude),\(item.location.coordinate.longitude)",
                       coordinate: item.location.coordinate, title: item.name ?? "",
                       color: UIColor(Theme.coral), symbol: cat == .other ? "mappin" : cat.symbol, kind: .marker)]
    }

    var body: some View {
        FootprintMap(
            places: shownPlaces,
            walks: shownWalks,
            pins: searchPins,
            style: style,
            compassTop: 250,
            selectedWalkID: selectedWalk?.id,
            command: $command,
            onSelectPlace: { id in selectedPlace = places.first { $0.id == id } },
            onSelectWalk: { id in selectedWalk = walks.first { $0.id == id } },
            onRegionChange: { visibleRegion = $0 },
            onLongPress: { addRequest = AddPlaceRequest(coordinate: $0) },
            onTilesFailed: {
                guard style.tileTemplate == nil else { return }
                styleRaw = style.fallback.rawValue
                showToast("Apple Maps couldn't load here — switched to \(style.fallback.title)")
            }
        )
        .ignoresSafeArea()
        .overlay(alignment: .top) { topChrome }
        .overlay(alignment: .bottom) { bottomChrome }
        .overlay {
            if places.isEmpty && walks.isEmpty && !searchFocused && searchResult == nil { emptyState }
        }
        .overlay(alignment: .center) {
            if let toast {
                Text(toast)
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 30)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .sheet(item: $selectedPlace) { place in
            NavigationStack { PlaceDetailView(place: place) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $selectedWalk) { walk in
            NavigationStack { WalkDetailView(walk: walk) }
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $addRequest) { req in
            AddPlaceSheet(initialCoordinate: req.coordinate, initialName: req.name, initialCategory: req.category)
        }
        .onAppear(perform: positionCamera)
        .onChange(of: app.mapFocus) { positionCamera() }
        #if DEBUG
        .task {
            // `-searchQuery "Eiffel Tower"` runs a search on launch (for screenshots/tests).
            if let q = UserDefaults.standard.string(forKey: "searchQuery") {
                try? await Task.sleep(for: .seconds(2))
                searchText = q
                await runFreeSearch()
            }
        }
        #endif
        .onChange(of: searchText) { completer.update(searchText, region: visibleRegion) }
    }

    // MARK: Camera

    private func positionCamera() {
        if let focus = app.mapFocus {
            command = MapCommand(kind: .region(focus.region))
            app.mapFocus = nil
            didPositionCamera = true
            return
        }
        guard !didPositionCamera else { return }
        didPositionCamera = true
        if let here = app.lastKnownCoordinate {
            command = MapCommand(kind: .region(MKCoordinateRegion(center: here, latitudinalMeters: 6000, longitudinalMeters: 6000)))
        } else if !places.isEmpty || !walks.isEmpty {
            fitAll()
        }
    }

    private func fitAll() {
        let coords = shownPlaces.map(\.coordinate) + shownWalks.map(\.center)
        guard !coords.isEmpty else { return }
        command = MapCommand(kind: .fit(coords))
    }

    private func showToast(_ text: String) {
        withAnimation(.spring) { toast = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            withAnimation { toast = nil }
        }
    }

    // MARK: Top chrome

    private var topChrome: some View {
        VStack(spacing: 10) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    searchField
                    if searchFocused {
                        Button("Cancel") {
                            searchFocused = false
                            searchText = ""
                        }
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .padding(.horizontal, 14)
                        .frame(height: 48)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    } else {
                        filterMenu
                    }
                }
            }

            if searchFocused && !searchText.isEmpty {
                suggestions
            } else if !searchFocused {
                HStack(alignment: .top) {
                    statsPill
                    Spacer()
                    mapControls
                }
            }
        }
        .padding(.horizontal)
        .animation(.snappy, value: searchFocused)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.headline)
                .foregroundStyle(.secondary)
            TextField("Search places, cities, addresses", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { Task { await runFreeSearch() } }
            if searching {
                ProgressView()
            } else if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private var filterMenu: some View {
        Menu {
            Picker("Show", selection: $layer) {
                ForEach(MapLayer.allCases) { Label($0.rawValue, systemImage: $0.symbol).tag($0) }
            }
            Picker("Time", selection: $timeFilter) {
                ForEach(TimeFilter.allCases) { Text($0.rawValue).tag($0) }
            }
            Picker("Map style", selection: $styleRaw) {
                ForEach(MapStyleChoice.allCases) { Label($0.title, systemImage: $0.symbol).tag($0.rawValue) }
            }
        } label: {
            Image(systemName: layer == .all && timeFilter == .all ? "slider.horizontal.3" : "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 48, height: 48)
        }
        .glassEffect(.regular.interactive(), in: .circle)
    }

    private var statsPill: some View {
        let countries = Set(places.compactMap(\.countryCode) + walks.compactMap(\.countryCode)).count
        let distance = walks.reduce(0) { $0 + $1.distance }
        return HStack(spacing: 12) {
            statItem("globe.americas.fill", "\(countries)", Theme.ocean)
            statItem("mappin", "\(places.count)", Theme.coral)
            statItem("shoeprints.fill", Fmt.compactDistance(distance, metric: metric), Theme.teal)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .glassEffect(.regular, in: .capsule)
    }

    private func statItem(_ symbol: String, _ value: String, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(value).fontDesign(.rounded).monospacedDigit()
        }
        .font(.caption.weight(.semibold))
    }

    private var mapControls: some View {
        GlassEffectContainer(spacing: 8) {
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    controlButton("plus", "Zoom in") { command = MapCommand(kind: .zoomIn) }
                    Divider().frame(width: 26)
                    controlButton("minus", "Zoom out") { command = MapCommand(kind: .zoomOut) }
                }
                .glassEffect(.regular.interactive(), in: .capsule)

                controlButton("location.fill", "My location") {
                    app.requestLocation()
                    command = MapCommand(kind: .user)
                }
                .glassEffect(.regular.interactive(), in: .circle)

                controlButton("globe.europe.africa.fill", "Show all footprints") { fitAll() }
                    .glassEffect(.regular.interactive(), in: .circle)
            }
        }
    }

    private func controlButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 46, height: 46)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Search

    private var matchingPlaces: [Place] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        return Array(places.filter {
            $0.displayName.localizedStandardContains(q) || ($0.locality ?? "").localizedStandardContains(q)
        }.prefix(3))
    }

    private var suggestions: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !matchingPlaces.isEmpty {
                    sectionLabel("Your footprints")
                    ForEach(matchingPlaces) { place in
                        Button {
                            searchFocused = false
                            searchText = ""
                            command = MapCommand(kind: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 800, longitudinalMeters: 800)))
                            selectedPlace = place
                        } label: {
                            suggestionRow(symbol: place.category.symbol, tint: place.tint, title: place.displayName, subtitle: place.placeLine)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !completer.results.isEmpty {
                    sectionLabel("On the map")
                    ForEach(Array(completer.results.enumerated()), id: \.offset) { _, result in
                        Button {
                            Task { await select(result) }
                        } label: {
                            suggestionRow(symbol: result.subtitle.isEmpty ? "magnifyingglass" : "mappin",
                                          tint: Theme.ocean, title: result.title, subtitle: result.subtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if matchingPlaces.isEmpty && completer.results.isEmpty {
                    Text("Press search to look for “\(searchText)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.vertical, 6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .glassEffect(.regular, in: .rect(cornerRadius: 26))
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.bold))
            .tracking(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func suggestionRow(symbol: String, tint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(tint.gradient, in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .contentShape(.rect)
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        searching = true
        defer { searching = false }
        guard let response = try? await MKLocalSearch(request: MKLocalSearch.Request(completion: completion)).start() else {
            showToast("Couldn't find that place")
            return
        }
        show(response)
    }

    private func runFreeSearch() async {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        searching = true
        defer { searching = false }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = q
        if let visibleRegion { request.region = visibleRegion }
        guard let response = try? await MKLocalSearch(request: request).start() else {
            showToast("No results for “\(q)”")
            return
        }
        show(response)
    }

    private func show(_ response: MKLocalSearch.Response) {
        guard let item = response.mapItems.first else { return }
        searchFocused = false
        searchText = ""
        withAnimation(.snappy) { searchResult = item }
        let isPOI = item.pointOfInterestCategory != nil || response.boundingRegion.span.latitudeDelta < 0.02
        if isPOI {
            command = MapCommand(kind: .region(MKCoordinateRegion(center: item.location.coordinate, latitudinalMeters: 900, longitudinalMeters: 900)))
        } else {
            command = MapCommand(kind: .region(response.boundingRegion))
        }
    }

    // MARK: Bottom chrome

    @ViewBuilder
    private var bottomChrome: some View {
        if let item = searchResult {
            searchResultCard(item)
                .padding(.horizontal)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if !searchFocused {
            actionBar
        }
    }

    private func searchResultCard(_ item: MKMapItem) -> some View {
        let cat = AddPlaceSheet.category(for: item.pointOfInterestCategory)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: cat == .other ? "mappin" : cat.symbol)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(cat.color.gradient, in: .circle)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name ?? "Dropped pin").font(.headline).lineLimit(2)
                    if let addr = item.address?.shortAddress ?? item.address?.fullAddress {
                        Text(addr).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    if let here = app.lastKnownCoordinate {
                        Text("\(Fmt.distance(Geo.distance(here, item.location.coordinate), metric: metric)) away")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.ocean)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    withAnimation(.snappy) { searchResult = nil }
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
            }
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button {
                        addRequest = AddPlaceRequest(coordinate: item.location.coordinate, name: item.name, category: cat)
                    } label: {
                        Label("Save place", systemImage: "mappin.and.ellipse")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.coral)

                    Button {
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                    } label: {
                        Label("Directions", systemImage: "figure.walk")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(18)
        .glassEffect(.regular, in: .rect(cornerRadius: 30))
    }

    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let attribution = style.attribution {
                Text(attribution)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.background.opacity(0.7), in: .capsule)
                    .padding(.leading, 20)
            }
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button {
                        addRequest = AddPlaceRequest(coordinate: visibleRegion?.center ?? app.lastKnownCoordinate)
                    } label: {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.title3.weight(.semibold))
                            .frame(width: 32, height: 40)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Add place")

                    Button {
                        if app.recorder.isActive { app.showRecorder = true } else { app.startWalk() }
                    } label: {
                        Label(app.recorder.isActive ? "Back to walk" : "Start walk", systemImage: "figure.walk")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.coral)
                }
                .padding(.horizontal)
            }
        }
        .padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "shoeprints.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(Theme.sunrise)
            Text("Your life map starts here")
                .font(.title3.weight(.bold)).fontDesign(.rounded)
            Text("Take a walk, search for a place, or long-press anywhere on the map to pin it.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Load a sample journey") {
                withAnimation { SampleData.load(into: context) }
                Task { @MainActor in fitAll() }
            }
            .buttonStyle(.glass)
        }
        .padding(24)
        .frame(maxWidth: 340)
        .glassEffect(.regular, in: .rect(cornerRadius: 28))
        .padding()
    }
}

struct WalkStartMarker: View {
    var body: some View {
        Image(systemName: "figure.walk")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 26, height: 26)
            .background(LinearGradient(colors: [Theme.teal, Theme.ocean], startPoint: .top, endPoint: .bottom), in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: Theme.ocean.opacity(0.4), radius: 4, y: 2)
    }
}
