import SwiftUI
import SwiftData

@main
struct FootprintsApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .tint(Theme.coral)
        }
        .modelContainer(for: [Place.self, Walk.self])
    }
}
