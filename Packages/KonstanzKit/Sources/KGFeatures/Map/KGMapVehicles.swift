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
    /// a bus, which is a bright capsule with its line number.
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

    /// Moves the buses by changing the layer's data: the map draws them itself, in step with every frame.
    func updateVehicles(on map: MLNMapView) {
        guard styleReady, let style = map.style, model.vehicles != shownVehicles else { return }
        shownVehicles = model.vehicles
        for vehicle in model.vehicles { addImages(for: vehicle, to: style) }
        let shape = MLNShapeCollectionFeature(shapes: model.vehicles.map { vehicle in
            let feature = MLNPointFeature()
            feature.coordinate = vehicle.coordinate.location
            feature.attributes = ["image": vehicle.imageName, "nose": vehicle.noseName, "heading": vehicle.heading]
            return feature
        })
        if let source = style.source(withIdentifier: Self.vehiclesSource) as? MLNShapeSource {
            source.shape = shape
            return
        }
        let source = MLNShapeSource(identifier: Self.vehiclesSource, shape: shape, options: nil)
        style.addSource(source)
        // The nose first, under the marker, pointing where the bus heads; its offset turns with it.
        for (name, distance) in [("kg-nose-red", 15.0), ("kg-nose-yellow", 15.0), ("kg-nose-trip", 22.0)] {
            let nose = MLNSymbolStyleLayer(identifier: "kg-vehicles-\(name)", source: source)
            nose.predicate = NSPredicate(format: "nose == %@", name)
            nose.iconImageName = NSExpression(forConstantValue: name)
            nose.iconRotation = NSExpression(forKeyPath: "heading")
            nose.iconOffset = NSExpression(forConstantValue: NSValue(cgVector: CGVector(dx: 0, dy: -distance)))
            nose.iconAllowsOverlap = NSExpression(forConstantValue: true)
            nose.iconIgnoresPlacement = NSExpression(forConstantValue: true)
            style.addLayer(nose)
        }
        let markers = MLNSymbolStyleLayer(identifier: Self.vehiclesSource, source: source)
        markers.iconImageName = NSExpression(forKeyPath: "image")
        markers.iconAllowsOverlap = NSExpression(forConstantValue: true)
        markers.iconIgnoresPlacement = NSExpression(forConstantValue: true)
        style.addLayer(markers)
    }

    private func addImages(for vehicle: MapVehicle, to style: MLNStyle) {
        if vehicleImages.insert(vehicle.imageName).inserted, let image = Self.markerImage(for: vehicle) {
            style.setImage(image, forName: vehicle.imageName)
        }
        if vehicleImages.insert(vehicle.noseName).inserted, let image = Self.noseImage(for: vehicle) {
            style.setImage(image, forName: vehicle.noseName)
        }
    }

    private static func image(of view: some View) -> UIImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// The design's own marker views, drawn once into an image.
    static func markerImage(for vehicle: MapVehicle) -> UIImage? {
        switch vehicle.look {
        case let .vehicle(isTrain, isYellow, isLive):
            // A soft glow in its own colour lifts a moving bus off the map and the quiet stops.
            image(of: KGVehicleMarker(line: vehicle.line, isTrain: isTrain, isKreuzlingen: isYellow, isLive: isLive)
                .shadow(color: (isYellow ? KGColor.kreuzlingen : KGColor.coral).opacity(0.75), radius: 5)
                .padding(10))
        case .trip:
            image(of: KGBusMarker(line: vehicle.line, animated: false).padding(6))
        }
    }

    static func noseImage(for vehicle: MapVehicle) -> UIImage? {
        switch vehicle.look {
        case let .vehicle(_, isYellow, _): image(of: KGVehicleNose(isYellow: isYellow))
        case .trip: image(of: KGBusMarkerNose())
        }
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
        addSubview(host.view)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }
}
#endif
