import SwiftUI
import MapKit

/// One-shot camera instructions sent to `FootprintMap`.
struct MapCommand: Equatable {
    enum Kind {
        case zoomIn, zoomOut, user
        case region(MKCoordinateRegion)
        case fit([CLLocationCoordinate2D])
    }
    let id = UUID()
    let kind: Kind
    static func == (a: MapCommand, b: MapCommand) -> Bool { a.id == b.id }
}

/// A simple marker that isn't a saved place (search result, route start/finish, preview dot).
struct MapPin: Equatable {
    enum Kind { case dot, marker }
    let id: String
    let coordinate: CLLocationCoordinate2D
    var title: String = ""
    var color: UIColor
    var symbol: String
    var kind: Kind = .dot
}

/// A real, zoomable map built on MKMapView. Supports Apple map styles plus an
/// OpenStreetMap street style (raster tiles) that also works where Apple tiles don't load.
struct FootprintMap: UIViewRepresentable {
    var places: [Place] = []
    var walks: [Walk] = []
    var route: [CLLocationCoordinate2D] = []
    var pins: [MapPin] = []
    var style: MapStyleChoice = .standard
    var clusters = true
    var interactive = true
    var showsUser = true
    var followUser = false
    var initialRegion: MKCoordinateRegion?
    var compassTop: CGFloat = 16
    var selectedWalkID: UUID?
    @Binding var command: MapCommand?

    var onSelectPlace: ((UUID) -> Void)?
    var onSelectWalk: ((UUID) -> Void)?
    var onSelectPin: ((String) -> Void)?
    var onRegionChange: ((MKCoordinateRegion) -> Void)?
    var onRegionWillChange: (() -> Void)?
    var onLongPress: ((CLLocationCoordinate2D) -> Void)?
    var onTilesFailed: (() -> Void)?

    @Environment(\.colorScheme) private var scheme

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = showsUser
        map.showsCompass = false
        map.showsScale = false
        map.pointOfInterestFilter = .excludingAll
        map.isScrollEnabled = interactive
        map.isZoomEnabled = interactive
        map.isRotateEnabled = interactive
        map.isPitchEnabled = interactive
        map.register(PlaceDotView.self, forAnnotationViewWithReuseIdentifier: PlaceDotView.reuse)
        map.register(ClusterBubbleView.self, forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        map.register(MKMarkerAnnotationView.self, forAnnotationViewWithReuseIdentifier: "marker")

        if let initialRegion {
            map.setRegion(map.regionThatFits(initialRegion), animated: false)
        }
        if followUser {
            map.setUserTrackingMode(.follow, animated: false)
        }

        if interactive {
            let compass = MKCompassButton(mapView: map)
            compass.compassVisibility = .adaptive
            compass.translatesAutoresizingMaskIntoConstraints = false
            map.addSubview(compass)
            NSLayoutConstraint.activate([
                compass.trailingAnchor.constraint(equalTo: map.safeAreaLayoutGuide.trailingAnchor, constant: -20),
                compass.topAnchor.constraint(equalTo: map.safeAreaLayoutGuide.topAnchor, constant: compassTop)
            ])

            let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
            tap.delegate = context.coordinator
            map.addGestureRecognizer(tap)
            if onLongPress != nil {
                let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
                press.minimumPressDuration = 0.45
                map.addGestureRecognizer(press)
            }
        }
        context.coordinator.sync(map, dark: scheme == .dark)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.sync(map, dark: scheme == .dark)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: FootprintMap

        private var placeAnnotations: [UUID: PlaceAnnotation] = [:]
        private var placeSignatures: [UUID: String] = [:]
        private var walkOverlays: [UUID: RoutePolyline] = [:]
        private var selectedWalk: UUID?
        private var routeOverlay: RoutePolyline?
        private var routeCount = -1
        private var pinAnnotations: [String: PinAnnotation] = [:]
        private var appliedStyle: MapStyleChoice?
        private var appliedDark: Bool?
        private var tileOverlay: MKTileOverlay?
        private var lastCommand: UUID?
        private var reportedFailure = false
        private var fullyRendered = false

        init(parent: FootprintMap) { self.parent = parent }

        func sync(_ map: MKMapView, dark: Bool) {
            applyStyle(map, dark: dark)
            syncPlaces(map)
            syncWalks(map)
            syncRoute(map)
            syncPins(map)
            if let cmd = parent.command, cmd.id != lastCommand {
                lastCommand = cmd.id
                run(cmd, on: map)
            }
        }

        // MARK: Style

        private func applyStyle(_ map: MKMapView, dark: Bool) {
            let style = parent.style
            guard style != appliedStyle else { return }
            appliedStyle = style
            appliedDark = dark

            switch style {
            case .standard:
                map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
            case .muted, .street, .worldImagery:
                map.preferredConfiguration = MKStandardMapConfiguration(emphasisStyle: .muted)
            case .satellite:
                map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .realistic)
            case .hybrid:
                map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .realistic)
            }
            if let old = tileOverlay {
                map.removeOverlay(old)
                tileOverlay = nil
            }
            if style.tileTemplate == nil {
                fullyRendered = false
                // Watchdog: Apple's map sometimes never finishes loading (no service on the network).
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                    guard let self, !self.fullyRendered, self.appliedStyle == style else { return }
                    self.reportTileFailure()
                }
            }
            if let template = style.tileTemplate {
                let tiles = WebTileOverlay(urlTemplate: template)
                tiles.canReplaceMapContent = true
                tiles.maximumZ = 19
                map.insertOverlay(tiles, at: 0, level: .aboveLabels)
                tileOverlay = tiles
                map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 350)
            } else {
                map.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 60)
            }
        }

        // MARK: Places

        private func syncPlaces(_ map: MKMapView) {
            var wanted = Set<UUID>()
            var toAdd: [PlaceAnnotation] = []
            var toRemove: [PlaceAnnotation] = []
            for place in parent.places {
                wanted.insert(place.id)
                let sig = "\(place.latitude),\(place.longitude)|\(place.photoColorHex ?? "")|\(place.categoryRaw)|\(place.photoData?.count ?? 0)|\(place.name)|\(parent.clusters)"
                if placeSignatures[place.id] == sig { continue }
                if let old = placeAnnotations[place.id] { toRemove.append(old) }
                let ann = PlaceAnnotation(
                    id: place.id,
                    coordinate: place.coordinate,
                    title: place.displayName,
                    color: UIColor(place.tint),
                    symbol: place.category.symbol,
                    image: ThumbnailCache.shared.image(id: place.id, data: place.photoData, side: 40),
                    clusters: parent.clusters
                )
                placeAnnotations[place.id] = ann
                placeSignatures[place.id] = sig
                toAdd.append(ann)
            }
            for (id, ann) in placeAnnotations where !wanted.contains(id) {
                toRemove.append(ann)
                placeAnnotations[id] = nil
                placeSignatures[id] = nil
            }
            if !toRemove.isEmpty { map.removeAnnotations(toRemove) }
            if !toAdd.isEmpty { map.addAnnotations(toAdd) }
        }

        // MARK: Walks

        private func syncWalks(_ map: MKMapView) {
            let wanted = Set(parent.walks.map(\.id))
            let selectionChanged = selectedWalk != parent.selectedWalkID
            for (id, overlay) in walkOverlays where !wanted.contains(id) || (selectionChanged && (id == selectedWalk || id == parent.selectedWalkID)) {
                map.removeOverlay(overlay)
                walkOverlays[id] = nil
            }
            selectedWalk = parent.selectedWalkID
            for walk in parent.walks where walkOverlays[walk.id] == nil {
                var coords = RouteCache.shared.displayCoordinates(for: walk)
                guard coords.count > 1 else { continue }
                let line = RoutePolyline(coordinates: &coords, count: coords.count)
                line.walkID = walk.id
                line.isSelected = walk.id == parent.selectedWalkID
                walkOverlays[walk.id] = line
                map.addOverlay(line, level: .aboveLabels)
            }
        }

        private func syncRoute(_ map: MKMapView) {
            guard parent.route.count != routeCount else { return }
            routeCount = parent.route.count
            if let old = routeOverlay { map.removeOverlay(old) }
            routeOverlay = nil
            guard parent.route.count > 1 else { return }
            var coords = parent.route
            let line = RoutePolyline(coordinates: &coords, count: coords.count)
            line.isSelected = true
            routeOverlay = line
            map.addOverlay(line, level: .aboveLabels)
        }

        // MARK: Pins

        private func syncPins(_ map: MKMapView) {
            let wanted = Dictionary(uniqueKeysWithValues: parent.pins.map { ($0.id, $0) })
            for (id, ann) in pinAnnotations {
                if let w = wanted[id], w == ann.pin { continue }
                map.removeAnnotation(ann)
                pinAnnotations[id] = nil
            }
            for pin in parent.pins where pinAnnotations[pin.id] == nil {
                let ann = PinAnnotation(pin: pin)
                pinAnnotations[pin.id] = ann
                map.addAnnotation(ann)
            }
        }

        // MARK: Commands

        private func run(_ cmd: MapCommand, on map: MKMapView) {
            switch cmd.kind {
            case .zoomIn: zoom(map, factor: 0.45)
            case .zoomOut: zoom(map, factor: 2.2)
            case .user:
                if let c = map.userLocation.location?.coordinate {
                    map.setRegion(MKCoordinateRegion(center: c, latitudinalMeters: 1200, longitudinalMeters: 1200), animated: true)
                } else {
                    map.setUserTrackingMode(.follow, animated: true)
                }
            case .region(let r):
                map.setRegion(map.regionThatFits(r), animated: true)
            case .fit(let coords):
                guard !coords.isEmpty else { return }
                var rect = MKMapRect.null
                for c in coords {
                    let p = MKMapPoint(c)
                    rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 1, height: 1))
                }
                let minSide = 6000.0
                if rect.width < minSide || rect.height < minSide {
                    rect = rect.insetBy(dx: -(minSide - min(rect.width, minSide)) / 2, dy: -(minSide - min(rect.height, minSide)) / 2)
                }
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: 160, left: 40, bottom: 200, right: 70), animated: true)
            }
        }

        private func zoom(_ map: MKMapView, factor: Double) {
            guard let camera = map.camera.copy() as? MKMapCamera else { return }
            camera.centerCoordinateDistance = min(max(camera.centerCoordinateDistance * factor, 150), 40_000_000)
            map.setCamera(camera, animated: true)
        }

        // MARK: Delegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tiles)
            }
            if let line = overlay as? RoutePolyline {
                return RouteRenderer(line: line, lineWidth: line.isSelected ? 7 : 5,
                                     colors: [UIColor(Theme.teal), UIColor(Theme.ocean), UIColor(Theme.violet)])
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case is MKUserLocation:
                return nil
            case let cluster as MKClusterAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier, for: cluster)
                (v as? ClusterBubbleView)?.configure(cluster)
                return v
            case let place as PlaceAnnotation:
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PlaceDotView.reuse, for: place) as! PlaceDotView
                v.configure(color: place.color, symbol: place.symbol, image: place.image, size: place.image == nil ? 28 : 40)
                v.clusteringIdentifier = place.clusters ? "place" : nil
                return v
            case let pin as PinAnnotation:
                if pin.pin.kind == .marker {
                    let v = mapView.dequeueReusableAnnotationView(withIdentifier: "marker", for: pin) as! MKMarkerAnnotationView
                    v.markerTintColor = pin.pin.color
                    v.glyphImage = UIImage(systemName: pin.pin.symbol)
                    v.titleVisibility = .visible
                    v.displayPriority = .required
                    v.clusteringIdentifier = nil
                    v.animatesWhenAdded = true
                    return v
                }
                let v = mapView.dequeueReusableAnnotationView(withIdentifier: PlaceDotView.reuse, for: pin) as! PlaceDotView
                v.configure(color: pin.pin.color, symbol: pin.pin.symbol, image: nil, size: 28)
                v.clusteringIdentifier = nil
                v.displayPriority = .required
                return v
            default:
                return nil
            }
        }

        func mapView(_ mapView: MKMapView, didSelect annotation: MKAnnotation) {
            switch annotation {
            case let cluster as MKClusterAnnotation:
                mapView.showAnnotations(cluster.memberAnnotations, animated: true)
                mapView.deselectAnnotation(cluster, animated: false)
            case let place as PlaceAnnotation:
                mapView.deselectAnnotation(place, animated: false)
                parent.onSelectPlace?(place.id)
            case let pin as PinAnnotation:
                parent.onSelectPin?(pin.pin.id)
            default:
                break
            }
        }

        func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
            let cb = parent.onRegionWillChange
            Task { @MainActor in cb?() }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let cb = parent.onRegionChange
            Task { @MainActor in cb?(region) }
        }

        func mapViewDidFailLoadingMap(_ mapView: MKMapView, withError error: Error) {
            reportTileFailure()
        }

        /// Apple's tiles can fail silently (e.g. no Apple Maps service on the network); an
        /// incomplete first render is the reliable signal.
        func mapViewDidFinishRenderingMap(_ mapView: MKMapView, fullyRendered: Bool) {
            if fullyRendered { self.fullyRendered = true } else { reportTileFailure() }
        }

        private func reportTileFailure() {
            guard !reportedFailure, parent.style.tileTemplate == nil, parent.onTilesFailed != nil else { return }
            reportedFailure = true
            let cb = parent.onTilesFailed
            Task { @MainActor in cb?() }
        }

        // MARK: Gestures

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView, let onSelectWalk = parent.onSelectWalk else { return }
            let point = g.location(in: map)
            if let hit = map.hitTest(point, with: nil), hit is MKAnnotationView || hit.superview is MKAnnotationView { return }
            var best: (UUID, CGFloat)?
            for (id, line) in walkOverlays {
                let d = distance(from: point, to: line, in: map)
                if d < 22, d < (best?.1 ?? .infinity) { best = (id, d) }
            }
            if let best { onSelectWalk(best.0) }
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let c = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress?(c)
        }

        private func distance(from p: CGPoint, to line: MKPolyline, in map: MKMapView) -> CGFloat {
            let pts = line.points()
            guard line.pointCount > 1 else { return .infinity }
            // Skip lines far from the tap.
            let tapPoint = MKMapPoint(map.convert(p, toCoordinateFrom: map))
            let slack = map.visibleMapRect.width * 0.08
            guard line.boundingMapRect.insetBy(dx: -slack, dy: -slack).contains(tapPoint) else { return .infinity }
            var best = CGFloat.infinity
            var prev = map.convert(pts[0].coordinate, toPointTo: map)
            for i in 1..<line.pointCount {
                let cur = map.convert(pts[i].coordinate, toPointTo: map)
                let dx = cur.x - prev.x, dy = cur.y - prev.y
                let len2 = dx * dx + dy * dy
                let t = len2 == 0 ? 0 : max(0, min(1, ((p.x - prev.x) * dx + (p.y - prev.y) * dy) / len2))
                let proj = CGPoint(x: prev.x + t * dx, y: prev.y + t * dy)
                best = min(best, hypot(p.x - proj.x, p.y - proj.y))
                prev = cur
            }
            return best
        }
    }
}

// MARK: - Overlays & annotations

/// Draws a route with Core Graphics: a white casing plus a start→finish gradient.
/// (CPU-drawn, so it renders wherever raster tiles do.)
nonisolated final class RouteRenderer: MKOverlayRenderer {
    private let points: [MKMapPoint]
    private let lineWidth: CGFloat
    private let colors: [CGColor]

    init(line: MKPolyline, lineWidth: CGFloat, colors: [UIColor]) {
        let buffer = line.points()
        self.points = (0..<line.pointCount).map { buffer[$0] }
        self.lineWidth = lineWidth
        self.colors = colors.map(\.cgColor)
        super.init(overlay: line)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard points.count > 1 else { return }
        let width = lineWidth / zoomScale
        let path = CGMutablePath()
        path.move(to: point(for: points[0]))
        for p in points.dropFirst() { path.addLine(to: point(for: p)) }

        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.addPath(path)
        context.setLineWidth(width * 1.7)
        context.setStrokeColor(UIColor.white.withAlphaComponent(0.92).cgColor)
        context.strokePath()

        context.saveGState()
        context.addPath(path)
        context.setLineWidth(width)
        context.replacePathWithStrokedPath()
        context.clip()
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 0.5, 1]) {
            var start = point(for: points[0])
            var end = point(for: points[points.count - 1])
            if hypot(end.x - start.x, end.y - start.y) < width * 4 {
                // Loops: run the gradient across the bounding box instead.
                let box = path.boundingBox
                start = CGPoint(x: box.minX, y: box.minY)
                end = CGPoint(x: box.maxX, y: box.maxY)
            }
            context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
        context.restoreGState()
    }
}

/// Web map tiles fetched with an identifying User-Agent (required by the OSM tile policy) and a disk cache.
nonisolated final class WebTileOverlay: MKTileOverlay {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        let bundle = Bundle.main.bundleIdentifier ?? "footprints"
        config.httpAdditionalHeaders = ["User-Agent": "Footprints/1.0 (iOS; \(bundle))"]
        config.urlCache = URLCache(memoryCapacity: 32 << 20, diskCapacity: 256 << 20)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Self.session.dataTask(with: url(forTilePath: path)) { data, response, error in
            let ok = (response as? HTTPURLResponse).map { (200..<300).contains($0.statusCode) } ?? false
            result(ok ? data : nil, error)
        }.resume()
    }
}

nonisolated final class RoutePolyline: MKPolyline {
    var walkID: UUID?
    var isSelected = false
}

final class PlaceAnnotation: NSObject, MKAnnotation {
    let id: UUID
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let color: UIColor
    let symbol: String
    let image: UIImage?
    let clusters: Bool

    init(id: UUID, coordinate: CLLocationCoordinate2D, title: String, color: UIColor, symbol: String, image: UIImage?, clusters: Bool) {
        self.id = id
        self.coordinate = coordinate
        self.title = title
        self.color = color
        self.symbol = symbol
        self.image = image
        self.clusters = clusters
    }
}

final class PinAnnotation: NSObject, MKAnnotation {
    let pin: MapPin
    var coordinate: CLLocationCoordinate2D { pin.coordinate }
    var title: String? { pin.title.isEmpty ? nil : pin.title }
    init(pin: MapPin) { self.pin = pin }
}

final class PlaceDotView: MKAnnotationView {
    static let reuse = "placeDot"
    private let dot = UIView()
    private let photo = UIImageView()
    private let glyph = UIImageView()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(dot)
        dot.addSubview(photo)
        dot.addSubview(glyph)
        dot.layer.borderColor = UIColor.white.cgColor
        dot.layer.borderWidth = 2.5
        photo.contentMode = .scaleAspectFill
        photo.clipsToBounds = true
        glyph.contentMode = .center
        glyph.tintColor = .white
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 4
        layer.shadowOffset = CGSize(width: 0, height: 2)
        collisionMode = .circle
        displayPriority = .defaultHigh
        canShowCallout = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(color: UIColor, symbol: String, image: UIImage?, size: CGFloat) {
        frame = CGRect(x: 0, y: 0, width: size, height: size)
        dot.frame = bounds
        dot.layer.cornerRadius = size / 2
        dot.backgroundColor = color
        photo.frame = bounds.insetBy(dx: 2.5, dy: 2.5)
        photo.layer.cornerRadius = photo.bounds.width / 2
        photo.image = image
        photo.isHidden = image == nil
        glyph.frame = bounds
        glyph.image = UIImage(systemName: symbol, withConfiguration: UIImage.SymbolConfiguration(pointSize: size * 0.4, weight: .bold))
        glyph.isHidden = image != nil
    }

    override func prepareForDisplay() {
        super.prepareForDisplay()
        transform = .identity
    }
}

final class ClusterBubbleView: MKAnnotationView {
    private let halo = UIView()
    private let bubble = UIView()
    private let label = UILabel()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        addSubview(halo)
        addSubview(bubble)
        bubble.addSubview(label)
        bubble.layer.borderColor = UIColor.white.cgColor
        bubble.layer.borderWidth = 3
        label.textAlignment = .center
        label.textColor = .white
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 5
        layer.shadowOffset = CGSize(width: 0, height: 2)
        collisionMode = .circle
        displayPriority = .defaultHigh
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ cluster: MKClusterAnnotation) {
        let count = cluster.memberAnnotations.count
        let size = min(64, 34 + log2(Double(count)) * 5)
        let color = (cluster.memberAnnotations.first as? PlaceAnnotation)?.color ?? UIColor(Theme.coral)
        frame = CGRect(x: 0, y: 0, width: size + 12, height: size + 12)
        halo.frame = bounds
        halo.layer.cornerRadius = bounds.width / 2
        halo.backgroundColor = color.withAlphaComponent(0.25)
        bubble.frame = bounds.insetBy(dx: 6, dy: 6)
        bubble.layer.cornerRadius = bubble.bounds.width / 2
        bubble.backgroundColor = color
        label.frame = bubble.bounds
        label.font = .systemFont(ofSize: size * 0.36, weight: .bold).rounded
        label.text = count > 999 ? "\(count / 1000)k" : "\(count)"
    }
}

private extension UIFont {
    var rounded: UIFont {
        guard let d = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: d, size: pointSize)
    }
}
