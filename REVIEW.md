# KonstanzGo review

Audit against `CLAUDE.md`, on branch `review/brief` at `725d79b`, 5 Nov 2026. No app code was changed for this review.

**Short version:** what the app does today is solid. Times, clock changes, service days and offline planning are correct and well tested. The gaps are the new connected features (timetable updates, live delays, disruptions), plus one deadline: the timetable ends on 12 Dec 2026.

**Baseline:** the build succeeds; 143 KGCore tests pass. Paths below are relative to the repo; `KGCore/` and `KGFeatures/` are in `Packages/KonstanzKit/Sources/`.

## Status

Fixes so far are on `review/brief`; see `CHANGES.md`.

| ID | Status |
|---|---|
| R-02 | **Fixed.** Stop numbers kept in `station_ids.json`. Alarms match on trip number and time, rather than the GTFS trip ID proposed below, because GTFS trip IDs also change between feeds |
| R-03 | **Fixed** in the app. The App Store privacy answers still need checking when you fill them in |
| R-04 | **Fixed**, in departure lists, the next direct bus and the planner |
| R-05 | **Fixed.** Checked in the simulator with a copy of the app holding an expired timetable. The widgets aren't changed |
| R-01 | **Blocked:** NVBW hasn't published a newer file yet, and shipping needs a paid Apple account |
| R-06 | **Open:** a whole new timetable still needs a release. Waiting for your decision on the host |
| R-07 | **Built with EFA-BW:** live times on the stop sheet, and reported delays on the map's buses. The trip card and the route list still show timetable times. See R-22 |
| R-08 | **Built with EFA-BW:** X on the map, Seeri's message, notices list, alternatives, planner avoids closed stops, auto-clear at the end time. Real detour streets aren't available: see R-23. See R-22 |
| R-15, R-18 | **Fixed:** contact in the `User-Agent`; buses with a live report get a green dot |

## Findings

Severity: `P0` data loss, crash, wrong times, or broken offline · `P1` correctness or offline failure · `P2` UX or performance · `P3` polish. Effort: S under 2 h · M up to a day · L several days.

| ID | Severity | Area | Finding | Evidence | Fix | Effort |
|---|---|---|---|---|---|---|
| R-01 | P0 | Data | The timetable ends on **12 Dec 2026**. After that, stops show no departures and only a new app release can fix it. NVBW's file is still the 11 Oct version, so a rebuild can't extend it yet. | `meta.feed_end = 20261212`; `vhb.zip` `Last-Modified: 11 Oct 2026` (checked today) | Check NVBW weekly, rebuild and release before 12 Dec. Needs R-02 first and a paid Apple account. R-06 removes the problem for good. | M |
| R-02 | P1 | Data | **Saved things can point to the wrong stop or trip after any timetable update.** Stop and trip numbers are handed out fresh on each import, and favourites, recents and alarms store those numbers. | `import_gtfs.py:333`, `:379`; `KGCore/Models/UserData.swift:6`; `KGCore/User/UserStore.swift:52`, `:54`. Compared feeds 20260920 and 20261011: 3 stops changed name under the same number (109 "Kreuzlingen #ddb" → "Kreuzlingen Hafen"); all 2871 shared trip numbers are different trips | Keep stop numbers stable in the pipeline (a saved ID map), and re-link saved stops by name and position after an update. Alarms should keep the GTFS trip ID. | M |
| R-03 | P1 | Privacy | **The privacy text is now wrong, because of the weather I added.** It says the app is fully offline and transmits no personal data, but each weather request gives DWD the phone's IP address, which DWD stores for up to 7 days. | `KGFeatures/More/MoreScreen.swift:373-376`; `opendata.dwd.de/README.txt`; `KGCore/Weather/Weather.swift:188` | Correct the privacy text now and check the App Store privacy answers. Your own shared-file host would hide IPs from DWD, but that host would then see them. | S |
| R-04 | P1 | Time | Late in the evening, departures just after midnight are missing. The list looks at today's and yesterday's service days, never tomorrow's. Example: at 23:30 the 00:09 S14 from Konstanz Bahnhof isn't listed. The planner has the same limit. | `KGCore/Time/ServiceTime.swift:81`; `KGCore/Timetable/TimetableStore.swift:87`, `:174`; `KGCore/Routing/JourneyPlanner.swift:88`, `:175-181`; SQL on `service_date = 20261106` | Add the next service day to departure lists and to the planner when near midnight, with a test that fails first. | S |
| R-05 | P1 | Data | Once the timetable has ended, the app still says "ends soon" rather than saying it has ended, and lists are simply empty. | `KGFeatures/Map/MapScreen.swift:440-442`; `KGFeatures/More/MoreScreen.swift:197-199` | Add an "ended" state with a clear message on the map and stop screens. | S |
| R-06 | P1 | Sync | No timetable updates without a release (A2, A3, A8). The database is only read from the app bundle, and the widget reads the same file. | `KGCore/BundledData.swift:25`; the only `URLSession` is `Weather.swift:188` | Phase 3 of the plan. Move the active database to the App Group folder so the widget sees updates too. | L |
| R-07 | P1 | Live | No live delays (A4). At 19:00 today EFA-BW showed line 4 **+5 min** and line 2 **+3 min**; the app can only show the timetable time. Timetable rows are labelled "laut Fahrplan", so nothing is faked. | EFA-BW `XML_DM_REQUEST` for stop 8711882 (no key needed); no real-time code in the repo | Phase 4. `gtfs_id` is already stored for trips, routes and platforms, which helps with matching. | L |
| R-08 | P1 | Alerts | No disruptions at all (A5, A6). | No alert code in the repo | Phase 5. Needs a GTFS-RT source for structured alerts: EFA-BW only offers free text. | L |
| R-09 | P2 | Launch | Launch misses the 1 s goal (A9). First frame is 1.11 s; the search bar is ready after about 3.2 s, which includes your start logo and test overhead. Simulator numbers; iPhone 11 not measured. | `testLaunchTime` (1.17, 1.08, 1.07 s); temporary test (3.2 s); `KGFeatures/RootView.swift` keeps the logo on every launch at your request | Your call: you asked for the logo on every launch, and that conflicts with this goal. A shorter logo would be the compromise. | S |
| R-10 | P2 | Weather | The last weather reading shows forever with no age, so a 3-week-old "9°" looks current. You asked for the last reading offline, but the brief (A7) wants old values marked or hidden. | `KGFeatures/Map/WeatherChip.swift`; `Weather.swift` `init` | Your call: hide it, or dim it, after about 6 hours. | S |
| R-11 | P2 | Network | The 20-minute weather limit is only kept in memory, so every cold launch makes a request. Failures retry every 2 minutes with no backoff. | `Weather.swift:148`, `:168` | Save the time; add growing retry delays. | S |
| R-12 | P2 | Storage | If `user.sqlite` can't be opened, favourites silently stop saving with no message and no recovery. Failed saves are also silent. | `KGFeatures/App/AppServices.swift:35`, `:84` | Back up the bad file, start a new one, and say so once. Never wipe silently. | M |
| R-13 | P2 | Storage | `UNVERIFIED`: the user database is shared with the widget in the App Group without GRDB's suspension handling, which iOS can punish by killing the app (`0xDEAD10CC`). No crash seen. | `KGCore/User/UserStore.swift:24`; no `observesSuspensionNotifications` in the repo | Turn on GRDB's handling for that store. | S |
| R-14 | P2 | Data | Some trains are missing. EFA-BW lists IR 2134 to Kreuzlingen at 19:09 from Konstanz; the database has no InterRegio routes. All other departures compared matched exactly. | EFA-BW vs SQL for `station_id = 15`; 0 IR routes | Your call, tied to the Swiss-stops question. Likely needs another feed. | M |
| R-15 | P3 | Weather | The DWD request's `User-Agent` has no contact, which the brief asks for. | `Weather.swift:187` | Add the support email. | S |
| R-16 | P3 | Weather | Moon or sun follows the reading's time rather than the current time, so it can be wrong for up to an hour around sunrise and sunset. | `WeatherChip.swift:11` | Use the current time. | S |
| R-17 | P3 | UX | A10 is partial: the app shows "Fahrplan bis …" but no "Stand: …" data version. | `MoreScreen.swift:201`; `meta.feed_version` exists | Add it to the offline data screen. | S |
| R-18 | P3 | UX | Moving buses are estimates with no sign of it on the map. Only the tour says so, and a bus 5 minutes late is drawn in the wrong place. | `KGFeatures/Map/SeeriTour.swift:59`; `KGCore/Vehicles/Trajectory.swift:10` | Use delays once R-07 lands; mention "geschätzt" when a bus is tapped until then. | S |
| R-19 | P3 | UX | Read errors look the same as "no departures". The read-only database makes this very unlikely. | `KGFeatures/Stop/StopScreen.swift:216-217` | Show an error state. | S |
| R-20 | P3 | Data | Leftover Android table `room_master_table` in the iOS database, and seconds are dropped from times. Both harmless today. | `.schema`; `import_gtfs.py:57-59` | Drop the table at the next rebuild; keep minutes. | S |
| R-21 | P3 | Text | The About screen credit is in English ("© OpenStreetMap contributors") where the brief wants "© OpenStreetMap-Mitwirkende". A real-time credit will be needed with R-07. | `MoreScreen.swift:422` | Update the text. | S |

### Found while building live data

| ID | Severity | Area | Finding | Evidence | Fix | Effort |
|---|---|---|---|---|---|---|
| R-22 | P1 | Live | Live data depends on EFA-BW, called directly from every phone. It's public but undocumented, with no guarantee and no written permission for this use. If it changes or blocks the app, the app falls back to timetable times and the last notices. | `KGCore/Live/LiveModel.swift`; `KGCore/Live/ServiceNotice.swift` | Before release, ask NVBW or MobiData BW for permission or proper GTFS-RT access. Only `LiveModel` and the two parsers would change. | M |
| R-23 | P2 | Map | A bus on a diversion is still drawn on its normal road, and route lines still pass the closed stop. The feed says which stops are closed but not which streets the bus takes instead. | Feed sample of 5 Nov 2026; `KGCore/Vehicles/VehicleTracker.swift` | Needs detour geometry, for example from GTFS-RT shapes or the operator. | L |
| R-24 | P2 | Text | `ems-1014946` (line 6) says "this stop" without naming one, so it's only listed and draws no X. Text rules decide whether a named stop is closed, and could miss other wordings. | `saysClosed` in `ServiceNotice.swift` | Fails safe by listing the notice. Review the wordings as more notices appear. | S |
| R-25 | P3 | Data | `departuresByLine` and `StopScreen` aren't marked for closures or live times; the map's stop sheet is. | `KGCore/TransitService.swift` | Mark them too, if `StopScreen` stays in use. | S |

## Top 5 fixes, in order

1. **R-02 stable numbers:** must come first, because every later data update would otherwise break saved stops and alarms.
2. **R-01 fresh timetable before 12 Dec:** the only item with a hard date. It depends on NVBW publishing, and on a paid Apple account to ship.
3. **R-03 privacy text:** a false statement in the app today, and a very small fix.
4. **R-04 midnight departures:** a real bug for late riders, and a very small fix.
5. **R-05 ended state, then R-06 updates:** tell people clearly when the timetable has ended, then make sure it can't happen again.

R-07 and R-08 are the largest features, and they need your decision on the live source.

## Acceptance criteria

| # | Requirement | Result | Note |
|---|---|---|---|
| A1 | Full timetable offline | ✅ Partly verified | The weather is the only network code and fails safely. **Not tested in real airplane mode:** the simulator shares the Mac's network, so this needs one check on your iPhone. |
| A2 | Refresh at most once per 24 h | ❌ | R-06 |
| A3 | Manual refresh, single-flight | ❌ | R-06 |
| A4 | Live delays when online | ✅ | Via EFA-BW; checked on real data on 5 Nov 2026 |
| A5 | Disruptions on the map | ✅ | Via EFA-BW, for notices that name stops |
| A6 | Disruption detail, auto-clear | ✅ | Tested at the end time and when the operator lifts a notice |
| A7 | Offline shows no fake live data | ⚠️ Partly | Delays are never kept. Weather age is still R-10. |
| A8 | New data without a release | ❌ | R-06 |
| A9 | Usable in under 1 s | ❌ | R-09 |
| A10 | Data version visible | ⚠️ Partly | R-17 |

## Audit checklist

### 3.1 Persistence and offline
| Check | Result | Evidence |
|---|---|---|
| WAL, foreign keys, migrations | PASS / N/A | The timetable is read-only (N/A). `UserStore` uses `DatabaseMigrator` (`UserStore.swift:28`) |
| Times stored as integers, past 24:00 | PASS | Integer **minutes**, up to 1671 (27:51), not seconds |
| Transactional import, off main thread, atomic swap | N/A today | Import runs on the dev machine; the app loads off the main thread (`TransitLoader.swift:20`). Required by R-06 |
| Indexes for hot queries | PASS | `index_stop_time_platform_id_departure`, `index_service_date_date` |
| Survives a corrupt database | PARTLY | Timetable: `integrity_check` ok, failure screen at `HomeView.swift:64`. User store: R-12 |
| Stop deduplication | PASS | `import_gtfs.py:68` uses `parent_station` |
| Unbounded growth | N/A | Fixed file; recents capped at 50 |

### 3.2 Sync policy
Only the weather syncs today (R-11). The rest of this section is **FAIL/N/A** until R-06. There is no `BGTaskScheduler`.

### 3.3 Time
| Check | Result | Evidence |
|---|---|---|
| Service day vs wall-clock day | PASS | `ServiceTime.swift:77-82`; test `runningDaysAfterMidnightIncludeYesterday` |
| `calendar.txt` and `calendar_dates.txt` | PASS | `import_gtfs.py:235-252` |
| Times after 24:00 | PASS | `ServiceTime.swift:60-72` |
| `Europe/Berlin`, not device time | PASS | `TimetableInfo.swift:79-83`; no `TimeZone.current` or `Calendar.current` found |
| Clock changes tested | PASS | `clocksGoBackOn25October2026`, `clocksGoForwardOn29March2026` |
| Shows the next departures | **FAIL** | R-04 |

### 3.4 Real-time and 3.5 Disruptions
Not built, so **N/A** until R-07 and R-08. Two things already pass: route lines draw offline from the bundled shapes, and the 142 stops load without trouble.

### 3.6 Notifications
| Check | Result | Evidence |
|---|---|---|
| Permission timing | PASS | Explained in an onboarding step (`SystemPermissions.swift`) or requested when setting an alarm (`AlarmScheduler.swift:41`) |
| Local only, no backend | PASS | Alarms are local |
| Alert dedup, quiet hours | N/A | No alert notifications yet |

### 3.7 Networking
| Check | Result | Evidence |
|---|---|---|
| Explicit timeout | PASS | 15 s (`Weather.swift`) |
| Backoff | FAIL | R-11 |
| Rate limiting, User-Agent | PARTLY | 20-minute limit in memory (R-11); no contact (R-15) |
| Background errors silent | PASS | Weather keeps the last reading |
| No secrets, no ATS exceptions | PASS | `grep` for tokens and keys found nothing |

### 3.8 Performance and UX
| Check | Result | Evidence |
|---|---|---|
| Database doesn't block the first frame | PASS | `TransitLoader.swift:20`. Total time: R-09 |
| Departure lists bounded | PASS | `limit: 12` (`StopScreen.swift:216`) |
| Search debounced, off main thread | PASS | 120 ms (`MapSearchSheet.swift:98-110`) |
| Dynamic Type | PASS | `testVeryLargeText` |
| Disruption state not colour-only | N/A | No alerts yet |

### 3.9 Code health
| Check | Result | Evidence |
|---|---|---|
| Layers separated | PASS | SQL only in KGCore |
| `try!`, force unwraps on risky paths | PASS | No `try!` or `as!`; force unwraps only on fixed constants |
| Task cancellation | PASS | Loops use `.task` and check `isCancelled` |
| Tests | PASS | 143 KGCore tests including time and planner, plus UI tests. No test for a real feed import beyond `DataPipeline/check.py` |

## Where the brief doesn't fit this app
- It assumes MapKit; the app uses **MapLibre**, so overlay checks apply to MapLibre layers.
- It stores times in seconds; the app uses minutes, which is fine for a timetable. Live delays arrive in seconds and can be rounded for display.
- It has live data in the timetable database; here that database will stay replaceable and read-only, so live data must live elsewhere.

## Decisions needed from you
1. **R-09:** keep the logo on every launch, or shorten it?
2. **R-10:** how old may the weather get before it's hidden or dimmed?
3. **Live source (R-07, R-08):** will you register at MobiData BW for a token?
4. **Timetable host (R-06):** GitHub Releases or Cloudflare?
5. **Swiss trains and stops (R-14)**, and is the app free or commercial?
6. **One check on your iPhone:** airplane mode, force-quit, open the app, open a stop (A1).
