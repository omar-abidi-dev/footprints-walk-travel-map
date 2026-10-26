import SwiftUI
import SwiftData

struct BadgesView: View {
    @Environment(AppModel.self) private var app
    @Query private var places: [Place]
    @Query private var walks: [Walk]

    @State private var stats = FootprintStats()
    @State private var selectedAchievement: Achievement?

    private var signature: String {
        "\(places.count)-\(walks.count)-\(app.resolver.remaining)-\(app.resolver.isRunning)"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if app.resolver.remaining > 0 { resolvingBanner }

                    WorldHeroCard(stats: stats)

                    VStack(spacing: 12) {
                        SectionHeader(title: "Regional badges", subtitle: "Fill every region by visiting it")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            ForEach(stats.regionProgress) { progress in
                                NavigationLink {
                                    AtlasDetailView(progress: progress)
                                } label: {
                                    AtlasCard(progress: progress)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(spacing: 12) {
                        SectionHeader(title: "Achievements",
                                      subtitle: "\(stats.achievements.filter { $0.tier != .locked }.count) of \(stats.achievements.count) unlocked")
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 18) {
                            ForEach(stats.achievements) { a in
                                Button { selectedAchievement = a } label: {
                                    VStack(spacing: 8) {
                                        MedalView(achievement: a)
                                        Text(a.title)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                        Text(a.nextThreshold.map { "\(a.label(a.value)) / \(a.label($0))" } ?? "Maxed out")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .card()
                    }

                    if !stats.countries.isEmpty {
                        VStack(spacing: 12) {
                            SectionHeader(title: "Countries", subtitle: "In the order you first set foot")
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                                ForEach(stats.countries.sorted { $0.value < $1.value }, id: \.key) { code, date in
                                    HStack(spacing: 10) {
                                        Text(Flag.emoji(code)).font(.title2)
                                        VStack(alignment: .leading, spacing: 0) {
                                            Text(Flag.name(code)).font(.subheadline.weight(.semibold)).lineLimit(1)
                                            Text(date.formatted(.dateTime.month(.abbreviated).year()))
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .card(padding: 12, radius: 18)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .background(Theme.canvas)
            .navigationTitle("Badges")
            .task(id: signature) {
                withAnimation(.smooth) { stats = BadgeEngine.compute(places: places, walks: walks) }
            }
            .sheet(item: $selectedAchievement) { a in
                AchievementDetail(achievement: a)
                    .presentationDetents([.height(380)])
            }
        }
    }

    private var resolvingBanner: some View {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text("Placing your footprints").font(.subheadline.weight(.semibold))
                Text("\(app.resolver.remaining) left to locate — badges update as we go")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .card(padding: 14)
    }
}

// MARK: - World hero

struct WorldHeroCard: View {
    let stats: FootprintStats

    var body: some View {
        let total = WorldCatalog.totalCountries
        let fraction = Double(stats.countries.count) / Double(total)

        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("WORLD EXPLORER")
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.8))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(stats.countries.count)")
                            .font(.system(size: 54, weight: .heavy, design: .rounded))
                            .contentTransition(.numericText())
                        Text("of \(total) countries")
                            .font(.headline)
                            .foregroundStyle(.white.opacity(0.85))
                    }
                    Text(String(format: "%.1f%% of the world", fraction * 100))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                ZStack {
                    ProgressRing(progress: fraction, lineWidth: 10, colors: [.white.opacity(0.6), .white, .white.opacity(0.6)])
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 30))
                }
                .frame(width: 84, height: 84)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 14), GridItem(.flexible())], spacing: 12) {
                ForEach(stats.continents) { c in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Label(c.continent.name, systemImage: c.continent.symbol)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            Text("\(c.visited)/\(c.continent.countries.count)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                        }
                        GeometryReader { geo in
                            Capsule().fill(.white.opacity(0.25))
                                .overlay(alignment: .leading) {
                                    Capsule().fill(.white)
                                        .frame(width: max(c.visited > 0 ? 6 : 0, geo.size.width * c.fraction))
                                }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.mesh(Theme.worldMesh), in: .rect(cornerRadius: 30, style: .continuous))
        .shadow(color: Theme.ocean.opacity(0.25), radius: 18, y: 8)
    }
}

// MARK: - Atlas

struct AtlasCard: View {
    let progress: RegionProgress

    var body: some View {
        let colors = progress.atlas.swiftColors
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(Flag.emoji(progress.atlas.code)).font(.system(size: 30))
                Spacer()
                ZStack {
                    ProgressRing(progress: progress.fraction, lineWidth: 5, colors: colors + [colors[0]])
                    Text("\(Int((progress.fraction * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(progress.atlas.title).font(.headline).lineLimit(1)
                Text("\(progress.count) of \(progress.total) \(progress.atlas.unitName.lowercased())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            MiniTiles(progress: progress)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 14)
        .opacity(progress.count == 0 ? 0.75 : 1)
    }
}

/// A strip of tiny tiles hinting at completion.
struct MiniTiles: View {
    let progress: RegionProgress
    var body: some View {
        let colors = progress.atlas.swiftColors
        let regions = progress.atlas.regions
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 8, maximum: 9), spacing: 2.5)], alignment: .leading, spacing: 2.5) {
            ForEach(regions.prefix(52)) { r in
                RoundedRectangle(cornerRadius: 2)
                    .fill(progress.visited[r.id] != nil ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .frame(height: 48, alignment: .top)
    }
}

struct AtlasDetailView: View {
    let progress: RegionProgress
    @State private var appeared = false

    var body: some View {
        let atlas = progress.atlas
        let colors = atlas.swiftColors
        let visited = atlas.regions.filter { progress.visited[$0.id] != nil }
            .sorted { progress.visited[$0.id]!.first < progress.visited[$1.id]!.first }
        let remaining = atlas.regions.filter { progress.visited[$0.id] == nil }

        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 16) {
                    ZStack {
                        ProgressRing(progress: appeared ? progress.fraction : 0, lineWidth: 10, colors: colors + [colors[0]])
                        Text(Flag.emoji(atlas.code)).font(.system(size: 38))
                    }
                    .frame(width: 96, height: 96)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(progress.count)")
                                .font(.system(size: 44, weight: .heavy, design: .rounded))
                                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            Text("/ \(progress.total)").font(.title2.weight(.bold)).foregroundStyle(.secondary)
                        }
                        Text("\(atlas.unitName) explored").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .card()

                Group {
                    if atlas.hasTileMap {
                        TileCartogram(progress: progress, appeared: appeared)
                    } else {
                        HexGrid(progress: progress, appeared: appeared)
                    }
                }
                .card()

                if !visited.isEmpty {
                    VStack(spacing: 0) {
                        SectionHeader(title: "Visited").padding(.bottom, 8)
                        ForEach(visited) { r in
                            let info = progress.visited[r.id]!
                            HStack {
                                Circle().fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom)).frame(width: 10, height: 10)
                                Text(r.name).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text("\(info.count) footprint\(info.count == 1 ? "" : "s") · since \(info.first.formatted(.dateTime.month(.abbreviated).year()))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 9)
                            if r.id != visited.last?.id { Divider() }
                        }
                    }
                    .card()
                }

                if !remaining.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(title: "Still to explore", subtitle: "\(remaining.count) to go")
                        FlowText(items: remaining.map(\.name))
                    }
                    .card()
                }
            }
            .padding()
        }
        .background(Theme.canvas)
        .navigationTitle(atlas.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { withAnimation(.spring(duration: 1.0).delay(0.15)) { appeared = true } }
    }
}

struct TileCartogram: View {
    let progress: RegionProgress
    let appeared: Bool

    var body: some View {
        let atlas = progress.atlas
        let cols = atlas.tileColumns, rows = atlas.tileRows
        let colors = atlas.swiftColors
        GeometryReader { geo in
            let gap: CGFloat = 4
            let side = (geo.size.width - gap * CGFloat(cols - 1)) / CGFloat(cols)
            ZStack(alignment: .topLeading) {
                ForEach(atlas.regions) { r in
                    if let t = r.tile {
                        let on = progress.visited[r.id] != nil
                        RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                            .fill(on ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color(.tertiarySystemFill)))
                            .overlay(
                                Text(r.code)
                                    .font(.system(size: side * 0.32, weight: .bold, design: .rounded))
                                    .foregroundStyle(on ? .white : .secondary)
                            )
                            .frame(width: side, height: side)
                            .scaleEffect(appeared || !on ? 1 : 0.4)
                            .opacity(appeared || !on ? 1 : 0)
                            .animation(.spring(duration: 0.6).delay(Double(t.col + t.row) * 0.03), value: appeared)
                            .offset(x: CGFloat(t.col) * (side + gap), y: CGFloat(t.row) * (side + gap))
                    }
                }
            }
        }
        .aspectRatio(CGFloat(cols) / CGFloat(rows), contentMode: .fit)
    }
}

struct HexGrid: View {
    let progress: RegionProgress
    let appeared: Bool

    var body: some View {
        let colors = progress.atlas.swiftColors
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 6)], spacing: 6) {
            ForEach(Array(progress.atlas.regions.enumerated()), id: \.element.id) { idx, r in
                let on = progress.visited[r.id] != nil
                Hexagon()
                    .fill(on ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color(.tertiarySystemFill)))
                    .overlay(
                        Text(r.name)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .minimumScaleFactor(0.6)
                            .lineLimit(2)
                            .foregroundStyle(on ? .white : .secondary)
                            .padding(8)
                    )
                    .aspectRatio(0.9, contentMode: .fit)
                    .scaleEffect(appeared || !on ? 1 : 0.3)
                    .animation(.spring(duration: 0.5).delay(Double(idx) * 0.02), value: appeared)
            }
        }
    }
}

struct FlowText: View {
    let items: [String]
    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
            ForEach(items, id: \.self) { name in
                Text(name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.tertiarySystemFill), in: .capsule)
            }
        }
    }
}

// MARK: - Medals

struct MedalView: View {
    let achievement: Achievement
    var size: CGFloat = 74

    var body: some View {
        let locked = achievement.tier == .locked
        ZStack {
            Circle()
                .fill(LinearGradient(colors: achievement.tierColors, startPoint: .top, endPoint: .bottom))
            Circle()
                .stroke(.white.opacity(locked ? 0.3 : 0.65), lineWidth: 2.5)
                .padding(size * 0.08)
            Image(systemName: achievement.symbol)
                .font(.system(size: size * 0.34, weight: .bold))
                .foregroundStyle(locked ? AnyShapeStyle(.secondary) : AnyShapeStyle(.white))
                .shadow(color: .black.opacity(locked ? 0 : 0.2), radius: 2, y: 1)
            if achievement.tier != .gold {
                ProgressRing(progress: achievement.progressToNext, lineWidth: 3.5,
                             colors: [Theme.coral, Theme.amber, Theme.coral])
                    .padding(-6)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: (achievement.tierColors.last ?? .clear).opacity(locked ? 0 : 0.45), radius: 8, y: 4)
    }
}

struct AchievementDetail: View {
    let achievement: Achievement

    var body: some View {
        VStack(spacing: 18) {
            MedalView(achievement: achievement, size: 110)
                .padding(.top, 28)
            VStack(spacing: 4) {
                Text(achievement.title).font(.title2.weight(.bold)).fontDesign(.rounded)
                Text(achievement.tier == .locked ? "Locked" : "\(String(describing: achievement.tier).capitalized) tier")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(achievement.tierColors.last ?? .secondary)
            }
            HStack(spacing: 10) {
                ForEach(Array(achievement.thresholds.enumerated()), id: \.offset) { i, t in
                    let reached = achievement.value >= t
                    VStack(spacing: 4) {
                        Image(systemName: reached ? "checkmark.seal.fill" : "seal")
                            .font(.title3)
                            .foregroundStyle(reached ? [Theme.bronze, Theme.silver, Theme.gold][i] : .secondary)
                        Text(["Bronze", "Silver", "Gold"][i]).font(.caption.weight(.semibold))
                        Text(achievement.label(t)).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.card, in: .rect(cornerRadius: 16))
                }
            }
            .padding(.horizontal)
            Text("Current: \(achievement.label(achievement.value))")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background(Theme.canvas)
    }
}
