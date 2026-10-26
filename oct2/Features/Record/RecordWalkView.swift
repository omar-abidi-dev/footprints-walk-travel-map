import SwiftUI
import MapKit

struct RecordWalkView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    @AppStorage("mapStyle") private var styleRaw = MapStyleChoice.standard.rawValue
    @State private var command: MapCommand?
    @State private var draft: WalkDraft?
    @State private var showTooShort = false
    @State private var showDiscard = false
    @State private var showDropPin = false
    @State private var pulse = false

    private var recorder: WalkRecorder { app.recorder }

    var body: some View {
        ZStack(alignment: .bottom) {
            FootprintMap(
                route: recorder.points.map(\.coordinate),
                pins: recorder.points.first.map {
                    [MapPin(id: "start", coordinate: $0.coordinate, color: UIColor(Theme.teal), symbol: "figure.walk")]
                } ?? [],
                style: MapStyleChoice(rawValue: styleRaw) ?? .standard,
                followUser: true,
                compassTop: 70,
                command: $command
            )
            .ignoresSafeArea()
            .overlay(alignment: .top) { header }
            .overlay(alignment: .trailing) {
                Button {
                    command = MapCommand(kind: .user)
                } label: {
                    Image(systemName: "location.fill").font(.headline).frame(width: 46, height: 46)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .padding(.trailing)
                .padding(.bottom, 200)
            }

            panel
        }
        .sheet(item: $draft) { draft in
            SaveWalkSheet(draft: draft) { app.showRecorder = false }
        }
        .sheet(isPresented: $showDropPin) {
            AddPlaceSheet(initialCoordinate: recorder.currentLocation?.coordinate ?? app.lastKnownCoordinate, walkID: recorder.walkID)
        }
        .alert("Too short to save", isPresented: $showTooShort) {
            Button("Keep walking", role: .cancel) {}
            Button("Discard", role: .destructive) { recorder.discard(); dismiss() }
        } message: {
            Text("Walk at least 30 meters to save it to your map.")
        }
        .confirmationDialog("Discard this walk?", isPresented: $showDiscard, titleVisibility: .visible) {
            Button("Discard walk", role: .destructive) { recorder.discard(); dismiss() }
        } message: {
            Text("Your route won't be saved.")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: recorder.state)
        .onAppear { pulse = true }
    }

    // MARK: Header

    private var header: some View {
        GlassEffectContainer(spacing: 10) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.down").font(.headline).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Minimize")

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 9, height: 9)
                        .scaleEffect(pulse && recorder.state == .recording ? 1.35 : 0.85)
                        .animation(.easeInOut(duration: 0.9).repeatForever(), value: pulse)
                    Text(statusText).font(.subheadline.weight(.semibold))
                }
                .padding(.horizontal, 16)
                .frame(height: 44)
                .glassEffect(.regular, in: .capsule)

                Spacer()

                Button { showDiscard = true } label: {
                    Image(systemName: "xmark").font(.headline).frame(width: 44, height: 44)
                }
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Discard walk")
            }
            .padding(.horizontal)
        }
    }

    private var statusText: String {
        switch recorder.state {
        case .idle: "Ready"
        case .paused: "Paused"
        case .recording: recorder.signalIsWeak ? "Finding GPS…" : "Recording"
        }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .recording: recorder.signalIsWeak ? Theme.amber : Theme.rose
        case .paused: Theme.amber
        case .idle: .secondary
        }
    }

    // MARK: Panel

    private var panel: some View {
        let parts = Fmt.distanceParts(recorder.distance, metric: metric)
        return VStack(spacing: 18) {
            if app.locationDenied {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                } label: {
                    Label("Location is off — tap to enable in Settings", systemImage: "location.slash.fill")
                        .font(.footnote.weight(.semibold))
                }
                .tint(Theme.rose)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.value)
                    .font(.system(size: 68, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: recorder.distance))
                    .animation(.snappy, value: recorder.distance)
                Text(parts.unit)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                let elapsed = recorder.elapsed(at: ctx.date)
                HStack {
                    metricCell("Time", Fmt.duration(elapsed))
                    Divider().frame(height: 30)
                    metricCell("Pace \(Fmt.paceUnit(metric: metric))", Fmt.pace(distance: recorder.distance, duration: elapsed, metric: metric))
                    Divider().frame(height: 30)
                    metricCell("Climb", Fmt.elevation(recorder.elevationGain, metric: metric))
                }
            }

            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    Button { showDropPin = true } label: {
                        Image(systemName: "mappin.and.ellipse").font(.title3.weight(.semibold)).frame(width: 36, height: 44)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Pin a place")

                    Button {
                        recorder.state == .paused ? recorder.resume() : recorder.pause()
                    } label: {
                        Label(recorder.state == .paused ? "Resume" : "Pause",
                              systemImage: recorder.state == .paused ? "play.fill" : "pause.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glass)

                    Button(action: finish) {
                        Label("Finish", systemImage: "flag.checkered")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.coral)
                }
            }
        }
        .padding(20)
        .glassEffect(.regular, in: .rect(cornerRadius: 34))
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func metricCell(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .fontDesign(.rounded)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func finish() {
        guard recorder.distance >= 30, recorder.points.count >= 2 else {
            showTooShort = true
            return
        }
        draft = recorder.finish()
    }
}

/// Mini player shown above the tab bar while a walk is running.
struct LiveWalkAccessory: View {
    @Environment(AppModel.self) private var app
    @AppStorage(Fmt.metricKey) private var metric = Fmt.defaultMetric

    var body: some View {
        let recorder = app.recorder
        HStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(recorder.state == .paused ? Theme.amber : Theme.coral, in: .circle)
                .symbolEffect(.pulse, isActive: recorder.state == .recording)

            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                HStack(spacing: 8) {
                    Text(Fmt.distance(recorder.distance, metric: metric))
                        .font(.subheadline.weight(.bold))
                    Text(Fmt.duration(recorder.elapsed(at: ctx.date)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .fontDesign(.rounded)
                .monospacedDigit()
            }

            Spacer(minLength: 0)

            Button {
                recorder.state == .paused ? recorder.resume() : recorder.pause()
            } label: {
                Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                    .font(.headline)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(recorder.state == .paused ? "Resume" : "Pause")
        }
        .padding(.horizontal, 14)
        .contentShape(.rect)
        .onTapGesture { app.showRecorder = true }
    }
}
