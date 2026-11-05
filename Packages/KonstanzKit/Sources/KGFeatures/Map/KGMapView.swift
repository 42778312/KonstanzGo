#if canImport(MapLibre) && canImport(UIKit)
import KGCore
import KGDesign
import MapLibre
import SwiftUI

/// The offline map (MapLibre) with the bundled tiles and the design's style (plan M1–M4, M9). Follows light
/// and dark mode without losing the camera, keeps to Konstanz, draws stops and buses as map layers and reports
/// taps on stops. The user dot rides on the map too. Only the selected stop and dropped pins are placed by
/// SwiftUI, at points this view reports while they exist, so a plain pan costs SwiftUI nothing.
public struct KGMapView: UIViewRepresentable {
    let data: BundledData
    let model: MapModel
    @Environment(\.colorScheme) private var colorScheme

    public init(data: BundledData, model: MapModel) {
        self.data = data
        self.model = model
    }

    public func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    public func makeUIView(context: Context) -> MLNMapView {
        #if DEBUG
        MLNLoggingConfiguration.shared.loggingLevel = .info
        #endif
        let dark = colorScheme == .dark
        let map = MLNMapView(frame: .zero, styleURL: try? MapStyleFile.url(data: data, dark: dark))
        context.coordinator.dark = dark
        map.delegate = context.coordinator
        map.minimumZoomLevel = MapRegion.minZoom
        map.maximumZoomLevel = MapRegion.maxZoom
        // The view slides along the edge of the map instead of a move being refused, which froze it there.
        map.maximumScreenBounds = MLNCoordinateBounds(
            sw: CLLocationCoordinate2D(latitude: MapRegion.mapSouth, longitude: MapRegion.mapWest),
            ne: CLLocationCoordinate2D(latitude: MapRegion.mapNorth, longitude: MapRegion.mapEast))
        map.setCenter(MapRegion.center.location, zoomLevel: MapRegion.startZoom, animated: false)
        map.preferredFramesPerSecond = .maximum
        map.logoView.isHidden = true
        map.compassView.compassVisibility = .hidden
        map.allowsTilting = false
        map.allowsRotating = false
        // The licence notice is drawn by the screen above the sheet ("© OpenStreetMap"), and in Mehr › Über.
        map.attributionButton.isHidden = true
        map.accessibilityLabel = String(localized: "Karte von Konstanz", bundle: .module)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        for recognizer in map.gestureRecognizers ?? [] {
            if let other = recognizer as? UITapGestureRecognizer, other.numberOfTapsRequired == 2 {
                tap.require(toFail: other)
            }
        }
        map.addGestureRecognizer(tap)
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.pressed(_:)))
        map.addGestureRecognizer(press)
        return map
    }

    public func updateUIView(_ map: MLNMapView, context: Context) {
        let coordinator = context.coordinator
        let dark = colorScheme == .dark
        if dark != coordinator.dark {
            // A new style keeps the camera; the stops layer is added again when it has loaded.
            coordinator.dark = dark
            map.styleURL = try? MapStyleFile.url(data: data, dark: dark)
        }
        let insets = UIEdgeInsets(top: model.insets.top, left: 0, bottom: model.insets.bottom, right: 0)
        if map.contentInset != insets {
            map.setContentInset(insets, animated: true, completionHandler: nil)
        }
        coordinator.updateStops(on: map)
        coordinator.updateClosedStops(on: map)
        coordinator.updateVehicles(on: map)
        coordinator.updateUserDot(on: map)
        coordinator.updateLines(on: map)
        if let step = model.takePendingZoom() {
            map.setZoomLevel(min(max(map.zoomLevel + step, MapRegion.minZoom), MapRegion.maxZoom), animated: true)
        }
        if let move = model.takePendingMove() { coordinator.queuedMove = move }
        coordinator.runQueuedMove(on: map)
        coordinator.reportOverlayPoints(map)
    }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        let model: MapModel
        var dark = false
        private var shownStations: [Int] = []
        var shownClosed: [Int]?
        var shownVehicles: [MapVehicle]?
        var vehicleImages: Set<String> = []
        let userAnnotation = MLNPointAnnotation()
        var userDot: UserDotView?
        var showsUserAnnotation = false
        private var shownLines: [MapLine] = []
        var styleReady = false
        /// A camera move waiting for the map to have a size and its style; fitting a route before that lands
        /// on the wrong place and zoom.
        var queuedMove: CameraMove?
        private var drawing: Task<Void, Never>?

        func runQueuedMove(on map: MLNMapView) {
            guard styleReady, map.bounds.width > 0, map.bounds.height > 0, let move = queuedMove else { return }
            queuedMove = nil
            if move.fit.count > 1 {
                let bounds = MLNCoordinateBounds(
                    sw: CLLocationCoordinate2D(latitude: move.fit.map(\.latitude).min() ?? 0,
                                               longitude: move.fit.map(\.longitude).min() ?? 0),
                    ne: CLLocationCoordinate2D(latitude: move.fit.map(\.latitude).max() ?? 0,
                                               longitude: move.fit.map(\.longitude).max() ?? 0))
                let padding = UIEdgeInsets(top: 48, left: 40, bottom: 48, right: 40)
                map.setVisibleCoordinateBounds(bounds, edgePadding: padding, animated: move.animated,
                                               completionHandler: nil)
            } else {
                map.setCenter(move.center.location, zoomLevel: move.zoom, animated: move.animated)
            }
        }

        static let stopsSource = "kg-stops"
        static let stopsLayer = "kg-stops"
        static let stopNamesLayer = "kg-stop-names"
        static let stopRingsLayer = "kg-stop-rings"
        static let stopTileName = "kg-stop-tile"
        static let closedSource = "kg-closed-stops"
        static let vehiclesSource = "kg-vehicles"
        static let closedTileName = "kg-closed-tile"

        static let routeSource = "kg-route"

        // MARK: Route lines (plan M7)

        func updateLines(on map: MLNMapView) {
            guard styleReady, let style = map.style else { return }
            guard model.lines != shownLines || style.source(withIdentifier: Self.routeSource) == nil else { return }
            shownLines = model.lines
            if style.source(withIdentifier: Self.routeSource) == nil { addRouteLayers(to: style) }
            draw(shownLines, on: map)
        }

        /// Draws the route in from its start, walk and bus in order, over 1.4 s (at once with Reduce Motion).
        private func draw(_ lines: [MapLine], on map: MLNMapView) {
            drawing?.cancel()
            guard !lines.isEmpty, !UIAccessibility.isReduceMotionEnabled else {
                show(lines, upTo: 1, on: map)
                return
            }
            show(lines, upTo: 0, on: map)
            drawing = Task { [weak self, weak map] in
                try? await Task.sleep(for: .milliseconds(250))
                let start = ContinuousClock.now
                while !Task.isCancelled {
                    guard let self, let map else { return }
                    let t = (ContinuousClock.now - start) / .seconds(1)
                    let eased = 1 - pow(1 - min(1, t / 1.4), 3)
                    self.show(lines, upTo: eased, on: map)
                    if t >= 1.4 { return }
                    try? await Task.sleep(for: .milliseconds(16))
                }
            }
        }

        private func show(_ lines: [MapLine], upTo progress: Double, on map: MLNMapView) {
            guard let source = map.style?.source(withIdentifier: Self.routeSource) as? MLNShapeSource else { return }
            source.shape = MLNShapeCollectionFeature(shapes: Self.features(lines, upTo: progress))
        }

        /// The route's first `progress` (0…1) of its length, as map features.
        static func features(_ lines: [MapLine], upTo progress: Double) -> [MLNPolylineFeature] {
            let lengths = lines.map { line in
                zip(line.points, line.points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
            }
            var budget = lengths.reduce(0, +) * progress
            var features: [MLNPolylineFeature] = []
            for (line, length) in zip(lines, lengths) where budget > 0 {
                let points = budget >= length ? line.points : prefix(of: line.points, metres: budget)
                budget -= length
                guard points.count > 1 else { continue }
                var locations = points.map(\.location)
                let feature = MLNPolylineFeature(coordinates: &locations, count: UInt(locations.count))
                feature.attributes = ["kind": line.kind.rawValue]
                features.append(feature)
            }
            return features
        }

        private static func prefix(of points: [Coordinate], metres: Double) -> [Coordinate] {
            var left = metres
            var result = [points[0]]
            for (a, b) in zip(points, points.dropFirst()) {
                let step = a.distance(to: b)
                if step >= left {
                    let f = step > 0 ? left / step : 0
                    result.append(Coordinate(latitude: a.latitude + (b.latitude - a.latitude) * f,
                                             longitude: a.longitude + (b.longitude - a.longitude) * f))
                    return result
                }
                result.append(b)
                left -= step
            }
            return result
        }

        private func addRouteLayers(to style: MLNStyle) {
            let source = MLNShapeSource(identifier: Self.routeSource, shape: nil, options: nil)
            style.addSource(source)
            let isBus = NSPredicate(format: "kind == 'bus'")
            let isWalk = NSPredicate(format: "kind == 'walk'")

            let casing = MLNLineStyleLayer(identifier: "kg-route-casing", source: source)
            casing.predicate = isBus
            casing.lineColor = NSExpression(forConstantValue: UIColor.white)
            casing.lineWidth = NSExpression(forConstantValue: 9)
            casing.lineCap = NSExpression(forConstantValue: "round")
            casing.lineJoin = NSExpression(forConstantValue: "round")
            let bus = MLNLineStyleLayer(identifier: "kg-route-bus", source: source)
            bus.predicate = isBus
            bus.lineColor = NSExpression(forConstantValue: UIColor(KGColor.coral))
            bus.lineWidth = NSExpression(forConstantValue: 5.5)
            bus.lineCap = NSExpression(forConstantValue: "round")
            bus.lineJoin = NSExpression(forConstantValue: "round")
            let walk = MLNLineStyleLayer(identifier: "kg-route-walk", source: source)
            walk.predicate = isWalk
            walk.lineColor = NSExpression(forConstantValue: UIColor(KGColor.location))
            walk.lineWidth = NSExpression(forConstantValue: 4)
            walk.lineCap = NSExpression(forConstantValue: "round")
            walk.lineDashPattern = NSExpression(forConstantValue: [0.1, 2])
            for layer in [casing, bus, walk] {
                if let stops = style.layer(withIdentifier: Self.stopRingsLayer) {
                    style.insertLayer(layer, below: stops)
                } else {
                    style.addLayer(layer)
                }
            }
        }

        init(model: MapModel) {
            self.model = model
        }

        // MARK: Stops layer (plan M4): rings from zoom 14, names from 16.

        func updateStops(on map: MLNMapView) {
            guard styleReady, let style = map.style else { return }
            let ids = model.stations.map(\.id)
            guard ids != shownStations || style.source(withIdentifier: Self.stopsSource) == nil else { return }
            shownStations = ids
            let features = model.stations.map { station -> MLNPointFeature in
                let feature = MLNPointFeature()
                feature.coordinate = station.coordinate.location
                feature.attributes = ["id": station.id, "name": station.shortName]
                return feature
            }
            let shape = MLNShapeCollectionFeature(shapes: features)
            if let source = style.source(withIdentifier: Self.stopsSource) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: Self.stopsSource, shape: shape, options: nil)
            style.addSource(source)

            // Far out: small coral rings; from zoom 14.5: the bus tile (white bus on coral, white edge).
            let rings = MLNCircleStyleLayer(identifier: Self.stopRingsLayer, source: source)
            rings.minimumZoomLevel = 12.5
            rings.maximumZoomLevel = 14.5
            rings.circleColor = NSExpression(forConstantValue: UIColor.white)
            rings.circleRadius = NSExpression(forConstantValue: 3)
            rings.circleStrokeColor = NSExpression(forConstantValue: UIColor(KGColor.coral))
            rings.circleStrokeWidth = NSExpression(forConstantValue: 2.5)
            style.addLayer(rings)

            if let tile = Self.stopTileImage() { style.setImage(tile, forName: Self.stopTileName) }
            let tiles = MLNSymbolStyleLayer(identifier: Self.stopsLayer, source: source)
            tiles.minimumZoomLevel = 14.5
            tiles.iconImageName = NSExpression(forConstantValue: Self.stopTileName)
            tiles.iconAllowsOverlap = NSExpression(forConstantValue: true)
            tiles.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(tiles)

            let names = MLNSymbolStyleLayer(identifier: Self.stopNamesLayer, source: source)
            names.minimumZoomLevel = Float(MapRegion.destinationZoom)
            names.text = NSExpression(forKeyPath: "name")
            names.textFontNames = NSExpression(forConstantValue: ["Noto Sans Medium"])
            names.textFontSize = NSExpression(forConstantValue: 12)
            names.textAnchor = NSExpression(forConstantValue: "top")
            names.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 1.5)))
            names.textOptional = NSExpression(forConstantValue: true)
            names.textColor = NSExpression(forConstantValue: UIColor(dark ? KGColor.white : KGColor.ink))
            names.textHaloColor = NSExpression(forConstantValue: UIColor(KGColor.mapLand))
            names.textHaloWidth = NSExpression(forConstantValue: 1.6)
            style.addLayer(names)
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            shownStations = []
            shownClosed = nil
            shownVehicles = nil
            vehicleImages = []
            // Labels appear at once rather than fading in behind the movement.
            style.performsPlacementTransitions = false
            shownLines = []
            updateLines(on: mapView)
            updateStops(on: mapView)
            updateClosedStops(on: mapView)
            updateVehicles(on: mapView)
            runQueuedMove(on: mapView)
        }

        // MARK: Camera

        public func mapViewRegionIsChanging(_ mapView: MLNMapView) {
            reportOverlayPoints(mapView)
        }

        public func mapView(_ mapView: MLNMapView, regionDidChangeAnimated animated: Bool) {
            reportOverlayPoints(mapView)
            let inset = mapView.contentInset
            let middle = CGPoint(x: mapView.bounds.midX,
                                 y: inset.top + (mapView.bounds.height - inset.top - inset.bottom) / 2)
            let center = Coordinate(mapView.convert(middle, toCoordinateFrom: mapView))
            if model.centerCoordinate != center { model.centerCoordinate = center }
        }

        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let map = recognizer.view as? MLNMapView else { return }
            let point = Coordinate(map.convert(recognizer.location(in: map), toCoordinateFrom: map))
            if MapRegion.contains(point) { model.onLongPress?(point) }
        }

        func reportOverlayPoints(_ map: MLNMapView) {
            // Nothing placed by SwiftUI: nothing to do on this frame.
            guard model.selectedStationID != nil || !model.pins.isEmpty || model.selectedPoint != nil
                || !model.pinPoints.isEmpty else { return }
            let selected = model.selectedStation.map { map.convert($0.coordinate.location, toPointTo: map) }
            var pins: [String: CGPoint] = [:]
            for pin in model.pins { pins[pin.id] = map.convert(pin.coordinate.location, toPointTo: map) }
            model.setOverlayPoints(selected: selected, pins: pins)
        }

        // MARK: Taps

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let map = recognizer.view as? MLNMapView else { return }
            let point = recognizer.location(in: map)
            let area = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let hits = map.visibleFeatures(in: area, styleLayerIdentifiers: [Self.stopsLayer, Self.stopRingsLayer])
            let nearest = hits.min { lhs, rhs in
                distance(map.convert(lhs.coordinate, toPointTo: map), point)
                    < distance(map.convert(rhs.coordinate, toPointTo: map), point)
            }
            guard let id = (nearest?.attribute(forKey: "id") as? NSNumber)?.intValue,
                  let station = model.stations.first(where: { $0.id == id }) else {
                model.onTapMap?()
                return
            }
            model.onSelectStation?(station)
        }

        private func distance(_ lhs: CGPoint, _ rhs: CGPoint) -> CGFloat { hypot(lhs.x - rhs.x, lhs.y - rhs.y) }
    }
}

extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(_ location: CLLocationCoordinate2D) {
        self.init(latitude: location.latitude, longitude: location.longitude)
    }
}
#endif
