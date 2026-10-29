import KGCore
import KGDesign
import SwiftUI

/// A small, still map at the top of a screen (09 Haltestelle, 15 Ort, 17): centred on a point with a marker,
/// and an optional route drawn on it. Taps go to the screen, not the map.
struct MapStrip: View {
    let services: AppServices
    let center: Coordinate
    var zoom: Double = 16.2
    var lines: [MapLine] = []
    /// What sits on the centre: the coral stop marker, a place pin, or nothing.
    var marker: Marker = .stop

    enum Marker { case stop, place, none }

    @State private var model = MapModel()

    var body: some View {
        ZStack {
            #if canImport(MapLibre) && canImport(UIKit)
            KGMapView(data: services.data, model: model)
            #else
            KGColor.mapLand
            #endif
            switch marker {
            case .stop: KGStopMarker("", isSelected: true, showsName: false)
            case .place:
                KGIconView(.pinFilled, size: 40).foregroundStyle(KGColor.coral)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 3)
                    .offset(y: -18)
            case .none: EmptyView()
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            model.stations = services.transit.stations
            model.lines = lines
            model.move(CameraMove(center: center, zoom: zoom, animated: false))
        }
    }
}
