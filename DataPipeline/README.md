# Data pipeline

Builds the offline data the app ships (timetable, places, search index, walking network, map style)
into `App/Resources/Data/`. File formats: [FORMATS.md](FORMATS.md).

```sh
DataPipeline/build.sh
```

The first run creates `.venv/` with the two Python packages the place importer needs
(`requirements.txt`). The whole run takes about 5 seconds and ends with `check.py`, which fails if a
file is missing, a table is empty, or the timetable ends within 30 days.

## Inputs

They are not in git (each tool's `data/` folder is ignored). Get them like this:

| Input | Where from |
|---|---|
| `gtfs-import/data/vhb.zip` | NVBW open data, GTFS for Verkehrsverbund Hegau-Bodensee: https://www.nvbw.de/open-data/fahrplandaten/fahrplandaten-mit-liniennetz |
| `gtfs-import/data/bushaltestellen_konstanz.geojson` | City of Konstanz bus stop register (open data portal) |
| `map/data/konstanz.pmtiles` | `pmtiles extract https://build.protomaps.com/<yyyymmdd>.pmtiles konstanz.pmtiles --bbox=9.05,47.63,9.26,47.74 --maxzoom=15` |
| `walk-graph/data/ways.json` | `python3 DataPipeline/walk-graph/fetch_osm.py` (Overpass, about 2 min) |
| `places-import/data/search-osm.json` | `python3 DataPipeline/places-import/fetch_search_osm.py` (Overpass) |

`gtfs-import/l219_closure.py` adds the line changes for the L219 closure from 26 Oct 2026 that the
feed does not contain yet. Remove it once a feed with the new lines is imported.

## Updating the timetable

1. Download the new `vhb.zip` into `gtfs-import/data/`.
2. Run `DataPipeline/build.sh`.
3. Commit the changed files in `App/Resources/Data/` and `gtfs-import/station_ids.json`. That file keeps
   each stop's number across timetables, because favourites and alarms on phones store those numbers.

If the timetable has under 30 days left, `check.py` fails the build. For an emergency build, run
`check.py --allow-short-validity` after the other steps.

## Publishing without an app release

The app can download a new timetable, search index and walking network (the map stays in the app).

```sh
DataPipeline/.venv/bin/python DataPipeline/publish.py keygen   # once; back up ~/.konstanzgo
DataPipeline/.venv/bin/python DataPipeline/publish.py data
DataPipeline/.venv/bin/python DataPipeline/publish.py config path/to/config.json
```

Upload `DataPipeline/publish/out/` to the host, the numbered folder first and `manifest.*` last. The app checks
at most once a day, verifies the signature and hashes, opens the new database to test it, and uses the set from
its next launch. A set that doesn't start is dropped automatically. The host address goes in `DataHost.base`
(`KGCore/Data/DataSync.swift`); while it is nil, the app makes no such requests.

`config.json` switches things off without a release; every field is optional:

```json
{"liveEnabled": true, "stopReadSeconds": 30, "bannerID": "2026-12-a", "bannerDE": "…", "bannerEN": "…"}
```

## Feed watch

`check_feed.py` runs daily in `.github/workflows/feed-watch.yml`. It opens a GitHub issue when NVBW publishes a
newer file, and when the timetable has 30, 14 or 7 days left.

## Licences

- Timetable: "Datensatz der NVBW GmbH", Datenlizenz Deutschland – Namensnennung – Version 2.0
- Map, places, streets, walking network: © OpenStreetMap contributors, ODbL (via Protomaps)
