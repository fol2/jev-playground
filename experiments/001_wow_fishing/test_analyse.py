"""Offline checks for the provisional rules; never call a provider."""

import unittest
from analyse import rules


def state(area=380, y=289, background=2):
    prior = [{"orange_pixels": 380, "y_px": 289, "background_change": 2}
             for _ in range(5)]
    return {"recent_observations": prior + [
        {"orange_pixels": area, "y_px": y, "background_change": background}]}


class RulesTests(unittest.TestCase):
    def test_waits_during_ordinary_bobbing(self):
        self.assertEqual(rules(state(y=291)), "WAIT")

    def test_recommends_reel_on_local_downward_area_drop(self):
        self.assertEqual(rules(state(area=112, y=300)), "REEL")

    def test_does_not_reel_on_missing_target_or_background_change(self):
        self.assertEqual(rules(state(area=0, y=None)), "ABSTAIN")
        self.assertNotEqual(rules(state(area=112, y=300, background=10)), "REEL")

    def test_needs_stable_history(self):
        missing = state(area=112, y=300)
        missing["recent_observations"][0] = {"orange_pixels": 0, "y_px": None}
        self.assertEqual(rules(missing), "ABSTAIN")
        self.assertEqual(rules({"recent_observations": []}), "ABSTAIN")


if __name__ == "__main__":
    unittest.main()
