#if canImport(Glibc)
import Glibc
#else
import Darwin
#endif

/// `live healthcheck`: asks `GET /v1/health` on 127.0.0.1 and exits 0 on a 200. The runtime image has no shell or
/// curl, so Docker's HEALTHCHECK runs this. Plain sockets keep it independent of Vapor and quick to start.
enum Healthcheck {
    static func run(port: UInt16) -> Int32 {
        #if canImport(Glibc)
        let fd = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
        #else
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        #endif
        guard fd >= 0 else { return 1 }
        defer { close(fd) }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = UInt32(0x7F00_0001).bigEndian
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { return 1 }
        let request = Array("GET /v1/health HTTP/1.0\r\nHost: 127.0.0.1\r\n\r\n".utf8)
        guard send(fd, request, request.count, 0) == request.count else { return 1 }
        var buffer = [UInt8](repeating: 0, count: 64)
        let count = recv(fd, &buffer, buffer.count, 0)
        guard count > 0 else { return 1 }
        let statusLine = String(decoding: buffer[0..<count], as: UTF8.self).split(separator: "\r\n").first ?? ""
        return statusLine.split(separator: " ").dropFirst().first == "200" ? 0 : 1
    }
}
