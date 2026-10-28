import Foundation

/// Google's encoded polyline format, precision 1e-5 (the `shape.points` column).
public enum Polyline {
    public static func decode(_ text: String) -> [Coordinate] {
        var points: [Coordinate] = []
        var index = text.utf8.startIndex
        let bytes = text.utf8
        var lat = 0, lon = 0

        func next() -> Int? {
            var result = 0, shift = 0
            while index < bytes.endIndex {
                let byte = Int(bytes[index]) - 63
                index = bytes.index(after: index)
                result |= (byte & 0x1F) << shift
                shift += 5
                if byte < 0x20 { return (result & 1) != 0 ? ~(result >> 1) : result >> 1 }
            }
            return nil
        }

        while index < bytes.endIndex {
            guard let dLat = next(), let dLon = next() else { break }
            lat += dLat
            lon += dLon
            points.append(Coordinate(latitude: Double(lat) / 1e5, longitude: Double(lon) / 1e5))
        }
        return points
    }
}
