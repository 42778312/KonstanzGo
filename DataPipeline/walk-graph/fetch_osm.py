"""
Downloads every OSM way tagged highway=* around Konstanz (the map's area) from Overpass, in small tiles
(the public servers refuse one big request), into data/ways.json. Run: python3 fetch_osm.py
"""
import json
import os
import sys
import time
import urllib.parse
import urllib.request

SOUTH, WEST, NORTH, EAST = 47.63, 9.05, 47.74, 9.26
STEP = 0.025
SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/DataPipeline/overpass/api/interpreter",
]
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "data", "ways.json")


def fetch(s, w, n, e):
    q = f'[out:json][timeout:100];way["highway"]({s},{w},{n},{e});out body geom qt;'
    body = urllib.parse.urlencode({"data": q}).encode()
    for attempt in range(8):
        url = SERVERS[attempt % len(SERVERS)]
        try:
            req = urllib.request.Request(url, body, {"User-Agent": "konstanz-transit-dev/1.0"})
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.load(r)["elements"]
        except Exception as ex:  # busy server: wait and try the other one
            print(f"  retry {attempt + 1} ({ex})", flush=True)
            time.sleep(5 + attempt * 5)
    raise SystemExit(f"tile {s},{w} failed")


def main():
    ways = {}
    lat = SOUTH
    while lat < NORTH:
        lon = WEST
        while lon < EAST:
            cache = os.path.join(HERE, "data", "tiles", f"{lat:.3f}_{lon:.3f}.json")
            if os.path.exists(cache):
                with open(cache) as f:
                    els = json.load(f)
            else:
                els = fetch(lat, lon, min(lat + STEP, NORTH), min(lon + STEP, EAST))
                os.makedirs(os.path.dirname(cache), exist_ok=True)
                with open(cache, "w") as f:
                    json.dump(els, f)
                time.sleep(1)
            for el in els:
                if el["type"] == "way" and "geometry" in el:
                    ways[el["id"]] = {"tags": el.get("tags", {}), "nodes": el["nodes"],
                                      "geom": [[g["lat"], g["lon"]] for g in el["geometry"]]}
            print(f"{lat:.3f},{lon:.3f}: {len(els)} ways, total {len(ways)}", flush=True)
            lon += STEP
        lat += STEP
    with open(OUT, "w") as f:
        json.dump(list(ways.values()), f)


if __name__ == "__main__":
    main()
