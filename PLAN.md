# KonstanzGo for iOS — build plan

**What:** a new iPhone app, written from scratch in Swift and SwiftUI, that looks and behaves exactly like the design.
**Design:** https://claude.ai/artifact/GtvRYmP3LA5RMZpjKAVD9x, page **KonstanzGo**: 29 phone screens at 390×844 pt, plus the brand board. The page "First draft (Seelinie)" is old and is not built.
**Separate from Android:** its own folder (`~/XcodeProjects/KonstanzGo`), its own git repo, no shared code. The Android app (`~/AndroidStudioProjects/konstanz`) is not touched.
The only things taken from the Android project are **data files and the Python data tools** (timetable, map tiles, walking graph, search index). They are copied once into this repo, then live here on their own. The Kotlin code is only used as a *reference*: when Swift and Kotlin get the same input, they must give the same answer (see T5).

**Tools on this Mac:** Xcode 27.1, iOS 27.1 SDK, Swift 6.2.

---

## Ground rules (they apply to every step)

1. **Each step builds, runs in the Simulator and passes its tests** before it is ticked.
2. **One step = one small commit.** No mixing of tokens, components and screens in one commit.
3. **Pixel check against the design:** every screen has a snapshot test on a **390×844 pt** simulator (iPhone 17e: 1170×2532 px at 3×, measured — the same size as the design frames). It is compared with the exported artboard PNG. The difference must be explained or fixed before the step is done.
4. **Tokens only:** no hex colours, raw point sizes or font names in screen code. All of it comes from `KGTheme`. A SwiftLint rule enforces this (T8).
5. **Every screen covers six cases:** content, loading, empty, error, offline, and dark mode. Plus Dynamic Type up to AX3.
6. **German first** (the design is German), English second, in one String Catalog (`Localizable.xcstrings`).
7. **Honest data:** never show what the app does not know (part 0.3).
8. **Accessibility in the same step:** VoiceOver labels, 44 pt touch targets, contrast ≥ 4.5:1 for text, Reduce Motion respected.

---

## Part 0 — Setup and decisions

### 0.1 Mac setup (you, once)

- [x] 0.1.1 Point the command line at Xcode (needs your password):
  `sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`
- [ ] 0.1.2 Open Xcode once, accept the licence, and install two Simulator runtimes in Xcode › Settings › Components: **iOS 27.1** and **iOS 18.x** (needed to test the lowest supported version).
  - Done: licence accepted; iOS 27.1 and iOS 26.5 installed.
  - Open: Xcode 27.1 offers no iOS 18 runtime (`xcodebuild -downloadPlatform` says 18.0–18.6 are "not available"). Download "iOS 18.6 Simulator Runtime" from developer.apple.com/download/all and add it with `xcrun simctl runtime add <file>.dmg`. Until then the iOS 18 look is tested on iOS 26.5/27.1 with the `-KGLegacyLook YES` switch (P6a), and on a real iOS 18 iPhone (T11).
- [ ] 0.1.3 *(open — not needed for the Simulator)* Sign in with your Apple Developer account in Xcode › Settings › Accounts. A paid account is needed for widgets and Live Activities on a real iPhone, App Groups, Siri and TestFlight.
- [x] 0.1.4 Install the helper tools: `brew install swiftlint xcodegen` (XcodeGen keeps the project file readable and free of merge conflicts).

### 0.2 Decisions that are yours

Decided on 28.10.2026:

- [x] 0.2.1 **Lowest iOS version: iOS 18.** Reaches as many iPhones as possible. iOS 26+ gets real Liquid Glass; iOS 18–25 gets a blur material in the same shapes. See "Supporting iOS 18 and 26" below.
- [x] 0.2.2 **Bundle ID: `de.konstanzgo.app`.** Widgets `de.konstanzgo.app.widgets`, App Group `group.de.konstanzgo.app`. Team: your Apple Developer account.
- [ ] 0.2.3 **Name check (still open):** is "KonstanzGo" free on the App Store and as a trademark? Reserve the name in App Store Connect early.
- [x] 0.2.4 **Internet: fully offline.** All data ships inside the app and updates come with app updates. The offline screen shows what is stored and its date, with no download buttons. App Store privacy label: "Data Not Collected". No internet code in the app at all.
- [x] 0.2.5 **Line colours: all yellow `#FFC043`** with dark text `#3A2A00`, as in the design.

### Supporting iOS 18 and 26

One app, one look. Where iOS 26 has something iOS 18 lacks, we write a fallback that looks the same, checked with `if #available(iOS 26, *)`.

| Part | iOS 26 and newer | iOS 18–25 |
|---|---|---|
| Floating tab bar (07, 12, 13) | Our own pill bar from the design, with `glassEffect` | Same bar with `.ultraThinMaterial` + white 92 % tint |
| Glass buttons on the map | `glassEffect` | White fill + `kgShadowFloating` (the design's own look) |
| App icon | Icon Composer layers (glass, light / dark / tinted / clear) | Classic 1024 pt icon with light / dark / tinted |
| Widgets | Also the "clear" and tinted looks | Standard light / dark / tinted |
| Sheets, Live Activity, App Intents, Spotlight, Control Center controls | Same code (all available since iOS 18 or earlier) | Same code |

Every snapshot test runs on **both** an iOS 18 and an iOS 27 simulator (T1).

### 0.3 Design vs. reality (what we build instead)

| Screen | In the design | What we build |
|---|---|---|
| 07, 09, 12, 26 | Green minutes + pulsing dot = live | There is no live feed. Times are **scheduled**: black minutes. Green + dot only if live data is ever added. |
| 07, 11, 21 | Buses moving on the map | Moving buses, estimated from the timetable. Labelled "geschätzt" in VoiceOver and in the layers menu. |
| 17 | "Pünktlich" | "Laut Fahrplan" (shown as "Pünktlich" only with live data). |
| 09, 17, 22 | "Steig A / B / D" | **Possible:** the timetable has platform codes (263 platforms). Shown where a code exists, hidden where it doesn't. |
| 10, 13, 19 | "Barrierefrei" | The timetable has no wheelchair data today. The switches are hidden until it does (D9). |
| 25 | "Anonyme Nutzungsstatistik", "Absturzberichte senden" | **Removed.** The app collects nothing; these switches would be misleading. Apple's own crash reports (opt-in at system level) still reach us through Xcode Organizer. |
| 24 | Region downloads, auto-update | **Removed** (fully offline, 0.2.4): the screen shows stored data and its date only. |
| 13 | "Hilfe & Feedback" | Opens a Mail draft to the support address. |

### 0.4 Contrast fixes (measured from the design's colours)

| Pair | Ratio | Needed | Fix |
|---|---|---|---|
| Green `#05944F` text on white | 3.92 | 4.5 | Darker green for **text** (about `#047A41`, measured in A1.4). `#05944F` stays for dots and fills. |
| Green on card `#F6F6F6` | 3.63 | 4.5 | Same darker green. |
| White text on coral `#F05A62` | 3.31 | 4.5 (3.0 for ≥ 24 pt bold) | White text only on `#D1343E` (4.92). Coral is for shapes, the mascot, icons and large bold text. |
| Coral text on white | 3.31 | 4.5 | Never used for small text. Links are blue `#276EF1` (4.58). |

### 0.5 Reference material

- [ ] 0.5.1 *(open — needs a claude.ai sign-in to the canvas, or Share › Export from it; needed from Milestone 2)* Export all 29 artboards from the canvas as PNG at 1×, 2× and 3× into `Design/Reference/` (`01-start.png` … `29-saisonal.png`, `brand.png`).
- [x] 0.5.2 Copy the design's HTML sources into `Design/Source/` (read-only). They are the source for exact numbers: positions, sizes, colours, curves, delays.
- [ ] 0.5.3 Write `Design/Spec/<screen>.md` for each screen: every element with its frame (x, y, w, h), font, colour, radius, shadow, animation, and what it links to. This is the checklist each screen step is compared with. (Done screen by screen, just before the screen is built.)
- [ ] 0.5.4 Record the animated screens (01, 02–06, 07, 11, 20, 29) as short videos from the canvas so motion can be compared, not only still frames.

---

## Part P — Project skeleton

- [x] P1. `git init` in `~/XcodeProjects/KonstanzGo`, `.gitignore` for Xcode, `README.md`.
- [x] P2. `project.yml` (XcodeGen) with these targets:
  - `KonstanzGo` (the app, SwiftUI life cycle)
  - `KonstanzGoWidgets` (widget extension: home-screen widgets, lock-screen widgets, Live Activity)
  - `KonstanzGoTests` (Swift Testing), `KonstanzGoSnapshotTests`, `KonstanzGoUITests` (XCUITest)
- [x] P3. Local Swift packages, so the logic is testable without the app (built as **one** package, `Packages/KonstanzKit`, with three modules; `swift test` runs the core tests on macOS in seconds):
  - `KGCore`: models, timetable database, routing, walking router, search, vehicle positions, time and service-day maths. No UI.
  - `KGDesign`: tokens, fonts, icons, Seeri, all components. No data.
  - `KGFeatures`: screens and their view models. Depends on the two above.
- [x] P4. Dependencies (Swift Package Manager), as few as possible. Pinned to exact versions: MapLibre 6.31.0 (latest 6.x; 7.0 is a new major, try later), GRDB 7.11.1, swift-snapshot-testing 1.19.7.
  - **MapLibre Native for iOS** (offline vector map from the existing `konstanz.pmtiles`; Apple's MapKit cannot show our own offline tiles and style).
  - **GRDB.swift** (read-only SQLite access to `timetable.db`, plus a small writable database for favourites, history, alarms).
  - **swift-snapshot-testing** (test target only).
- [x] P5. Swift 6 language mode with strict concurrency on all targets from day one.
- [x] P6. Build settings: deployment target **iOS 18.0** on every target, iPhone only, portrait only for v1 (the design is portrait), bundle ID `de.konstanzgo.app`, App Group `group.de.konstanzgo.app`, signing team.
- [x] P6a. `KGDesign/Compat.swift`: small helpers for the iOS 26 extras (`.kgGlass(in:)` uses `glassEffect` on 26+, the material fallback on 18–25), so no screen has its own `#available` checks.
- [x] P7. `Info.plist` texts (German + English): location when in use, location always (only during an active trip, see L5), notifications.
- [x] P8. Capabilities: App Groups (app + widgets), Background Modes (location, only for the trip), Live Activities, Push Notifications **off** (not needed: Live Activity is updated locally). No Siri entitlement: App Intents and App Shortcuts (X4) work without it.
- [x] P9. SwiftLint config + a build phase that runs it. Custom rules reject raw colours and fonts outside `KGDesign` as errors (checked with a probe file).
- [ ] P10. *(written, not run yet: the repo has no GitHub remote)* GitHub Actions job `.github/workflows/ci.yml`: core tests on macOS, then build + all app tests on the iPhone 17e simulator. Check the runner image has Xcode 27 when the repo is pushed; snapshot images may need re-recording on the CI machine if rendering differs.
- [x] P11. Empty app runs on the iPhone 17e simulator and shows "KonstanzGo". Commit.

---

## Part D — Data (copied from the Android project, then owned here)

- [x] D1. Copy the data tools into `DataPipeline/`: `gtfs-import/`, `walk-graph/`, `places-import/`, `map/` (Python scripts + their small input files). Write `DataPipeline/README.md` with the one command that rebuilds everything.
- [x] D2. Change the tools' output folder to `KonstanzGo/Resources/Data/`.
- [x] D3. Run them once (whole pipeline: about 5 s); check the outputs are the same as the Android assets (same row counts: 142 stations, 263 platforms, 18 city lines, 3,380 trips, 33,991 stop times, 2,870 places; feed valid 12.07.–12.12.2026).
- [x] D4. Bundle in the app (checked by `AppBundleTests`): `timetable.db` (3.5 MB), `konstanz.pmtiles` + `style.json` + map fonts (7.8 MB), `konstanz-walk.bin` (1.4 MB), `places.tsvz` (0.5 MB). Total about 13 MB.
- [ ] D5. *(moved to Part M, with the map's look)* Map fonts: the map style uses Noto Sans; switch the style's labels to the design's look (uppercase district labels with letter spacing, italic water names) and build Figtree glyph files so map labels match the app font.
- [ ] D6. *(moved to Part M, with the map's look)* Map style colours from the design (land `#F2F1ED`, water `#B9D8E8`, parks `#D8E8D2`, buildings `#E5E2DE`, road casing `#D5D3CF`, roads white, labels `#757575`, water labels `#3F6FB0`) + a dark style (land `#1E1E1E`, water `#182D38`, park `#203126`, water labels `#6E9BD6`). Generated by `DataPipeline/map/make_style.py`.
- [x] D7. Write down the binary formats in `DataPipeline/FORMATS.md`:
  - `konstanz-walk.bin`: magic `KWG1`, big-endian; names (count, then UTF-8 strings with a 2-byte length), vertices (lat/lon × 10⁷ as Int32), edges (from, to, name, kind, flags, length in cm, shape points).
  - `places.tsvz`: gzip, tab-separated columns (list from `build_search.py`).
  - `timetable.db` tables: station, platform, route, trip, stop_time, service_date, shape, place, street_point, meta.
- [x] D8. Check if the feed has wheelchair data; if yes, import it (for "Barrierefrei").
  - Result (feed 20261011): the fields exist but are unusable. All 1,284 trips of the Konstanz city lines say `wheelchair_accessible = 2` (not accessible), although the buses are low-floor; 2,884 of 2,948 stops say 0 (no information). **Not imported. "Barrierefrei" stays hidden** (0.3). Check again with each new feed.
- [x] D9. Add `DataPipeline/check.py`: fails if the feed ends within 30 days, so a release is never shipped with old data.
- [ ] D10. Platform directions in German: the importer turns the city's "Konzilstraße, Richtung Bahnhof" into English "Towards Bahnhof". Store the German text (and translate in the app) so the German UI shows "Richtung Bahnhof".
- [ ] D11. **New timetable before release:** the current feed ends on **12.12.2026** (45 days after 28.10.2026). Import the next NVBW feed before the first TestFlight; `check.py` will block a build with less than 30 days left.

---

## Part C — Core logic in Swift (`KGCore`)

Each item: Swift code + Swift Testing tests. Golden tests compare results with the Kotlin app on the same data (T5).

- [x] C1. **Models:** `Station`, `Platform` (with `code`), `Line`, `Trip`, `StopTime`, `Departure`, `Journey`, `Leg` (walk / bus), `Place`, `SearchResult`, `Favorite`, `RecentItem`, `Alarm`. All `Sendable`, `Hashable`.
- [x] C2. **Service-day time** (read as wall-clock times, like the stop signs and the Android app): GTFS times past midnight (e.g. 25:10), the Europe/Berlin time zone, daylight-saving days. Tests on 25.10.2026 (clocks back) and 29.03.2026 (forward).
- [x] C3. **TimetableStore** (GRDB, read-only, opened from the app bundle). Departure query < 20 ms. Real data note: the design's "9A" is line **9** in the timetable; destinations are shortened ("Konstanz Universität" → "Universität"); a trip's arrival at its last stop is not listed as a departure:
  - departures at a station from a given time (all platforms, sorted, with platform code)
  - next 3 times per line and direction at a station (screen 09 "Linien")
  - trip with all stops and times (screen 17)
  - first departure on the next service day to a target (screen 23)
  - lines serving a station (badges in 09)
- [x] C4. **Router:** Connection Scan Algorithm, the same approach and rules as the Android app (walk 80 m/min × 1.25 detour, stations within 15 min, transfers on foot up to 400 m, 1 min to change). Measured: a few ms per plan on the Mac; check on an iPhone 12 in T9. Real data: line 4's "Nachtschwärmer" runs go to Mainau at night (01:44), so screen 23's example time differs for real stops.
  - depart-at and arrive-by searches
  - walking to the first stop and from the last stop; transfers with walking between nearby platforms
  - returns several journeys, ranked as "Schnellste", "Wenig laufen", "Wenig umsteigen"
  - performance: under 150 ms for any Konstanz trip on an iPhone 12 (measured in a test)
- [x] C5. **Walking router:** reads `konstanz-walk.bin`, A* search, turn-by-turn steps with street names ("Rechts in die Bahnhofstraße · 120 m"). Steps carry turn type, street, way kind and distance; the wording is made in the UI (S13). **Better than the Android app:** each end also tries ways within 8 m of the nearest one, so sidewalks mapped beside a street no longer cause loops (a 370 m loop became the 18 m walk). The planner uses it for real walking paths and steps; walking routes may therefore differ from Android in T5.
- [x] C6. **Search** (Android scoring; stations indexed by short name so "Sternenplatz" finds the stop before the street; 2–9 ms per keystroke in release on a Mac, work spread over the CPU cores): reads `places.tsvz` + stations; matches as you type; handles umlauts (ä = ae), "str." = "straße", typos of one letter; ranks stations, places, streets. Returns which part matched (for the bold highlight in screen 08).
- [x] C7. **Reverse lookup:** nearest street name and nearest station to a point (screen 16).
- [ ] C8. **Vehicle positions:** for each running trip, the estimated position along its shape at time t, plus heading. Smooth between stops; waits at stops.
- [ ] C9. **Trip progress:** current stop, stops left, minutes to arrival, progress 0…1 (screen 11, Live Activity).
- [ ] C10. **UserStore** (GRDB, writable, in the App Group container so widgets can read it): favourites (Zuhause, Arbeit, Uni + stops, with order), recent searches, finished trips (for "5 Fahrten diese Woche"), alarms. Nothing leaves the phone.
- [ ] C11. **Mock data** with exactly the design's examples (Sternenplatz; 9A Universität 3 Min.; 1 Staad 6 Min.; 5 Petershausen 11 Min.; route 14:21–14:35) for previews and snapshot tests, behind the same protocols as the real stores.

---

## Part A — Design tokens (`KGDesign`)

### A1. Colours

- [ ] A1.1 Asset catalog colour sets with light + dark values (no hex values in code):
  - Brand: `coral #F05A62 / #FF5A62`, `coralDeep #D1343E`, `coralPressed #C93D45`, `coralTint #FFCDD0`
  - Ink: `ink #000000 / #FFFFFF`, `ink2 #545454 / #E0E0E0`, `ink3 #757575 / #9E9E9E`, `ink4 #9E9E9E / #5A5A5A` (decoration only), `chevron #C7C7CC`
  - Surfaces: `surface #FFFFFF / #181818`, `card #F6F6F6 / #242424`, `pressed #EEEEEE / #2A2A2A`, `line #E2E2E2 / #2D2D2D`, `switchOff #E9E9EB`, `handle #D1D1D6`
  - Status: `live #05944F`, `liveText` (darker, 0.4) `/ #5BD08F`, `liveTint #E6F4EC`, `location #276EF1 / #0A84FF`, `locationTint #E9F0FE`, `warn #FF9500`
  - Lines: `lineFill #FFC043`, `onLine #3A2A00`, `lineTint #FFF4D1`
  - Seeri: `seeriBody #F05A62`, `seeriFace #EAF6FF`, `seeriDark #33283A`, `seeriCheek #FFB3A7`
  - Halloween: `#2A1638`, `#1F0F2C`, `#1A0C24`, `#FFB067`, `#5B3478`, `#FFD9B0`, `#D9C4E8`
- [ ] A1.2 `KGColor` Swift namespace with one static property per colour set (generated by Xcode's asset symbols, checked by lint).
- [ ] A1.3 High-contrast variants for "Increase Contrast" (darker ink3, stronger lines).
- [ ] A1.4 Contrast test: every text/background pair the app uses, in light, dark and high contrast, ≥ 4.5:1 (≥ 3:1 for pairs marked "large only").

### A2. Type

- [ ] A2.1 Bundle **Figtree** (variable font, OFL licence, add licence to the Über screen) and register it in `Info.plist`.
- [ ] A2.2 `KGFont` styles, measured from the design, each tied to a Dynamic Type text style so it grows with the user's setting (`Font.custom(_:size:relativeTo:)`):
  - `hero` 40 Bold (start, "Alles bereit!") → `.largeTitle`
  - `display` 32–34 ExtraBold (onboarding titles) → `.largeTitle`
  - `titleL` 28 Bold ("Favoriten", "Mehr") → `.title`
  - `title` 22 ExtraBold ("In deiner Nähe") → `.title2`
  - `headline` 19 Bold → `.title3`
  - `bodyStrong` 17 Bold / SemiBold → `.headline`
  - `body` 16 Regular → `.body`
  - `callout` 15 SemiBold → `.callout`
  - `footnote` 14 SemiBold (chips, line badges) → `.subheadline`
  - `caption` 13 Medium → `.footnote`
  - `overline` 12 Bold, tracking 1.5, uppercase ("ERGEBNISSE") → `.caption`
  - `tab` 11 Bold → `.caption2`
  - `minutes` 17 ExtraBold, **monospaced digits** (times don't jump when they change)
  - `bigMinutes` 26–44 ExtraBold, monospaced digits
- [ ] A2.3 Preview of every style at default size and at AX3.

### A3. Shape, spacing, shadows

- [ ] A3.1 Radius: 4, 8, 12, 14 (buttons, map buttons), 18 (search bar), 20 (cards, sheet top), capsule. Use `.continuous` corners (iOS look).
- [ ] A3.2 Spacing on a 2/4 pt grid: 4, 6, 8, 10, 12, 14, 16 (screen side margin), 20, 24, 32.
- [ ] A3.3 Sizes: row 44, button 56, search bar 56, map button 48, line badge 26 high (min 36 wide), tab item 96×54, toggle = system.
- [ ] A3.4 Shadow modifiers (two layers where the design has two):
  - `.kgShadowCard` 0/2/8 at 10 %
  - `.kgShadowFloating` 0/4/14 at 12 % (map buttons, chips on the map)
  - `.kgShadowSearch` 0/6/20 at 10 % + 0/1/3 at 8 %
  - `.kgShadowSheet` 0/−8/30 at 12 %
  - `.kgShadowBus` 0/4/10 rgba(120,20,30,.3)
- [ ] A3.5 Dark mode: shadows become a 1 pt `white 8 %` outline.

### A4. Motion

- [ ] A4.1 `KGMotion` with the design's curves and timings as SwiftUI animations:
  - `rise`: 18 pt up + fade, `timingCurve(.2, .8, .2, 1)`, 0.45 s (`k-up`, used 26 times)
  - `sheet`: `timingCurve(.2, .9, .3, 1)`, 0.6 s, from 120 pt below (`k-sheet`)
  - `pop`: scale 0.6 → 1.08 → 1 (`k-pop`), with a `keyframeAnimator`
  - `stagger`: 60 ms between list items
  - `livePulse`: ring scale 1 → 2.6, fade out, 1.3 s loop
  - `locationPulse`: 1 → 3.4, 2.4 s loop
  - `busBob`: 1 pt up and down, 0.5 s loop
  - `seeriPeek`: 6 pt up + −3°, 2.6 s loop
  - `seeriBounce`: squash and stretch (`k-bounce`)
  - `drive`: from −260 pt with tilt, overshoot 8 pt, settle (`k-drive`, 1 s)
  - `typing`: letters appear + blinking caret (`k-type`, `k-caret`)
- [ ] A4.2 **Reduce Motion:** every loop stops, moves become cross-fades. One environment value checked by all components.
- [ ] A4.3 Loops run only while their view is on screen (no battery use in the background).
- [ ] A4.4 Haptics: `.sensoryFeedback` for selection (segmented controls, wheels), success (saved, alarm set), warning (delete).

### A5. Icons

- [ ] A5.1 List every icon in the design (about 45: search, back, close, chevron, star, map, more, layers, locate arrow, walk, bus, swap, bell, accessibility, globe, moon, shield, help, refresh, check, trash, share, home, briefcase, graduation cap, pin, clock, calendar, ferry, train, download, wifi-off, info …).
- [ ] A5.2 Export each from the design's inline SVG into the asset catalog as an SVG symbol image ("Preserve Vector Data", template rendering), so they tint like SF Symbols and stay exactly the design's drawing (stroke 2–2.8, round caps).
- [ ] A5.3 Where the design draws a standard iOS glyph (share, chevron), check if the SF Symbol matches; use the design's version when it doesn't.
- [ ] A5.4 Icon gallery in the design-system screen.

### A6. Seeri, the mascot

- [ ] A6.1 Rebuild Seeri in SwiftUI `Canvas`/`Shape`s from the design's SVG (viewBox 160×170): body, roof, mirrors, face screen, eyes with highlights, mouth, cheeks, headlights, bumper, wheels. Exact coordinates from `Design/Source/`.
- [ ] A6.2 Separate animatable parts: eyes (blink), mouth (smile / open / sleepy / teeth), cheeks, headlights (glow), whole body (bounce, tilt).
- [ ] A6.3 Expressions: `happy`, `excited`, `thinking` (search), `sleepy` (with "z z Z", screen 23), `cheering` (screen 11).
- [ ] A6.4 Hats as overlays: Halloween witch hat (screen 29); later Christmas, Fasnacht, New Year.
- [ ] A6.5 `SeeriView(size:expression:hat:animated:)` + previews of every combination.
- [ ] A6.6 Small logo tile: coral rounded square with the white face and wave line (search bar, widget, app icon).
- [ ] A6.7 Snapshot test of Seeri against the design's SVG rendered at the same size (difference < 1 %).

### A7. App icon and launch

- [ ] A7.1 App icon: coral background, Seeri face. Icon Composer file for iOS 26+ (glass layers, light / dark / tinted / clear) **and** the classic 1024 pt icon with light / dark / tinted for iOS 18–25. Checked on both simulators.
- [ ] A7.2 Launch screen (static, in `Info.plist`): same background colour as the first frame of screen 01, so there is no flash into the animation.

### A8. Theme screen

- [ ] A8.1 Hidden "Design system" screen (debug builds only) = the brand board: logo, Seeri, icons, type, colours, every component in every state. Snapshot-tested against `brand.png`.

---

## Part B — Components (`KGDesign`)

Each component: one file, previews (light, dark, AX3), a snapshot test, VoiceOver label, 44 pt hit area.

- [ ] B1. `KGPrimaryButton`: black fill, white 16 Medium, 56 high, radius 14; pressed: 0.85 opacity + scale 0.98; disabled; loading (spinner, same width).
- [ ] B2. `KGSecondaryButton` (card fill, black text), `KGTextButton` (blue).
- [ ] B3. `KGRoundIconButton`: white + shadow over maps, card fill on surfaces; required `accessibilityLabel`.
- [ ] B4. `KGMapSearchBar`: 56 high, radius 18, magnifier, placeholder "Wohin möchtest du?", Seeri tile right; the whole bar is one button.
- [ ] B5. `KGSearchField`: text field, clear button, "Abbrechen"; focus on appear.
- [ ] B6. `KGLineBadge`: yellow capsule, 26 high, min 36 wide, 14 ExtraBold dark text; S / M / L; VoiceOver "Linie 9A".
- [ ] B7. `KGMinutes`: "3 Min.", "jetzt", or "14:35" after 60 min; monospaced digits; changes with `.contentTransition(.numericText())`; live style only with live data.
- [ ] B8. `KGLiveDot`: 8 pt dot + pulse ring (hidden from VoiceOver).
- [ ] B9. `KGWalkChip`: walking person + "2 Min." in a white capsule.
- [ ] B10. `KGStatusPill` ("Offline bereit"): green check + text, white capsule with shadow.
- [ ] B11. `KGDepartureRow`: badge, destination, optional platform, minutes; 44 high; dividers between rows only. VoiceOver reads one sentence: "Linie 9A nach Universität, Steig A, in 3 Minuten, laut Fahrplan".
- [ ] B12. `KGStopCard`: card fill, radius 20, stop name 17 Bold, walk chip, up to 3 rows.
- [ ] B13. `KGSegmentedControl` ("Abfahrten | Linien", "Jetzt | Abfahrt | Ankunft"): card track, white thumb with shadow that slides (`matchedGeometryEffect`, spring).
- [ ] B14. `KGToggleRow`: label + toggle as one control; toggle tinted `live` green (design `#05944F` on, `#E9E9EB` off).
- [ ] B15. `KGSettingsRow` + `KGSettingsGroup`: coloured icon tile 30 pt (radius 8), title, value, chevron; white rounded group with inset dividers.
- [ ] B16. `KGSectionHeader`: overline style, `ink2`, marked as a header for VoiceOver.
- [ ] B17. Map sheet: native `.sheet` with `presentationDetents` (peek / medium / large), `presentationBackgroundInteraction(.enabled)` so the map stays usable, radius 20, handle 36×5. Check it matches the design's sheet; if the native sheet's look differs too much, a custom sheet with the same three stops.
- [ ] B18. `KGFloatingTabBar`, our own, built from screen 07: pill centred 26 pt above the bottom safe area, 5 pt padding, 3 items of 96×54 "Karte · Favoriten · Mehr", selected item on an `#EEEEEE` capsule with the coral-filled icon, shadow 0/10/30 at 14 % + 0.5 pt inner line. Background via `.kgGlass` (Liquid Glass on 26+, material on 18–25). The system tab bar is hidden; tabs keep their own navigation stacks. Selected capsule slides between items (`matchedGeometryEffect`). VoiceOver: tab trait + "Tab 1 von 3". Hides when the keyboard is up or a sheet is full height.
- [ ] B19. `KGStepDots` ("Schritt 1 von 4"): active dot is a wider black capsule; animated width.
- [ ] B20. `KGTimelineStop`: line, dot, name, time; past (grey), current (coral, pulsing, "jetzt"), coming, last.
- [ ] B21. `KGRouteCard` (screen 10): "14:21 – 14:35", tag ("Schnellste"), "14 Min.", leg strip, note ("Fährt in 3 Min. ab Sternenplatz"); selected = black 2 pt outline.
- [ ] B22. `KGLegStrip`: walk + minutes › line badge › walk; wraps at large text sizes (`ViewThatFits` / flow layout).
- [ ] B23. `KGEmptyState`: Seeri (expression), title, text, buttons.
- [ ] B24. `KGSpeechBubble` ("Ich warte an Steig D!"): white bubble with tail, pops in.
- [ ] B25. `KGToast` (black capsule, white text, optional "Rückgängig").
- [ ] B26. Swipe to delete (screen 18): native `swipeActions` with the red "Löschen", plus the VoiceOver action.
- [ ] B27. `KGMapControls`: layers + location buttons 48×48, radius 14.
- [ ] B28. `KGBusMarker`: coralDeep capsule with 2.5 pt white border, white circle with bus icon, line number, heading arrow behind it, pulse ring, bob. On the map drawn as a MapLibre symbol layer (images cached per line) so 50 buses stay smooth; the SwiftUI version is for previews and the design-system screen.
- [ ] B29. `KGUserDot`: blue 24 pt, 4 pt white border, pulse ring, heading cone.
- [ ] B30. `KGStopMarker`: white circle with 3.5 pt coral ring; bigger and labelled when selected.
- [ ] B31. `KGDayStrip` + `KGTimeWheel` (screen 19): day chips that snap; hour and 5-minute wheels (`Picker(.wheel)` styled, or a custom wheel if the native one can't match).

---

## Part M — Map (MapLibre, used by screens 07, 15, 16, 21, 22, 11)

- [ ] M1. `KGMapView` (`UIViewRepresentable` around MapLibre) loading `konstanz.pmtiles` and the style from the bundle; no network.
- [ ] M2. Light / dark style follows the system and the "Darstellung" setting, without losing the camera position.
- [ ] M3. Camera: starts on Konstanz (bbox 47.645–47.725 N, 9.08–9.23 E), limits panning to the region, zoom 12–18.
- [ ] M4. Stops layer (`KGStopMarker`) from zoom 14, labels from 16; tap → screen 09.
- [ ] M5. Buses layer: positions from C8 updated every second with smooth movement; tap → screen 17.
- [ ] M6. User location (CoreLocation) with `KGUserDot`; follow mode with heading.
- [ ] M7. Route layer: bus parts coral with white casing, walk parts dotted; start, transfer and end markers.
- [ ] M8. Long-press → drop pin (screen 16).
- [ ] M9. Insets: the map knows the sheet height and the search bar, so "fit route" and "my location" keep things visible.
- [ ] M10. Performance: 60 fps (120 on ProMotion) with all buses visible, measured with Instruments; a screenshot of the trace in the commit.

---

## Part S — Screens

For every screen: (1) write its spec sheet (0.5.3), (2) build with mock data, (3) snapshot test vs. the artboard, (4) connect real data, (5) all states, (6) VoiceOver + Dynamic Type check, (7) dark mode check.

### S1. Start (01)

- [ ] S1.1 Background, scenery, Seeri drives in (`drive`), wordmark "Konstanz" + coral "Go" tag rises in, tagline "Dein Bus durch Konstanz". Exact timings from `SeerotLaunch.dc.html`.
- [ ] S1.2 Meanwhile: open the timetable, warm the map. Leave when both the animation minimum (~1.6 s) and loading are done.
- [ ] S1.3 Tap skips ahead.
- [ ] S1.4 Later launches: short version (~0.7 s) or straight to the map (decide by trying both).
- [ ] S1.5 Reduce Motion: still image + fade.

### S2. Seasonal start (29)

- [ ] S2.1 Halloween exactly as the design: night `#2A1638`, moon `#FFB067` rising, town silhouette with glowing windows, two bats flapping across, wave, Seeri with witch hat and glowing headlights, "Schaurig schöne Fahrt!", "Halloween · 31. Oktober".
- [ ] S2.2 Calendar of events (Halloween, Christmas, New Year, Fasnacht with its moving date) in `KGCore` + tests.
- [ ] S2.3 Other events in the same style once Halloween is approved.
- [ ] S2.4 Switch to turn seasonal starts off (Mehr › Darstellung).

### S3. Onboarding (02–06)

- [ ] S3.1 Shared scaffold: back button, `KGStepDots`, illustration area, title, feature rows, bottom buttons; swipe between steps; content rises in with `stagger`.
- [ ] S3.2 **02 Willkommen:** Seeri with speech bubble "Hallo! Ich bin Seeri und bring dich durch ganz Konstanz.", "Willkommen bei KonstanzGo", "Los geht's".
- [ ] S3.3 **03 Offline:** "Kein Netz? Kein Problem!", animated illustration, rows "Offline-Karte · Ganz Konstanz, auch ohne Internet" and "Alle Haltestellen · Jede Linie, jeder Fahrplan", "Weiter".
- [ ] S3.4 **04 Suchen:** "Sag mir, wohin du willst.", search field typing "Universität", result row, departure with ticking minutes; rows "Schnell finden · Haltestellen, Straßen und Orte" and the departures row (reworded to "Abfahrten auf einen Blick" while there is no live data, 0.3).
- [ ] S3.5 **05 Standort & Mitteilungen:** "Soll ich dir sagen, wann ich komme?", sample notification "Dein Bus 9A kommt in 3 Min.", two toggles, "Später" / "Erlauben".
  - "Erlauben" asks for location (When In Use) and then notifications, only for the toggles that are on.
  - Refused → toggle off, carry on. Approximate location must also work.
- [ ] S3.6 **06 Alles bereit:** Seeri happy, "Alles bereit!", "Gute Fahrt durch Konstanz.", checks "Offline gespeichert" and "Alarme an" (only if allowed), "Losfahren" → map.
- [ ] S3.7 Shown once (saved in `UserDefaults`); progress kept if the app is closed in the middle.
- [ ] S3.8 UI test: allow both / refuse both.

### S4. Karte (07) and Dunkelmodus (28)

- [ ] S4.1 Map full screen under the status bar; `KGMapSearchBar` 16 pt from the sides, 14 pt under the safe area.
- [ ] S4.2 "Offline bereit" pill under it → screen 24; turns orange "Fahrplan endet bald" in the last 14 days of the data.
- [ ] S4.3 Map buttons on the right (layers, my location); they move up with the sheet.
- [ ] S4.4 Layers menu: buses (geschätzt) on/off, stops on/off, map style.
- [ ] S4.5 Sheet "In deiner Nähe" + "Alle": nearest `KGStopCard`, updates every 30 s; pull up for more stops.
- [ ] S4.6 Seeri peeking over the sheet's top right edge (only when the sheet is at rest).
- [ ] S4.7 States: no location permission (card with "Standort erlauben"); outside Konstanz; loading; no buses tonight ("Heute fährt hier nichts mehr · Erster Bus 05:42").
- [ ] S4.8 Dark version compared with screen 28.

### S5. Suche (08)

- [ ] S5.1 Search field focused on open, "Abbrechen".
- [ ] S5.2 Quick chips: Zuhause, Arbeit, Uni (no address → set it).
- [ ] S5.3 "ERGEBNISSE": stations (with line badges), places, streets; matched part bold ("**Uni**versität").
- [ ] S5.4 "ZULETZT" when empty.
- [ ] S5.5 Tip card "Tipp: Halte eine Haltestelle gedrückt, um sie zu merken." + long-press saves (haptic + toast).
- [ ] S5.6 Routing: station → 09, place → 15, street → 16.
- [ ] S5.7 No results: Seeri thinking + "Nichts gefunden für …".

### S6. Haltestelle (09)

- [ ] S6.1 Header: small map strip, back, favourite star, view button; "Sternenplatz", "Haltestelle · 2 Min. zu Fuß", badges of all lines.
- [ ] S6.2 Segmented "Abfahrten | Linien".
- [ ] S6.3 Abfahrten: badge, destination, "Steig A", big minutes; refresh each 30 s; departed rows slide out.
- [ ] S6.4 Linien: "Richtung Universität · 14:21 · 14:36 · 14:51" per line and direction.
- [ ] S6.5 "Alarm stellen" → choose minutes → becomes "Alarm 2 Min. vorher" (bell). Scheduling in X1.
- [ ] S6.6 Tap a departure → 17. States: nothing today, end of data.

### S7. Ort (15) and Pin gesetzt (16)

- [ ] S7.1 **15:** map header, "Konzil", "Hafenstraße 2 · Veranstaltungsort", "4 Min. zu Fuß", area; "Merken", "Teilen"; "HALTESTELLEN IN DER NÄHE" with distance, line, minutes; "Route hierher".
- [ ] S7.2 **16:** pin drops with a bounce + haptic, can be dragged; "Pin gesetzt · Gedrückt halten zum Verschieben"; "Markierter Ort", street name, "47,66° N · 9,18° O"; nearest station card; "Als Zuhause", "Merken", "Route hierher".

### S8. Abfahrtsdetails (17)

- [ ] S8.1 Back "Sternenplatz"; badge, "Bus 9A", "Richtung Universität"; share.
- [ ] S8.2 Card: "Abfahrt Sternenplatz 14:35", "Steig D", status, "in 4 Min. · 17 Min. Fahrt".
- [ ] S8.3 "HALTESTELLEN" timeline with the estimated bus between stops.
- [ ] S8.4 "Auf der Karte" → 21. Share = `ShareLink` with plain text.

### S9. Wann & wie (19)

- [ ] S9.1 Sheet with close, "Wann & wie".
- [ ] S9.2 Segmented "Jetzt | Abfahrt | Ankunft".
- [ ] S9.3 Day strip "Mo 26. Okt. … Fr 30. Okt." with "Heute"; time wheels (hours, 5-minute steps).
- [ ] S9.4 "BEVORZUGEN": Schnellste / Wenig laufen / Wenig umsteigen cards (one chosen, black outline).
- [ ] S9.5 Barrierefrei (only with data, 0.3).
- [ ] S9.6 Button text follows the choice: "Jetzt suchen" / "Ab heute 15:00 suchen" / "Ankunft heute 15:00 suchen".

### S10. Suche läuft (20)

- [ ] S10.1 "Mein Standort → Universität", "Heute · ab 15:00 · Schnellste"; Seeri thinking with bouncing dots, "Seeri sucht deine Verbindung".
- [ ] S10.2 Only shown if the search takes > 300 ms; once shown, stays ≥ 600 ms (no flicker).

### S11. Verbindungen (10)

- [ ] S11.1 Back, "Verbindungen", Von / Nach fields + swap button (rotates on tap).
- [ ] S11.2 Chips "Jetzt" (→ 19), "Später", "Barrierefrei".
- [ ] S11.3 `KGRouteCard` list, tags from comparing the results; first one selected; minutes until departure tick.
- [ ] S11.4 "Los geht's" → 21 (or straight to 11; try both).
- [ ] S11.5 "Später" loads more at the end.

### S12. Route auf Karte (21)

- [ ] S12.1 Map fitted to the route above the sheet; the trip's bus moving.
- [ ] S12.2 Sheet: "14 Min. · 14:21 – 14:35", legs (walk 2 Min. · 9A 10 Min. · walk 2 Min.), "Fußweg zum Sternenplatz" → 22, "Los geht's" → 11.

### S13. Fußweg (22)

- [ ] S13.1 Map with the path and the user dot; Seeri at the stop: "Ich warte an Steig D!".
- [ ] S13.2 Big next step "120 m · Rechts in die Bahnhofstraße".
- [ ] S13.3 Sheet: "Fußweg zum Sternenplatz · 3 Min. · 220 m · 14:18 – 14:21" + step list; current step follows the user.
- [ ] S13.4 Last step "Ankunft Sternenplatz · Steig D · Bus 9A um 14:21".

### S14. Keine Verbindung (23)

- [ ] S14.1 Seeri sleepy + "z z Z"; "Keine Verbindung gefunden"; "Um 01:30 fährt leider kein Bus zur Insel Mainau. Seeri schläft gerade."
- [ ] S14.2 Green chip "Erster Bus morgen um 05:42" → search at that time.
- [ ] S14.3 "Ziel ändern", "Andere Zeit wählen".
- [ ] S14.4 Other reasons with their own text: start = target, target far from any stop, date outside the timetable.

### S15. Unterwegs (11)

- [ ] S15.1 Map with the bus and the rest of the route; "Fahrt beenden".
- [ ] S15.2 Card: badge, "Universität", Seeri cheering "Noch 4 Haltestellen!", "11 Min.", "Ankunft 14:35"; progress bar; VoiceOver "Fahrtfortschritt, 4 von 8 Haltestellen".
- [ ] S15.3 Timeline past / "jetzt" / coming, auto-scrolls.
- [ ] S15.4 Phases: walk to stop → wait → ride → change → walk → arrived ("Du bist da!", trip saved for the widget).
- [ ] S15.5 Progress uses the timetable and, when available, the user's position on the route (so it stays right when the bus is late).
- [ ] S15.6 "Auf den Sperrbildschirm" starts the Live Activity (X2).

### S16. Favoriten (12) and Zuletzt (18)

- [ ] S16.1 **12:** "Favoriten" + "Bearbeiten"; "SCHNELL LOS": Zuhause / Uni / Arbeit cards with line, duration and black "Los"; "Noch keine Adresse · Festlegen".
- [ ] S16.2 "MEINE HALTESTELLEN" with next 2 lines and ticking minutes ("LIVE" tag only with live data).
- [ ] S16.3 "Zuletzt gesucht" with count → 18.
- [ ] S16.4 Edit mode: reorder, delete, rename. Empty state with Seeri.
- [ ] S16.5 **18:** back "Favoriten", "Alle löschen" (confirm); list with type and date ("Haltestelle · Heute", "Ort · Gestern", "21. Okt."); swipe to delete + undo; footer "Nach links wischen zum Löschen. Dein Verlauf bleibt nur auf diesem iPhone."

### S17. Mehr (13), Offline-Daten (24), Datenschutz (25)

- [ ] S17.1 **13:** "Mehr"; offline card on top; group: Mitteilungen (toggle), Abfahrtsalarm ("2 Min. vorher"), Barrierefreie Wege (with data); group: Sprache (opens the app's page in iOS Settings, the iOS way to change one app's language), Darstellung (Automatisch / Hell / Dunkel + seasonal toggle); group: Datenschutz, Hilfe & Feedback, Über (sources, licences, "not an official app"); footer "KonstanzGo · Version 1.0".
- [ ] S17.2 Mitteilungen on while refused in iOS → opens the app's notification settings.
- [ ] S17.3 **24:** total size (real, computed), "Alles aktuell · Bereit ohne Netz", data date, parts (Karte / Fahrpläne / Haltestellen) with real sizes, "GEBIETE" with the bundled area (Konstanz Stadt). No download, auto-update or "Jetzt aktualisieren" controls. When the timetable ends within 14 days: "Fahrplan endet bald · Bitte App aktualisieren".
- [ ] S17.3a The offline card on **13** shows the same status, with no refresh button.
- [ ] S17.4 **25:** "Deine Daten bleiben bei dir"; the three promises; no analytics/crash toggles; "Datenschutzerklärung lesen" (bundled, in-app); "Verlauf löschen" (confirm).

---

## Part X — iPhone extras (14, 26, 27, alarms)

### X1. Departure alarms

- [ ] X1.1 Local notifications (`UNCalendarNotificationTrigger`) "Dein Bus 9A kommt in 2 Min. · Sternenplatz, Steig D", time-sensitive interruption level (with the entitlement).
- [ ] X1.2 Actions "Route", "Erledigt".
- [ ] X1.3 iOS keeps at most 64 pending notifications: keep only the next ones scheduled, top up when the app opens.
- [ ] X1.4 Past alarms removed automatically. Tests with a fixed clock.

### X2. Live Activity and Dynamic Island (14)

- [ ] X2.1 `ActivityAttributes`: line, target, stops list. `ContentState`: current stop, stops left, arrival date.
- [ ] X2.2 Lock screen view as the design: "Sternenplatz", badge 9A, "Universität", big "11 Min.", "Noch 4 Haltestellen", "Ankunft 14:35", progress bar.
- [ ] X2.3 Dynamic Island: compact (badge + minutes), minimal (badge), expanded (as lock screen, smaller).
- [ ] X2.4 Minutes and progress count down on their own with `Text(timerInterval:)` and `ProgressView(timerInterval:)`, so they stay right even when the app is asleep.
- [ ] X2.5 Stop changes: updated by the app while the trip runs, using background location (Background Modes › location, only during an active trip; the reason is written in `Info.plist` and in the App Review notes).
- [ ] X2.6 Ends at arrival or "Fahrt beenden"; stale after 2 hours.
- [ ] X2.7 Tap opens screen 11.

### X3. Widgets (26), WidgetKit

- [ ] X3.1 **Haltestelle (medium):** stop name, next 3 departures with badges and minutes; the stop is chosen in the widget's edit menu (App Intent configuration, favourites first).
- [ ] X3.2 **Nach Hause (small):** "Nach Hause · 18 Min. · Bus 1 · ab 14:24".
- [ ] X3.3 **Fahrten (small):** Seeri + "5 Fahrten diese Woche".
- [ ] X3.4 Lock-screen widgets: next departure at a favourite stop (circular, rectangular, inline).
- [ ] X3.5 Timelines built from the offline timetable: one entry per departure for the next hours, minutes shown with `Text(date, style: .relative)`, so no network or app wake-up is needed.
- [ ] X3.6 Data shared through the App Group (timetable in the shared container, user store readable).
- [ ] X3.7 Light, dark and tinted appearances on iOS 18+, plus the clear look on iOS 26+; widget gallery previews.
- [ ] X3.8 Taps open the right screen (deep links `konstanzgo://stop/<id>`, `konstanzgo://route/home`).

### X4. Siri, Spotlight and Shortcuts (27)

- [ ] X4.1 App Intents: "Wann kommt mein Bus?", "Bus nach Hause", "Weg zur Uni", "Abfahrten an <Haltestelle>".
- [ ] X4.2 `AppShortcutsProvider` with German and English phrases, so they work without setup.
- [ ] X4.3 Spoken answer + snippet view as in the design: "Dein Bus 9A kommt in 3 Minuten an der Haltestelle Sternenplatz."
- [ ] X4.4 Stops and favourites as `AppEntity` + `IndexedEntity`, so they show up in Spotlight ("Nächster Bus nach Hause · KonstanzGo · Linie 1 ab Sternenplatz · in 6 Min." with a "Starten" button).
- [ ] X4.5 Action button and Control Center control (iOS 18+): "Nächster Bus".

---

## Part L — Language and polish

- [ ] L1. All German text exactly as in the design; English written in the same friendly tone, Seeri speaking in first person.
- [ ] L2. Plurals with String Catalog variations ("1 Haltestelle" / "4 Haltestellen").
- [ ] L3. Dates and times with the user's locale (24 h in German, "Mi., 28. Okt.").
- [ ] L4. Motion pass on every screen against the recorded design videos (0.5.4).
- [ ] L5. Haptics pass (only where A4.4 says).
- [ ] L6. Dark-mode pass on every screen.

---

## Part T — Quality gates

- [ ] T1. **Snapshot tests**: every screen × light/dark × German/English × default text size and AX3, on iPhone 17e (390×844, same as the design), on **iOS 18 and iOS 27** (two reference image sets). Plus iPhone SE (375×667), iPhone 17 (402×874) and iPhone 17 Pro Max (440×956) for layout only.
- [ ] T2. **Design diff**: for each screen, overlay the app screenshot on the artboard PNG (50 % opacity) and save it in `Design/Diff/`; every visible difference is fixed or explained.
- [ ] T3. **VoiceOver** walk through every screen: every control named, headers marked, order logical; departure rows read as one sentence.
- [ ] T4. **Dynamic Type** up to AX5, Bold Text, Increase Contrast, Reduce Transparency (glass becomes solid), Reduce Motion, Smart Invert: all screens checked.
- [ ] T5. **Golden tests vs. the Android app**: the same 50 searches (stations, times, days) give the same departures and journeys in Swift and Kotlin. The expected results are exported once from the Kotlin tests into JSON.
- [ ] T6. **Unit tests** for all of `KGCore` (target: 90 % line coverage there).
- [ ] T7. **UI tests** for the main flows: onboarding → map → search → stop → alarm; map → plan → route → journey → arrived; favourites edit; history delete.
- [ ] T8. **SwiftLint**: no hex colours, raw font names or magic numbers outside `KGDesign`; no force unwraps in `KGCore`.
- [ ] T9. **Performance** (Instruments): launch to first frame < 400 ms; map 60/120 fps with buses; search results < 50 ms per keystroke; memory < 150 MB on the map.
- [ ] T10. **Battery**: no location or animation work in the background except during an active trip.
- [ ] T11. **Real devices**: an older iPhone on iOS 18 (e.g. an XS/XR, the oldest models iOS 18 runs on) and a current Pro on iOS 27; test outdoors in Konstanz for location, the walking guide and the Live Activity.

---

## Part R — Release

- [ ] R1. App Store Connect record: name, bundle ID, category Navigation, age rating.
- [ ] R2. Privacy label "Data Not Collected"; privacy policy page; Privacy Manifest (`PrivacyInfo.xcprivacy`) with the required-reason APIs used (`UserDefaults`, file timestamps).
- [ ] R3. Attribution: NVBW timetable licence (dl-de/by-2-0), OpenStreetMap, Protomaps, Figtree (OFL), MapLibre, GRDB — on the Über screen and in the store text.
- [ ] R4. Screenshots for 6.9" and 6.3" made from the snapshot tests, with captions in the brand style; app preview video from the start animation.
- [ ] R5. Review notes: why background location (only during a trip, for the Live Activity), and that the app is not the official operator's app.
- [ ] R6. TestFlight internal → external with bus riders in Konstanz → fixes → release.

---

## Order of work (milestones)

1. **M0 Setup:** part 0, P, D. Result: an empty app that builds, with all data bundled.
2. **M1 Foundation:** C (core logic, tested), A, B, the design-system screen. Result: brand board and components match the design.
3. **M2 First look:** M (map), S1–S4. Result: start, onboarding and the map look exactly like the design.
4. **M3 Core use:** S5–S14. Result: search → stop → plan → route work end to end.
5. **M4 On the way:** S15, X1, X2. Result: journey screen, alarms, Live Activity.
6. **M5 Everything else:** S16, S17, X3, X4. Result: every artboard is built.
7. **M6 Polish and release:** L, T, R.

Each milestone ends with a full design diff (T2) before the next starts.
