import Foundation

/// The walking network of Konstanz from `konstanz-walk.bin` (format in DataPipeline/FORMATS.md):
/// junctions, and the streets and paths between them with their shapes, names and kinds.
/// Immutable after loading; shared by every walking route.
public final class WalkGraph: Sendable {
    let names: [String]
    let vertexLat: [Double]
    let vertexLon: [Double]
    let edgeA: [Int]
    let edgeB: [Int]
    /// -1 = unnamed.
    let edgeName: [Int]
    let edgeKind: [WayKind]
    let edgeFlags: [UInt8]
    /// Metres.
    let edgeLength: [Double]
    /// Points between the edge's two vertices: shapeLat/Lon[shapeStart[e] ..< shapeStart[e + 1]].
    let shapeStart: [Int]
    let shapeLat: [Double]
    let shapeLon: [Double]
    /// Edges at each vertex (compressed rows): adjacentEdges[adjacencyStart[v] ..< adjacencyStart[v + 1]].
    let adjacencyStart: [Int]
    let adjacentEdges: [Int]
    /// Edges crossing each grid cell of `cellSize` degrees, for finding the nearest street.
    let cells: [Int64: [Int]]

    static let bridgeFlag: UInt8 = 1
    static let cellSize = 0.001

    public var vertexCount: Int { vertexLat.count }
    public var edgeCount: Int { edgeA.count }
    public var nameCount: Int { names.count }

    public enum ReadError: Error { case notAWalkGraph, truncated }

    public static func read(from url: URL) throws -> WalkGraph {
        try WalkGraph(data: Data(contentsOf: url, options: .mappedIfSafe))
    }

    init(data: Data) throws {
        var reader = BigEndianReader(bytes: [UInt8](data))
        guard try reader.bytes(4) == Array("KWG1".utf8) else { throw ReadError.notAWalkGraph }

        var names: [String] = []
        for _ in 0..<(try reader.int32()) {
            let length = Int(try reader.uint16())
            names.append(String(bytes: try reader.bytes(length), encoding: .utf8) ?? "")
        }
        let vertices = Int(try reader.int32())
        var lat = [Double](repeating: 0, count: vertices), lon = lat
        for index in 0..<vertices {
            lat[index] = Double(try reader.int32()) / 1e7
            lon[index] = Double(try reader.int32()) / 1e7
        }
        let edges = Int(try reader.int32())
        var edgeA = [Int](repeating: 0, count: edges), edgeB = edgeA, edgeName = edgeA
        var kinds = [WayKind](repeating: .street, count: edges), flags = [UInt8](repeating: 0, count: edges)
        var lengths = [Double](repeating: 0, count: edges)
        var shapeStart = [Int](repeating: 0, count: edges + 1)
        var shapeLat: [Double] = [], shapeLon: [Double] = []
        shapeLat.reserveCapacity(edges * 2)
        shapeLon.reserveCapacity(edges * 2)
        for edge in 0..<edges {
            edgeA[edge] = Int(try reader.int32())
            edgeB[edge] = Int(try reader.int32())
            edgeName[edge] = Int(try reader.int32())
            kinds[edge] = WayKind(rawValue: try reader.uint8()) ?? .footpath
            flags[edge] = try reader.uint8()
            lengths[edge] = Double(try reader.int32()) / 100
            for _ in 0..<Int(try reader.uint16()) {
                shapeLat.append(Double(try reader.int32()) / 1e7)
                shapeLon.append(Double(try reader.int32()) / 1e7)
            }
            shapeStart[edge + 1] = shapeLat.count
        }

        self.names = names
        vertexLat = lat
        vertexLon = lon
        self.edgeA = edgeA
        self.edgeB = edgeB
        self.edgeName = edgeName
        edgeKind = kinds
        edgeFlags = flags
        edgeLength = lengths
        self.shapeStart = shapeStart
        self.shapeLat = shapeLat
        self.shapeLon = shapeLon
        (adjacencyStart, adjacentEdges) = Self.adjacency(vertices: vertices, edgeA: edgeA, edgeB: edgeB)
        cells = Self.grid(edges: edges) { edge in
            Self.points(edge, edgeA, edgeB, lat, lon, shapeStart, shapeLat, shapeLon)
        }
    }

    /// The edge's shape from vertex A to vertex B, both ends included.
    func points(_ edge: Int) -> [Coordinate] {
        Self.points(edge, edgeA, edgeB, vertexLat, vertexLon, shapeStart, shapeLat, shapeLon)
    }

    func name(of edge: Int) -> String? {
        edgeName[edge] >= 0 && edgeName[edge] < names.count ? names[edgeName[edge]] : nil
    }

    func isBridge(_ edge: Int) -> Bool { edgeFlags[edge] & Self.bridgeFlag != 0 }

    func vertex(_ index: Int) -> Coordinate { Coordinate(latitude: vertexLat[index], longitude: vertexLon[index]) }

    static func cell(_ lat: Double, _ lon: Double) -> (y: Int, x: Int) {
        (Int((lat / cellSize).rounded(.down)), Int((lon / cellSize).rounded(.down)))
    }

    static func key(_ y: Int, _ x: Int) -> Int64 {
        Int64(y) << 32 | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: x)))
    }

    // MARK: Building

    // swiftlint:disable:next function_parameter_count
    private static func points(_ edge: Int, _ edgeA: [Int], _ edgeB: [Int], _ lat: [Double], _ lon: [Double],
                               _ start: [Int], _ shapeLat: [Double], _ shapeLon: [Double]) -> [Coordinate] {
        var result = [Coordinate(latitude: lat[edgeA[edge]], longitude: lon[edgeA[edge]])]
        for index in start[edge]..<start[edge + 1] {
            result.append(Coordinate(latitude: shapeLat[index], longitude: shapeLon[index]))
        }
        result.append(Coordinate(latitude: lat[edgeB[edge]], longitude: lon[edgeB[edge]]))
        return result
    }

    private static func adjacency(vertices: Int, edgeA: [Int], edgeB: [Int]) -> ([Int], [Int]) {
        var start = [Int](repeating: 0, count: vertices + 1)
        for edge in edgeA.indices {
            start[edgeA[edge] + 1] += 1
            start[edgeB[edge] + 1] += 1
        }
        for index in 1...vertices { start[index] += start[index - 1] }
        var fill = start
        var edges = [Int](repeating: 0, count: start[vertices])
        for edge in edgeA.indices {
            edges[fill[edgeA[edge]]] = edge
            fill[edgeA[edge]] += 1
            edges[fill[edgeB[edge]]] = edge
            fill[edgeB[edge]] += 1
        }
        return (start, edges)
    }

    private static func grid(edges: Int, points: (Int) -> [Coordinate]) -> [Int64: [Int]] {
        var cells: [Int64: [Int]] = [:]
        for edge in 0..<edges {
            let shape = points(edge)
            for (from, to) in zip(shape, shape.dropFirst()) {
                let low = cell(min(from.latitude, to.latitude), min(from.longitude, to.longitude))
                let high = cell(max(from.latitude, to.latitude), max(from.longitude, to.longitude))
                for y in low.y...high.y {
                    for x in low.x...high.x where cells[key(y, x)]?.last != edge {
                        cells[key(y, x), default: []].append(edge)
                    }
                }
            }
        }
        return cells
    }
}

/// Reads big-endian numbers from a byte array.
struct BigEndianReader {
    let bytes: [UInt8]
    var offset = 0

    mutating func bytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw WalkGraph.ReadError.truncated }
        defer { offset += count }
        return Array(bytes[offset..<offset + count])
    }

    mutating func uint8() throws -> UInt8 {
        guard offset < bytes.count else { throw WalkGraph.ReadError.truncated }
        defer { offset += 1 }
        return bytes[offset]
    }

    mutating func uint16() throws -> UInt16 {
        UInt16(try uint8()) << 8 | UInt16(try uint8())
    }

    mutating func int32() throws -> Int32 {
        guard offset + 4 <= bytes.count else { throw WalkGraph.ReadError.truncated }
        defer { offset += 4 }
        let value = UInt32(bytes[offset]) << 24 | UInt32(bytes[offset + 1]) << 16
            | UInt32(bytes[offset + 2]) << 8 | UInt32(bytes[offset + 3])
        return Int32(bitPattern: value)
    }
}
