#!/usr/bin/env python3
"""
Builds the offline search index the app searches as you type: App/Resources/Data/search/places.tsvz

    python3 DataPipeline/places-import/fetch_search_osm.py   # Overpass → data/search-osm.json
    python3 DataPipeline/places-import/build_search.py       # needs timetable.db with its place table filled

One line per thing to find — every named place (shops, cafés, schools, doctors, sights …), every street,
district and town, and every house address — with the words it should answer to in English and German
("Apotheke pharmacy chemist"). Places already in timetable.db keep their ids, so saved places still work.

Columns (tab-separated, UTF-8):
    id  name  group  category  area  lat  lon  rank  keywords  address  category_de

Data © OpenStreetMap contributors, ODbL.
"""
import gzip
import json
import math
import re
import sqlite3
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DB = ROOT / "App/Resources/Data/timetable.db"
OUT = ROOT / "App/Resources/Data/search/places.tsvz"

# (tag, value) → (group, English label, rank, extra search words). Groups decide the icon and colour.
C = {}


def cat(key, values, group, label, rank, words=""):
    for v in values.split():
        C[(key, v)] = (group, label, rank, words)


# Food & drink
cat("amenity", "restaurant", "Food", "Restaurant", 30, "restaurant essen food eat dinner lunch gaststätte")
cat("amenity", "fast_food", "Food", "Fast food", 22, "fast food imbiss snack takeaway")
cat("amenity", "cafe", "Cafe", "Café", 30, "cafe café coffee kaffee")
cat("amenity", "ice_cream", "Cafe", "Ice cream", 25, "ice cream eis eisdiele gelato")
cat("amenity", "bar", "Food", "Bar", 22, "bar drinks cocktails")
cat("amenity", "pub", "Food", "Pub", 22, "pub kneipe beer bier")
cat("amenity", "biergarten", "Food", "Beer garden", 25, "biergarten beer garden")
cat("amenity", "food_court", "Food", "Food court", 22, "food court")
cat("amenity", "nightclub", "Food", "Nightclub", 22, "club disco nightclub")
cat("shop", "bakery", "Cafe", "Bakery", 25, "bakery bäckerei bäcker brot bread")
cat("shop", "pastry confectionery", "Cafe", "Pastry shop", 22, "konditorei pastry cake kuchen")
# Shopping
cat("shop", "supermarket", "Shop", "Supermarket", 35, "supermarket supermarkt groceries lebensmittel einkaufen")
cat("shop", "convenience", "Shop", "Convenience store", 25, "convenience kiosk späti shop")
cat("shop", "kiosk", "Shop", "Kiosk", 18, "kiosk")
cat("shop", "mall department_store", "Shop", "Shopping centre", 45, "shopping centre mall einkaufszentrum kaufhaus")
cat("shop", "clothes", "Shop", "Clothes", 22, "clothes kleidung fashion mode")
cat("shop", "shoes", "Shop", "Shoes", 20, "shoes schuhe")
cat("shop", "chemist", "Shop", "Drugstore", 28, "drugstore drogerie dm rossmann müller")
cat("shop", "books", "Shop", "Bookshop", 22, "books bücher buchhandlung bookshop")
cat("shop", "electronics mobile_phone computer", "Shop", "Electronics", 20, "electronics elektronik handy phone")
cat("shop", "optician", "Shop", "Optician", 20, "optician optiker glasses brille")
cat("shop", "hairdresser", "Shop", "Hairdresser", 18, "hairdresser friseur frisör haircut")
cat("shop", "beauty cosmetics", "Shop", "Beauty", 16, "beauty kosmetik")
cat("shop", "florist", "Shop", "Florist", 16, "florist blumen flowers")
cat("shop", "butcher", "Shop", "Butcher", 18, "butcher metzgerei metzger")
cat("shop", "jewelry", "Shop", "Jewellery", 16, "jewellery schmuck")
cat("shop", "sports outdoor bicycle", "Shop", "Sports shop", 20, "sports sport fahrrad bike")
cat("shop", "furniture doityourself hardware garden_centre", "Shop", "Home & DIY", 20, "baumarkt diy hardware möbel furniture")
cat("shop", "gift toys stationery", "Shop", "Gifts & toys", 16, "gift geschenke toys spielzeug schreibwaren")
cat("shop", "beverages wine alcohol", "Shop", "Drinks", 18, "getränke drinks wine wein")
cat("shop", "tobacco", "Shop", "Tobacco", 12, "tabak tobacco")
cat("amenity", "marketplace", "Shop", "Market", 35, "market markt wochenmarkt")
# Health
cat("amenity", "hospital", "Health", "Hospital", 70, "hospital krankenhaus klinikum klinik emergency notaufnahme")
cat("amenity", "clinic", "Health", "Clinic", 40, "clinic klinik praxis")
cat("amenity", "pharmacy", "Health", "Pharmacy", 40, "pharmacy apotheke chemist medicine medikamente")
cat("amenity", "doctors", "Health", "Doctor", 28, "doctor arzt ärztin praxis gp hausarzt")
cat("amenity", "dentist", "Health", "Dentist", 28, "dentist zahnarzt zahnärztin")
cat("healthcare", "physiotherapist", "Health", "Physiotherapy", 18, "physiotherapie physio")
cat("amenity", "veterinary", "Health", "Vet", 20, "vet tierarzt")
# Education
cat("amenity", "university", "University", "University", 100, "university universität uni hochschule campus")
cat("amenity", "college", "Education", "College", 60, "college hochschule fachhochschule")
cat("amenity", "school", "Education", "School", 45, "school schule gymnasium realschule grundschule")
cat("amenity", "kindergarten childcare", "Education", "Kindergarten", 25, "kindergarten kita daycare")
cat("amenity", "library", "Education", "Library", 50, "library bibliothek bücherei")
cat("amenity", "language_school music_school driving_school", "Education", "School", 18, "school schule kurs")
# Culture & sights
cat("tourism", "museum", "Culture", "Museum", 60, "museum")
cat("tourism", "attraction", "Culture", "Sight", 50, "sight sehenswürdigkeit attraction")
cat("tourism", "artwork", "Culture", "Artwork", 15, "art kunst sculpture statue")
cat("tourism", "gallery", "Culture", "Gallery", 35, "gallery galerie art kunst")
cat("tourism", "viewpoint", "Culture", "Viewpoint", 35, "viewpoint aussicht aussichtspunkt view")
cat("amenity", "theatre", "Culture", "Theatre", 55, "theatre theater bühne")
cat("amenity", "cinema", "Culture", "Cinema", 50, "cinema kino movies film")
cat("amenity", "arts_centre", "Culture", "Arts centre", 35, "arts kultur kulturzentrum")
cat("amenity", "concert_hall", "Culture", "Concert hall", 50, "concert konzert konzerthaus")
cat("amenity", "place_of_worship", "Culture", "Church", 35, "church kirche münster chapel kapelle mosque moschee synagogue")
cat("historic", "castle", "Culture", "Castle", 50, "castle schloss burg")
cat("historic", "monument memorial ruins city_gate tower archaeological_site", "Culture", "Historic site", 30, "historic denkmal monument tor")
cat("tourism", "information", "Service", "Tourist information", 30, "tourist information touristinfo")
# Leisure
cat("leisure", "park", "Park", "Park", 45, "park garten green grün")
cat("leisure", "garden", "Park", "Garden", 35, "garden garten")
cat("leisure", "playground", "Park", "Playground", 20, "playground spielplatz kids kinder")
cat("leisure", "sports_centre fitness_centre", "Leisure", "Sports & fitness", 30, "gym fitness sport fitnessstudio sporthalle")
cat("leisure", "stadium sports_hall", "Leisure", "Stadium", 40, "stadium stadion sporthalle")
cat("leisure", "swimming_pool water_park", "Leisure", "Swimming pool", 40, "swimming pool schwimmbad hallenbad bad therme")
cat("leisure", "beach_resort swimming_area", "Leisure", "Lido", 45, "beach strand strandbad lido baden swimming")
cat("natural", "beach", "Leisure", "Beach", 40, "beach strand baden")
cat("leisure", "marina", "Transport", "Marina", 40, "marina hafen harbour boats")
cat("leisure", "pitch", "Leisure", "Sports field", 12, "sportplatz pitch field")
cat("leisure", "nature_reserve", "Park", "Nature reserve", 40, "nature reserve naturschutzgebiet")
cat("tourism", "zoo", "Park", "Zoo", 50, "zoo tierpark")
cat("tourism", "camp_site", "Hotel", "Campsite", 30, "camping campsite campingplatz")
cat("landuse", "recreation_ground", "Park", "Recreation area", 25, "park")
cat("landuse", "cemetery", "Park", "Cemetery", 25, "cemetery friedhof")
cat("landuse", "allotments", "Park", "Allotments", 10, "kleingarten allotments")
cat("landuse", "forest", "Park", "Forest", 25, "wald forest wood")
cat("natural", "wood", "Park", "Forest", 25, "wald forest wood")
cat("natural", "peak", "Park", "Hill", 25, "hill berg")
cat("natural", "bay cape spring", "Park", "Nature", 20, "")
# Stay
cat("tourism", "hotel", "Hotel", "Hotel", 35, "hotel übernachtung")
cat("tourism", "hostel", "Hotel", "Hostel", 30, "hostel jugendherberge")
cat("tourism", "guest_house apartment motel", "Hotel", "Guest house", 22, "pension guest house ferienwohnung")
# Transport
cat("amenity", "ferry_terminal", "Transport", "Ferry", 60, "ferry fähre schiff boat pier anleger")
cat("public_transport", "station", "Transport", "Station", 60, "station bahnhof train zug")
cat("railway", "station", "Transport", "Train station", 80, "station bahnhof train zug db")
cat("railway", "halt", "Transport", "Train stop", 55, "station haltepunkt train zug")
cat("amenity", "parking", "Transport", "Parking", 18, "parking parkplatz parkhaus car park")
cat("amenity", "bicycle_rental", "Transport", "Bike rental", 18, "bike rental fahrradverleih")
cat("amenity", "car_rental car_sharing", "Transport", "Car rental", 18, "car rental autovermietung carsharing")
cat("amenity", "fuel", "Transport", "Petrol station", 22, "petrol fuel tankstelle gas station")
cat("amenity", "charging_station", "Transport", "EV charging", 12, "charging ladestation ev")
cat("amenity", "taxi", "Transport", "Taxi", 20, "taxi")
cat("man_made", "pier", "Transport", "Pier", 30, "pier steg anleger")
cat("man_made", "lighthouse tower", "Culture", "Landmark", 35, "tower turm leuchtturm")
# Services
cat("amenity", "bank", "Service", "Bank", 28, "bank sparkasse volksbank atm geldautomat")
cat("amenity", "atm", "Service", "ATM", 22, "atm geldautomat cash bargeld")
cat("amenity", "post_office", "Service", "Post office", 35, "post office post postamt dhl packstation")
cat("amenity", "post_box", "Service", "Post box", 8, "briefkasten post box")
cat("amenity", "police", "Service", "Police", 40, "police polizei")
cat("amenity", "fire_station", "Service", "Fire station", 30, "fire feuerwehr")
cat("amenity", "townhall", "Service", "Town hall", 50, "rathaus town hall city hall bürgerbüro")
cat("amenity", "courthouse", "Service", "Court", 30, "gericht court")
cat("amenity", "community_centre social_facility", "Service", "Community centre", 22, "community gemeinde")
cat("amenity", "toilets", "Service", "Toilets", 12, "toilet toilette wc restroom")
cat("amenity", "drinking_water", "Service", "Drinking water", 5, "water wasser")
cat("amenity", "coworking_space", "Service", "Coworking", 15, "coworking")
cat("office", "government", "Service", "Government office", 30, "amt behörde government")
cat("amenity", "embassy", "Service", "Consulate", 25, "consulate konsulat")
for v in "company it insurance lawyer estate_agent tax_advisor architect association educational_institution ngo research travel_agent employment_agency".split():
    C.setdefault(("office", v), ("Service", "Office", 12, "office büro"))
C[("office", "employment_agency")] = ("Service", "Job centre", 25, "arbeitsagentur jobcenter")
C[("office", "research")] = ("Education", "Research institute", 30, "forschung research institut")
# Buildings with a name (when nothing more specific is tagged)
cat("building", "university", "University", "University building", 55, "universität university uni")
cat("building", "college", "Education", "College", 40, "hochschule college")
cat("building", "school", "Education", "School", 40, "school schule")
cat("building", "kindergarten", "Education", "Kindergarten", 20, "kindergarten kita")
cat("building", "church chapel", "Culture", "Church", 35, "church kirche")
cat("building", "hospital", "Health", "Hospital", 55, "krankenhaus hospital")
cat("building", "train_station", "Transport", "Station", 50, "bahnhof station")
cat("building", "museum", "Culture", "Museum", 50, "museum")
cat("building", "hotel", "Hotel", "Hotel", 30, "hotel")
cat("building", "stadium", "Leisure", "Stadium", 35, "stadion")
cat("building", "civic public government", "Service", "Public building", 25, "")
cat("building", "dormitory", "Hotel", "Student housing", 25, "wohnheim studentenwohnheim dorm")
cat("amenity", "studentenwohnheim", "Hotel", "Student housing", 25, "wohnheim")
cat("place", "square", "Square", "Square", 45, "platz square")
cat("place", "locality", "District", "Area", 25, "")
cat("place", "island islet", "District", "Island", 45, "insel island")
cat("place", "neighbourhood quarter suburb hamlet village", "District", "Neighbourhood", 30, "")


# Category names in German (the app shows them when the phone is in German).
GERMAN = {
    "ATM": "Geldautomat", "Address": "Adresse", "Allotments": "Kleingärten", "Area": "Gebiet", "Arts centre": "Kulturzentrum",
    "Artwork": "Kunstwerk", "Bakery": "Bäckerei", "Bank": "Bank", "Bar": "Bar", "Beach": "Strand", "Beauty": "Kosmetik",
    "Beer garden": "Biergarten", "Bike rental": "Fahrradverleih", "Bookshop": "Buchhandlung", "Butcher": "Metzgerei",
    "Café": "Café", "Campsite": "Campingplatz", "Car rental": "Autovermietung", "Castle": "Schloss", "Cemetery": "Friedhof",
    "Church": "Kirche", "Cinema": "Kino", "Clinic": "Klinik", "Clothes": "Bekleidung", "College": "Hochschule",
    "Community centre": "Gemeindezentrum", "Concert hall": "Konzerthaus", "Consulate": "Konsulat",
    "Convenience store": "Lebensmittelladen", "Court": "Gericht", "Coworking": "Coworking", "Cycle path": "Radweg",
    "Dentist": "Zahnarzt", "Department store": "Kaufhaus", "Doctor": "Arztpraxis", "Drinking water": "Trinkwasser",
    "Drinks": "Getränke", "Drugstore": "Drogerie", "EV charging": "Ladestation", "Electronics": "Elektronik",
    "Fast food": "Imbiss", "Ferry": "Fähre", "Fire station": "Feuerwehr", "Florist": "Blumenladen", "Food court": "Food-Court",
    "Footpath": "Fußweg", "Forest": "Wald", "Gallery": "Galerie", "Garden": "Garten", "Gifts & toys": "Geschenke & Spielzeug",
    "Government office": "Behörde", "Guest house": "Pension", "Hairdresser": "Friseur", "Hill": "Hügel",
    "Historic site": "Historische Stätte", "Home & DIY": "Baumarkt & Wohnen", "Hospital": "Krankenhaus", "Hostel": "Hostel",
    "Hotel": "Hotel", "Ice cream": "Eisdiele", "Island": "Insel", "Jewellery": "Schmuck", "Job centre": "Arbeitsagentur",
    "Kindergarten": "Kita", "Kiosk": "Kiosk", "Landmark": "Wahrzeichen", "Library": "Bibliothek", "Lido": "Strandbad",
    "Marina": "Hafen", "Market": "Markt", "Museum": "Museum", "Nature": "Natur", "Nature reserve": "Naturschutzgebiet",
    "Neighbourhood": "Stadtteil", "Nightclub": "Club", "Office": "Büro", "Optician": "Optiker", "Park": "Park",
    "Parking": "Parkplatz", "Pastry shop": "Konditorei", "Path": "Weg", "Pedestrian zone": "Fußgängerzone",
    "Petrol station": "Tankstelle", "Pharmacy": "Apotheke", "Physiotherapy": "Physiotherapie", "Pier": "Anleger",
    "Playground": "Spielplatz", "Police": "Polizei", "Pool": "Bad", "Post box": "Briefkasten", "Post office": "Post",
    "Pub": "Kneipe", "Public building": "Öffentliches Gebäude", "Recreation area": "Erholungsgebiet",
    "Research institute": "Forschungsinstitut", "Restaurant": "Restaurant", "School": "Schule", "Shoes": "Schuhe",
    "Shopping centre": "Einkaufszentrum", "Sight": "Sehenswürdigkeit", "Sports & fitness": "Sport & Fitness",
    "Sports centre": "Sportzentrum", "Sports field": "Sportplatz", "Sports shop": "Sportgeschäft", "Square": "Platz",
    "Stadium": "Stadion", "Station": "Bahnhof", "Steps": "Treppe", "Street": "Straße", "Student housing": "Wohnheim",
    "Supermarket": "Supermarkt", "Swimming area": "Badestelle", "Swimming pool": "Schwimmbad", "Taxi": "Taxi",
    "Theatre": "Theater", "Tobacco": "Tabak", "Toilets": "Toiletten", "Tourist information": "Touristeninformation",
    "Town hall": "Rathaus", "Track": "Feldweg", "Train station": "Bahnhof", "Train stop": "Haltepunkt",
    "University": "Universität", "University building": "Universitätsgebäude", "Vet": "Tierarzt", "Viewpoint": "Aussichtspunkt",
    "Zoo": "Zoo", "Germany": "Deutschland", "Switzerland": "Schweiz", "Konstanz": "Konstanz",
}

ORDER = ["amenity", "shop", "railway", "public_transport", "tourism", "leisure", "healthcare", "historic",
         "office", "craft", "man_made", "natural", "landuse", "place", "building", "sport", "club"]

CUISINE = {
    "pizza": "pizza pizzeria", "italian": "italian italienisch pizza pasta", "burger": "burger",
    "kebab": "kebab döner doner", "asian": "asian asiatisch", "chinese": "chinese chinesisch",
    "japanese": "japanese japanisch", "sushi": "sushi", "indian": "indian indisch curry", "thai": "thai",
    "vietnamese": "vietnamese vietnamesisch pho", "greek": "greek griechisch", "turkish": "turkish türkisch",
    "mexican": "mexican mexikanisch tacos", "german": "german deutsch", "regional": "regional",
    "vegan": "vegan", "vegetarian": "vegetarian vegetarisch", "coffee_shop": "coffee kaffee",
    "ice_cream": "eis ice cream", "steak_house": "steak", "seafood": "fish fisch seafood", "fish": "fish fisch",
    "french": "french französisch", "spanish": "spanish spanisch tapas", "korean": "korean koreanisch",
    "bagel": "bagel", "sandwich": "sandwich", "chicken": "chicken hähnchen", "breakfast": "breakfast frühstück",
}


def fold(text):
    text = text.lower().replace("ß", "ss")
    return "".join(c for c in unicodedata.normalize("NFD", text) if unicodedata.category(c) != "Mn")


def slug(name):
    s = name.lower().replace("ä", "ae").replace("ö", "oe").replace("ü", "ue").replace("ß", "ss")
    s = "".join(c for c in unicodedata.normalize("NFD", s) if unicodedata.category(c) != "Mn")
    return re.sub(r"[^a-z0-9]+", "-", s).strip("-")


def meters(a, b):
    kx = 111_320 * math.cos(math.radians((a[0] + b[0]) / 2))
    return math.hypot((a[1] - b[1]) * kx, (a[0] - b[0]) * 111_180)


# Mapped, but nothing anyone searches for by name.
SKIP = {("amenity", v) for v in "bbq bench waste_basket recycling vending_machine shelter bicycle_parking parking_entrance "
        "parking_space hunting_stand telephone clock fountain grit_bin waste_disposal brothel stripclub "
        "smoking_area loading_dock watering_place lounger photo_booth".split()} | \
       {("tourism", "information")} | {("leisure", v) for v in "picnic_table firepit bleachers outdoor_seating".split()}


def classify(tags):
    if tags.get("tourism") == "information" and tags.get("information") in ("office", "visitor_centre"):
        return C[("tourism", "information")], "tourism", "information"
    if any((k, tags.get(k)) in SKIP for k in ("amenity", "tourism", "leisure")) and not any(
            tags.get(k) for k in ("shop", "office", "healthcare")):
        return None, None, None
    for key in ORDER:
        v = tags.get(key)
        if v and (key, v) in C:
            return C[(key, v)], key, v
    for key in ("shop", "amenity", "office", "craft", "tourism", "leisure", "healthcare", "sport", "club"):
        v = tags.get(key)
        if v and v not in ("yes", "no", "vacant"):
            group = {"shop": "Shop", "amenity": "Service", "office": "Service", "craft": "Service",
                     "tourism": "Culture", "leisure": "Leisure", "healthcare": "Health", "sport": "Leisure",
                     "club": "Leisure"}[key]
            label = v.replace("_", " ").capitalize()
            return (group, label, 12, v.replace("_", " ")), key, v
    return None, None, None


def clean(s):
    return s.replace("\t", " ").replace("\n", " ").strip()


def cluster(points, gap=250):
    """Split one street name into separate streets (the same name in two villages)."""
    parent = list(range(len(points)))

    def root(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i

    cell = defaultdict(list)
    size = gap / 111_000
    for i, (lat, lon) in enumerate(points):
        cx, cy = int(lon / size), int(lat / size)
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                for j in cell.get((cx + dx, cy + dy), []):
                    if meters(points[i], points[j]) <= gap:
                        parent[root(i)] = root(j)
        cell[(cx, cy)].append(i)
    groups = defaultdict(list)
    for i, p in enumerate(points):
        groups[root(i)].append(p)
    return list(groups.values())


ALIASES = Path(__file__).parent / "aliases.json"
# Places mapped under a bare letter or number: fine on a site plan, meaningless in a search result.
BARE_NAME_PREFIX = {"Pier": "Steg", "Hospital": "Haus", "University": "Gebäude", "University building": "Gebäude",
                    "College": "Gebäude"}


def tidy_names(rows):
    """Short, familiar names and search words from aliases.json, and bare letters made readable."""
    aliases = json.loads(ALIASES.read_text(encoding="utf-8"))
    used = set()
    for r in rows:
        alias = aliases.get(r[1])
        if alias:
            used.add(r[1])
            r[8] = " ".join(p for p in (r[8], r[1], alias.get("keywords", "")) if p)
            r[1] = alias.get("name", r[1])
        elif len(r[1]) <= 2 and r[3] in BARE_NAME_PREFIX:
            r[8] = " ".join(p for p in (r[8], r[1]) if p)
            r[1] = f"{BARE_NAME_PREFIX[r[3]]} {r[1]}"
    missing = set(aliases) - used
    if missing:
        sys.exit(f"aliases.json names places that no longer exist: {sorted(missing)}")


def main():
    db = sqlite3.connect(DB)
    base = db.execute("SELECT slug, name, kind, detail, area, lat, lon, rank FROM place").fetchall()
    areas = db.execute("SELECT name, kind, detail, lat, lon, rank FROM place WHERE kind IN ('District','Town')").fetchall()
    db.close()
    districts = [(n, (la, lo)) for n, k, d, la, lo, r in areas if k == "District"]
    towns = [(n, (la, lo), r) for n, k, d, la, lo, r in areas if k == "Town"]

    def nearest(options, point, max_m):
        best = min(options, key=lambda o: meters(o[1], point), default=None)
        return best[0] if best and meters(best[1], point) <= max_m else None

    def area(point, city=None):
        town = city or nearest([(n, p) for n, p, r in towns if r == 1], point, 5000) or nearest([(n, p) for n, p, _ in towns], point, 4000)
        district = nearest(districts, point, 1200)
        parts = [p for p in (district, town) if p]
        if len(parts) == 2 and parts[0] == parts[1]:
            parts = parts[:1]
        return ", ".join(parts)

    rows = []  # id, name, group, category, area, lat, lon, rank, keywords, address
    used = set()
    seen = defaultdict(list)  # folded name → points already in

    def unique(s):
        u, n = s, 2
        while u in used:
            u, n = f"{s}-{n}", n + 1
        used.add(u)
        return u

    # 1. What timetable.db already has (ids stay the same: saved places keep working).
    group_of = {"University": "University", "Library": "Education", "Station": "Transport", "Harbour": "Transport",
                "Square": "Square", "Street": "Street", "District": "District", "Town": "Town"}
    base_by_name = {}
    for s, name, kind, detail, ar, lat, lon, rank in base:
        used.add(s)
        group = group_of.get(kind) or {"Museum": "Culture", "Theatre": "Culture", "Cinema": "Culture",
                                       "Hospital": "Health", "Pharmacy": "Health", "Park": "Park", "Garden": "Park",
                                       "Café": "Cafe", "Restaurant": "Food", "Bar": "Food", "Pub": "Food",
                                       "Fast food": "Food", "Bakery": "Cafe", "Hotel": "Hotel", "School": "Education",
                                       "Supermarket": "Shop", "Shopping centre": "Shop", "Department store": "Shop",
                                       "Church": "Culture", "Sight": "Culture", "Castle": "Culture",
                                       "Viewpoint": "Culture", "Beach": "Leisure", "Pool": "Leisure",
                                       "Stadium": "Leisure", "Sports centre": "Leisure", "Zoo": "Park",
                                       "Post office": "Service", "Police": "Service", "Town hall": "Service",
                                       "Swimming area": "Leisure", "Market": "Shop"}.get(detail, "Service")
        row = [s, name, group, detail if kind not in ("Street",) else "Street", ar, lat, lon, rank, "", ""]
        rows.append(row)
        base_by_name[(fold(name), group)] = row
        seen[fold(name)].append((lat, lon))

    # 2. Everything named from OpenStreetMap.
    osm = json.loads((HERE / "data/search-osm.json").read_text())
    addresses = []
    added = 0
    for key, el in osm.items():
        t = el["tags"]
        point = (el["lat"], el["lon"])
        if "addr:housenumber" in t and "addr:street" in t:
            addresses.append((t["addr:street"], t["addr:housenumber"], t.get("addr:postcode", ""), t.get("addr:city", ""), point))
        name = t.get("name")
        if not name:
            continue
        info, k, v = classify(t)
        if not info:
            continue
        group, label, rank, words = info
        fname = fold(name)
        # Same thing twice (node + building, or already in timetable.db): keep one, add the words.
        near = [p for p in seen.get(fname, []) if meters(p, point) < 120]
        extra = [words]
        for c in t.get("cuisine", "").split(";"):
            extra.append(CUISINE.get(c.strip(), c.strip().replace("_", " ")))
        for alt in ("alt_name", "old_name", "short_name", "official_name", "brand", "operator", "name:en", "name:de"):
            if t.get(alt) and t[alt] != name:
                extra.append(t[alt])
        if t.get("diet:vegan") in ("yes", "only"):
            extra.append("vegan")
        keywords = " ".join(w for w in extra if w)
        street = t.get("addr:street")
        address = f"{street} {t.get('addr:housenumber', '')}".strip() if street else ""
        if near:
            existing = base_by_name.get((fname, group))
            if existing is not None and not existing[8]:
                existing[8] = keywords
                existing[9] = existing[9] or address
            continue
        seen[fname].append(point)
        rid = unique(slug(name) or "place")
        rows.append([rid, name, group, label, area(point, None), point[0], point[1], rank, keywords, address])
        added += 1

    # 3. Streets, footpaths and pedestrian zones the map tiles left out (Marktstätte, Seestraße …),
    #    from the walking network (DataPipeline/walk-graph).
    ways_file = ROOT / "DataPipeline/walk-graph/data/ways.json"
    n_streets = 0
    if ways_file.exists():
        named = defaultdict(list)
        kind_of = {}
        for w in json.loads(ways_file.read_text()):
            t = w["tags"]
            if t.get("name") and t.get("highway") not in (None, "bus_stop", "platform", "construction", "proposed"):
                named[t["name"]] += [tuple(p) for p in w["geom"]]
                if t["highway"] == "pedestrian" or kind_of.get(t["name"]) is None:
                    kind_of[t["name"]] = t["highway"]
        for name, points in named.items():
            for group in cluster(points):
                lat = sum(p[0] for p in group) / len(group)
                lon = sum(p[1] for p in group) / len(group)
                middle = min(group, key=lambda p: meters(p, (lat, lon)))
                if any(meters(p, middle) < 400 for p in seen.get(fold(name), [])):
                    continue
                seen[fold(name)].append(middle)
                hw = kind_of.get(name)
                label = {"pedestrian": "Pedestrian zone", "footway": "Footpath", "path": "Path",
                         "cycleway": "Cycle path", "steps": "Steps", "track": "Track"}.get(hw, "Street")
                rows.append([unique(slug(name)), name, "Street", label, area(middle), middle[0], middle[1],
                             35 if label == "Pedestrian zone" else 30 if label == "Street" else 15, "strasse street weg", ""])
                n_streets += 1

    # 4. House addresses: "Schottenstraße 12".
    addr_seen = set()
    n_addr = 0
    for street, number, postcode, city, point in addresses:
        name = f"{street} {number}"
        k = fold(name)
        if k in addr_seen:
            continue
        addr_seen.add(k)
        where = " ".join(p for p in (postcode, city) if p) or area(point)
        rows.append([unique("addr-" + slug(name)), name, "Address", "Address", where, point[0], point[1], 5, "", ""])
        n_addr += 1

    tidy_names(rows)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with gzip.open(OUT, "wt", encoding="utf-8") as f:
        for r in rows:
            f.write("\t".join([clean(str(r[0])), clean(r[1]), r[2], clean(r[3]), clean(r[4]),
                               f"{r[5]:.6f}", f"{r[6]:.6f}", str(r[7]), clean(r[8]), clean(r[9]),
                               clean(GERMAN.get(r[3], r[3]))]) + "\n")
    groups = defaultdict(int)
    for r in rows:
        groups[r[2]] += 1
    print(f"{len(rows)} entries ({len(base)} from timetable.db, {added} new places, {n_streets} more streets, {n_addr} addresses)")
    print(dict(sorted(groups.items(), key=lambda kv: -kv[1])))
    print(f"{OUT.relative_to(ROOT)}: {OUT.stat().st_size / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
