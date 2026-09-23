"""Tabletop: situations from the owner's recorded demo play (23 Sept 2026) put to Jev as choices, each
compared with what the owner did. A regression check for Jev's hunting judgement: the state carries the
game's mechanics and costs as facts, not rules (a first run missed two situations until it did).

  python3 tabletop.py --check   offline: every scenario is well formed; no network
  python3 tabletop.py           live: asks Jev (TYPESAFE_API_KEY in the environment); no game input
"""
import json, os, sys, urllib.request

GOAL = ("The owner wants the character to level up by finishing quests quickly and safely, like a skilled human: "
        "plan a route through one region where several quests overlap, kill anything that counts for any unfinished "
        "objective, fight one enemy at a time, and never die.")
BASE = {"goal": GOAL, "character": {"class": "shaman", "level": 4, "health": 1.0, "mana": 1.0, "in_combat": False,
                                     "spells": ["Lightning Bolt (ranged, 2 s cast)", "Healing Wave", "weapon buff", "melee auto-attack"]}}

def sc(name, human, state, choices, instructions="Which action should the character take next?"):
    return dict(name=name, human=human, state={**BASE, **state}, choices=choices, instructions=instructions)

S = [
    sc("plan_region", "OPEN_MAP_PLAN", {"where": "Thendal Village, safe, just handed in quests",
        "objectives": ["Aggressive Encroachment 0/6 Scrawny Ursera Claw", "Foul Matriarch 0/8 Ursera Scavenger, 0/1 Head of Urs'anah",
                       "Call of Earth 0/1 Signet of Akir", "Harvesting Windstones 0/15 Windstone Cluster", "The Cirrusfly Queen 0/1"]},
       {"OPEN_MAP_PLAN": "Open the map and quest log, see where each quest's area is, and pick the region where most areas overlap",
        "GO_SELECTED_QUEST": "Walk straight to the area of the one quest currently selected in the tracker",
        "WANDER": "Walk out of the village and fight whatever appears"}),
    sc("choose_region", "SOUTH_GROVE", {"quest_areas": [
            {"region": "Thendal Grove south", "quests": ["Aggressive Encroachment", "Foul Matriarch", "Call of Earth"], "distance_yards": 150},
            {"region": "north shore", "quests": ["The Cirrusfly Queen"], "distance_yards": 120, "quest_level": 3},
            {"region": "scattered along roads", "quests": ["Harvesting Windstones"], "distance_yards": 0}]},
       {"SOUTH_GROVE": "Go to Thendal Grove south: three quests overlap there; gather Windstones seen on the way",
        "NORTH_SHORE": "Go to the north shore for the single nearer quest first",
        "WINDSTONES_FIRST": "Collect all 15 Windstones before anything else"}),
    sc("node_on_route", "GATHER", {"seen": ["a glowing cyan Raw Windstone crystal 8 yards off the path, no enemies near"],
        "objectives": ["Harvesting Windstones 4/15", "Aggressive Encroachment 0/6 (area 60 yards ahead)"]},
       {"GATHER": "Step over and harvest the Windstone (3 s), then continue", "IGNORE": "Keep running to the quest area"}),
    sc("pull_at_range", "BUFF_THEN_BOLT", {"target": {"name": "Scrawny Ursera", "level": 4, "hostile": True, "distance_yards": 28,
        "counts_for": "Scrawny Ursera Claw"}, "weapon_buff_active": False, "other_enemies_within_20_yards_of_target": 0},
       {"BUFF_THEN_BOLT": "Apply the weapon buff, then open with Lightning Bolt at range", "RUN_IN_MELEE": "Run up and auto-attack",
        "BOLT_NO_BUFF": "Bolt immediately without the buff"}),
    sc("mob_in_melee", "MELEE", {"in_combat": True, "target": {"name": "Scrawny Ursera", "health": 0.55, "distance_yards": 2},
        "note": "each hit taken pushes a cast back about 0.5-1 s, so a 2 s bolt in melee often takes 4 s or is interrupted, wasting its 15% mana; melee costs no mana and hits every swing; a melee mob runs as fast as the character, so backing off only gives it free hits on your back and you cannot get range"},
       {"MELEE": "Keep auto-attacking in melee", "CAST_BOLT": "Stand and cast Lightning Bolt", "BACK_OFF": "Walk back to try to get range for bolts (the mob follows at the same speed)"}),
    sc("facing_error", "TURN_TO_TARGET", {"in_combat": True, "error_text": "You are facing the wrong way!",
        "target": {"name": "Ursera Scavenger", "bearing_from_facing_degrees": 140, "distance_yards": 3}},
       {"TURN_TO_TARGET": "Turn until the target is in front, then attack", "RECAST": "Press the attack again", "TAB_NEW": "Tab to a different enemy"}),
    sc("tapped_mob", "SKIP_GREY", {"seen": [{"name": "Ursera Scavenger", "plate": "grey health bar", "fighting": "another player"},
        {"name": "Ursera Scavenger", "plate": "red", "distance_yards": 25, "alone": True}], "objectives": ["Foul Matriarch 3/8 Ursera Scavenger"]},
       {"SKIP_GREY": "Leave the grey one to the other player and pull the red one", "HELP_GREY": "Attack the grey one to finish it faster"}),
    sc("caster_mob", "BOLT_THEN_CLOSE", {"in_combat": True, "target": {"name": "Al'Aketh Neophyte", "casting": "Lightning Bolt",
        "distance_yards": 25, "stays_at_range": True}, "health": 0.8, "mana": 0.6,
        "note": "each Lightning Bolt costs about 15% mana; melee costs none; a duel at range spends your mana while its bolts keep hitting you"},
       {"BOLT_THEN_CLOSE": "Trade one bolt, then run in to melee so it stops casting", "BOLT_DUEL": "Stand and keep casting bolts at range",
        "FLEE": "Run away"}),
    sc("quest_giver_on_route", "TALK", {"seen": ["Hanaa Nightwind <Rangers of Thendal Grove> with a yellow ! over her head, 10 yards off the road"],
        "quest_log": "6/40"},
       {"TALK": "Talk to her and accept her quest", "IGNORE": "Keep going; quests only come from the village"}),
    sc("pack_ahead", "PULL_EDGE", {"seen": [{"name": "Al'Aketh Brute", "distance_yards": 30}, {"name": "Al'Aketh Brute", "distance_yards": 34},
        {"name": "Al'Aketh Neophyte", "distance_yards": 36}], "note": "the three stand within 8 yards of each other in ruins",
        "objectives": ["Al'Aketh Thugs 0/6 Brute, 0/4 Neophyte"]},
       {"PULL_EDGE": "Bolt the nearest one from the edge and fight it back where you stand, away from the others",
        "CHARGE_IN": "Run into the group and fight them together", "AVOID_ALL": "Leave the ruins"}),
    sc("low_mana_pull", "FIGHT", {"character": {**BASE["character"], "health": 0.95, "mana": 0.25},
        "target": {"name": "Scrawny Ursera", "level": 3, "alone": True, "distance_yards": 25, "counts_for": "Scrawny Ursera Claw 4/6"},
        "note": "melee does most of the damage against same-level mobs; a fight takes about 10 s and costs 15-30% health; drinking to full takes about 20 s"},
       {"FIGHT": "Pull it now and finish it mostly in melee", "DRINK_FIRST": "Sit and drink to full mana before pulling", "WAIT": "Stand and let mana regenerate naturally"}),
    sc("recover_after_hard_fight", "HEAL_THEN_DRINK", {"character": {**BASE["character"], "health": 0.3, "mana": 0.13},
        "enemies_near": 0, "bags": ["Refreshing Spring Water x5", "Tough Hunk of Bread x4"],
        "note": "Healing Wave costs about 25% mana and heals about 60%; sitting to drink and eat restores both in about 20 s; natural regeneration takes minutes"},
       {"HEAL_THEN_DRINK": "Cast Healing Wave, then sit and drink/eat to full", "PULL_NEXT": "Pull the next quest mob now", "STAND_REGEN": "Stand still until health and mana come back naturally"}),
    sc("distance_band", "BOLT_NOW", {"target": {"name": "Scrawny Ursera", "alone": True, "counts_for": "Scrawny Ursera Claw 2/6"},
        "weapon_buff_active": True, "hotkey_range": {"1 Attack (melee, 5 yd)": "red: out of range", "3 Earth Shock (20 yd)": "red: out of range",
                                                      "2 Lightning Bolt (30 yd)": "white: in range"},
        "note": "a hotkey's digit turns red while the target is beyond that spell's range"},
       {"BOLT_NOW": "Cast Lightning Bolt now", "APPROACH": "Walk closer first", "EARTH_SHOCK": "Cast Earth Shock now"}),
]

def ask(s, key):
    body = {"model": "jev-1.13.0", "state": s["state"],
            "questions": {"action": {"type": "choice", "instructions": s["instructions"], "criteria": s["choices"]}}}
    req = urllib.request.Request("https://api.typesafe.ai/v1/systemone", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    for attempt in range(3):
        try:
            return json.load(urllib.request.urlopen(req, timeout=20))
        except Exception as e:
            err = e
    raise err

def check():
    names = [s["name"] for s in S]
    assert len(set(names)) == len(names), "scenario names repeat"
    for s in S:
        assert len(s["choices"]) >= 2 and s["human"] in s["choices"], s["name"]
        assert all(isinstance(v, str) and v for v in s["choices"].values()), s["name"]
        json.dumps(s["state"])
    print(f"tabletop scenarios checked: {len(S)}")

if sys.argv[1:] == ["--check"]:
    check()
    sys.exit(0)
if sys.argv[1:]:
    sys.exit("usage: tabletop.py [--check]")
check()
key = os.environ["TYPESAFE_API_KEY"]
agree = 0
for s in S:
    a = ask(s, key)["answers"]["action"]
    probs = a.get("probabilities", {})
    pick = max(probs, key=probs.get) if probs else a.get("choice")
    agree += pick == s["human"]
    print(json.dumps({"scenario": s["name"], "jev": pick, "owner": s["human"], "match": pick == s["human"],
                      "p": {k: round(v, 2) for k, v in probs.items()}}))
print(f"agreement {agree}/{len(S)}")
