"""
Full closure of the L 219 between Wallhausen and Dingelsdorf (from Monday 26 Oct 2026 until about mid-2027).

Stadtwerke Konstanz replace the ring lines 4/13 and 13/4 and the night ring N with two lines that turn at the
closure: 4 (Bahnhof – Mainau – Litzelstetten – Dingelsdorf) and 13 (Bahnhof – Industriegebiet – Wollmatingen –
Dettingen – Wallhausen), each with "Nachtschwärmer" night runs. The NVBW feed of 11 Oct 2026 doesn't have this
yet, so this module writes it in from the operator's timetable booklet:

    "Roter Arnold – Linien 4, 13 und Nachtschwärmer", Fahrplan gültig während der Vollsperrung der L219
    https://www.stadtwerke-konstanz.de/fahrplanheft-linie-4-und-13vollsperrung-dingelsdorf_wallhausen/

Delete this module (and its call in import_gtfs.py) once NVBW publishes the closure timetable itself:
`python3 -I DataPipeline/gtfs-import/l219_closure.py --check path/to/vhb.zip` says whether a feed already has lines 4
and 13 for Stadtwerke Konstanz.

Platforms and street paths come from the old ring's own trips in the feed, so stops and route lines match.
"""
import datetime
import sys
from collections import Counter, defaultdict

AGENCY = "vhb-SW-KN"
FIRST_DAY = datetime.date(2026, 10, 26)
OLD_ROUTES = {"4/13", "13/4", "N"}  # end on 25 Oct 2026

# Public holidays in Baden-Württemberg: Sunday timetable ("Sonn- und Feiertag").
HOLIDAYS = {datetime.date(*d) for d in [
    (2026, 11, 1), (2026, 12, 25), (2026, 12, 26),
    (2027, 1, 1), (2027, 1, 6), (2027, 3, 26), (2027, 3, 29), (2027, 5, 1), (2027, 5, 6),
    (2027, 5, 17), (2027, 5, 27), (2027, 10, 3), (2027, 11, 1), (2027, 12, 25), (2027, 12, 26),
]}

# Stop areas (de:08335:<area>) as named in the booklet.
BAHNHOF_DEP, BAHNHOF_ARR = "6554", "11882"  # buses leave from Bstg 1 and arrive at the bus station
KONZIL, STERNENPLATZ, ZAEHRINGERPLATZ = "11868", "11918", "11935"
ALLMANNSDORFER_STR, SALZBERG, TANNENHOF, AN_DER_STEIG = "11802", "11899", "11923", "11917"
ALLMANNSDORF, STAAD, JUGENDHERBERGE, EGG, MAINAU = "11801", "11351", "11863", "10200", "11879"
WALDFRIEDHOF, TANKSTELLE, ZUM_PURREN, OBERDORF = "11875", "11874", "11873", "11886"
THINGOLTHALLE, DINGELSDORF = "11951", "11833"
LINZGAUBLICK, BIRNAUBLICK, FEUERWEHR, DETTINGEN, SPIELPLATZ = "11930", "11928", "11828", "11830", "2153"
WOLLMATINGEN_RATHAUS, BODAN_RIED, BHF_WOLLMATINGEN = "11933", "11814", "11808"
MSS_WEST, MSS_OST, NEUWERK, EUROPABRUECKE, BODENSEEFORUM = "11884", "11883", "11952", "60200", "61500"
RHEINUFER, SPANIERSTR = "71100", "11920"
BISMARCKSTEIG, FRIEDHOF, TABORWEG, FUERSTENBERG = "11809", "11844", "11922", "11847"
HEROSESTR, HARDTSTR, BODAN = "11859", "11855", "11811"

# Patterns: (area, minutes after the first stop), read off the booklet's columns.
P4_OUT = [(BAHNHOF_DEP, 0), (KONZIL, 2), (STERNENPLATZ, 4), (ZAEHRINGERPLATZ, 7), (ALLMANNSDORFER_STR, 8),
          (SALZBERG, 9), (TANNENHOF, 11), (AN_DER_STEIG, 13), (ALLMANNSDORF, 14), (JUGENDHERBERGE, 16), (EGG, 18),
          (MAINAU, 20), (WALDFRIEDHOF, 23), (TANKSTELLE, 24), (ZUM_PURREN, 25), (OBERDORF, 27),
          (THINGOLTHALLE, 28), (DINGELSDORF, 29)]
# "S: über Staad" (late evening).
P4_OUT_STAAD = P4_OUT[:9] + [(STAAD, 16), (JUGENDHERBERGE, 18), (EGG, 20), (MAINAU, 22), (WALDFRIEDHOF, 25),
                             (TANKSTELLE, 26), (ZUM_PURREN, 27), (OBERDORF, 29), (THINGOLTHALLE, 30), (DINGELSDORF, 31)]
P4_IN = [(DINGELSDORF, 0), (THINGOLTHALLE, 1), (OBERDORF, 3), (ZUM_PURREN, 5), (TANKSTELLE, 6), (WALDFRIEDHOF, 7),
         (MAINAU, 11), (EGG, 14), (JUGENDHERBERGE, 16), (ALLMANNSDORF, 18), (AN_DER_STEIG, 19), (TANNENHOF, 21),
         (SALZBERG, 23), (ALLMANNSDORFER_STR, 24), (ZAEHRINGERPLATZ, 26), (STERNENPLATZ, 28), (KONZIL, 30),
         (BAHNHOF_ARR, 32)]
# The first run of the day reaches Bahnhof a minute sooner.
P4_IN_EARLY = P4_IN[:-1] + [(BAHNHOF_ARR, 31)]

P13_OUT = [(BAHNHOF_DEP, 0), (KONZIL, 2), (SPANIERSTR, 4), (RHEINUFER, 6), (BODENSEEFORUM, 7), (EUROPABRUECKE, 8),
           (NEUWERK, 10), (MSS_OST, 12), (MSS_WEST, 13), (BHF_WOLLMATINGEN, 15), (BODAN_RIED, 16),
           (WOLLMATINGEN_RATHAUS, 18), (SPIELPLATZ, 26), (DETTINGEN, 27), (FEUERWEHR, 28), (BIRNAUBLICK, 30),
           (LINZGAUBLICK, 31)]
# First runs start at Max-Stromeyer-Straße Ost (the depot).
P13_OUT_DEPOT = [(a, m - 12) for a, m in P13_OUT[7:]]
# "Wo: über Zähringerplatz – Friedhof – Herosestraße" (afternoon peak).
P13_OUT_WO = [(BAHNHOF_DEP, 0), (KONZIL, 2), (STERNENPLATZ, 4), (ZAEHRINGERPLATZ, 7), (BISMARCKSTEIG, 9),
              (FRIEDHOF, 11), (HEROSESTR, 13), (WOLLMATINGEN_RATHAUS, 16), (SPIELPLATZ, 24), (DETTINGEN, 25),
              (FEUERWEHR, 26), (BIRNAUBLICK, 28), (LINZGAUBLICK, 29)]
# Nachtschwärmer.
P13_OUT_NIGHT = [(BAHNHOF_DEP, 0), (KONZIL, 2), (STERNENPLATZ, 4), (ZAEHRINGERPLATZ, 7), (BISMARCKSTEIG, 9),
                 (FRIEDHOF, 11), (TABORWEG, 12), (NEUWERK, 13), (FUERSTENBERG, 15), (HEROSESTR, 17), (HARDTSTR, 18),
                 (BODAN, 19), (WOLLMATINGEN_RATHAUS, 21), (SPIELPLATZ, 29), (DETTINGEN, 30), (FEUERWEHR, 31),
                 (BIRNAUBLICK, 33), (LINZGAUBLICK, 34)]
P13_IN = [(LINZGAUBLICK, 0), (BIRNAUBLICK, 1), (FEUERWEHR, 3), (DETTINGEN, 4), (SPIELPLATZ, 6),
          (WOLLMATINGEN_RATHAUS, 14), (BODAN_RIED, 16), (BHF_WOLLMATINGEN, 17), (MSS_WEST, 19), (MSS_OST, 20),
          (NEUWERK, 22), (EUROPABRUECKE, 24), (BODENSEEFORUM, 25), (RHEINUFER, 26), (SPANIERSTR, 28), (KONZIL, 30),
          (BAHNHOF_ARR, 32)]
# "W: über Herosestraße – Friedhof – Zähringerplatz" (morning peak).
P13_IN_W = [(LINZGAUBLICK, 0), (BIRNAUBLICK, 1), (FEUERWEHR, 3), (DETTINGEN, 4), (SPIELPLATZ, 6),
            (WOLLMATINGEN_RATHAUS, 14), (HEROSESTR, 17), (FRIEDHOF, 20), (BISMARCKSTEIG, 21), (ZAEHRINGERPLATZ, 23),
            (STERNENPLATZ, 25), (KONZIL, 27), (BAHNHOF_ARR, 29)]
P13_IN_NIGHT = [(LINZGAUBLICK, 0), (BIRNAUBLICK, 1), (FEUERWEHR, 3), (DETTINGEN, 4), (SPIELPLATZ, 6),
                (WOLLMATINGEN_RATHAUS, 14), (HEROSESTR, 17), (FUERSTENBERG, 18), (NEUWERK, 19), (TABORWEG, 21),
                (FRIEDHOF, 22), (BISMARCKSTEIG, 23), (ZAEHRINGERPLATZ, 25), (STERNENPLATZ, 27), (KONZIL, 29),
                (BAHNHOF_ARR, 31)]


def t(hhmm):
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def every(first, last, step):
    """"Alle <step> Min." from [first] to [last], both included ("00:25" after midnight is written "24:25")."""
    return list(range(t(first), t(last) + 1, step))


# Days: weekday (Mo–Fr), Saturday, Sunday/holiday; night runs only on the nights the booklet names.
WD, SA, SU, NIGHT_WD, NIGHT_SA = "WD", "SA", "SU", "NIGHT_WD", "NIGHT_SA"

LINES = {
    "4": {
        "long_name": "Bahnhof - Allmannsdorf - Mainau - Litzelstetten - Dingelsdorf",
        "out_headsign": "Dingelsdorf Ortsmitte",
        "in_headsign": "Konstanz Bahnhof",
        "runs": [
            # (days, direction, pattern, start minutes)
            (WD, 0, P4_OUT, [t("05:15"), t("05:45"), t("06:30")] + every("07:00", "15:30", 30) + every("15:45", "18:30", 15)
                + every("19:00", "20:30", 30) + every("21:00", "24:00", 60)),
            (WD, 0, P4_OUT_STAAD, [t("25:00")]),
            (NIGHT_WD, 0, P4_OUT_STAAD, [t("25:40")]),
            (SA, 0, P4_OUT, [t("05:15"), t("05:45"), t("06:30")] + every("07:00", "20:30", 30) + every("21:00", "24:00", 60)),
            (SA, 0, P4_OUT_STAAD, [t("25:00")]),
            (NIGHT_SA, 0, P4_OUT_STAAD, [t("25:40")]),
            (SU, 0, P4_OUT, [t("06:20"), t("07:30")] + every("08:00", "20:30", 30) + every("21:00", "24:00", 60)),
            (SU, 0, P4_OUT_STAAD, [t("25:00")]),
            (WD, 1, P4_IN_EARLY, [t("04:43")]),
            (WD, 1, P4_IN, [t("05:46"), t("06:22"), t("06:52")] + every("07:08", "10:08", 15) + every("10:38", "16:08", 30)
                + every("16:38", "18:38", 15) + every("19:08", "21:08", 30) + every("21:38", "24:38", 60)),
            (NIGHT_WD, 1, P4_IN, [t("26:16")]),
            (SA, 1, P4_IN_EARLY, [t("04:43")]),
            (SA, 1, P4_IN, [t("05:46"), t("06:22"), t("06:52"), t("07:08")] + every("07:38", "21:08", 30)
                + every("21:38", "24:38", 60)),
            (NIGHT_SA, 1, P4_IN, [t("26:16")]),
            (SU, 1, P4_IN, [t("05:22"), t("06:52"), t("07:38")] + every("08:08", "21:08", 30) + every("21:38", "24:38", 60)),
        ],
    },
    "13": {
        "long_name": "Bahnhof - Industriegebiet - Dettingen - Wallhausen",
        "out_headsign": "Wallhausen Linzgaublick",
        "in_headsign": "Konstanz Bahnhof",
        "runs": [
            (WD, 0, P13_OUT_DEPOT, [t("04:19")]),
            (WD, 0, P13_OUT, [t("05:12"), t("05:46")] + every("06:16", "07:16", 15) + every("07:46", "19:46", 30)
                + every("20:25", "24:25", 60)),
            (WD, 0, P13_OUT_WO, every("16:02", "17:32", 30)),
            (NIGHT_WD, 0, P13_OUT_NIGHT, [t("25:40")]),
            (SA, 0, P13_OUT_DEPOT, [t("04:19")]),
            (SA, 0, P13_OUT, [t("05:46"), t("06:46")] + every("07:16", "19:46", 30) + every("20:25", "24:25", 60)),
            (NIGHT_SA, 0, P13_OUT_NIGHT, [t("25:40")]),
            (SU, 0, P13_OUT_DEPOT, [t("04:58")]),
            (SU, 0, P13_OUT, [t("06:16")] + every("07:16", "19:46", 30) + every("20:25", "24:25", 60)),
            (WD, 1, P13_IN, [t("04:39"), t("05:51"), t("06:21"), t("07:06"), t("07:36")] + every("08:18", "20:18", 30)
                + every("20:57", "24:57", 60)),
            (WD, 1, P13_IN_W, [t("06:50"), t("07:20"), t("07:50")]),
            (NIGHT_WD, 1, P13_IN_NIGHT, [t("26:15")]),
            (SA, 1, P13_IN, [t("04:39"), t("06:21")] + every("07:18", "20:18", 30) + every("20:57", "24:57", 60)),
            (NIGHT_SA, 1, P13_IN_NIGHT, [t("26:15")]),
            (SU, 1, P13_IN, [t("05:18"), t("06:48")] + every("07:48", "20:18", 30) + every("20:57", "24:57", 60)),
        ],
    },
}


def day_kind(d):
    if d.weekday() == 6 or d in HOLIDAYS:
        return SU
    return SA if d.weekday() == 5 else WD


def days_of(kind, start, end):
    """Service days of [kind] from FIRST_DAY to [end] (a night run belongs to the evening it starts)."""
    out = set()
    d = max(start, FIRST_DAY)
    while d <= end:
        k = day_kind(d)
        if kind == k or (kind == NIGHT_WD and k == WD and d.weekday() in (2, 3, 4)) or (kind == NIGHT_SA and k == SA):
            out.add(int(d.strftime("%Y%m%d")))
        d += datetime.timedelta(days=1)
    return out


def area(stop_id):
    parts = stop_id.split(":")
    return parts[2] if len(parts) >= 3 else stop_id


def apply(feed_stop_times, routes, trips, calls, service_dates, start, end, in_area):
    """
    Ends the old ring on 25 Oct and adds lines 4 and 13 from 26 Oct. Mutates [routes], [trips], [calls] like the
    importer's own tables and returns {service_id: dates} for the services it made.

    [feed_stop_times]: every call of every trip in the feed, {trip_id: [(seq, stop_id), ...]} (platform choice);
    [service_dates](ids): the feed's dates of those services; [in_area](stop_id): whether the importer keeps a stop.
    """
    last_old = int((FIRST_DAY - datetime.timedelta(days=1)).strftime("%Y%m%d"))
    extra = {}

    # --- the old ring stops after 25 Oct: its trips get a copy of their service, cut at that day ---
    ring = [tid for tid, row in trips.items()
            if routes.get(row["route_id"], {}).get("agency_id") == AGENCY
            and routes[row["route_id"]]["route_short_name"].strip() in OLD_ROUTES]
    old = service_dates({trips[tid]["service_id"] for tid in ring})
    for tid in ring:
        sid = trips[tid]["service_id"]
        cut = f"{sid}#until-{last_old}"
        extra.setdefault(cut, {d for d in old.get(sid, ()) if d <= last_old})
        trips[tid] = dict(trips[tid], service_id=cut)

    # --- platforms: the one the feed's trips use when going from one area to the next ---
    pair = defaultdict(Counter)  # (from area, to area) -> Counter((from stop, to stop))
    seen = defaultdict(Counter)  # area -> Counter(stop)
    for seq_stops in feed_stop_times.values():
        for (_, a), (_, b) in zip(seq_stops, seq_stops[1:]):
            pair[(area(a), area(b))][(a, b)] += 1
        for _, s in seq_stops:
            seen[area(s)][s] += 1

    def platforms(pattern):
        areas = [a for a, _ in pattern]
        chosen = [None] * len(areas)
        for i in range(len(areas) - 1):
            options = pair.get((areas[i], areas[i + 1]))
            if options:
                a, b = options.most_common(1)[0][0]
                chosen[i] = chosen[i] or a
                chosen[i + 1] = chosen[i + 1] or b
        for i, a in enumerate(areas):
            if chosen[i] is None:
                if not seen[a]:
                    raise SystemExit(f"L219: stop area de:08335:{a} is not in the feed")
                chosen[i] = seen[a].most_common(1)[0][0]
        return chosen

    # --- street paths: the shape of an old ring trip that passes the pattern's stops in order ---
    ring_paths = []
    for tid in ring:
        stops_in_order = [area(s) for _, s in feed_stop_times.get(tid, [])]
        if trips[tid].get("shape_id"):
            ring_paths.append((stops_in_order, trips[tid]["shape_id"]))

    def shape_for(pattern):
        wanted = [a for a, _ in pattern]
        for stops_in_order, shape in sorted(ring_paths, key=lambda p: len(p[0])):
            it = iter(stops_in_order)
            if all(any(x == w or (w == BAHNHOF_DEP and x == BAHNHOF_ARR) or (w == BAHNHOF_ARR and x == BAHNHOF_DEP)
                       for x in it) for w in wanted):
                return shape
        return ""  # straight from stop to stop

    made = 0
    for line, spec in LINES.items():
        route_id = f"l219-{line}"
        routes[route_id] = {"route_id": route_id, "agency_id": AGENCY, "route_short_name": line,
                            "route_long_name": spec["long_name"], "route_type": "3"}
        for n, (kind, direction, pattern, starts) in enumerate(spec["runs"]):
            service = f"l219-{kind}"
            extra.setdefault(service, days_of(kind, start, end))
            stop_ids = platforms(pattern)
            shape = shape_for(pattern)
            headsign = spec["in_headsign"] if direction else spec["out_headsign"]
            for first in starts:
                trip_id = f"l219-{line}-{n}-{first}"
                trips[trip_id] = {"trip_id": trip_id, "route_id": route_id, "service_id": service,
                                  "trip_headsign": headsign, "direction_id": str(direction), "shape_id": shape}
                c = [(seq, s, first + m, first + m) for seq, (s, (_, m)) in enumerate(zip(stop_ids, pattern), start=1)
                     if in_area(s)]
                if len(c) >= 2:
                    calls[trip_id] = c
                    made += 1
    print(f"L219 closure: old ring ends {last_old}; lines 4 and 13 from {FIRST_DAY:%Y%m%d}, {made} trips in the area")
    return extra


def check(feed):
    """Whether [feed] already has the city's lines 4 and 13 (then this module can go)."""
    import csv
    import io
    import zipfile
    zf = zipfile.ZipFile(feed)
    names = {r["route_short_name"].strip() for r in csv.DictReader(io.TextIOWrapper(zf.open("routes.txt"), "utf-8-sig"))
             if r["agency_id"] == AGENCY}
    has = {"4", "13"} <= names
    print(f"{feed}: city lines {sorted(names, key=lambda s: (len(s), s))}")
    print("NVBW has lines 4 and 13 – remove l219_closure.py" if has else "still the old ring – keep l219_closure.py")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--check":
        check(sys.argv[2])
    else:
        print(__doc__)
