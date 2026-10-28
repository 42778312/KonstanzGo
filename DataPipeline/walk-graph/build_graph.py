#!/usr/bin/env python3
"""
Builds the offline walking network the app routes on: App/Resources/Data/walk/konstanz-walk.bin
from the OpenStreetMap ways fetched by fetch_osm.py (data/ways.json).

    python3 DataPipeline/walk-graph/fetch_osm.py     # ~2 min, Overpass
    python3 DataPipeline/walk-graph/build_graph.py

Vertices are the junctions (and dead ends); every edge keeps the shape of the street between them, its
name and what kind of way it is, so the app can draw the walk along the streets and say
"Turn left onto Schottenstraße". Unnamed sidewalks take the name of the street they run along.

File (big-endian, read by the app's walking router; see FORMATS.md):
    "KWG1"
    int nNames, nNames × UTF name
    int nVertices, nVertices × (int latE7, int lonE7)
    int nEdges, nEdges × (int a, int b, int nameIndex or -1, byte kind, byte flags, int lengthCm,
                          short nShape, nShape × (int latE7, int lonE7))   # shape points between a and b
"""
import json
import math
import struct
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "App/Resources/Data/walk/konstanz-walk.bin"

WALKABLE = {
    "footway", "path", "pedestrian", "steps", "living_street", "residential", "service", "unclassified",
    "tertiary", "tertiary_link", "secondary", "secondary_link", "primary", "primary_link", "track",
    "cycleway", "road", "corridor", "bridleway", "platform",
}
STREETS = {"living_street", "residential", "service", "unclassified", "tertiary", "tertiary_link",
           "secondary", "secondary_link", "primary", "primary_link", "road", "trunk", "trunk_link"}
# Kinds (WalkGraph.Kind in the app).
STREET, FOOTPATH, STEPS, PEDESTRIAN, CROSSING = 0, 1, 2, 3, 4
FLAG_BRIDGE, FLAG_TUNNEL = 1, 2


def meters(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.hypot((b[1] - a[1]) * 111_320 * math.cos(lat), (b[0] - a[0]) * 111_133)


def bearing(a, b):
    lat = math.radians((a[0] + b[0]) / 2)
    return math.degrees(math.atan2((b[1] - a[1]) * math.cos(lat), b[0] - a[0])) % 360


def walkable(t):
    hw = t.get("highway")
    if hw not in WALKABLE and not (hw in ("trunk", "trunk_link") and t.get("sidewalk") in ("both", "left", "right")):
        return False
    foot = t.get("foot")
    if foot == "no" or t.get("access") in ("no", "private") and foot not in ("yes", "designated", "permissive"):
        return False
    if hw == "cycleway" and foot not in ("yes", "designated", "permissive") and t.get("segregated") is None:
        return foot != "no"
    return True


def kind(t):
    hw = t["highway"]
    if hw == "steps":
        return STEPS
    if hw == "pedestrian":
        return PEDESTRIAN
    if t.get("footway") == "crossing" or t.get("path") == "crossing" or t.get("cycleway") == "crossing":
        return CROSSING
    if hw in STREETS:
        return STREET
    return FOOTPATH


def main():
    ways = [w for w in json.loads((HERE / "data/ways.json").read_text()) if walkable(w["tags"])]

    # Named streets, to name the sidewalks drawn as their own ways.
    cell = 0.0004  # ~45 m
    grid = defaultdict(list)
    for w in json.loads((HERE / "data/ways.json").read_text()):
        t = w["tags"]
        if t.get("highway") in STREETS | {"pedestrian"} and t.get("name"):
            g = w["geom"]
            for i in range(len(g) - 1):
                key = (int(g[i][0] / cell), int(g[i][1] / cell))
                grid[key].append((g[i], g[i + 1], t["name"]))

    def street_beside(g):
        votes = defaultdict(float)
        for i in range(len(g) - 1):
            a, b = g[i], g[i + 1]
            mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
            br = bearing(a, b)
            ky, kx = int(mid[0] / cell), int(mid[1] / cell)
            best = None
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    for p, q, name in grid.get((ky + dy, kx + dx), ()):
                        d = point_segment(mid, p, q)
                        diff = abs((bearing(p, q) - br + 90) % 180 - 90)
                        if d < 25 and diff < 25 and (best is None or d < best[0]):
                            best = (d, name)
            if best:
                votes[best[1]] += meters(a, b)
        if not votes:
            return None
        name, length = max(votes.items(), key=lambda kv: kv[1])
        total = sum(meters(g[i], g[i + 1]) for i in range(len(g) - 1))
        return name if length >= 0.5 * total else None

    # Junctions: nodes on more than one way, and every way's ends.
    uses = defaultdict(int)
    for w in ways:
        for n in w["nodes"]:
            uses[n] += 1
        uses[w["nodes"][0]] += 1
        uses[w["nodes"][-1]] += 1

    coord = {}
    for w in ways:
        for n, g in zip(w["nodes"], w["geom"]):
            coord[n] = g

    names, name_index = [], {}

    def name_id(name):
        if not name:
            return -1
        if name not in name_index:
            name_index[name] = len(names)
            names.append(name)
        return name_index[name]

    vertex = {}

    def vid(n):
        if n not in vertex:
            vertex[n] = len(vertex)
        return vertex[n]

    edges = []
    named_sidewalks = 0
    for w in ways:
        t = w["tags"]
        k = kind(t)
        name = t.get("name")
        if not name and k == FOOTPATH:
            name = street_beside(w["geom"])
            if name:
                named_sidewalks += 1
        flags = (FLAG_BRIDGE if t.get("bridge") not in (None, "no") else 0) | (FLAG_TUNNEL if t.get("tunnel") not in (None, "no") else 0)
        nodes = w["nodes"]
        start = 0
        for i in range(1, len(nodes)):
            if uses[nodes[i]] > 1 or i == len(nodes) - 1:
                seg = nodes[start:i + 1]
                pts = [coord[n] for n in seg]
                length = sum(meters(pts[j], pts[j + 1]) for j in range(len(pts) - 1))
                if seg[0] != seg[-1] or length > 0:
                    edges.append((vid(seg[0]), vid(seg[-1]), name_id(name), k, flags, length, pts[1:-1]))
                start = i

    verts = [None] * len(vertex)
    for n, i in vertex.items():
        verts[i] = coord[n]

    OUT.parent.mkdir(parents=True, exist_ok=True)
    e7 = lambda v: int(round(v * 1e7))
    with open(OUT, "wb") as f:
        f.write(b"KWG1")
        f.write(struct.pack(">i", len(names)))
        for n in names:
            b = n.encode("utf-8")
            f.write(struct.pack(">H", len(b)) + b)
        f.write(struct.pack(">i", len(verts)))
        for lat, lon in verts:
            f.write(struct.pack(">ii", e7(lat), e7(lon)))
        f.write(struct.pack(">i", len(edges)))
        for a, b, nm, k, fl, length, shape in edges:
            f.write(struct.pack(">iiibbiH", a, b, nm, k, fl, int(round(length * 100)), len(shape)))
            for lat, lon in shape:
                f.write(struct.pack(">ii", e7(lat), e7(lon)))
    print(f"{OUT}: {len(verts)} vertices, {len(edges)} edges, {len(names)} names, "
          f"{named_sidewalks} sidewalks named, {OUT.stat().st_size / 1e6:.1f} MB")


def point_segment(p, a, b):
    lat = math.radians(p[0])
    kx, ky = 111_320 * math.cos(lat), 111_133
    px, py = (p[1] - a[1]) * kx, (p[0] - a[0]) * ky
    bx, by = (b[1] - a[1]) * kx, (b[0] - a[0]) * ky
    l2 = bx * bx + by * by
    s = 0 if l2 == 0 else max(0, min(1, (px * bx + py * by) / l2))
    return math.hypot(px - s * bx, py - s * by)


if __name__ == "__main__":
    main()
