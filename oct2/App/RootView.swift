import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @AppStorage("hasOnboarded") private var hasOnboarded = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.selectedTab) {
            Tab("Map", systemImage: "map.fill", value: AppTab.map) {
                ExploreMapView()
            }
            Tab("Journal", systemImage: "book.pages.fill", value: AppTab.journal) {
                JournalView()
            }
            Tab("Badges", systemImage: "medal.fill", value: AppTab.badges) {
                BadgesView()
            }
            Tab("You", systemImage: "person.crop.circle.fill", value: AppTab.profile) {
                ProfileView()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .tabViewBottomAccessory(isEnabled: app.recorder.isActive) {
            LiveWalkAccessory()
        }
        .fullScreenCover(isPresented: $app.showRecorder) {
            RecordWalkView()
        }
        .overlay {
            if !hasOnboarded {
                OnboardingView { hasOnboarded = true }
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: hasOnboarded)
        .task {
            #if DEBUG
            applyDebugLaunchArguments()
            #endif
            app.resolver.resolvePending(in: context)
        }
        .task(id: hasOnboarded) {
            guard hasOnboarded else { return }
            let model = self.app
            AdManager.shared.isSuppressed = { [weak model] in
                (model?.recorder.isActive ?? false) || !UserDefaults.standard.bool(forKey: "hasOnboarded")
            }
            // Give the location prompt from onboarding time to settle before consent/ATT.
            try? await Task.sleep(for: .seconds(1.5))
            await AdManager.shared.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background: AdManager.shared.didEnterBackground()
            case .active: AdManager.shared.didBecomeActive()
            default: break
            }
        }
    }

    #if DEBUG
    /// `-loadSample YES` seeds demo data; `-startTab journal|badges|profile` picks a tab (for screenshots).
    private func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "loadSample"), ((try? context.fetchCount(FetchDescriptor<Place>())) ?? 0) == 0 {
            SampleData.load(into: context)
        }
        switch defaults.string(forKey: "startTab") {
        case "journal": app.selectedTab = .journal
        case "badges": app.selectedTab = .badges
        case "profile": app.selectedTab = .profile
        default: break
        }
    }
    #endif
}
