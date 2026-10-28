# Data formats

Everything the app reads lives in `App/Resources/Data/` and is built by `DataPipeline/build.sh`.

| File | Size | Built by |
|---|---|---|
| `timetable.db` | 3.6 MB | `gtfs-import/import_gtfs.py`, then `places-import/import_places.py` |
| `search/places.tsvz` | 0.5 MB | `places-import/build_search.py` |
| `walk/konstanz-walk.bin` | 1.5 MB | `walk-graph/build_graph.py` |
| `map/konstanz.pmtiles` | 6.9 MB | copied from `map/data/` (Protomaps extract) |
| `map/style.json` | 40 KB | `map/make_style.py` |
| `map/fonts/<fontstack>/<range>.pbf` | 0.8 MB | copied once (MapLibre glyphs, Noto Sans) |

## timetable.db (SQLite, read-only in the app)

Schema version 4 (`PRAGMA user_version`), from `gtfs-import/schema/4.json`.

| Table | Columns | Notes |
|---|---|---|
| `station` | id, name, short_name, lat, lon, search_name | One per stop area ("Sternenplatz"). `search_name` is lower case without accents. |
| `platform` | id, station_id, gtfs_id, code, lat, lon, direction | One per boarding point. `code` is the platform letter or number ("A", "1"), may be empty. `direction` is an **English** label ("Towards Bahnhof") from the city's stop register, may be empty. |
| `route` | id, gtfs_id, short_name, long_name, type, agency, is_city | `short_name` is the line number ("9A"). `is_city = 1` for the Konstanz city lines. |
| `trip` | id, gtfs_id, route_id, service_id, headsign, direction, shape_id | `headsign` is the destination shown on the bus. |
| `stop_time` | trip_id, seq, platform_id, arrival, departure | Times are **minutes after midnight of the service day**; values ≥ 1440 are after midnight (1671 = 27:51 = 03:51 next day). Index on (platform_id, departure). |
| `service_date` | service_id, date | `date` is `yyyymmdd` as an integer. A trip runs on the dates of its service_id. |
| `shape` | id, points | Google encoded polyline, precision 1e-5. |
| `place` | id, slug, name, kind, detail, area, lat, lon, search_name, rank | Kind: Venue, Station, Harbour, Library, Square, University, Street, District, Town. |
| `street_point` | id, place_id, lat, lon | Points along streets (for "nearest street" and street search). |
| `meta` | key, value | feed_version, feed_start, feed_end (yyyymmdd), built_at, attribution, license, license_url, source_url, bbox, places_source. |

Times are local time in Europe/Berlin. On the days the clocks change, a service day is still counted from midnight.

## search/places.tsvz

gzip of UTF-8 text, one entry per line, tab-separated:

```
id  name  group  category  area  lat  lon  rank  keywords  address  category_de
```

Groups: Address, Street, Shop, Culture, Service, Food, District, Transport, Health, Leisure, Park, Hotel,
Education, Cafe, University, Town, Square. `keywords` holds English and German search words.
Entries that are also in `timetable.db`'s `place` table use the same id.

## walk/konstanz-walk.bin

Big-endian binary.

```
"KWG1"                                   4 bytes, magic
Int32 nNames
nNames × (UInt16 byteLength, UTF-8 bytes)
Int32 nVertices
nVertices × (Int32 latE7, Int32 lonE7)   degrees × 10^7
Int32 nEdges
nEdges × (
    Int32 a, Int32 b                     vertex indexes
    Int32 nameIndex                      -1 = no name
    Int8  kind                           way kind (see build_graph.py)
    Int8  flags
    Int32 lengthCm
    Int16 nShape
    nShape × (Int32 latE7, Int32 lonE7)  points between a and b
)
```

Current size: 29,277 vertices, 37,861 edges, 1,564 street names.

## map/style.json

MapLibre style. Sources and glyphs use `asset://` URLs (Android); the iOS app replaces
`asset://` with the file URL of `Data/` in the app bundle when it loads the style.
