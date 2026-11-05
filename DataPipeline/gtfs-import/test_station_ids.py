"""python3 DataPipeline/gtfs-import/test_station_ids.py"""
import unittest

from station_ids import assign


class StationIdsTest(unittest.TestCase):
    def test_the_first_import_numbers_in_order(self):
        numbers, known = assign([{"a"}, {"b"}], {})
        self.assertEqual(numbers, [1, 2])
        self.assertEqual(known, {"a": 1, "b": 2})

    def test_a_stop_keeps_its_number_when_another_is_added_before_it(self):
        numbers, _ = assign([{"new"}, {"a"}, {"b"}], {"a": 1, "b": 2})
        self.assertEqual(numbers, [3, 1, 2])

    def test_a_removed_stops_number_is_never_used_again(self):
        numbers, known = assign([{"b"}, {"new"}], {"a": 1, "b": 2})
        self.assertEqual(numbers, [2, 3])
        self.assertEqual(known["a"], 1)

    def test_merged_stop_areas_share_a_number(self):
        numbers, known = assign([{"train", "bus"}], {"bus": 7})
        self.assertEqual(numbers, [7])
        self.assertEqual(known["train"], 7)

    def test_a_split_stop_gives_only_one_side_the_old_number(self):
        numbers, _ = assign([{"a"}, {"a2", "a"}], {"a": 1})
        self.assertEqual(sorted(numbers), [1, 2])


if __name__ == "__main__":
    unittest.main()
