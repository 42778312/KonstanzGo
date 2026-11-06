#!/usr/bin/env python3
"""
Says when the timetable needs attention: NVBW has published a newer file, the shipped one is about to end,
or the file can't be checked. Prints one "ALERT: <title>" line per finding; the titles stay the same from
day to day, so the daily workflow opens each only once. Standard library only.

    python3 DataPipeline/check_feed.py
"""
import datetime
import email.utils
import sqlite3
import urllib.request
from pathlib import Path

DB = Path(__file__).resolve().parents[1] / "App/Resources/Data/timetable.db"
FEED_URL = "https://www.nvbw.de/fileadmin/user_upload/service/open_data/fahrplandaten_mit_liniennetz/vhb.zip"
WARN_DAYS = (7, 14, 30)


def findings(feed_version, feed_end, last_modified, today):
    """`feed_version` and `feed_end` as yyyymmdd; `last_modified` a date, or None when the check failed."""
    version = datetime.datetime.strptime(feed_version, "%Y%m%d").date()
    end = datetime.datetime.strptime(feed_end, "%Y%m%d").date()
    alerts = []
    if last_modified is None:
        alerts.append("Timetable feed could not be checked")
    elif last_modified > version:
        alerts.append(f"New NVBW timetable published on {last_modified.isoformat()}")
    days_left = (end - today).days
    if days_left < 0:
        alerts.append(f"Timetable ended on {end.isoformat()}")
    else:
        # Only the nearest deadline, so it isn't announced three times.
        for limit in WARN_DAYS:
            if days_left <= limit:
                alerts.append(f"Timetable ends on {end.isoformat()}: {limit} days or less left")
                break
    return alerts


def feed_date(url=FEED_URL):
    request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "KonstanzGo feed watch"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            return email.utils.parsedate_to_datetime(response.headers["Last-Modified"]).date()
    except (OSError, TypeError, ValueError):
        return None


def main():
    meta = dict(sqlite3.connect(DB).execute("SELECT key, value FROM meta"))
    modified = feed_date()
    print(f"shipped feed {meta['feed_version']}, ends {meta['feed_end']}; NVBW's file dated {modified}")
    for alert in findings(meta["feed_version"], meta["feed_end"], modified, datetime.date.today()):
        print(f"ALERT: {alert}")


if __name__ == "__main__":
    main()
