# KonstanzGo Live — server build plan

**What:** a small Swift server that gives the app real-time bus delays for Stadtbus Konstanz, without ever letting phones talk to EFA-BW directly.
**Design doc:** https://claude.ai/artifact/7xPktqUVsauwJg7JAX39VG (KonstanzGo Live — Backend Design). This plan is the build order for it. If the two disagree, this plan wins and the design doc gets updated.
**Diagram:** https://claude.ai/artifact/DzUC9myZLCGT2rMLpghfdP
**Same repo as the app.** The server lives in `Server/`. It shares two small modules with the app, so a change to the API breaks the build on both sides instead of breaking users.

---

## For Claude Code: how to work through this plan

1. Read this whole file, then `PLAN.md` (the app's plan and ground rules), then `Packages/KonstanzKit/Package.swift`.
2. Work **one step at a time, in order**. Each step ends with its "Done when" checks passing.
3. After each step: run the tests, make **one commit** with a clear message, tick the step in this file (`- [x]`), then **stop and report** what you did and what you checked. Wait for "go" before the next step.
4. Steps marked **(you)** need a human: an account, an email, a password, a purchase. Do not attempt them; list them in your report when they block you.
5. If something in this plan turns out wrong (an API field has another name, a library does not build on Linux), stop, explain what you found, and propose the change. Do not quietly work around it.
6. Never call EFA-BW from tests or CI. Tests use recorded fixtures only. The only live EFA-BW calls during development are the ones a step explicitly asks for, rate-limited by hand to at most 1 per second.

---

## Ground rules (they apply to every step)

1. **Phones never reach EFA-BW.** Only the poller inside the server calls it. No HTTP handler may call `RealtimeSource` directly, except through the rate limiter (step S8).
2. **Hard upstream cap: 1 request per second, burst 2.** Enforced in code by one shared `RateLimiter`. Normal load is about 0.5 per second.
3. **One instance only.** Two instances would double the traffic to EFA-BW. No horizontal scaling, no Redis, no database.
4. **`LiveCore` never imports Vapor.** All logic is plain Swift, tested with `swift test` in seconds. `LiveServer` is a thin Vapor shell.
5. **Swift 6, strict concurrency, no warnings.** Same settings as the app. Shared state lives in actors.
6. **Never key anything on EFA-BW's numeric stop IDs.** Only the `gid` (`de:08335:6554`) and the timetable's DHIDs. Asking for `8711882` returned departures with `stopID` `8706554`.
7. **Honest data** (the app's rule 7): a delay older than 3 minutes is dropped; unknown is shown as "Laut Fahrplan", never guessed.
8. **No personal data.** No user IDs, device IDs or locations in any request. The server logs no IP addresses.
9. **Config from environment variables only.** No secrets in git. `.env.example` lists every variable with a safe default.
10. **Everything runs in Docker.** `docker compose up` must be the only command needed on any Linux server.

---

## Decisions (already made)

| Decision | Choice |
|---|---|
| Framework | Vapor 4, pinned to an exact 4.x version. Swift 6.2 toolchain. |
| Data source now | EFA-BW departure monitor: `https://www.efa-bw.de/nvbw/XML_DM_REQUEST?outputFormat=JSON&type_dm=stop&mode=direct&useRealtime=1&depType=stopEvents&name_dm=<gid>&limit=<n>` |
| Data source later | TRIAS or GTFS-RT from NVBW, behind the same `RealtimeSource` protocol |
| Storage | In memory. `timetable.db` is loaded once at boot (142 stations, 263 platforms, 3,380 trips, 33,991 stop times). |
| Trip key | `<service date yyyyMMdd>\|<line>\|<first station gid>\|<planned first departure, minutes after service-day start>` |
| Matching | Station gid + line number + planned departure minute (+ headsign to break ties) |
| Edge | Cloudflare (free plan) with a Cache Rule on `/v1/*`, rate limiting and Cloudflare Tunnel |
| Packaging | One Docker image, multi-stage build, run with Docker Compose |
| Host | Any small Linux VM (for example Hetzner, Germany, 2 vCPU / 4 GB) |

---

## Part S0 — Before any code

- [ ] **S0.1 (you)** Email `mobidata-bw@nvbw.de`: describe KonstanzGo, the server, and the exact budget (one server, one IP, at most 1 request per second, about 30 per minute). Ask (a) whether this use of EFA-BW is fine until official access, (b) for TRIAS or GTFS-RT access, (c) what attribution they want in the app.
- [ ] **S0.2 (you)** Install Docker on the Mac: Docker Desktop or OrbStack. Check: `docker run --rm swift:6.2 swift --version` prints Swift 6.2.
- [ ] **S0.3 (you)** Refresh the timetable. `timetable.db` ends on **12.12.2026**, so `check.py` already fails (it needs 30 days left). Run the GTFS import with the new NVBW feed before step S3, or every build will fail.
- [ ] **S0.4** Record fixtures. Write `Server/scripts/record_fixtures.py` that calls the departure monitor for 6 stops (Konstanz Bahnhof, Sternenplatz, Zähringerplatz, Universität, Schulthaißstraße, Petershausen Bahnhof), **one request every 2 s**, and saves each raw JSON response to `Server/Tests/LiveCoreTests/Fixtures/dm_<stop>_<yyyyMMdd-HHmm>.json`. Run it 3 times: a weekday morning rush, an evening, and a late night.
  Done when: at least 18 fixture files are in git, and `Fixtures/README.md` lists, from the real responses, the exact JSON paths of: planned time, real time, delay, line number, destination, platform, stop gid, realtime status, and any cancellation field (or "not seen").

## Part S1 — Shared code

- [ ] **S1.1** Create the module `KGTimetable` in `Packages/KonstanzKit` and move into it, unchanged: `KGCore/Models/*`, `KGCore/Time/ServiceTime.swift`, `KGCore/Timetable/*`. `KGCore` depends on `KGTimetable` and re-exports it (`@_exported import KGTimetable`) so the app code needs no edits.
  Done when: `xcodegen && xcodebuild` builds the app, and every existing test passes with no test file changed except imports.
- [ ] **S1.2** Add the platform's GTFS stop ID (the DHID, `platform.gtfs_id` in `timetable.db`) to the `Platform` model and load it in `TimetableStore`. Add `Platform.stationGID` (the DHID without its last `:segment`, for example `de:08335:6553`).
  Done when: a test checks that Konstanz Bahnhof's platforms all share one `stationGID`.
- [ ] **S1.3** Add `TripKey` to `KGTimetable`: builds the key above from a trip and its service day. Uses `ServiceTime` for times past midnight and the clock change.
  Done when: tests cover a normal trip, a trip starting after 24:00, and both clock-change Sundays.
- [ ] **S1.4** Create the module `KGLiveAPI`: `Codable` DTOs only, `import Foundation` only. `LiveSnapshot { v, generatedAt, upstream, trips: [TripLiveDTO], cancelled: [String] }`, `TripLiveDTO { k, d, t }`, `UpstreamState { ok, degraded, off }`, `StopDeparturesDTO`. The JSON shape is in the design doc, section "API contract".
  Done when: a round-trip test encodes and decodes a sample, and decoding ignores unknown fields.
- [ ] **S1.5** Make `KGTimetable` and `KGLiveAPI` build on Linux. Add a GitHub Actions job `linux-shared` that runs `swift build --target KGTimetable --target KGLiveAPI` inside `swift:6.2`. If GRDB 7 does not build on Linux, stop and report (fallback: the server reads SQLite through SQLiteNIO, with a small loader of its own).
  Done when: the job is green.

## Part S2 — Server skeleton and Docker

- [ ] **S2.1** Create `Server/Package.swift` (Vapor 4, `swift-log`, `swift-metrics`, a Prometheus exporter) with targets `LiveCore`, `LiveServer`, `Run` and test target `LiveCoreTests`. It depends on `../Packages/KonstanzKit` for `KGTimetable` and `KGLiveAPI` only (never `KGCore`, `KGDesign` or `KGFeatures`).
- [ ] **S2.2** `GET /v1/health` returns `{ status, version, feedVersion, upstream, snapshotAgeSeconds }`. Config loaded from the environment: `PORT`, `LOG_LEVEL`, `TIMETABLE_PATH`, `EFA_STOPS_PATH`, `LIVE_UPSTREAM_ENABLED`, `UPSTREAM_MAX_RPS`, `POLL_INTERVAL_SECONDS`, `CONTACT_EMAIL`, `PUBLIC_URL`.
- [ ] **S2.3** `Server/Dockerfile`, multi-stage:
  - build stage: `swift:6.2-noble`, `swift build -c release --static-swift-stdlib`
  - run stage: `ubuntu:noble` slim with only `ca-certificates` and `tzdata`, non-root user `live`, `TZ=Europe/Berlin`
  - copies the binary plus `timetable.db` and `efa_stops.json` into `/app/data` (read-only)
  - `HEALTHCHECK` on `/v1/health`, `STOPSIGNAL SIGTERM`
  The Docker build context is the repo root, because the server needs `Packages/` and the data files. Add a `.dockerignore` that leaves out `App/`, `Design/`, `Widgets/`, build folders and map tiles.
- [ ] **S2.4** `Server/deploy/docker-compose.yml`: service `live` (image, `restart: unless-stopped`, `read_only: true`, `tmpfs: /tmp`, memory limit 512 MB, env file, port bound to `127.0.0.1` only) and service `cloudflared` (official image, token from env, under a `tunnel` profile so local dev runs without it). Plus `Server/deploy/.env.example`.
- [ ] **S2.5** CI job `server`: `swift test` in `swift:6.2` for `Server/`, then `docker build`. On a tag `server-v*`, push the image to GitHub Container Registry (`ghcr.io/42778312/konstanzgo-live`).
  Done when (whole part): `docker compose up` on the Mac serves `/v1/health` at `http://127.0.0.1:8080`, the image is under 150 MB, `docker stop` exits within 5 s, and CI is green.

## Part S3 — Stop directory and hub list

- [ ] **S3.1** `DataPipeline/efa-stops/build_efa_stops.py`: for each of the 142 stations, call `XML_STOPFINDER_REQUEST` (one call per second, `User-Agent` with contact email), take the result whose `gid` matches the station's DHID prefix, and write `efa_stops.json`: `{ stationGID, name, efaNumericID, efaName }`. Stations that do not match are listed in the output, not guessed.
- [ ] **S3.2** Same script computes the **hub list**: greedy set cover over city trips (`route.is_city = 1`), choosing stations until at least 90 % of city trips pass one of them, at most 15 stations. Written into `efa_stops.json` as `hubs`, with the coverage it reaches.
- [ ] **S3.3** `check.py` also checks `efa_stops.json`: all 142 stations present or explicitly unmatched, the hub list not empty, and the file built from the same `feed_version` as `timetable.db`.
  Done when: the file is in git, at least 140 of 142 stations are matched, and the hub coverage is reported.

## Part S4 — Upstream (talking to EFA-BW)

- [ ] **S4.1** `RealtimeSource` protocol and `UpstreamDeparture` struct (see design doc, section "Upstream").
- [ ] **S4.2** `EFAClient: RealtimeSource` with `AsyncHTTPClient` (the HTTP client Vapor itself uses; `LiveCore` imports it directly, never Vapor). Sends `User-Agent: KonstanzGo-Live/<version> (+<PUBLIC_URL>; <CONTACT_EMAIL>)` and `Accept-Encoding: gzip`. Timeout 5 s. Parses the JSON paths recorded in S0.4.
- [ ] **S4.3** `RateLimiter` actor: token bucket, `UPSTREAM_MAX_RPS` (default 1), burst 2, takes an injected clock. Callers `await` a token or get `.denied` when the queue would wait more than 10 s.
- [ ] **S4.4** `CircuitBreaker` actor: opens after 5 failures in a row, stays open 2 min, then lets 1 probe through. Honours `Retry-After`. Backoff 30 s, 60 s, 120 s, capped at 5 min, with jitter.
- [ ] **S4.5** `GuardedSource`: wraps any `RealtimeSource` with the limiter and breaker. This is the only `RealtimeSource` the rest of the server gets.
  Done when: parser tests pass on every fixture; a test with an injected clock sends 10,000 requests through `GuardedSource` and proves no 1-minute window has more than 60; breaker tests cover open, half-open and close.

## Part S5 — Matching and live state

- [ ] **S5.1** `StopDirectory`: loads `efa_stops.json`, maps station gid ↔ EFA names.
- [ ] **S5.2** `TripIndex`: built once at boot from `timetable.db`: `(stationGID, line, serviceDay, plannedMinute) → [TripKey]`, only for city routes.
- [ ] **S5.3** `TripMatcher`: `UpstreamDeparture → TripLive?` with the rule from the design doc. Ties broken by headsign; still a tie means no match. Counts matched and unmatched.
- [ ] **S5.4** `LiveStore` actor: `[TripKey: TripLive]`. Newer observation wins. Drops entries older than 3 min from reads; deletes trips that ended more than 10 min ago.
- [ ] **S5.5** `SnapshotBuilder`: after each write batch, encodes `LiveSnapshot` with `KGLiveAPI`, gzips it, computes a strong `ETag` (SHA-256 of the bytes, first 16 hex chars), and keeps the bytes in memory.
  Done when: on the recorded fixtures the match rate is **at least 95 %** of city-bus departures (a golden test), and the snapshot for a full fixture set is under 4 KB gzipped.

## Part S6 — Polling

- [ ] **S6.1** `PollScheduler`: a single long-running task started by Vapor's lifecycle. Every `POLL_INTERVAL_SECONDS` (default 30) it asks each hub station once, in order, with 100–400 ms random gaps, through `GuardedSource`. Writes results through the matcher into the store, then rebuilds the snapshot.
- [ ] **S6.2** Quiet hours: skip a cycle when no city trip runs in the next 20 min (from `TripIndex`).
- [ ] **S6.3** Kill switch: `LIVE_UPSTREAM_ENABLED=false` stops all upstream calls; the snapshot then says `upstream: "off"` with no trips.
- [ ] **S6.4** Graceful shutdown: on SIGTERM, finish the in-flight request, then stop.
  Done when: a local run against real EFA-BW (`docker compose up`) keeps `snapshotAgeSeconds` under 60 for 2 hours, logs **zero** 429 responses, and the `upstream_requests_total` counter shows at most 60 per minute.

## Part S7 — Snapshot API

- [ ] **S7.1** `GET /v1/live/snapshot`: returns the prebuilt bytes with `Content-Type: application/json`, `Content-Encoding: gzip`, `ETag`, `Cache-Control: public, max-age=5, s-maxage=10, stale-while-revalidate=20, stale-if-error=300`. `If-None-Match` match → `304`. Never touches the store or upstream on the request path.
- [ ] **S7.2** Before the first poll finishes: `200` with `upstream: "degraded"` and no trips (never a 5xx).
- [ ] **S7.3** `GET /metrics` (Prometheus format), on a separate port or protected so Cloudflare does not expose it: `live_snapshot_age_seconds`, `upstream_requests_total{status}`, `live_match_rate`, `live_trip_coverage`, `circuit_state`.
  Done when: `oha -z 60s -c 50 http://127.0.0.1:8080/v1/live/snapshot` on the Mac shows p99 under 5 ms and no errors, and upstream traffic does not change during the test.

## Part S8 — Stop departures (on demand)

- [ ] **S8.1** `GET /v1/stops/{gid}/departures?limit=10`: answers from a 20 s per-stop cache. On a miss, at most **one** in-flight upstream request per stop (single-flight); everyone else waits for it. Goes through `GuardedSource`; when the limiter says `.denied`, return the cached or timetable-only answer with `upstream: "degraded"`, never an error.
- [ ] **S8.2** `Cache-Control: public, s-maxage=20, stale-if-error=120`.
  Done when: a test fires 1,000 concurrent requests for one stop and sees exactly one upstream call.

## Part S9 — Deploy

- [ ] **S9.1 (you)** Buy or pick the API domain (for example `api.konstanzgo.de`), add it to Cloudflare, create a Tunnel and copy its token.
- [ ] **S9.2 (you)** Create the server: Ubuntu 24.04, 2 vCPU / 4 GB, in Germany. Add your SSH key, disable password login, enable the provider's firewall with **no inbound ports** except SSH from your IP.
- [ ] **S9.3** `Server/deploy/README.md`: the exact commands to install Docker, copy `docker-compose.yml` and `.env`, `docker compose --profile tunnel up -d`, update to a new image tag, roll back, and read logs.
- [ ] **S9.4 (you, with the README)** Cloudflare settings: Cache Rule "`/v1/*` eligible for cache, respect origin headers"; rate limiting rule 120 requests per minute per IP on `/v1/*`; block `/metrics` from the internet.
- [ ] **S9.5 (you)** Uptime check on `https://<domain>/v1/health` every minute with push alerts (UptimeRobot or Better Stack). Alert when `snapshotAgeSeconds` is over 120 during service hours.
  Done when: `curl -I https://<domain>/v1/live/snapshot` twice shows `cf-cache-status: HIT` on the second call, and stopping the container triggers an alert on your phone within 5 min.

## Part S10 — App integration (behind a feature flag)

- [ ] **S10.1** `KGCore`: `LiveClient` (URLSession, `If-None-Match`, 5 s timeout, decodes `KGLiveAPI`) and `LiveDelays` (immutable lookup by `TripKey`, with `upstream` and age).
- [ ] **S10.2** `KGFeatures`: `LiveModel` (`@MainActor @Observable`): fetch on becoming active, then every 15 s while the map, a stop sheet, a trip or a journey is visible; stop when `scenePhase` leaves `.active`; 60 s when the network is constrained.
- [ ] **S10.3** `VehicleTracker`: position at `seconds − smoothedDelay`; the delay eases from old to new over 4 s; a bus never jumps back more than 30 m on screen.
- [ ] **S10.4** Departures, connections and `TripProgress` use `planned + delay`. The five UI states from the design doc: Live, Late (+N), Scheduled ("Laut Fahrplan"), Cancelled ("Fällt aus", only if S0.4 found the field), Live paused.
- [ ] **S10.5** Feature flag: build setting `KG_LIVE_ENABLED` plus a `UserDefaults` switch in the debug menu. Off by default in release until S11.
- [ ] **S10.6** Update `PLAN.md` decision 0.2.4 ("fully offline") to the new rule: timetable offline, live delays as an optional layer. Update the privacy text (screen 25) and the App Store privacy notes.
  Done when: in the Simulator with the flag on, a delayed bus sits behind its scheduled place and its stop shows green "+N"; with airplane mode on, the app shows the timetable and no error; snapshot tests for all five states pass on iOS 18 and iOS 27.

## Part S11 — Prove it

- [ ] **S11.1** Load test through Cloudflare with `k6`: 500 requests per second on `/v1/live/snapshot` for 10 min. The origin must stay under 1 request per second.
- [ ] **S11.2** Chaos test: point the server at a fake upstream that returns 429 and 500. Check backoff, the breaker, `upstream: "degraded"`, and that the app falls back to the timetable.
- [ ] **S11.3** TestFlight with the flag on, one week of real rides.
  Done when: one week passes with no 429 from EFA-BW, match rate at least 95 %, and live coverage of running city trips reported.

## Part S12 — Later (not now)

- Staleness-driven `CoveragePlanner` (design doc, "Phase 2") to reach 90 % live coverage at the same budget.
- Disruption texts (EFA-BW stop `infos`, later GTFS-RT ServiceAlerts).
- Switch to the official NVBW source once access is granted: one new `RealtimeSource`, nothing else changes.
- App Attest on `/v1/stops/*` if someone scrapes the API.

---

## Repository layout after this plan

```
KonstanzGo/
├── PLAN.md                      app plan (decision 0.2.4 updated in S10.6)
├── SERVER_PLAN.md               this file
├── Packages/KonstanzKit/Sources/
│   ├── KGTimetable/             NEW (S1.1) models, ServiceTime, TimetableStore, TripKey
│   ├── KGLiveAPI/               NEW (S1.4) Codable DTOs, Foundation only
│   ├── KGCore/                  app logic, re-exports KGTimetable; LiveClient (S10)
│   ├── KGDesign/  KGFeatures/   unchanged except S10
├── Server/
│   ├── Package.swift
│   ├── Dockerfile
│   ├── Sources/
│   │   ├── LiveCore/            Upstream/ Matching/ Scheduling/ Store/  (no Vapor)
│   │   ├── LiveServer/          Vapor: configure.swift, Routes/, lifecycle
│   │   └── Run/main.swift
│   ├── Tests/LiveCoreTests/     Fixtures/ (recorded EFA-BW JSON)
│   ├── scripts/record_fixtures.py
│   └── deploy/                  docker-compose.yml, .env.example, README.md
└── DataPipeline/efa-stops/      NEW (S3) build_efa_stops.py → efa_stops.json
```
