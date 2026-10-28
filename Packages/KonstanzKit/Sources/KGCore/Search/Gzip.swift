import Compression
import Foundation

/// Unpacks a gzip file (RFC 1952), such as `places.tsvz`. Apple's Compression framework reads the raw
/// DEFLATE stream inside; this strips the gzip header and trailer around it.
enum Gzip {
    enum Failure: Error { case notGzip, corrupt }

    static func decompress(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count >= 18, bytes[0] == 0x1F, bytes[1] == 0x8B, bytes[2] == 8 else { throw Failure.notGzip }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {  // FEXTRA
            guard offset + 2 <= bytes.count else { throw Failure.corrupt }
            offset += 2 + (Int(bytes[offset]) | Int(bytes[offset + 1]) << 8)
        }
        if flags & 0x08 != 0 { offset = try skipZeroTerminated(bytes, from: offset) }  // FNAME
        if flags & 0x10 != 0 { offset = try skipZeroTerminated(bytes, from: offset) }  // FCOMMENT
        if flags & 0x02 != 0 { offset += 2 }  // FHCRC
        guard offset < bytes.count - 8 else { throw Failure.corrupt }

        // ISIZE: the unpacked size modulo 2^32, in the last four bytes.
        let tail = bytes.count - 4
        let size = Int(bytes[tail]) | Int(bytes[tail + 1]) << 8
            | Int(bytes[tail + 2]) << 16 | Int(bytes[tail + 3]) << 24
        let deflated = Array(bytes[offset..<(bytes.count - 8)])
        var output = [UInt8](repeating: 0, count: max(size, 1))
        let written = deflated.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { target in
                compression_decode_buffer(target.baseAddress!, target.count,  // swiftlint:disable:this force_unwrapping
                                          source.baseAddress!, source.count,  // swiftlint:disable:this force_unwrapping
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw Failure.corrupt }
        return Data(output.prefix(written))
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from start: Int) throws -> Int {
        guard let end = bytes[start...].firstIndex(of: 0) else { throw Failure.corrupt }
        return end + 1
    }
}
