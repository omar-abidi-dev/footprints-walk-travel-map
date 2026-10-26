import SwiftUI
import SwiftData
import Charts

struct ProfileView: View {
    @Environment(AppModel.self) private var app
    @Query private var places: [Place]
    @Query(sort: \Walk.startDate, order: .reverse) private var walks: [Walk]
    @AppStorage("displayName") private var displayName = ""
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    @State private var stats = FootprintStats()

    private var signature: String {
        "\(places.count)-\(walks.count)-\(app.resolver.remaining)-\(walks.first?.id.uuidString ?? "")"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    header

                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        StatTile(value: Fmt.compactDistance(stats.totalDistance, metric: metric), label: "Walked", symbol: "shoeprints.fill", tint: Theme.teal)
                        StatTile(value: "\(stats.walkCount)", label: "Walks", symbol: "figure.walk", tint: Theme.ocean)
                        StatTile(value: "\(stats.placeCount)", label: "Places", symbol: "mappin.and.ellipse", tint: Theme.coral)
                        StatTile(value: "\(stats.countries.count)", label: "Countries", symbol: "globe.europe.africa.fill", tint: Theme.violet)
                        StatTile(value: "\(stats.regionsVisited)", label: "Regions", symbol: "map.fill", tint: Theme.rose)
                        StatTile(value: String(format: stats.exploredKm2 < 10 ? "%.1f" : "%.0f", stats.exploredKm2), label: "km² explored", symbol: "square.grid.3x3.fill", tint: Theme.moss)
                    }

                    weeklyChart
                    heatmap
                    records
                    if !stats.topRegions.isEmpty { favoriteRegions }
                }
                .padding()
            }
            .background(Theme.canvas)
            .navigationTitle("You")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "gearshape") }
                }
            }
            .task(id: signature) {
                withAnimation(.smooth) { stats = BadgeEngine.compute(places: places, walks: walks) }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        let name = displayName.isEmpty ? "Explorer" : displayName
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Text(String(name.prefix(1)).uppercased())
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.coral)
                    .frame(width: 66, height: 66)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.title2.weight(.bold)).fontDesign(.rounded)
                    if let first = stats.firstDate {
                        Text("Leaving footprints since \(first.formatted(.dateTime.month(.wide).year()))")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        Text("Your story starts with one step").font(.subheadline).foregroundStyle(.white.opacity(0.85))
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Level \(stats.level) · \(stats.levelTitle)").font(.headline)
                    Spacer()
                    Text("\(stats.xp.formatted()) XP").font(.subheadline.weight(.semibold)).monospacedDigit()
                }
                GeometryReader { geo in
                    Capsule().fill(.white.opacity(0.25))
                        .overlay(alignment: .leading) {
                            Capsule().fill(.white).frame(width: max(8, geo.size.width * stats.levelProgress))
                        }
                }
                .frame(height: 8)
                Text("Walk, pin places and visit new regions to level up")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(Theme.mesh(Theme.heroMesh), in: .rect(cornerRadius: 30, style: .continuous))
        .shadow(color: Theme.coral.opacity(0.3), radius: 18, y: 8)
    }

    // MARK: Charts

    private var weeklyChart: some View {
        let unit = metric ? 1000.0 : 1609.344
        let total = stats.weeks.reduce(0) { $0 + $1.meters }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last 12 weeks").font(.headline)
                    Text("\(Fmt.compactDistance(total, metric: metric)) · avg \(Fmt.compactDistance(total / 12, metric: metric))/week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Chart(stats.weeks) { week in
                BarMark(
                    x: .value("Week", week.start, unit: .weekOfYear),
                    y: .value(metric ? "km" : "mi", week.meters / unit)
                )
                .foregroundStyle(LinearGradient(colors: [Theme.amber, Theme.coral], startPoint: .top, endPoint: .bottom))
                .cornerRadius(5)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                }
            }
            .frame(height: 160)
        }
        .card()
    }

    private var heatmap: some View {
        let cal = Calendar.current
        let weeks = 20
        let thisWeek = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let start = cal.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek) ?? thisWeek
        let maxCount = max(stats.activeDays.values.max() ?? 1, 1)
        let activeInRange = stats.activeDays.filter { $0.key >= start }.count

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activity").font(.headline)
                Spacer()
                Text("\(activeInRange) active days").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 3) {
                ForEach(0..<weeks, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            let count = stats.activeDays[cal.startOfDay(for: day)] ?? 0
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(count == 0 ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Theme.coral.opacity(0.35 + 0.65 * Double(count) / Double(maxCount))))
                                .aspectRatio(1, contentMode: .fit)
                                .opacity(day > .now ? 0.3 : 1)
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                Spacer()
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach([0.0, 0.4, 0.7, 1.0], id: \.self) { o in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(o == 0 ? AnyShapeStyle(Color(.tertiarySystemFill)) : AnyShapeStyle(Theme.coral.opacity(0.35 + 0.65 * o)))
                        .frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .card()
    }

    private var records: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Personal records").font(.headline)
            HStack(spacing: 10) {
                recordCell("flame.fill", "\(stats.currentStreak)", "Day streak", Theme.coral)
                recordCell("trophy.fill", "\(stats.bestStreak)", "Best streak", Theme.gold)
                recordCell("flag.checkered", Fmt.compactDistance(stats.longestWalk, metric: metric), "Longest walk", Theme.ocean)
            }
            HStack(spacing: 10) {
                recordCell("clock.fill", Fmt.longDuration(stats.totalDuration), "Time on foot", Theme.violet)
                recordCell("camera.fill", "\(stats.photoCount)", "Memories", Theme.rose)
                recordCell("globe", "\(stats.continents.filter { $0.visited > 0 }.count)", "Continents", Theme.teal)
            }
        }
        .card()
    }

    private func recordCell(_ symbol: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.title3).foregroundStyle(tint)
            Text(value).font(.headline.weight(.bold)).fontDesign(.rounded).lineLimit(1).minimumScaleFactor(0.6)
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 16, style: .continuous))
    }

    private var favoriteRegions: some View {
        let top = stats.topRegions.first?.count ?? 1
        return VStack(alignment: .leading, spacing: 12) {
            Text("Favorite regions").font(.headline)
            ForEach(Array(stats.topRegions.enumerated()), id: \.element.id) { i, r in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(i + 1)").font(.caption.weight(.heavy)).foregroundStyle(.secondary).frame(width: 16)
                        Text("\(Flag.emoji(r.countryCode)) \(r.name)").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(r.count)").font(.subheadline.weight(.bold)).monospacedDigit()
                    }
                    GeometryReader { geo in
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.coral, Theme.amber], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(8, geo.size.width * Double(r.count) / Double(top)))
                    }
                    .frame(height: 6)
                    .padding(.leading, 24)
                }
            }
        }
        .card()
    }
}
