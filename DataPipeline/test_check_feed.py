#!/usr/bin/env python3
"""python3 DataPipeline/test_check_feed.py"""
import datetime
import unittest

from check_feed import findings

D = datetime.date


class Findings(unittest.TestCase):
    def check(self, modified, today):
        return findings("20261011", "20261212", modified, today)

    def test_quiet_when_nothing_is_due(self):
        self.assertEqual(self.check(D(2026, 10, 11), D(2026, 11, 1)), [])

    def test_a_newer_file_alerts(self):
        self.assertEqual(self.check(D(2026, 11, 20), D(2026, 11, 1)), ["New NVBW timetable published on 2026-11-20"])

    def test_only_the_nearest_deadline(self):
        self.assertEqual(self.check(D(2026, 10, 11), D(2026, 11, 12)), ["Timetable ends on 2026-12-12: 30 days or less left"])
        self.assertEqual(self.check(D(2026, 10, 11), D(2026, 12, 1)), ["Timetable ends on 2026-12-12: 14 days or less left"])
        self.assertEqual(self.check(D(2026, 10, 11), D(2026, 12, 12)), ["Timetable ends on 2026-12-12: 7 days or less left"])

    def test_after_the_end(self):
        self.assertEqual(self.check(D(2026, 10, 11), D(2026, 12, 13)), ["Timetable ended on 2026-12-12"])

    def test_a_failed_check_is_reported(self):
        self.assertEqual(self.check(None, D(2026, 11, 1)), ["Timetable feed could not be checked"])


if __name__ == "__main__":
    unittest.main()
