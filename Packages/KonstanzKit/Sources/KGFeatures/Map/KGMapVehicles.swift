#if canImport(MapLibre) && canImport(UIKit)
import KGCore
import KGDesign
import MapLibre
import SwiftUI

extension KGMapView.Coordinator {
    /// A closed stop on the map: a white X on deep red, the size of the stop tile.
    static func closedTileImage() -> UIImage? {
        let tile = KGIconView(.close, size: 15)
            .foregroundStyle(KGColor.white)
            .frame(width: 28, height: 28)
            .background(KGColor.coralDeep, in: .kgRounded(8))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(KGColor.white, lineWidth: 2))
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .padding(4)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        return renderer.uiImage
    }

    /// A stop on the map: the German "H" sign in a small white disc. Quiet and round, so it can't be taken for
    /// a bus or train, which are bright 3D vehicles with their line number.
    static func stopTileImage() -> UIImage? {
        let tile = KGStopSign().padding(4).environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: tile)
        renderer.scale = 3
        return renderer.uiImage
    }
    /// Closed stops: an X on top of the stop, at every zoom, tappable through to the stop below.
    func updateClosedStops(on map: MLNMapView) {
        guard styleReady, let style = map.style else { return }
        let ids = model.closedStations.map(\.id)
        guard ids != shownClosed else { return }
        shownClosed = ids
        let shape = MLNShapeCollectionFeature(shapes: model.closedStations.map { station in
            let feature = MLNPointFeature()
            feature.coordinate = station.coordinate.location
            return feature
        })
        if let source = style.source(withIdentifier: Self.closedSource) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: Self.closedSource, shape: shape, options: nil)
        style.addSource(source)
        if let tile = Self.closedTileImage() { style.setImage(tile, forName: Self.closedTileName) }
        let layer = MLNSymbolStyleLayer(identifier: Self.closedSource, source: source)
        layer.iconImageName = NSExpression(forConstantValue: Self.closedTileName)
        layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
        layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        layer.iconScale = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                       stops: NSExpression(forConstantValue: [12: 0.6, 15: 1.0]))
        style.addLayer(layer)
    }

    // MARK: Buses and trains

    /// Moves the vehicles by changing the layer's data: the map draws them itself, in step with every frame. Only the
    /// ones in and near the view, so a busy timetable costs the map little.
    func updateVehicles(on map: MLNMapView) {
        guard styleReady, let style = map.style, model.vehicles != shownVehicles else { return }
        shownVehicles = model.vehicles
        let bounds = map.visibleCoordinateBounds
        let middle = CLLocationCoordinate2D(latitude: (bounds.ne.latitude + bounds.sw.latitude) / 2,
                                            longitude: (bounds.ne.longitude + bounds.sw.longitude) / 2)
        let reachLat = (bounds.ne.latitude - bounds.sw.latitude) * 0.75, reachLon = (bounds.ne.longitude - bounds.sw.longitude) * 0.75
        let blinks = !UIAccessibility.isReduceMotionEnabled
        let shown = model.vehicles.filter {
            abs($0.coordinate.latitude - middle.latitude) <= reachLat && abs($0.coordinate.longitude - middle.longitude) <= reachLon
        }
        for vehicle in shown { addImages(for: vehicle, to: style) }
        let shape = MLNShapeCollectionFeature(shapes: shown.map { vehicle in
            let feature = MLNPointFeature()
            feature.coordinate = vehicle.coordinate.location
            feature.attributes = ["image": vehicle.spriteName, "label": vehicle.labelName,
                                  "blink": blinks ? vehicle.blinkName : ""]
            return feature
        })
        if let source = style.source(withIdentifier: Self.vehiclesSource) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: Self.vehiclesSource, shape: shape, options: nil)
        style.addSource(source)
        // Small when zoomed out, so a crowded map stays readable; the offset of the number scales with it.
        let scale = NSExpression(forMLNInterpolating: .zoomLevelVariable, curveType: .linear, parameters: nil,
                                 stops: NSExpression(forConstantValue: [11: 0.75, 13: 1.1, 15: 1.35, 17: 1.7, 19: 2.1]))
        func layer(_ name: String, image: String) -> MLNSymbolStyleLayer {
            let layer = MLNSymbolStyleLayer(identifier: name, source: source)
            layer.iconImageName = NSExpression(forKeyPath: image)
            layer.iconScale = scale
            layer.iconAllowsOverlap = NSExpression(forConstantValue: true)
            layer.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            return layer
        }
        style.addLayer(layer(Self.vehiclesSource, image: "image"))
        let blink = layer("kg-vehicles-blink", image: "blink")
        blink.predicate = NSPredicate(format: "blink != ''")
        style.addLayer(blink)
        let label = layer("kg-vehicles-label", image: "label")
        // The buses always show; numbers that would overlap give way, so a crowded map stays readable.
        label.iconAllowsOverlap = NSExpression(forConstantValue: false)
        label.iconIgnoresPlacement = NSExpression(forConstantValue: false)
        label.minimumZoomLevel = 12
        label.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -18)))
        style.addLayer(label)
    }

    private func addImages(for vehicle: MapVehicle, to style: MLNStyle) {
        for name in [vehicle.spriteName, vehicle.blinkName] where !name.isEmpty && vehicleImages.insert(name).inserted {
            if let image = KGVehicleSprite.image(named: name) { style.setImage(image, forName: name) }
        }
        if vehicleImages.insert(vehicle.labelName).inserted, let image = Self.labelImage(for: vehicle) {
            style.setImage(image, forName: vehicle.labelName)
        }
    }

    /// The number over a vehicle, drawn once into an image.
    static func labelImage(for vehicle: MapVehicle) -> UIImage? {
        let label: KGVehicleLabel
        switch vehicle.look {
        case let .vehicle(isTrain, isYellow, isLive):
            label = KGVehicleLabel(line: vehicle.line, isTrain: isTrain, isYellow: isYellow, isLive: isLive)
        case let .trip(isTrain):
            label = KGVehicleLabel(line: vehicle.line, isTrain: isTrain, large: true)
        }
        let renderer = ImageRenderer(content: label.padding(4).environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }

    // MARK: The user

    /// The user's dot as an annotation: the map moves it in the same frame as itself.
    func updateUserDot(on map: MLNMapView) {
        guard let point = model.userLocation else {
            if showsUserAnnotation {
                map.removeAnnotation(userAnnotation)
                showsUserAnnotation = false
            }
            return
        }
        if userAnnotation.coordinate.latitude != point.latitude || userAnnotation.coordinate.longitude != point.longitude {
            userAnnotation.coordinate = point.location
        }
        if !showsUserAnnotation {
            map.addAnnotation(userAnnotation)
            showsUserAnnotation = true
        }
        userDot?.heading = model.userHeading
    }

    public func mapView(_ mapView: MLNMapView, viewFor annotation: MLNAnnotation) -> MLNAnnotationView? {
        guard annotation === userAnnotation else { return nil }
        let view = userDot ?? UserDotView(annotation: annotation, reuseIdentifier: nil)
        view.heading = model.userHeading
        userDot = view
        return view
    }
}

/// The user's dot on the map: the design's view, hosted once, moved by the map.
final class UserDotView: MLNAnnotationView {
    private let host = UIHostingController(rootView: KGUserDot())

    var heading: Double? {
        didSet {
            if heading != oldValue { host.rootView = KGUserDot(heading: heading.map { .degrees($0) }) }
        }
    }

    override init(annotation: MLNAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        isUserInteractionEnabled = false
        host.view.backgroundColor = .clear
        host.view.frame = bounds
        host.view.accessibilityElementsHidden = true
        addSubview(host.view)
        // The map lists this view itself, so it needs the name; the hosted label stays hidden.
        isAccessibilityElement = true
        accessibilityLabel = String(localized: "Mein Standort", bundle: .module)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif
