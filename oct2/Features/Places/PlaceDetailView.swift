import SwiftUI
import MapKit
import SwiftData

struct PlaceDetailView: View {
    @Bindable var place: Place

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var app

    @State private var showEdit = false
    @State private var confirmDelete = false
    @State private var linkedWalk: Walk?
    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    chips
                    miniMap
                    if !place.note.isEmpty {
                        Text(place.note)
                            .font(.body)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .card()
                    }
                    infoCard
                    if let walk = linkedWalk {
                        NavigationLink {
                            WalkDetailView(walk: walk)
                        } label: {
                            WalkRow(walk: walk)
                                .card(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom, 24)
        }
        .background(Theme.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.spring) { place.isFavorite.toggle() }
                } label: {
                    Image(systemName: place.isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(place.isFavorite ? Theme.rose : .primary)
                        .symbolEffect(.bounce, value: place.isFavorite)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit", systemImage: "pencil") { showEdit = true }
                    Button("Show on map", systemImage: "map") {
                        dismiss()
                        app.showOnMap(place.coordinate, span: 0.006)
                    }
                    ShareLink(item: shareURL, subject: Text(place.displayName), message: Text(place.note)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    Divider()
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showEdit) {
            AddPlaceSheet(editing: place)
        }
        .confirmationDialog("Delete this place?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(place)
                try? context.save()
                dismiss()
            }
        }
        .task(id: place.walkID) {
            guard let id = place.walkID else { linkedWalk = nil; return }
            linkedWalk = try? context.fetch(FetchDescriptor<Walk>(predicate: #Predicate { $0.id == id })).first
        }
    }

    private var shareURL: URL {
        let q = place.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://maps.apple.com/?ll=\(place.latitude),\(place.longitude)&q=\(q)")!
    }

    // MARK: Sections

    @ViewBuilder
    private var hero: some View {
        if let data = place.photoData, let image = UIImage(data: data) {
            Color.clear
                .frame(height: 280)
                .overlay {
                    Image(uiImage: image).resizable().scaledToFill()
                }
                .clipped()
                .overlay(alignment: .bottom) {
                    LinearGradient(colors: [.clear, Theme.canvas], startPoint: .center, endPoint: .bottom)
                }
        } else {
            ZStack {
                Theme.mesh([place.tint, place.tint.opacity(0.7), Theme.amber.opacity(0.7),
                            place.tint.opacity(0.8), place.tint, place.tint.opacity(0.6),
                            Theme.coral.opacity(0.5), place.tint.opacity(0.9), place.tint])
                Image(systemName: place.category.symbol)
                    .font(.system(size: 64, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(radius: 10)
            }
            .frame(height: 180)
            .clipShape(.rect(cornerRadius: 28, style: .continuous))
            .padding(.horizontal)
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(place.displayName)
                .font(.largeTitle.weight(.bold))
                .fontDesign(.rounded)
            if !place.placeLine.isEmpty {
                Text("\(Flag.emoji(place.countryCode)) \(place.placeLine)")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            } else if place.geocodeState == GeocodeState.pending {
                Label("Finding where this is…", systemImage: "location.magnifyingglass")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(text: place.category.title, symbol: place.category.symbol, tint: place.category.color)
                Chip(text: Fmt.day(place.firstVisit), symbol: "calendar", tint: Theme.ocean)
                if place.visitCount > 1 {
                    Chip(text: "Visited \(place.visitCount)×", symbol: "repeat", tint: Theme.violet)
                }
                if place.isFavorite {
                    Chip(text: "Favorite", symbol: "heart.fill", tint: Theme.rose)
                }
            }
        }
        .scrollClipDisabled()
    }

    private var miniMap: some View {
        FootprintMap(
            places: [place],
            style: MapStyleChoice(rawValue: styleRaw) ?? .standard,
            clusters: false,
            interactive: false,
            showsUser: false,
            initialRegion: MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 700, longitudinalMeters: 700),
            command: .constant(nil)
        )
        .allowsHitTesting(false)
        .overlay { Color.clear.contentShape(.rect) }
        .frame(height: 150)
        .clipShape(.rect(cornerRadius: 22, style: .continuous))
        .onTapGesture {
            dismiss()
            app.showOnMap(place.coordinate, span: 0.006)
        }
    }

    private var infoCard: some View {
        VStack(spacing: 12) {
            infoRow("First visit", Fmt.day(place.firstVisit), "calendar.badge.clock")
            if place.lastVisit > place.firstVisit.addingTimeInterval(3600) {
                Divider()
                infoRow("Last visit", Fmt.day(place.lastVisit), "clock.arrow.circlepath")
            }
            if let region = place.regionName {
                Divider()
                infoRow("Region", region, "map")
            }
            if let addr = place.address {
                Divider()
                infoRow("Address", addr, "signpost.right")
            }
            Divider()
            infoRow("Added from", sourceText, "tray.and.arrow.down")
        }
        .card()
    }

    private var sourceText: String {
        switch place.source {
        case .manual: "Pinned by you"
        case .walk: "During a walk"
        case .imported: "Google Timeline"
        case .sample: "Sample journey"
        }
    }

    private func infoRow(_ title: String, _ value: String, _ symbol: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Label(title, systemImage: symbol)
                .foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
    }
}
