"""
Keeps a stop's number the same from one timetable to the next. Favourites, recent searches and alarms on
people's phones store these numbers, so a number may never move to another stop or be used again.

station_ids.json maps every stop area in the feed ("de:08335:11882") to its number and is committed with
the data. A stop that leaves the feed keeps its entry, so its number stays retired.
"""
import json
from pathlib import Path

FILE = Path(__file__).resolve().parent / "station_ids.json"


def assign(stations, known):
    """Numbers for `stations` (a set of stop-area keys each, merged stops have several), in order.
    Returns the numbers and the updated map. New stops get numbers above every number ever used."""
    known = dict(known)
    next_id = max(known.values(), default=0) + 1
    numbers = [None] * len(stations)
    taken = set()
    # Stops that already have a number first, so a new stop can't take one.
    for index, keys in enumerate(stations):
        existing = sorted({known[k] for k in keys if k in known} - taken)
        if existing:
            numbers[index] = existing[0]
            taken.add(existing[0])
    for index, keys in enumerate(stations):
        if numbers[index] is None:
            numbers[index] = next_id
            next_id += 1
        for key in keys:
            known[key] = numbers[index]
    return numbers, known


def load():
    return json.loads(FILE.read_text()) if FILE.exists() else {}


def save(known):
    FILE.write_text(json.dumps(known, indent=0, sort_keys=True) + "\n")
