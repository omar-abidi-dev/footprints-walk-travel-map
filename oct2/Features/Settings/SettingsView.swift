import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query private var places: [Place]
    @Query private var walks: [Walk]

    @AppStorage("displayName") private var displayName = ""
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric
    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue
    @AppStorage("hasOnboarded") private var hasOnboarded = true

    private enum ImportKind { case timeline, backup }
    @State private var importKind: ImportKind = .timeline
    @State private var showImporter = false
    @State private var exportDoc: BackupDocument?
    @State private var showExporter = false
    @State private var working = false
    @State private var message: String?
    @State private var confirm: ConfirmAction?

    private enum ConfirmAction: Identifiable {
        case imported, sample, everything
        var id: Self { self }
    }

    var body: some View {
        Form {
            Section("Profile") {
                TextField("Your name", text: $displayName)
            }

            Section("Preferences") {
                Toggle("Metric units", isOn: $metric)
                Picker("Map style", selection: $styleRaw) {
                    ForEach(MapStyleChoice.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Button("Location permissions") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
            }

            Section {
                Button {
                    importKind = .timeline
                    showImporter = true
                } label: {
                    Label("Import Google Timeline", systemImage: "square.and.arrow.down.on.square")
                }
                Button {
                    do {
                        exportDoc = try BackupService.export(context: context)
                        showExporter = true
                    } catch { message = error.localizedDescription }
                } label: {
                    Label("Back up to Files or iCloud Drive", systemImage: "icloud.and.arrow.up")
                }
                Button {
                    importKind = .backup
                    showImporter = true
                } label: {
                    Label("Restore from backup", systemImage: "clock.arrow.circlepath")
                }
                if app.resolver.remaining > 0 {
                    HStack {
                        ProgressView()
                        Text("Locating \(app.resolver.remaining) footprints…").foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        app.resolver.retryFailed(in: context)
                    } label: {
                        Label("Retry locating regions", systemImage: "location.magnifyingglass")
                    }
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Everything is stored on this iPhone. To get your Timeline: open Google Maps → your profile → Settings → Personal content → Export Timeline data, then pick the file here.")
            }

            Section("Demo") {
                Button {
                    SampleData.load(into: context)
                    message = "Sample journey added across 9 countries."
                } label: {
                    Label("Load sample journey", systemImage: "sparkles")
                }
                Button {
                    hasOnboarded = false
                } label: {
                    Label("Show welcome again", systemImage: "hand.wave")
                }
            }

            Section {
                Button("Remove imported Timeline data", role: .destructive) { confirm = .imported }
                Button("Remove sample journey", role: .destructive) { confirm = .sample }
                Button("Erase all footprints", role: .destructive) { confirm = .everything }
            } header: {
                Text("Reset")
            } footer: {
                Text("\(places.count) places · \(walks.count) walks")
            }

            if AdManager.shared.privacyOptionsRequired {
                Section {
                    Button {
                        Task { await AdManager.shared.presentPrivacyOptions() }
                    } label: {
                        Label("Privacy choices", systemImage: "hand.raised")
                    }
                } header: {
                    Text("Ads")
                } footer: {
                    Text("Change how your data is used for ads.")
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                LabeledContent("Analytics", value: "None")
                Text("Footprints never uploads your location. Backups go only where you choose. Ads are provided by Google AdMob.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .disabled(working)
        .overlay {
            if working {
                ProgressView("Importing…")
                    .padding(24)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            Task { await runImport(url) }
        }
        .fileExporter(isPresented: $showExporter, document: exportDoc, contentType: .json,
                      defaultFilename: "Footprints-\(Date.now.formatted(.iso8601.year().month().day()))") { result in
            if case .success = result { message = "Backup saved." }
        }
        .alert("Footprints", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog("Are you sure?", isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), titleVisibility: .visible, presenting: confirm) { action in
            Button("Delete", role: .destructive) { perform(action) }
        } message: { action in
            switch action {
            case .imported: Text("Removes places and walks that came from Google Timeline.")
            case .sample: Text("Removes the demo places and walks.")
            case .everything: Text("Deletes every place and walk. This can't be undone.")
            }
        }
    }

    private func runImport(_ url: URL) async {
        working = true
        defer { working = false }
        do {
            switch importKind {
            case .timeline:
                let s = try await TimelineImporter.importFile(at: url, into: context)
                app.resolver.resolvePending(in: context)
                message = "Imported \(s.newPlaces) new places (\(s.rawVisits) visits) and \(s.walks) walks. Badges fill in as each footprint is located."
            case .backup:
                let (p, w) = try BackupService.restore(from: url, into: context)
                app.resolver.resolvePending(in: context)
                message = "Restored \(p) places and \(w) walks."
            }
        } catch {
            message = error.localizedDescription
        }
    }

    private func perform(_ action: ConfirmAction) {
        let match: (String) -> Bool = switch action {
        case .imported: { $0 == RecordSource.imported.rawValue }
        case .sample: { $0 == RecordSource.sample.rawValue }
        case .everything: { _ in true }
        }
        for p in places where match(p.sourceRaw) { context.delete(p) }
        for w in walks where match(w.sourceRaw) { context.delete(w) }
        try? context.save()
        RouteCache.shared.removeAll()
        ThumbnailCache.shared.removeAll()
    }
}
