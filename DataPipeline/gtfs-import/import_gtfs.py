#!/usr/bin/env python3
"""
Builds App/Resources/Data/timetable.db from the NVBW GTFS feed (Verkehrsverbund Hegau-Bodensee).

    python3 DataPipeline/gtfs-import/import_gtfs.py [path/to/vhb.zip] [path/to/output.db]

Keeps only the Konstanz area (BBOX): stops inside it and the trips calling at two or more of them.
Tables are created from the schema in DataPipeline/gtfs-import/schema/<version>.json (first written by the Android app),
so the file always matches what the app expects.

Then fill the place tables (they start empty): DataPipeline/places-import/import_places.py.

Data: "Datensatz der NVBW GmbH", Datenlizenz Deutschland – Namensnennung – Version 2.0.
"""
import csv
import datetime
import io
import json
import math
import re
import sqlite3
import sys
import unicodedata
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

import l219_closure
import station_ids

ROOT = Path(__file__).resolve().parents[2]
FEED = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "DataPipeline/gtfs-import/data/vhb.zip"
# City of Konstanz stop register (optional): platform directions, surveyed positions, full names.
CITY_STOPS = ROOT / "DataPipeline/gtfs-import/data/bushaltestellen_konstanz.geojson"
SCHEMA_DIR = Path(__file__).resolve().parent / "schema"
SHIPPED = ROOT / "App/Resources/Data/timetable.db"
OUT = Path(sys.argv[2]) if len(sys.argv) > 2 else SHIPPED

# Konstanz with Wollmatingen, Dettingen, Litzelstetten, Mainau, Staad and Kreuzlingen.
SOUTH, NORTH, WEST, EAST = 47.645, 47.725, 9.08, 9.23
CITY_AGENCY = "vhb-SW-KN"  # Stadtwerke Konstanz city buses
SKIP_AGENCIES = {"bus-8533"}  # long-distance coaches, not local transit
TOWN_PREFIX = "Konstanz "


def read(zf, name):
    with zf.open(name) as f:
        yield from csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig"))


LINE_GAP = re.compile(r"^([A-Z]+)\s+(\d+)$")


def line_name(short):
    """The feed spells some lines two ways ("S 6" / "S6", "RE 2" / "RE2"): one spelling, no gap."""
    return LINE_GAP.sub(r"\1\2", short.strip())


def minutes(hms):
    h, m, _ = hms.split(":")
    return int(h) * 60 + int(m)


def fold(text):
    text = text.lower().replace("ß", "ss")
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def station_key(stop):
    if stop["parent_station"]:
        return stop["parent_station"]
    parts = stop["stop_id"].split(":")
    # DHIDs "de:08335:11925:1:2" → stop area "de:08335:11925"; Swiss "ch:23021:19005:30" likewise.
    if parts[0] in ("de", "ch") and len(parts) >= 3 and parts[1] != "1":
        return ":".join(parts[:3])
    return stop["stop_id"]


PLATFORM_SUFFIX = re.compile(r"\s+(?:Bstg\s*(\w+)|[A-Z]{4,}(\d+))$")


def clean_name(name):
    m = PLATFORM_SUFFIX.search(name)
    return (name[: m.start()], m.group(1) or m.group(2)) if m else (name, None)


BUS_SUFFIX = re.compile(r"\s*\(Bus\)$")


def centre(members):
    return (sum(float(m["stop_lat"]) for m in members) / len(members),
            sum(float(m["stop_lon"]) for m in members) / len(members))


def merge_same_place(stations, max_m=300):
    """Stop areas with the same name (ignoring "(Bus)") close together are one place for riders:
    "Konstanz Bahnhof" (trains) and "Konstanz Bahnhof (Bus)" (bus terminal) → "Konstanz Bahnhof"."""
    merged = []
    for key, name, members in sorted(stations, key=lambda s: len(s[1])):
        base = BUS_SUFFIX.sub("", name)
        lat, lon = centre(members)
        for other in merged:
            olat, olon = centre(other[2])
            dist = math.hypot((lon - olon) * 111_320 * math.cos(math.radians(lat)), (lat - olat) * 110_574)
            if other[1] == base and dist <= max_m:
                other[2].extend(members)
                break
        else:
            merged.append((key, name, list(members)))
    return merged


SHAPE_MARGIN = 0.01  # degrees kept around the area, so paths don't stop dead at its edge
SHAPE_TOLERANCE_M = 2.0


def read_shapes(zf, wanted):
    """Points of the wanted shapes inside the (slightly larger) area, in order."""
    pts = defaultdict(list)
    for r in read(zf, "shapes.txt"):
        sid = r["shape_id"]
        if sid not in wanted:
            continue
        lat, lon = float(r["shape_pt_lat"]), float(r["shape_pt_lon"])
        if SOUTH - SHAPE_MARGIN <= lat <= NORTH + SHAPE_MARGIN and WEST - SHAPE_MARGIN <= lon <= EAST + SHAPE_MARGIN:
            pts[sid].append((int(r["shape_pt_sequence"]), lat, lon))
    return {sid: [(lat, lon) for _, lat, lon in sorted(p)] for sid, p in pts.items() if len(p) >= 2}


def simplify(points, tolerance_m=SHAPE_TOLERANCE_M):
    """Douglas–Peucker on a local metric plane."""
    if len(points) < 3:
        return points
    kx = 111_320 * math.cos(math.radians(points[0][0]))
    xy = [(lon * kx, lat * 111_180) for lat, lon in points]
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (x1, y1), (x2, y2) = xy[a], xy[b]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        best, index = 0.0, -1
        for i in range(a + 1, b):
            if length < 1e-6:
                # A loop (ring lines start and end at the same stop): the distance to that point. Measured
                # from the zero-length line, every point would count as 0 m off and the whole route vanished.
                d = math.hypot(xy[i][0] - x1, xy[i][1] - y1)
            else:
                d = abs(dy * (xy[i][0] - x1) - dx * (xy[i][1] - y1)) / length
            if d > best:
                best, index = d, i
        if best > tolerance_m:
            keep[index] = True
            stack += [(a, index), (index, b)]
    return [p for p, k in zip(points, keep) if k]


def encode_polyline(points):
    """Google encoded polyline, precision 1e-5."""
    out, last_lat, last_lon = [], 0, 0
    for lat, lon in points:
        ilat, ilon = round(lat * 1e5), round(lon * 1e5)
        for delta in (ilat - last_lat, ilon - last_lon):
            v = ~(delta << 1) if delta < 0 else delta << 1
            while v >= 0x20:
                out.append(chr((0x20 | (v & 0x1F)) + 63))
                v >>= 5
            out.append(chr(v + 63))
        last_lat, last_lon = ilat, ilon
    return "".join(out)


def direction_label(text):
    """The city's German platform note → English: "Konzilstraße, Richtung Bahnhof" → "Towards Bahnhof"."""
    note = text.split(",", 1)[1] if "," in text else text
    m = re.search(r"Richtung\s+([^,/()]+)", note)
    if m:
        # "Staad bzw. Mainau - Vororte" → "Staad"; fix the register's typos.
        where = re.split(r"\s+(?:bzw\.|-|und)\s+", m.group(1).strip())[0].rstrip(".")
        where = {"Wollmattingen": "Wollmatingen"}.get(where, where)
        if where.lower() in ("innenstadt", "stadtzentrum", "zentrum"):
            return "Towards city centre"
        if where.lower() == "stadtauswärts":
            return "Out of town"
        return f"Towards {where}"
    low = note.lower()
    if "stadtauswärts" in low:
        return "Out of town"
    if "stadteinwärts" in low or "stadtzentrum" in low or "innenstadt" in low:
        return "Towards city centre"
    return None


def read_city_stops():
    """{stop area number: [(lat, lon, full name, direction)]} from the city's GeoJSON, if present."""
    if not CITY_STOPS.exists():
        return {}
    out = defaultdict(list)
    for f in json.loads(CITY_STOPS.read_text(encoding="utf-8"))["features"]:
        p, g = f["properties"], f["geometry"]
        if not p.get("GID") or not p.get("BUSHALTEST") or g["type"] != "Point":
            continue
        lon, lat = g["coordinates"][:2]
        out[p["GID"]].append((lat, lon, p["BUSHALTEST"].split(",")[0].strip(), direction_label(p["BUSHALTEST"])))
    return out


def metres(a, b):
    return math.hypot((a[1] - b[1]) * 111_320 * math.cos(math.radians(a[0])), (a[0] - b[0]) * 111_180)


def city_match(stop, city):
    """The city's record for a timetable platform: same stop area number, within 40 m."""
    parts = stop["stop_id"].split(":")
    if parts[0] != "de" or len(parts) < 3:
        return None
    here = (float(stop["stop_lat"]), float(stop["stop_lon"]))
    near = [(metres(here, (c[0], c[1])), c) for c in city.get(parts[2], [])]
    near = [x for x in near if x[0] <= 40]
    return min(near, key=lambda x: x[0])[1] if near else None


def expanded_name(short, city_name):
    """Spell out the timetable's abbreviations ("Sternenpl./Spanierstr.") when the city's name is clearly the
    same stop written in full ("Sternenplatz/Spanierstraße")."""
    if "." not in short or not city_name or "(" in city_name:
        return short
    if city_name[:5].lower() != short[:5].lower() or len(city_name) <= len(short):
        return short
    return city_name


def service_dates(zf, wanted, start, end):
    dates = defaultdict(set)
    for r in read(zf, "calendar.txt"):
        sid = r["service_id"]
        if sid not in wanted:
            continue
        days = [r[d] == "1" for d in ("monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday")]
        d = max(datetime.date.fromisoformat(r["start_date"][:4] + "-" + r["start_date"][4:6] + "-" + r["start_date"][6:]), start)
        last = min(datetime.date.fromisoformat(r["end_date"][:4] + "-" + r["end_date"][4:6] + "-" + r["end_date"][6:]), end)
        while d <= last:
            if days[d.weekday()]:
                dates[sid].add(int(d.strftime("%Y%m%d")))
            d += datetime.timedelta(days=1)
    for r in read(zf, "calendar_dates.txt"):
        sid = r["service_id"]
        if sid not in wanted:
            continue
        if r["exception_type"] == "1":
            dates[sid].add(int(r["date"]))
        else:
            dates[sid].discard(int(r["date"]))
    return dates


def create_schema(db):
    schema_file = max(SCHEMA_DIR.glob("*.json"), key=lambda p: int(p.stem))
    schema = json.loads(schema_file.read_text())["database"]
    for entity in schema["entities"]:
        table = entity["tableName"]
        db.execute(entity["createSql"].replace("${TABLE_NAME}", table))
        for index in entity.get("indices", []):
            db.execute(index["createSql"].replace("${TABLE_NAME}", table))
    for q in schema["setupQueries"]:
        db.execute(q)
    db.execute(f"PRAGMA user_version = {schema['version']}")
    return schema["version"]


def numbers_in_shipped_data(stops):
    """The stop numbers already on phones, read once from the shipped database when station_ids.json is new."""
    if not SHIPPED.exists():
        return {}
    db = sqlite3.connect(SHIPPED)
    rows = db.execute("SELECT gtfs_id, station_id FROM platform").fetchall()
    db.close()
    return {station_key(stops[stop_id]): number for stop_id, number in rows if stop_id in stops}


def main():
    zf = zipfile.ZipFile(FEED)
    feed_info = next(read(zf, "feed_info.txt"))
    start = datetime.datetime.strptime(feed_info["feed_start_date"], "%Y%m%d").date()
    end = datetime.datetime.strptime(feed_info["feed_end_date"], "%Y%m%d").date()

    # --- stops inside the area, grouped into stations ---
    stops = {}
    for r in read(zf, "stops.txt"):
        if r["location_type"] not in ("", "0") or not r["stop_lat"]:
            continue
        lat, lon = float(r["stop_lat"]), float(r["stop_lon"])
        if SOUTH <= lat <= NORTH and WEST <= lon <= EAST:
            stops[r["stop_id"]] = r

    # --- trips with two or more calls inside the area ---
    routes = {r["route_id"]: r for r in read(zf, "routes.txt") if r["agency_id"] not in SKIP_AGENCIES}
    trips = {r["trip_id"]: r for r in read(zf, "trips.txt") if r["route_id"] in routes}
    calls = defaultdict(list)
    city_calls = defaultdict(list)  # every call of the city's trips, also outside the area (for l219_closure)
    for r in read(zf, "stop_times.txt"):
        if r["trip_id"] in trips and routes[trips[r["trip_id"]]["route_id"]]["agency_id"] == CITY_AGENCY:
            city_calls[r["trip_id"]].append((int(r["stop_sequence"]), r["stop_id"]))
        if r["stop_id"] in stops and r["trip_id"] in trips:
            calls[r["trip_id"]].append((int(r["stop_sequence"]), r["stop_id"], minutes(r["arrival_time"]), minutes(r["departure_time"])))
    calls = {t: sorted(c) for t, c in calls.items() if len(c) >= 2}

    # Timetable changes the feed doesn't have yet.
    extra_dates = l219_closure.apply(
        {k: sorted(v) for k, v in city_calls.items()}, routes, trips, calls,
        service_dates=lambda ids: service_dates(zf, ids, start, end), start=start, end=end,
        in_area=lambda stop_id: stop_id in stops)

    used_stops = {s for c in calls.values() for _, s, _, _ in c}
    groups = defaultdict(list)
    for sid in used_stops:
        groups[station_key(stops[sid])].append(stops[sid])

    stations = []  # (key, name, platforms)
    for key, members in groups.items():
        names = Counter(clean_name(m["stop_name"])[0] for m in members)
        name = min(names, key=lambda n: (-names[n], len(n)))
        stations.append((key, name, members))
    stations = merge_same_place(stations)
    stations.sort(key=lambda s: fold(s[1]))

    used_routes = sorted({trips[t]["route_id"] for t in calls},
                         key=lambda r: (routes[r]["agency_id"] != CITY_AGENCY, line_name(routes[r]["route_short_name"]), r))
    used_services = sorted({trips[t]["service_id"] for t in calls})
    dates = service_dates(zf, set(used_services), start, end)
    dates.update(extra_dates)
    numbers, known_ids = station_ids.assign([{station_key(m) for m in members} for _, _, members in stations],
                                            station_ids.load() or numbers_in_shipped_data(stops))

    # --- write ---
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.unlink(missing_ok=True)
    db = sqlite3.connect(OUT)
    version = create_schema(db)

    city = read_city_stops()
    platform_id = {}
    pid = 0
    city_matched = 0
    for sid, (key, name, members) in zip(numbers, stations):
        short = name[len(TOWN_PREFIX):] if name.startswith(TOWN_PREFIX) else name
        platforms = []
        for m in sorted(members, key=lambda m: m["stop_id"]):
            c = city_match(m, city)
            city_matched += c is not None
            # The city's surveyed point when it has one.
            lat, lon = (c[0], c[1]) if c else (float(m["stop_lat"]), float(m["stop_lon"]))
            platforms.append((m, lat, lon, c))
        # "Egg Egg/Universität": the feed puts the village in front of a name that already starts with it.
        first, _, rest = short.partition(" ")
        if rest and re.split(r"[ /,-]", rest)[0] == first:
            name, short = name.replace(short, rest), rest
        full = next((expanded_name(short, c[2]) for _, _, _, c in platforms if c), short)
        if full != short:
            name = name.replace(short, full) if short in name else full
            short = full
        lat = sum(p[1] for p in platforms) / len(platforms)
        lon = sum(p[2] for p in platforms) / len(platforms)
        db.execute("INSERT INTO station (id, name, short_name, lat, lon, search_name) VALUES (?,?,?,?,?,?)",
                   (sid, name, short, lat, lon, fold(short)))
        for m, plat, plon, c in platforms:
            pid += 1
            platform_id[m["stop_id"]] = pid
            code = m["platform_code"] or clean_name(m["stop_name"])[1]
            db.execute("INSERT INTO platform (id, station_id, gtfs_id, code, lat, lon, direction) VALUES (?,?,?,?,?,?,?)",
                       (pid, sid, m["stop_id"], code or None, plat, plon, c[3] if c else None))

    route_id = {}
    for rid, r in enumerate(used_routes, start=1):
        route_id[r] = rid
        row = routes[r]
        db.execute("INSERT INTO route VALUES (?,?,?,?,?,?,?)",
                   (rid, r, line_name(row["route_short_name"]), row["route_long_name"].strip(), int(row["route_type"]),
                    row["agency_id"], row["agency_id"] == CITY_AGENCY))

    shapes = read_shapes(zf, {trips[t]["shape_id"] for t in calls if trips[t]["shape_id"]})
    shape_id = {}
    for i, (sid, points) in enumerate(sorted(shapes.items()), start=1):
        shape_id[sid] = i
        db.execute("INSERT INTO shape (id, points) VALUES (?,?)", (i, encode_polyline(simplify(points))))

    service_id = {s: i for i, s in enumerate(used_services, start=1)}
    db.executemany("INSERT INTO service_date VALUES (?,?)",
                   ((service_id[s], d) for s in used_services for d in sorted(dates[s])))

    for tid, t in enumerate(sorted(calls), start=1):
        row = trips[t]
        db.execute("INSERT INTO trip (id, gtfs_id, route_id, service_id, headsign, direction, shape_id) VALUES (?,?,?,?,?,?,?)",
                   (tid, t, route_id[row["route_id"]], service_id[row["service_id"]],
                    row["trip_headsign"].strip(), int(row["direction_id"] or 0), shape_id.get(row["shape_id"])))
        db.executemany("INSERT INTO stop_time VALUES (?,?,?,?,?)",
                       ((tid, seq, platform_id[s], arr, dep) for seq, s, arr, dep in calls[t]))

    meta = {
        "feed_version": feed_info["feed_version"],
        "feed_start": feed_info["feed_start_date"],
        "feed_end": feed_info["feed_end_date"],
        "built_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "attribution": "Datensatz der NVBW GmbH",
        "license": "Datenlizenz Deutschland – Namensnennung – Version 2.0",
        "license_url": "https://www.govdata.de/dl-de/by-2-0",
        "source_url": "https://www.nvbw.de/open-data/fahrplandaten/fahrplandaten-mit-liniennetz",
        "bbox": f"{SOUTH},{WEST},{NORTH},{EAST}",
    }
    db.executemany("INSERT INTO meta VALUES (?,?)", meta.items())
    db.commit()
    station_ids.save(known_ids)
    db.execute("VACUUM")
    db.close()

    print(f"city stop register: {city_matched} of {pid} platforms matched")
    print(f"schema v{version}: {len(stations)} stations, {pid} platforms, {len(used_routes)} routes, "
          f"{len(calls)} trips, {sum(len(c) for c in calls.values())} stop times, {len(shapes)} shapes, "
          f"{sum(len(dates[s]) for s in used_services)} service dates")
    print(f"{OUT}: {OUT.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
