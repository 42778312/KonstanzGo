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
3. Commit the changed files in `App/Resources/Data/`.

## Licences

- Timetable: "Datensatz der NVBW GmbH", Datenlizenz Deutschland – Namensnennung – Version 2.0
- Map, places, streets, walking network: © OpenStreetMap contributors, ODbL (via Protomaps)
