"""
Checks the data in App/Resources/Data/ before it ships: every file is there, the timetable is not
empty, line 9's variants are right, and it is valid for at least 30 more days. Exits with an error otherwise.

    DataPipeline/.venv/bin/python DataPipeline/check.py [--allow-short-validity]

--allow-short-validity only reports the 30-day rule: for CI, and for an emergency build near the end date.
"""
import datetime
import json
import sqlite3
import sys
from pathlib import Path

DATA = Path(__file__).resolve().parents[1] / "App/Resources/Data"
FILES = ["timetable.db", "map/konstanz.pmtiles", "map/style.json", "walk/konstanz-walk.bin", "search/places.tsvz"]
MIN_DAYS_LEFT = 30

problems = []
for name in FILES:
    if not (DATA / name).is_file():
        problems.append(f"missing {name}")

db = sqlite3.connect(DATA / "timetable.db")
meta = dict(db.execute("SELECT key, value FROM meta"))
counts = {t: db.execute(f"SELECT count(*) FROM {t}").fetchone()[0]
          for t in ["station", "platform", "route", "trip", "stop_time", "place"]}
for table, n in counts.items():
    if n == 0:
        problems.append(f"table {table} is empty")

# Saved stops on phones rely on these numbers (gtfs-import/station_ids.py).
known_ids = json.loads((Path(__file__).parent / "gtfs-import/station_ids.json").read_text())
unknown = {n for (n,) in db.execute("SELECT id FROM station")} - set(known_ids.values())
if unknown:
    problems.append(f"stops without a kept number: {sorted(unknown)}")

end = datetime.datetime.strptime(meta["feed_end"], "%Y%m%d").date()
days_left = (end - datetime.date.today()).days
if days_left < MIN_DAYS_LEFT:
    message = f"timetable ends {end} ({days_left} days left, need {MIN_DAYS_LEFT})"
    if "--allow-short-validity" in sys.argv[1:]:
        print(f"allowed: {message}")
    else:
        problems.append(message)

# The printed timetable: 9A runs via Friedrichstraße and Paradies, 9B via Sonnenbühlstraße and Laube.
for line, via in {"9A": ("Friedrichstraße", "Ellenrieder Gymnasium"), "9B": ("Sonnenbühlstraße", "Bürgerbüro")}.items():
    wrong = db.execute(
        """SELECT count(*) FROM trip t JOIN route r ON r.id = t.route_id WHERE r.short_name = ? AND
           (SELECT count(DISTINCT s.short_name) FROM stop_time x JOIN platform p ON p.id = x.platform_id
            JOIN station s ON s.id = p.station_id WHERE x.trip_id = t.id AND s.short_name IN (?, ?)) < 2""",
        (line, *via)).fetchone()[0]
    if wrong:
        problems.append(f"{wrong} trips of line {line} miss its stops")

print(f"feed {meta['feed_version']}, valid {meta['feed_start']}–{meta['feed_end']} ({days_left} days left)")
print(", ".join(f"{n} {t}" for t, n in counts.items()))
with open(DATA / "walk/konstanz-walk.bin", "rb") as f:
    if f.read(4) != b"KWG1":
        problems.append("walk graph has the wrong header")

if problems:
    print("PROBLEMS:\n  " + "\n  ".join(problems))
    sys.exit(1)
print("data ok")
