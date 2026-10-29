#if canImport(MapLibre) && canImport(UIKit)
import KGCore
import KGDesign
import MapLibre
import SwiftUI

/// The offline map (MapLibre) with the bundled tiles and the design's style (plan M1–M4, M9). Follows light
/// and dark mode without losing the camera, keeps to Konstanz, draws the stops as a map layer and reports
/// taps on them. Overlay views (user dot, selected stop) are placed by SwiftUI at points this view reports.
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
        map.setCenter(MapRegion.center.location, zoomLevel: MapRegion.startZoom, animated: false)
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
        coordinator.updateLines(on: map)
        if let move = model.takePendingMove() {
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
        coordinator.reportOverlayPoints(map)
    }

    @MainActor
    public final class Coordinator: NSObject, @preconcurrency MLNMapViewDelegate {
        let model: MapModel
        var dark = false
        private var shownStations: [Int] = []
        private var shownLines: [MapLine] = []
        private var styleReady = false

        static let stopsSource = "kg-stops"
        static let stopsLayer = "kg-stops"
        static let stopNamesLayer = "kg-stop-names"
        static let routeSource = "kg-route"

        // MARK: Route lines (plan M7)

        func updateLines(on map: MLNMapView) {
            guard styleReady, let style = map.style else { return }
            guard model.lines != shownLines || style.source(withIdentifier: Self.routeSource) == nil else { return }
            shownLines = model.lines
            let features = model.lines.map { line -> MLNPolylineFeature in
                var points = line.points.map(\.location)
                let feature = MLNPolylineFeature(coordinates: &points, count: UInt(points.count))
                feature.attributes = ["kind": line.kind.rawValue]
                return feature
            }
            let shape = MLNShapeCollectionFeature(shapes: features)
            if let source = style.source(withIdentifier: Self.routeSource) as? MLNShapeSource {
                source.shape = shape
                return
            }
            let source = MLNShapeSource(identifier: Self.routeSource, shape: shape, options: nil)
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
                if let stops = style.layer(withIdentifier: Self.stopsLayer) {
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

            let rings = MLNCircleStyleLayer(identifier: Self.stopsLayer, source: source)
            rings.minimumZoomLevel = 14
            rings.circleColor = NSExpression(forConstantValue: UIColor.white)
            rings.circleRadius = NSExpression(forConstantValue: 4.5)
            rings.circleStrokeColor = NSExpression(forConstantValue: UIColor(KGColor.coral))
            rings.circleStrokeWidth = NSExpression(forConstantValue: 3.5)
            style.addLayer(rings)

            let names = MLNSymbolStyleLayer(identifier: Self.stopNamesLayer, source: source)
            names.minimumZoomLevel = 16
            names.text = NSExpression(forKeyPath: "name")
            names.textFontNames = NSExpression(forConstantValue: ["Noto Sans Medium"])
            names.textFontSize = NSExpression(forConstantValue: 12)
            names.textAnchor = NSExpression(forConstantValue: "top")
            names.textOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: 0.9)))
            names.textOptional = NSExpression(forConstantValue: true)
            names.textColor = NSExpression(forConstantValue: UIColor(dark ? KGColor.white : KGColor.ink))
            names.textHaloColor = NSExpression(forConstantValue: UIColor(KGColor.mapLand))
            names.textHaloWidth = NSExpression(forConstantValue: 1.6)
            style.addLayer(names)
        }

        public func mapView(_ mapView: MLNMapView, didFinishLoading style: MLNStyle) {
            styleReady = true
            shownStations = []
            shownLines = []
            updateLines(on: mapView)
            updateStops(on: mapView)
        }

        // MARK: Camera

        /// Keeps the centre inside Konstanz while panning (plan M3).
        public func mapView(_ mapView: MLNMapView, shouldChangeFrom oldCamera: MLNMapCamera,
                            to newCamera: MLNMapCamera) -> Bool {
            MapRegion.contains(Coordinate(newCamera.centerCoordinate))
        }

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
            let user = model.userLocation.map { map.convert($0.location, toPointTo: map) }
            let selected = model.selectedStation.map { map.convert($0.coordinate.location, toPointTo: map) }
            var pins: [String: CGPoint] = [:]
            for pin in model.pins { pins[pin.id] = map.convert(pin.coordinate.location, toPointTo: map) }
            model.setOverlayPoints(user: user, selected: selected, pins: pins)
        }

        // MARK: Taps

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard let map = recognizer.view as? MLNMapView else { return }
            let point = recognizer.location(in: map)
            let area = CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)
            let hits = map.visibleFeatures(in: area, styleLayerIdentifiers: [Self.stopsLayer])
            let nearest = hits.min { lhs, rhs in
                distance(map.convert(lhs.coordinate, toPointTo: map), point)
                    < distance(map.convert(rhs.coordinate, toPointTo: map), point)
            }
            guard let id = (nearest?.attribute(forKey: "id") as? NSNumber)?.intValue,
                  let station = model.stations.first(where: { $0.id == id }) else { return }
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
