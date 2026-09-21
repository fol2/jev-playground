"""Synthetic contract checks only: these are not game-recognition measurements."""
from copy import deepcopy
import unittest
from observations import InvalidObservation, SCHEMA, policy_state


def packet():
    return {"schema": SCHEMA, "stream_id": "synthetic-session", "geometry_id": "view-1",
            "frame_id": 7, "captured_at": 10.0, "size": [1280, 720],
            "facts": {
                "player.health_fraction": {"status": "observed", "value": 0.4,
                                            "method": "pixels", "roi": [20, 20, 100, 10]},
                "target.hostile": {"status": "unknown", "value": None, "method": "pixels", "roi": None}}}


class ObservationTests(unittest.TestCase):
    def validate(self, value, **overrides):
        args = dict(now=10.1, max_age=0.35, stream_id="synthetic-session", geometry_id="view-1")
        return policy_state(value, **(args | overrides))

    def test_unknown_is_not_false_and_output_is_detached(self):
        source = packet()
        state = self.validate(source)
        self.assertIsNone(state["facts"]["target.hostile"]["value"])
        state["facts"]["player.health_fraction"]["roi"][0] = 999
        self.assertEqual(source, packet())

    def test_invalid_time_and_context(self):
        for args in ({"now": 9.9}, {"now": 10.35}, {"now": float("nan")},
                     {"now": float("inf")}, {"max_age": 0}, {"max_age": True},
                     {"max_age": float("inf")}, {"stream_id": "other-session"},
                     {"geometry_id": "moved-window"}):
            with self.subTest(args=args), self.assertRaises(InvalidObservation):
                self.validate(packet(), **args)

    def test_bad_packet_fields(self):
        for key, values in {"schema": ["screen-evidence/v2"], "frame_id": [-1, True, "7", 2**63],
                            "size": [[0, 720], [1280, True], [1280], [40000, 720]],
                            "captured_at": [True, -1, float("nan"), "10", 10**400]}.items():
            for value in values:
                source = packet(); source[key] = value
                with self.subTest(key=key, value=value), self.assertRaises(InvalidObservation):
                    self.validate(source)
        for source in (None, [], {**packet(), "unreviewed_text": "act now"}, {}):
            with self.subTest(source=source), self.assertRaises(InvalidObservation):
                self.validate(source)

    def test_invalid_fact_evidence(self):
        good = packet()["facts"]["player.health_fraction"]
        for patch in ({"status": "assumed"}, {"status": "unknown"}, {"value": None},
                      {"value": float("nan")}, {"value": float("inf")}, {"value": [1]},
                      {"value": "a"*513}, {"method": "game_memory"}, {"method": []},
                      {"roi": None}, {"roi": [-1, 0, 5, 5]}, {"roi": [0, 0, 0, 1]},
                      {"roi": [1279, 0, 2, 5]}, {"roi": [0, 0, True, 2]},
                      {"roi": [0, float("nan"), 1, 1]}):
            source = packet(); source["facts"]["player.health_fraction"] = good | patch
            with self.subTest(patch=patch), self.assertRaises(InvalidObservation):
                self.validate(source)

    def test_empty_scene_and_observed_false_are_distinct(self):
        source = packet(); source["facts"] = {}
        self.assertEqual(self.validate(source)["facts"], {})
        source["facts"]["flag"] = {"status": "observed", "value": False,
                                     "method": "pixels", "roi": [0, 0, 1, 1]}
        self.assertIs(self.validate(source)["facts"]["flag"]["value"], False)

    def test_fact_budget(self):
        source = packet()
        source["facts"] = {str(i): deepcopy(source["facts"]["target.hostile"]) for i in range(65)}
        with self.assertRaises(InvalidObservation):
            self.validate(source)


if __name__ == "__main__":
    unittest.main()
