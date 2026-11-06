# Changes from the review

Each change maps to a finding in `REVIEW.md`.

| Finding | Commit | What changed | Why | Checked by |
|---|---|---|---|---|
| R-02 | `bc473a4` | `DataPipeline/gtfs-import/station_ids.py` and `station_ids.json` keep stop numbers; `check.py` fails on a stop without one. A saved stop no longer in the timetable opens as a place. Alarms match on trip and time | An update could point favourites and alarms at another stop | 5 pipeline tests, `MapSheetTests`, a rebuild giving all 142 stops their shipped numbers and all 263 platforms their shipped stops |
| R-04 | `7fb9028` | `ServiceClock.upcomingDays`; departure lists, next direct bus and planner see tomorrow's trips in the first 3 hours (lists up to their own time window) | The 00:09 S14 was missing at 23:30 | Failing test first, then 51 store, planner, time and scan tests |
| R-03 | See git log | Privacy text in German and English names DWD and the IP address | The text said the app sends no personal data | `testMoreOfflineAndPrivacy` |
| R-05 | See git log | `TimetableInfo.validity`; map, stop sheets and offline screen say the timetable has ended | The app said "ends soon" and "all up to date" with empty lists | `validityFollowsTheLastDay`, simulator run with an expired timetable, `SavedAndMoreTests` |

## Live data and disruptions

| Finding | What changed | Why | Checked by |
|---|---|---|---|
| R-07 | `LiveModel` and `EFADepartures`: stop sheets show live times, late buses move on the map, cancelled ones disappear | The app only knew the timetable | `LiveTests`, real data in the simulator |
| R-08 | `LiveModel` and `EFANotices`: notices are read when online and kept on the phone. Closed stops get an X, leave the planner and are crossed out in stop lists. Seeri announces new notices once; a pill and sheet list them with alternatives | The app knew nothing about disruptions | `LiveTests`, `LiveNoticesTests`, real closure in the simulator |

## Missed connections

| What changed | Why | Checked by |
|---|---|---|
| `Journey.risk` compares each change with live delays, cancellations and closed stops. `JourneyPlanner.rescue` finds up to three other ways to the same target; when on a bus it tries every stop ahead as the place to get off. The trip screen warns and offers one tap to another route, and always has a small "Andere Route" button | A late bus shouldn't leave the user stranded | `RescueTests` (core and UI), simulator screenshots of the whole flow |

## Ultimate test, 6 Nov 2026

Complete run: 265 of 265 app, snapshot and UI tests, 233 package tests, App Store check passed. On the simulator and Mac; the iPhone wasn't connected.

| Measured | Before | After |
|---|---|---|
| Opening the offline data (Mac, Release) | 307 ms | 18 ms |
| Live times on a stop's first frame | After 0.3–1.4 s of network | At once for any bus reported in the last 5 minutes |
| Hitches panning, 15 s (simulator) | 12 | 10 |
| Hitches zooming, 15 s (simulator) | 6 | 2 |
| Hitches dragging a sheet, 15 s (simulator) | 22–37 with Liquid Glass | 15–17 with the blur material |

| What changed | Why |
|---|---|
| `LiveModel.instant`, `status(ofTrip:)`, `warm(stations:)`, saved delays, one request per stop at a time | Real times without waiting |
| Stops are white H signs, only buses are coral, with a glow (`KGStopSign`) | They looked alike |
| Search index loads in the background | 98% of what opening the data waited for |
| Sheets use a blur material | About 40% fewer dropped frames while dragging |
| Trip card shows the real delay; route cards show a known delay | They only showed timetable times |

## Look, buses and line 9, 6 Nov 2026

Built on request and committed under plan task P1-01. Checked in the simulator and by building each commit; the full test suite runs next, in P1-05.

| What changed | Why | Checked by |
|---|---|---|
| Navy glass everywhere: `KGGlassBackdrop`, `kgGlassCard`, `kgGlassMenu` | One look for every sheet, card, list and menu, matching the search field | Simulator, the owner's iPhone |
| "Mehr" is now "Einstellungen" / "Settings" | The owner's request | Simulator |
| 3D sprites at 36 headings, turning and indicators, 8 updates a second | Buses should look and move like buses | Simulator, the owner's iPhone. iPhone smoothness and battery not measured |
| Exact delay seconds, `DelayGlide`, 30 s stop reads around the view | Buses on the map disagreed with the list. Over 15,304 stops today: mean gap 14 s → 8 s, max 30 s → 20 s, early 43% → 0% | `busesLeaveStopsWhenTheListSays`, `DelayGlideTests`, live comparison |
| Time picker: wheels fixed, readout, shortcuts, 1-minute steps, no past days | The day wheel squeezed the time wheels to nothing | Simulator |
| Line 9 split into 9A, 9B and 9, following the printed timetable (valid from 7 Apr 2026). The live feed still says "9", so `Line.feedNumber` matches it | They are different routes | Letters compared with the printed timetable on four days, simulator with live data |
| Back swipe in settings (`kgSwipeBack`) | iOS turns it off with the navigation bar hidden | Simulator, from the edge and mid-page |

`timetable.db` was patched with the importer's 9A/9B output instead of a full rebuild. Plan task P1-07 confirms a full rebuild gives the same data.

## Test baseline, 6 Nov 2026 (plan task P1-05)

First full run after the work above: 14 of 274 failed, none a bug in the app. 3 logic tests expected the old line 9, and 11 snapshot tests (16 pictures) predated the new look. The owner reviewed the picture changes and accepted them. Now, in two runs in a row: 273 passed, 0 failed, 1 skipped (`testPanZoomAndSheets`, on request only); package 237 tests.

`typingIsFast` failed twice on a busy Mac because it counted the one-time wait for the search index (about 310 ms in Release). It now waits for the index first. Typing itself takes 0-9 ms per key in Release.

| Known exception | Detail | Owner |
|---|---|---|
| Light-mode snapshots | They show the glass on light backgrounds, which the always-dark app and the widgets never display | Later clean-up |
| Rainbow block in the map snapshot | Also in the old picture; from the test gallery, not a screen | Later clean-up |

## Phase 1 fixes, 6 Nov 2026

| Plan task | What changed | Checked by |
|---|---|---|
| P1-06 | CI: package tests, lint and data check per push; full app tests on main or by hand | Workflow files parse; a real run still needs checking on GitHub |
| P1-07 | Full `build.sh` reproduces the shipped data; only `built_at` and the gzip timestamp differ. `check.py` verifies 9A and 9B | Table-by-table comparison |
| P1-08 | Daily feed watch opens GitHub issues | `test_check_feed.py`; a real run still needs checking on GitHub |
| P1-17 | Cards count door to door and say when to leave | `cardsCountFromTheDoor`, simulator |
| P1-18 | Buses a minute or more early are shown as early | `earlyBuses` |
| P1-19 | Lists sort by real time. New bug fixed: a late bus used to vanish when its timetable minute passed | `listsFollowRealTimes` |
| P1-20 | Without a location, routes say "Altstadt (ohne Standort)" | Code path shared by all three screens; UI suite |
| P1-21 | Privacy text and permission text no longer say location can't be inferred | Each sentence checked against the code |
| P1-22, P1-23 | Damaged user database is kept aside and replaced; failed saves are reported; suspension handling | `aDamagedFileIsKeptAndANewOneStarts`, `worksAgainAfterSuspension` |
| P1-27 | Failed stop reads back off across stops and honour `Retry-After`; no requests while not in front | `stopReadsBackOff`, `plainFailuresDouble` |
| P1-29 | MetricKit reports stay on the phone, shareable from About | `keepsOnlyTheNewestReports` |
| P1-12, P1-13, P1-15, P1-16 | Signed data sets and settings, verified download, swap on next launch, automatic rollback, "Stand:" (R-17). Off until `DataHost.base` is set (P1-14) | 18 `DataSyncTests`, Python signature checked in Swift, end-to-end in the simulator from a `file:` host |

## Phase 2 so far, 6 Nov 2026

| Plan task | What changed | Checked by |
|---|---|---|
| P2-02 to P2-05, P2-07, P2-08 | Jetzt card: saved and nearest stops, next bus per line and direction, live times, when to leave, empty states, folds away | `NowBoardTests` (11), simulator |
| P2-06 | A visible settings button on the map; the pull-up stays. Seeri's one job: what's going on now | UI suite |
| P2-10 | Bus options that lose on every count are dropped; walking always stays | `noOptionLosesOnEveryCount` |
| P2-11 | "Now" plans leave out cancelled buses and changes a delay has broken. Offline and later times are unchanged | `RescueTests` |
| P2-12 | The place sheet's walking time matches the walking option | Simulator |
| P2-13 | Reminders before your stop, on a locked phone, by the delays known when last open; can be turned off | `remindersComeBeforeTheStopAndFollowADelay`. Not yet tried on a real ride |
| P2-14 | "Echtzeit · Stand 22:25", and the map and trip screens say positions are calculated | Simulator |
| P2-15 | Weather older than 6 hours is hidden; the request limit survives restarts; failures back off (R-10, R-11, R-16) | `WeatherTests` |
| P2-17 | Bus numbers that would overlap give way; buses always show | Simulator. Check for flicker on a real iPhone |
| P2-19 | A fade keeps the clock readable | Simulator |
| P2-23 | Start logo 0.5 s (was 0.6) and still skippable by a tap. iPhone start time still unmeasured | Not measured |

## Not changed yet

- **R-01:** NVBW's newest file still ends on 12 Dec 2026. Rebuild as soon as a newer one appears (`DataPipeline/README.md`).
- **R-06:** a whole new timetable still needs an app release. Waiting for your decision on the host.
- **R-22:** written permission or proper access from NVBW or MobiData BW, before release.
- **R-23:** real detour streets for buses.
- **Phone numbers:** every smoothness number above is from a simulator on a Mac. The iPhone 11 hasn't been measured. Build with `OTHER_SWIFT_FLAGS=-DKGMETER` for the on-screen meter.
- **P2 and P3 findings:** still open.
