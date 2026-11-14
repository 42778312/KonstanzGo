#!/usr/bin/env python3
"""Record raw EFA-BW departure monitor responses as test fixtures.

One request every 2 seconds, six stops, nothing else. Run it at a weekday morning rush,
an evening and late at night, so the fixtures cover full buses, delays and quiet hours.

    python3 Server/scripts/record_fixtures.py
"""
import datetime
import pathlib
import time
import urllib.parse
import urllib.request

STOPS = {
    "bahnhof": "de:08335:11882",
    "sternenplatz": "de:08335:11918",
    "zaehringerplatz": "de:08335:11935",
    "universitaet": "de:08335:11925",
    "schulthaissstrasse": "de:08335:11905",
    "petershausen": "de:08335:6555",
}
BASE = "https://www.efa-bw.de/nvbw/XML_DM_REQUEST"
AGENT = "KonstanzGo-fixtures/1.0 (+https://github.com/42778312/KonstanzGo)"
OUT = pathlib.Path(__file__).resolve().parent.parent / "Tests" / "LiveCoreTests" / "Fixtures"


def url(gid: str) -> str:
    query = {
        "outputFormat": "rapidJSON", "type_dm": "stop", "mode": "direct", "useRealtime": "1",
        "depType": "stopEvents", "name_dm": gid, "limit": "40",
    }
    return BASE + "?" + urllib.parse.urlencode(query)


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    for index, (name, gid) in enumerate(STOPS.items()):
        if index:
            time.sleep(2)
        request = urllib.request.Request(url(gid), headers={"User-Agent": AGENT})
        with urllib.request.urlopen(request, timeout=10) as response:
            body = response.read()
        path = OUT / f"dm_{name}_{stamp}.json"
        path.write_bytes(body)
        print(f"{path.name}: {len(body)} bytes")


if __name__ == "__main__":
    main()
