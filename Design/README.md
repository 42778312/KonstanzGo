# Design reference

Source: https://claude.ai/artifact/GtvRYmP3LA5RMZpjKAVD9x (canvas "KonstanzGo"), copied on 28.10.2026.
The files in `Source/` are read-only copies; the canvas stays the source of truth. If the design changes, copy them again.

- `Source/` — each artboard's HTML (exact sizes, colours, fonts, animation timings) and `canvas.json` (layout).
- `Reference/` — each artboard as a PNG, for the side-by-side and overlay checks (plan rule 3, T2).
- `Spec/` — one spec sheet per screen, written just before the screen is built (plan 0.5.3).

## Screens (page "KonstanzGo")

| Screen | File | Size | Interactive |
|---|---|---|---|
| 01 Start | `SeerotLaunch.dc.html` | 390×844 | yes |
| 02 Willkommen | `SeerotWelcome.dc.html` | 390×844 | yes |
| 03 Offline-Karte & Haltestellen | `SeerotOffline.dc.html` | 390×844 | yes |
| 04 Suchen & Live-Abfahrten | `SeerotSearch.dc.html` | 390×844 | yes |
| 05 Standort & Mitteilungen | `SeerotLocation.dc.html` | 390×844 | yes |
| 06 Alles bereit | `SeerotReady.dc.html` | 390×844 | yes |
| 07 Karte | `AppMap.dc.html` | 390×844 | yes |
| 08 Suche | `AppSearch.dc.html` | 390×844 | yes |
| 09 Haltestelle | `AppStop.dc.html` | 390×844 | yes |
| 10 Verbindungen | `AppRoutes.dc.html` | 390×844 | yes |
| 11 Unterwegs | `AppJourney.dc.html` | 390×844 | yes |
| 12 Favoriten | `AppSaved.dc.html` | 390×844 | yes |
| 13 Mehr | `AppMore.dc.html` | 390×844 | yes |
| 14 Live-Aktivität | `AppLive.dc.html` | 390×844 |  |
| 15 Ort | `AppPlace.dc.html` | 390×844 | yes |
| 16 Pin gesetzt | `AppPin.dc.html` | 390×844 | yes |
| 17 Abfahrtsdetails | `AppTrip.dc.html` | 390×844 | yes |
| 18 Zuletzt | `AppRecent.dc.html` | 390×844 | yes |
| 19 Wann & wie | `AppWhen.dc.html` | 390×844 | yes |
| 20 Suche läuft | `AppFinding.dc.html` | 390×844 | yes |
| 21 Route auf Karte | `AppRouteMap.dc.html` | 390×844 | yes |
| 22 Fußweg | `AppWalk.dc.html` | 390×844 | yes |
| 23 Keine Verbindung | `AppNoRoute.dc.html` | 390×844 | yes |
| 24 Offline-Daten | `AppOffline.dc.html` | 390×844 | yes |
| 25 Datenschutz | `AppPrivacy.dc.html` | 390×844 | yes |
| 26 Widgets | `AppWidgets.dc.html` | 390×844 |  |
| 27 Siri & Spotlight | `AppSiri.dc.html` | 390×844 |  |
| 28 Dunkelmodus | `AppDark.dc.html` | 390×844 | yes |
| 29 Saisonaler Start | `AppHalloween.dc.html` | 390×844 | yes |
| KonstanzGo Marke | `SeerotBrand.dc.html` | 1200×760 |  |

## Old draft (page "First draft (Seelinie)", not built)

| Screen | File |
|---|---|
| Launch animation | `Main.dc.html` |
| Onboarding: offline map, search, ride | `Onboarding.dc.html` |
