import Crypto
import CZlib
import Foundation
import KGLiveAPI

/// A response body encoded once and served many times: plain and gzipped bytes and a strong ETag.
public struct EncodedBody: Sendable {
    public let json: Data
    public let gzipped: Data
    /// Quoted, as it goes into the header: the first 16 hex characters of the SHA-256 of the JSON.
    public let etag: String
    public let createdAt: Date

    public init<T: Encodable>(_ value: T, at date: Date) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        json = try encoder.encode(value)
        gzipped = Gzip.compress(json)
        etag = "\"" + SHA256.hash(data: json).prefix(8).map { String(format: "%02x", $0) }.joined() + "\""
        createdAt = date
    }
}

/// Builds the snapshot from the store after each poll cycle and keeps the encoded bytes. Serving it is a memory
/// copy: no request ever touches the store or the source.
public actor SnapshotCache {
    public private(set) var current: EncodedBody
    public private(set) var snapshot: LiveSnapshot
    /// When fresh data last came in; nil before the first successful poll.
    public private(set) var lastSuccess: Date?

    public init(now: Date, upstream: UpstreamState) {
        let empty = LiveSnapshot(generatedAt: Int(now.timeIntervalSince1970), upstream: upstream, trips: [], cancelled: [])
        snapshot = empty
        // Encoding a value made of strings and numbers cannot fail.
        current = try! EncodedBody(empty, at: now)
    }

    /// Rebuilds from the store. `upstream` says how the last cycle went.
    public func rebuild(from store: LiveStore, upstream: UpstreamState, at now: Date) async {
        let fresh = upstream == .off ? [:] : await store.fresh(at: now)
        let trips = fresh.filter { !$0.value.isCancelled }
            .map { TripLiveDTO(k: $0.key, d: $0.value.delay, t: Int($0.value.observedAt.timeIntervalSince1970)) }
            .sorted { $0.k < $1.k }
        let cancelled = fresh.filter(\.value.isCancelled).map(\.key).sorted()
        let next = LiveSnapshot(generatedAt: Int(now.timeIntervalSince1970), upstream: upstream, trips: trips,
                                cancelled: cancelled)
        guard let body = try? EncodedBody(next, at: now) else { return }
        snapshot = next
        current = body
    }

    public func markSuccess(at date: Date) { lastSuccess = date }

    public func age(at now: Date) -> Int { Int(now.timeIntervalSince(current.createdAt).rounded()) }
}

/// gzip with zlib, so the same code runs on macOS and Linux.
public enum Gzip {
    public static func compress(_ data: Data) -> Data {
        var stream = z_stream()
        // 31 = 15 window bits + 16 for a gzip header.
        guard deflateInit2_(&stream, 9, Z_DEFLATED, 31, 8, Z_DEFAULT_STRATEGY, ZLIB_VERSION,
                            Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return Data() }
        defer { deflateEnd(&stream) }
        var output = Data(count: Int(deflateBound(&stream, UInt(data.count))) + 32)
        var input = data
        let written: Int = input.withUnsafeMutableBytes { inBytes in
            output.withUnsafeMutableBytes { outBytes in
                stream.next_in = inBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_in = uInt(inBytes.count)
                stream.next_out = outBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outBytes.count)
                guard deflate(&stream, Z_FINISH) == Z_STREAM_END else { return 0 }
                return Int(stream.total_out)
            }
        }
        output.count = written
        return output
    }

    public static func decompress(_ data: Data) -> Data? {
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }
        var input = data
        var result = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        let ok: Bool = input.withUnsafeMutableBytes { inBytes in
            stream.next_in = inBytes.bindMemory(to: Bytef.self).baseAddress
            stream.avail_in = uInt(inBytes.count)
            while true {
                let status: Int32 = chunk.withUnsafeMutableBytes { outBytes in
                    stream.next_out = outBytes.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(outBytes.count)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                result.append(contentsOf: chunk[0..<(chunk.count - Int(stream.avail_out))])
                if status == Z_STREAM_END { return true }
                if status != Z_OK { return false }
            }
        }
        return ok ? result : nil
    }
}
