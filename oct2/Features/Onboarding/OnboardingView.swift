import SwiftUI
import SwiftData

struct OnboardingView: View {
    var onFinish: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(\.modelContext) private var context
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: String
        let body: String
    }

    private let pages = [
        Page(symbol: "shoeprints.fill", title: "Every step,\nremembered", body: "Record your walks and watch them paint a living map of your life."),
        Page(symbol: "photo.on.rectangle.angled", title: "Places that\nmean something", body: "Pin cafés, viewpoints and hidden corners. Add a photo and its colors tint the dot on your map."),
        Page(symbol: "medal.star.fill", title: "Fill in\nthe world", body: "Earn badges for every state, prefecture and province you visit — and track your progress across continents.")
    ]

    var body: some View {
        ZStack {
            TimelineView(.animation) { ctx in
                let t = Float(ctx.date.timeIntervalSinceReferenceDate)
                MeshGradient(
                    width: 3, height: 3,
                    points: [
                        [0, 0], [0.5, 0], [1, 0],
                        [0, 0.5], [0.5 + 0.18 * sin(t * 0.6), 0.5 + 0.14 * cos(t * 0.5)], [1, 0.5],
                        [0, 1], [0.5, 1], [1, 1]
                    ],
                    colors: page == 2 ? Theme.worldMesh : Theme.heroMesh
                )
                .animation(.easeInOut(duration: 0.8), value: page)
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    ForEach(pages.indices, id: \.self) { i in
                        VStack(alignment: .leading, spacing: 22) {
                            Spacer()
                            Image(systemName: pages[i].symbol)
                                .font(.system(size: 72, weight: .semibold))
                                .symbolEffect(.bounce, value: page == i)
                                .frame(width: 130, height: 130)
                                .glassEffect(.regular, in: .rect(cornerRadius: 36))
                            Text(pages[i].title)
                                .font(.system(size: 42, weight: .heavy, design: .rounded))
                                .lineSpacing(-4)
                            Text(pages[i].body)
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.88))
                            Spacer()
                            Spacer()
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 12) {
                        if page < pages.count - 1 {
                            Button {
                                withAnimation { page += 1 }
                            } label: {
                                Text("Continue").font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.glass)
                        } else {
                            Button {
                                app.requestLocation()
                                onFinish()
                            } label: {
                                Label("Start exploring", systemImage: "location.fill")
                                    .font(.headline).frame(maxWidth: .infinity, minHeight: 48)
                            }
                            .buttonStyle(.glassProminent)
                            .tint(.white.opacity(0.25))

                            Button {
                                SampleData.load(into: context)
                                app.requestLocation()
                                onFinish()
                            } label: {
                                Text("Explore with a sample journey").font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity, minHeight: 40)
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
