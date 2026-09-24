"""Put decision points read from a human's gameplay video to Jev; compare with the human.
  python3 video_jev.py DECISIONS.jsonl [...]    (TYPESAFE_API_KEY in the environment; KB=1 uses knowledge/)
  python3 video_jev.py --check                  (offline: every committed decision file parses and is askable)
Prints one JSON line per decision and the agreement; writes mismatches to <first file>.mismatches.jsonl."""
import json, os, sys, urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent

FACTS = ("Mechanics a skilled player knows: a same-level fight takes about 10 s and 15-30% health; melee costs no "
         "mana; each Lightning Bolt costs about 15% mana and each hit taken pushes a cast back 0.5-1 s; a melee "
         "creature runs as fast as the character, so walking away only gives it free hits; eating and drinking "
         "restore both to full in about 20 s, standing still takes minutes; creatures attack when approached "
         "within about 20 yards (less if lower level); grey nameplates are creatures another player has tagged and "
         "give no credit; a hotkey digit turns red while the target is out of that spell's range. Out of combat, health and mana regenerate while standing or walking once 5 s pass without casting; at levels 1-5 the pools are small and refill in about 10-20 s, so sitting to drink costs more time than it saves unless mana is below about 30%; a skilled player uses those seconds to turn the camera and find the next target.")
def knowledge():
    import re
    out, sec = {}, "general"
    for name in ("general.md", "shaman.md"):
        for line in open(HERE / "knowledge" / name):
            if line.startswith("## "): sec = name[:-3] + ": " + line[3:].strip()
            elif line.startswith("- "):
                fact = re.sub(r"\s*\[[a-z+\- ]+\].*$", "", line[2:].strip()).replace("**", "")
                out.setdefault(sec, []).append(fact)
    return out
if os.environ.get("KB") == "1": FACTS = knowledge()
GOAL = ("Level up a new Shaman by finishing quests quickly and safely, like a skilled human; never die.")

def ask(key, state, options):
    body = {"model": "jev-1.13.0", "state": {"goal": GOAL, "facts": FACTS, **state},
            "questions": {"action": {"type": "choice", "instructions": "Which action should the character take next?",
                                     "criteria": options}}}
    req = urllib.request.Request("https://api.typesafe.ai/v1/systemone", data=json.dumps(body).encode(),
                                 headers={"Authorization": "Bearer " + key, "Content-Type": "application/json"})
    err = None
    for _ in range(3):
        try:
            return json.load(urllib.request.urlopen(req, timeout=25))["answers"]["action"]
        except Exception as e:
            err = e
    raise err

def options_of(d):
    o = d.get("options")
    if isinstance(o, dict): return o
    out = {}
    for item in o or []:
        if isinstance(item, dict): out.update({k: str(v) for k, v in item.items()})
        elif isinstance(item, str) and ":" in item:
            k, v = item.split(":", 1); out[k.strip()] = v.strip()
    return out

if sys.argv[1:] == ["--check"]:
    n = 0
    for p in sorted(HERE.glob("*/part*_decisions.jsonl")):
        for l in open(p):
            d = json.loads(l)
            n += len(options_of(d)) >= 2 and d.get("human") in options_of(d)
    facts = sum(map(len, knowledge().values()))
    assert facts >= 100, f"knowledge base lost its facts ({facts})"
    print(f"askable decision points: {n}")
    sys.exit(0)

key = os.environ["TYPESAFE_API_KEY"]
rows = [json.loads(l) for p in sys.argv[1:] for l in open(p) if l.strip().startswith("{")]
agree, n, misses = 0, 0, []
for d in rows:
    opts = options_of(d)
    if len(opts) < 2 or d.get("human") not in opts: continue
    a = ask(key, d.get("state", {}), opts)
    probs = a.get("probabilities", {})
    pick = max(probs, key=probs.get) if probs else None
    n += 1; agree += pick == d["human"]
    line = {"t": d.get("t"), "jev": pick, "human": d["human"], "p": round(probs.get(pick, 0), 2)}
    print(json.dumps(line))
    if pick != d["human"]: misses.append({**d, "jev": pick, "p": {k: round(v, 2) for k, v in probs.items()}})
print(f"agreement {agree}/{n}")
with open(sys.argv[1] + ".mismatches.jsonl", "w") as f:
    for m in misses: f.write(json.dumps(m) + "\n")
