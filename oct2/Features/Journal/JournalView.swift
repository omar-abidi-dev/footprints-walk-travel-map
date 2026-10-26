import SwiftUI
import SwiftData

enum JournalFilter: String, CaseIterable, Identifiable {
    case all = "All", walks = "Walks", places = "Places", favorites = "Favorites"
    var id: String { rawValue }
}

enum JournalItem: Identifiable {
    case walk(Walk)
    case place(Place)

    var id: UUID {
        switch self {
        case .walk(let w): w.id
        case .place(let p): p.id
        }
    }

    var date: Date {
        switch self {
        case .walk(let w): w.startDate
        case .place(let p): p.firstVisit
        }
    }

    var searchText: String {
        switch self {
        case .walk(let w):
            [w.displayTitle, w.note, w.locality, w.regionName, w.countryCode.map { Flag.name($0) }].compactMap { $0 }.joined(separator: " ")
        case .place(let p):
            [p.displayName, p.note, p.locality, p.regionName, p.category.title, p.address, p.countryCode.map { Flag.name($0) }].compactMap { $0 }.joined(separator: " ")
        }
    }

    var isFavorite: Bool {
        switch self {
        case .walk(let w): w.isFavorite
        case .place(let p): p.isFavorite
        }
    }
}

struct JournalView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Query(sort: \Walk.startDate, order: .reverse) private var walks: [Walk]
    @Query(sort: \Place.firstVisit, order: .reverse) private var places: [Place]

    @State private var filter: JournalFilter = .all
    @State private var search = ""
    @State private var showAddPlace = false

    private var items: [JournalItem] {
        var list: [JournalItem] = []
        if filter != .places { list += walks.map(JournalItem.walk) }
        if filter != .walks { list += places.map(JournalItem.place) }
        if filter == .favorites { list = list.filter(\.isFavorite) }
        let q = search.trimmingCharacters(in: .whitespaces)
        if !q.isEmpty { list = list.filter { $0.searchText.localizedStandardContains(q) } }
        return list.sorted { $0.date > $1.date }
    }

    private var sections: [(Date, [JournalItem])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: items) { cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date }
        return grouped.sorted { $0.key > $1.key }
    }

    private var onThisDay: [JournalItem] {
        let cal = Calendar.current
        let today = cal.dateComponents([.month, .day, .year], from: .now)
        let all = walks.map(JournalItem.walk) + places.map(JournalItem.place)
        return all.filter {
            let c = cal.dateComponents([.month, .day, .year], from: $0.date)
            return c.month == today.month && c.day == today.day && (c.year ?? 0) < (today.year ?? 0)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Filter", selection: $filter) {
                        ForEach(JournalFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))

                if search.isEmpty, filter == .all, let memory = onThisDay.first {
                    Section {
                        NavigationLink { destination(memory) } label: { OnThisDayCard(item: memory) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                ForEach(sections, id: \.0) { month, monthItems in
                    Section {
                        ForEach(monthItems) { item in
                            NavigationLink { destination(item) } label: { row(item) }
                                .swipeActions {
                                    Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                                }
                        }
                    } header: {
                        HStack {
                            Text(month.formatted(.dateTime.month(.wide).year()))
                            Spacer()
                            Text(monthSummary(monthItems)).textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if items.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView {
                            Label("Nothing here yet", systemImage: "book.pages")
                        } description: {
                            Text("Your walks and places will appear here as a journal of your life on foot.")
                        } actions: {
                            Button("Start a walk") { app.startWalk() }
                                .buttonStyle(.glassProminent)
                                .tint(Theme.coral)
                        }
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Places, walks, notes, cities")
            .navigationTitle("Journal")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Pin a place", systemImage: "mappin.and.ellipse") { showAddPlace = true }
                        Button("Start a walk", systemImage: "figure.walk") { app.startWalk() }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddPlace) {
                AddPlaceSheet(initialCoordinate: app.lastKnownCoordinate)
            }
        }
    }

    @ViewBuilder
    private func row(_ item: JournalItem) -> some View {
        switch item {
        case .walk(let w): WalkRow(walk: w)
        case .place(let p): PlaceRow(place: p)
        }
    }

    @ViewBuilder
    private func destination(_ item: JournalItem) -> some View {
        switch item {
        case .walk(let w): WalkDetailView(walk: w)
        case .place(let p): PlaceDetailView(place: p)
        }
    }

    private func monthSummary(_ items: [JournalItem]) -> String {
        let w = items.filter { if case .walk = $0 { true } else { false } }.count
        let p = items.count - w
        return [w > 0 ? "\(w) walk\(w == 1 ? "" : "s")" : nil, p > 0 ? "\(p) place\(p == 1 ? "" : "s")" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func delete(_ item: JournalItem) {
        withAnimation {
            switch item {
            case .walk(let w): context.delete(w)
            case .place(let p): context.delete(p)
            }
            try? context.save()
        }
    }
}

struct OnThisDayCard: View {
    let item: JournalItem

    var body: some View {
        let years = Calendar.current.dateComponents([.year], from: item.date, to: .now).year ?? 1
        HStack(spacing: 14) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(.white.opacity(0.2), in: .rect(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 2) {
                Text("ON THIS DAY · \(years) YEAR\(years == 1 ? "" : "S") AGO")
                    .font(.caption2.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.85))
                Text(title).font(.headline).foregroundStyle(.white).lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.mesh(Theme.heroMesh), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private var title: String {
        switch item {
        case .walk(let w): w.displayTitle
        case .place(let p): p.displayName
        }
    }
}
