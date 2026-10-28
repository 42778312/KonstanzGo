# KonstanzGo (iOS)

Offline bus app for Konstanz: map, departures, trip planning and walking directions, all without
internet. Written in Swift and SwiftUI for iOS 18 and newer. Seeri, the little red bus, shows the way.

Not an official app of Stadtwerke Konstanz or NVBW. The build plan is in [PLAN.md](PLAN.md).

## Getting started

Requirements: Xcode 27.1 or newer, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and
[SwiftLint](https://github.com/realm/SwiftLint) (`brew install xcodegen swiftlint`).

```sh
xcodegen                 # writes KonstanzGo.xcodeproj from project.yml (not in git)
open KonstanzGo.xcodeproj
```

Run on the **iPhone 17e** simulator: its screen is 390×844 pt, the same as the design frames.

## Layout

| Folder | What |
|---|---|
| `App/` | The app target: entry point, assets, string catalogs, bundled data (`Resources/Data/`) |
| `Widgets/` | Widget extension: home and lock screen widgets, Live Activity |
| `Packages/KonstanzKit/` | `KGCore` (data and logic), `KGDesign` (look), `KGFeatures` (screens) |
| `Tests/` | App unit tests, snapshot tests, UI tests (package tests live in the package) |
| `DataPipeline/` | Python tools that build the offline data ([README](DataPipeline/README.md)) |
| `Design/` | The design's sources, reference images and per-screen specs ([README](Design/README.md)) |

## Tests

```sh
swift test --package-path Packages/KonstanzKit       # core logic, on macOS, seconds
xcodebuild test -scheme KonstanzGo -destination 'platform=iOS Simulator,name=iPhone 17e'
```

## Data

Timetable: "Datensatz der NVBW GmbH", Datenlizenz Deutschland – Namensnennung – Version 2.0.
Map, places and walking network: © OpenStreetMap contributors (ODbL), via Protomaps.
