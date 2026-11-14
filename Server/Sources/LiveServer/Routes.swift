import Foundation
import KGLiveAPI
import LiveCore
import Vapor

func routes(_ app: Application) throws {
    let v1 = app.grouped("v1")

    v1.get("health") { request async throws -> Response in
        let live = request.application.live
        let now = Date()
        let snapshot = await live.snapshot.snapshot
        let age = await live.snapshot.age(at: now)
        let health = HealthDTO(status: "ok", version: live.config.version, feedVersion: live.timetable.feedVersion,
                               upstream: snapshot.upstream, snapshotAgeSeconds: age)
        let response = try Response.json(health)
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }

    // Every phone asks this one URL, so the edge answers almost all of them. Never touches the store or upstream.
    v1.get("live", "snapshot") { request async -> Response in
        let body = await request.application.live.snapshot.current
        return Response.encoded(body, for: request,
                                cacheControl: "public, max-age=5, s-maxage=10, stale-while-revalidate=20, stale-if-error=300")
    }

    v1.get("stops", ":gid", "departures") { request async throws -> Response in
        let gid = request.parameters.get("gid") ?? ""
        let limit = (try? request.query.get(Int.self, at: "limit")) ?? 10
        guard let result = await request.application.live.stops.departures(gid: gid, limit: limit) else {
            throw Abort(.notFound, reason: "Unknown stop")
        }
        let body = try EncodedBody(result, at: Date())
        return Response.encoded(body, for: request, cacheControl: "public, s-maxage=20, stale-if-error=120")
    }

    // For the operator only: refused through Cloudflare (which always adds CF-Ray), and behind a token when set.
    app.get("metrics") { request async throws -> Response in
        let live = request.application.live
        if request.headers.first(name: "CF-Ray") != nil || request.headers.first(name: "CF-Connecting-IP") != nil {
            throw Abort(.notFound)
        }
        if let token = live.config.metricsToken, request.headers.bearerAuthorization?.token != token {
            throw Abort(.unauthorized)
        }
        let now = Date()
        await live.metrics.set("live_snapshot_age_seconds", Double(await live.snapshot.age(at: now)))
        if let success = await live.snapshot.lastSuccess {
            await live.metrics.set("live_upstream_success_age_seconds", now.timeIntervalSince(success))
        }
        let response = Response(status: .ok, body: .init(string: await live.metrics.render()))
        response.headers.contentType = HTTPMediaType(type: "text", subType: "plain", parameters: ["version": "0.0.4"])
        response.headers.replaceOrAdd(name: .cacheControl, value: "no-store")
        return response
    }
}

extension Response {
    static func json<T: Encodable>(_ value: T) throws -> Response {
        let response = Response(status: .ok, body: .init(data: try JSONEncoder().encode(value)))
        response.headers.contentType = .json
        return response
    }

    /// A prebuilt body with its ETag: 304 when the client has it, gzip when the client takes it.
    static func encoded(_ body: EncodedBody, for request: Request, cacheControl: String) -> Response {
        var headers = HTTPHeaders()
        headers.replaceOrAdd(name: .eTag, value: body.etag)
        headers.replaceOrAdd(name: .cacheControl, value: cacheControl)
        headers.replaceOrAdd(name: .vary, value: "Accept-Encoding")
        let sent = request.headers[.ifNoneMatch].flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "W/", with: "") }
        if sent.contains(body.etag) || sent.contains("*") {
            return Response(status: .notModified, headers: headers)
        }
        headers.contentType = .json
        let acceptsGzip = request.headers[.acceptEncoding].contains { $0.lowercased().contains("gzip") }
        if acceptsGzip, !body.gzipped.isEmpty {
            headers.replaceOrAdd(name: .contentEncoding, value: "gzip")
            return Response(status: .ok, headers: headers, body: .init(data: body.gzipped))
        }
        return Response(status: .ok, headers: headers, body: .init(data: body.json))
    }
}
