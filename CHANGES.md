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

## Not changed yet

- **R-01:** NVBW's newest file still ends on 12 Dec 2026. Rebuild as soon as a newer one appears (`DataPipeline/README.md`).
- **R-06:** a whole new timetable still needs an app release. Waiting for your decision on the host.
- **R-22:** written permission or proper access from NVBW or MobiData BW, before release.
- **R-23:** real detour streets for buses.
- **Phone numbers:** every smoothness number above is from a simulator on a Mac. The iPhone 11 hasn't been measured. Build with `OTHER_SWIFT_FLAGS=-DKGMETER` for the on-screen meter.
- **P2 and P3 findings:** still open.
