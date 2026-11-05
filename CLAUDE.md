# CLAUDE.md — Konstanz Bus App: Review & Improvement Brief

> **Mission:** This repository contains an **existing, working iOS app**. Do not rewrite it from scratch.
> Your job is to **audit it, find real defects, and improve it incrementally** against the criteria below.
> The owner built it already; treat their architecture as a starting point, not a mistake.

**App:** city bus app for Konstanz (Stadtbus / Verkehrsverbund Hegau-Bodensee)
**Stack:** Swift, SwiftUI, local SQLite timetable, offline-first
**Target:** iOS (confirm minimum deployment target from the project, do not raise it without asking)

---

## 0. How to work (read this first)

### 0.1 Do not start editing on line 1
1. **Inventory the repo before judging it.**
   ```bash
   find . -name "*.swift" | sed 's|/[^/]*$||' | sort | uniq -c | sort -rn
   grep -rn "CREATE TABLE\|import GRDB\|import SQLite\|CoreData\|NSPersistent" --include=*.swift .
   grep -rn "URLSession\|BGTaskScheduler\|Timer\|ScenePhase" --include=*.swift . | head -50
   ```
2. **Read the project file** (`*.xcodeproj/project.pbxproj`), entitlements, Info.plist, and every file over ~150 lines that touches persistence, networking, or sync.
3. **Run it if possible.** Build, launch simulator, and note what actually fails. Runtime evidence beats guessing.
4. **Write `REVIEW.md` first**, then make changes. No silent refactors.

### 0.2 Guardrails
- **Never** change the bundle identifier, app group, signing team, or deployment target without explicit approval.
- **Never** delete the existing SQLite database on launch or "reset" user data as a fix.
- **Never** commit API keys, tokens, or feed URLs containing secrets. Move them to `Secrets.xcconfig` (gitignored) or Keychain.
- **Never** reformat files you are not otherwise changing — it destroys review diffs.
- **Never** replace working code with a new dependency unless the gain is concrete and stated.
- Keep every change small, buildable, and independently revertable. One concern per commit.
- If a finding is speculative, say so and mark it `UNVERIFIED`. Do not present guesses as bugs.

### 0.3 Output contract
Produce `REVIEW.md` with:

| ID | Severity | Area | Finding | Evidence (file:line) | Fix | Effort |
|---|---|---|---|---|---|---|

- **Severity:** `P0` data loss / crash / wrong times shown · `P1` correctness or offline failure · `P2` UX/perf · `P3` polish.
- **Evidence:** exact `path:line`, or a command/output that proves it.
- Then a short **“Top 5 fixes, in order”** section with rationale.
- Only after `REVIEW.md` exists, implement the fixes — P0 and P1 first.

---

## 1. What the app must do (acceptance criteria)

Use these as the yardstick. If the code already does it, mark ✅ and move on. Do not redesign what passes.

| # | Requirement | How to verify |
|---|---|---|
| A1 | Full timetable available offline | Airplane mode, cold launch, search a stop, see departures |
| A2 | Schedule refresh at most once per 24 h | Inspect sync gate; simulate clock; count network calls |
| A3 | Manual refresh always possible, single-flight | Pull-to-refresh twice rapidly → one request |
| A4 | Real-time delays shown when online | Compare with EFA-BW departure monitor |
| A5 | Disruptions shown on the map per affected line/stop | Inject a ServiceAlert, confirm overlay |
| A6 | Disruption detail + auto-clear when it ends | Alert expiry removes overlay without restart |
| A7 | Offline = no fake live data | Cached live values marked stale or hidden |
| A8 | New routes/maps without App Store release | Data comes from feed, not bundled-only |
| A9 | Launch to usable timetable < 1 s, no network | Measure with Instruments / signpost |
| A10 | Data version visible (“Stand: …”) | Settings or banner |

---

## 2. Data sources (for cross-checking behaviour)

### 2.1 Timetable — GTFS Schedule
- **MobiData BW / NVBW**, “Soll-Fahrplandaten Baden-Württemberg” (with/without `shapes.txt`) and per-Verbund feeds.
- Konstanz = **Verkehrsverbund Hegau-Bodensee (VHB)**; indexed on Mobility Database as `mdb-914`.
- National fallback: DELFI / gtfs.de.
- `shapes.txt` is ODbL → “© OpenStreetMap-Mitwirkende”.

### 2.2 Real-time — GTFS-RT
- `TripUpdate`: delay, skipped stop, cancelled trip.
- `ServiceAlert`: `informed_entity` (route/stop/trip), `active_period`, `cause`, `effect`, header/description.
- Source: MobiData BW / Mobilithek (registration + token expected).
- Suggested cadence: TripUpdates 30 s while visible / 5 min background; ServiceAlerts 60 s.

### 2.3 EFA-BW — verified live fallback (no key)
Base `https://www.efa-bw.de/nvbw/`
- Stop search: `XML_STOPFINDER_REQUEST?outputFormat=JSON&name_sf=Konstanz%20Bahnhof&type_sf=any&coordOutputFormat=WGS84[DD.ddddd]`
- Departures: `XML_DM_REQUEST?outputFormat=JSON&name_dm=8711882&type_dm=stop&mode=direct&useRealtime=1&depType=stopEvents&limit=10`
- Known IDs: Bahnhof (Bus) `8711882` / `de:08335:11882`; Schulthaißstraße `8711905` / `de:08335:11905`.
- Stop search can include `infos` with live disruption text (unstructured).
- **Undocumented, no SLA.** Verify the app caches and rate-limits. If the app depends on it in production, flag as `P1` risk and propose the GTFS-RT path.

### 2.4 Operator page
`https://www.stadtwerke-konstanz.de/bus/verkehrsmeldungen/` — the advertised RSS feed is **currently empty** (verified `/feed/` and `?feed=rss2`). If the app scrapes this HTML, flag it `P1` (brittle) and propose GTFS-RT ServiceAlerts.

---

## 3. Audit checklist

Work top to bottom. For each item: **PASS / FAIL / N/A** plus evidence.

### 3.1 Persistence & offline (highest value)
- [ ] Is SQLite opened with WAL, `foreign_keys = ON`, and a real migration path (GRDB `DatabaseMigrator` / `user_version`)?
- [ ] Are GTFS times stored as **integer seconds** (may exceed 86 400), not `Date` and not `String`?
- [ ] Is the schedule import transactional? A crash mid-import must not leave a half-filled DB.
- [ ] Is the import off the main thread? Look for synchronous file I/O or bulk inserts inside `body`/`init` of a view.
- [ ] Is there an atomic swap (import into temp DB → replace), or does the app mutate the live DB in place?
- [ ] Are indexes present for the hot queries (stop name search, departures by stop + time)?
- [ ] Does the app survive a corrupt DB (backup/restore/re-import) rather than crash-looping?
- [ ] Are stops near-duplicates deduplicated by `parent_station` for display?
- [ ] Does the DB grow unbounded (old calendar dates, RT rows never truncated)?

### 3.2 Sync policy
- [ ] Is there exactly **one** gate for the 24 h schedule refresh, persisted across launches (not an in-memory flag)?
- [ ] Is the gate based on **last successful sync**, and does a failed attempt avoid resetting it?
- [ ] Is there single-flight protection (actor/serial queue) so two screens cannot both import?
- [ ] Is conditional fetch used (ETag / Last-Modified) so an unchanged feed skips the download?
- [ ] Are real-time and alert refreshes on **separate** timers from the schedule? (One shared timer is a defect.)
- [ ] Do timers stop when the screen disappears / app backgrounds? (Leaked `Timer` = battery + rate-limit risk.)
- [ ] Is `BGAppRefreshTask` registered with the correct identifier in Info.plist `BGTaskSchedulerPermittedIdentifiers`, and does it call `setTaskCompleted` on every path?
- [ ] Does the app refresh when returning to foreground after >24 h, not only on cold launch?

### 3.3 Time correctness (common silent failure)
- [ ] GTFS service day vs wall-clock day: a 00:30 trip belongs to the previous service date.
- [ ] `calendar.txt` + `calendar_dates.txt` exceptions both applied.
- [ ] Times after 24:00:00 resolved correctly (not clamped to 23:59).
- [ ] Timezone hardcoded correctly to `Europe/Berlin` (not device-local).
- [ ] DST transitions (March/October) tested, not assumed.
- [ ] Departure lists show the **next** departures, not “today from 00:00”.

### 3.4 Real-time merge
- [ ] Is `TripUpdate` matched by `trip_id` **and** `start_date`? (Matching by route alone is wrong.)
- [ ] Are skipped stops (`SKIPPED`) and cancelled trips rendered, not silently dropped?
- [ ] Is delay applied per stop, not only at trip start?
- [ ] Are stale RT rows expired (timestamp check), so a dead feed doesn’t freeze “+2 min” forever?
- [ ] Does the UI distinguish **planned**, **live**, and **stale cached** values visually?
- [ ] Is there a fallback when the RT feed is empty but the schedule exists?

### 3.5 Disruptions & map
- [ ] Are alerts persisted, or lost on relaunch?
- [ ] Are `active_period` start/end honoured (future alerts not shown as active)?
- [ ] Is geometry derived from `informed_entity` → route/stop ids, not from parsing German free text?
- [ ] If text parsing exists, is it clearly non-authoritative and fails safe?
- [ ] Are affected stops marked, and the affected segment distinct from the normal line (not colour-only)?
- [ ] Do alerts with no `informed_entity` stay out of the map overlay but remain in a list?
- [ ] Is the overlay recomputed on alert removal, or does it linger until restart?
- [ ] Are MapKit overlays reused/updated rather than removed and re-added every refresh (flicker/perf)?
- [ ] Is clustering handled, or does the map die with 500+ annotations?
- [ ] Offline: route geometry draws from `shapes.txt` even when tiles are unavailable?

### 3.6 Notifications
- [ ] In-app banner is non-blocking and dismissible.
- [ ] Local notifications deduplicated by alert id + content hash (no repeat spam on every poll).
- [ ] Quiet hours respected, if implemented.
- [ ] Permission requested at a sensible moment, not at first launch.
- [ ] No remote push assumed without a backend.

### 3.7 Networking & resilience
- [ ] Timeouts set explicitly (default 60 s is too long for a departure screen).
- [ ] Retry with backoff, no tight loops.
- [ ] Rate limiting / token bucket for EFA-BW.
- [ ] `User-Agent` identifies the app + contact.
- [ ] Errors surfaced only where actionable; background failures silent.
- [ ] No secrets in the repo or in `Info.plist` (`grep -rn "token\|apikey\|secret"`).
- [ ] ATS exceptions, if any, are justified.

### 3.8 Performance & UX
- [ ] Cold launch measured; DB open not blocking first frame.
- [ ] Departure list uses lazy containers; no full-table fetch into memory.
- [ ] Search debounced; uses indexed query, not `LIKE '%x%'` over all stops.
- [ ] No work in `body`; no `DateFormatter` created per row (cache it).
- [ ] Dynamic Type supported; contrast sufficient; disruption state not colour-only (accessibility).
- [ ] German UI strings consistent; umlauts and ß correct; no mixed English.

### 3.9 Code health
- [ ] Persistence, networking, and views separated (no SQL in a View).
- [ ] Force unwraps / `try!` on network or DB paths → flag `P1`.
- [ ] `Task` cancellation handled on view disappearance.
- [ ] Retain cycles in closures/timers.
- [ ] Tests: at least time resolution, GTFS import, alert→geometry. If zero tests, that is a `P1` finding for this app.

---

## 4. Reference model (only where the code diverges)

Do **not** impose this wholesale. Use it to justify a specific fix.

```
Features (SwiftUI)  →  Domain (repositories, SyncEngine)  →  Data (SQLite/GRDB, GTFS, GTFS-RT, EFA)
```

Minimum tables if missing:
`agency, stop, route, trip, stop_time, calendar, calendar_date, shape_point`
plus realtime `rt_trip_update`, alerts `alert` + `alert_entity`, and state `sync_state(last_schedule_sync, schedule_version, last_alert_sync, last_realtime_sync)`.

Sync skeleton (target behaviour, not necessarily the current one):
```swift
actor SyncEngine {
    private var isSyncing = false

    func refreshScheduleIfDue(now: Date = .now, force: Bool = false) async throws {
        guard !isSyncing else { return }
        isSyncing = true; defer { isSyncing = false }

        let state = try await syncState.load()
        guard force || now.timeIntervalSince(state.lastScheduleSync) >= 24 * 3600 else { return }

        let head = try await feed.head()                  // ETag / Last-Modified
        guard head.version != state.scheduleVersion else {
            try await syncState.markChecked(now); return  // unchanged → reset clock only
        }
        try await importer.downloadValidateSwap()          // temp DB → atomic replace
        try await syncState.markImported(version: head.version, at: now)
    }
}
```

Alert → map mapping:
```
ServiceAlert(informed_entity: route 6 + stop A,B,C, effect: NO_SERVICE)
  → find contiguous stop_sequence runs containing A,B,C
  → render run in warning style, mark A,B,C as not served
  → banner: "Linie 6 – 3 Haltestellen werden nicht bedient"
  → on expiry: recompute from alert table
```

---

## 5. Prioritised improvement plan (produce this, then execute)

1. **P0 correctness/data loss** — wrong times, crash on launch, DB corruption, broken offline.
2. **P1 sync correctness** — 24 h gate, atomic import, RT/alerts separation, stale expiry, secrets.
3. **P2 map & alerts quality** — geometry from structured data, auto-clear, perf/clustering.
4. **P3 UX/polish** — accessibility, empty states, strings, caching formatters.
5. **Refactor only with a measured win** — no architecture astronautics; no dependency swaps for style.

For every change: state the finding it fixes, keep the diff minimal, build, and update `REVIEW.md` with the resolution.

---

## 6. Definition of done for this review

- `REVIEW.md` exists, every finding has file:line evidence and a severity.
- All P0 and P1 items are either fixed on a branch or explicitly deferred with a reason.
- The app builds, launches, and passes: airplane-mode cold launch, 24 h gate simulation, injected `NO_SERVICE` alert, alert expiry, DST departure case.
- No secrets committed; no unrelated reformatting; no bundle-id change.
- A short `CHANGES.md` summarising what changed and why, mapped to finding IDs.

---

## 7. Ask the owner before assuming

1. Which GTFS/GTFS-RT endpoint is live in the app today (MobiData BW token? EFA-BW only?).
2. Is the app published / TestFlight, and is backward DB compatibility required?
3. Minimum iOS version and whether SwiftData/CoreData is intentionally avoided.
4. Free/non-commercial, or commercial (affects Transitous/MOTIS and feed licensing).
5. Should Swiss cross-border stops (Kreuzlingen) be included?
6. Notification strategy: local only (current recommendation) or planned backend push.

## 8. Attribution strings (About screen, if missing → P3)

- “Fahrplandaten: NVBW / MobiData BW”
- “Kartendarstellung: © OpenStreetMap-Mitwirkende (ODbL)” where shapes are used
- “Echtzeitdaten: DELFI / Verkehrsverbund Hegau-Bodensee”
