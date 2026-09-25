import Foundation

// Tabletop: situations from the owner's recorded demo play (23 Sept 2026) put to Jev as choices, each
// compared with what the owner did. A regression check for Jev's hunting judgement: the state carries the
// game's mechanics and costs as facts, not rules (a first run missed two situations until it did).
//
//   tabletop --check   offline: every scenario is well formed; no network
//   tabletop           live: asks Jev (TYPESAFE_API_KEY in the environment); no game input
//
// Build: swiftc -parse-as-library m4/Tabletop.swift runtime/JSON.swift -o tabletop

let goal = "The owner wants the character to level up by finishing quests quickly and safely, like a skilled human: "
    + "plan a route through one region where several quests overlap, kill anything that counts for any unfinished "
    + "objective, fight one enemy at a time, and never die."
let base = JSON.object([
    ("goal", .string(goal)),
    ("character", try! JSON.parse(#"""
        {"class": "shaman", "level": 4, "health": 1.0, "mana": 1.0, "in_combat": false,
         "spells": ["Lightning Bolt (ranged, 2 s cast)", "Healing Wave", "weapon buff", "melee auto-attack"]}
        """#))])

struct Scenario {
    let name, human: String
    let state, choices: JSON
    var instructions = "Which action should the character take next?"
}

/// The base state with this scenario's fields set over it; a "character" field changes only the fields it names.
func sc(_ name: String, _ human: String, state: String, choices: String) -> Scenario {
    var merged = base
    for (key, value) in (try! JSON.parse(state)).pairs! {
        if key == "character" {
            merged = merged.setting(key, value.pairs!.reduce(base["character"]!) { $0.setting($1.0, $1.1) })
        } else {
            merged = merged.setting(key, value)
        }
    }
    return Scenario(name: name, human: human, state: merged, choices: try! JSON.parse(choices))
}

let scenarios = [
    sc("plan_region", "OPEN_MAP_PLAN", state: #"""
        {"where": "Thendal Village, safe, just handed in quests",
         "objectives": ["Aggressive Encroachment 0/6 Scrawny Ursera Claw", "Foul Matriarch 0/8 Ursera Scavenger, 0/1 Head of Urs'anah", "Call of Earth 0/1 Signet of Akir", "Harvesting Windstones 0/15 Windstone Cluster", "The Cirrusfly Queen 0/1"]}
        """#,
       choices: #"""
        {"OPEN_MAP_PLAN": "Open the map and quest log, see where each quest's area is, and pick the region where most areas overlap",
         "GO_SELECTED_QUEST": "Walk straight to the area of the one quest currently selected in the tracker",
         "WANDER": "Walk out of the village and fight whatever appears"}
        """#),
    sc("choose_region", "SOUTH_GROVE", state: #"""
        {"quest_areas": [{"region": "Thendal Grove south", "quests": ["Aggressive Encroachment", "Foul Matriarch", "Call of Earth"], "distance_yards": 150}, {"region": "north shore", "quests": ["The Cirrusfly Queen"], "distance_yards": 120, "quest_level": 3}, {"region": "scattered along roads", "quests": ["Harvesting Windstones"], "distance_yards": 0}]}
        """#,
       choices: #"""
        {"SOUTH_GROVE": "Go to Thendal Grove south: three quests overlap there; gather Windstones seen on the way",
         "NORTH_SHORE": "Go to the north shore for the single nearer quest first",
         "WINDSTONES_FIRST": "Collect all 15 Windstones before anything else"}
        """#),
    sc("node_on_route", "GATHER", state: #"""
        {"seen": ["a glowing cyan Raw Windstone crystal 8 yards off the path, no enemies near"],
         "objectives": ["Harvesting Windstones 4/15", "Aggressive Encroachment 0/6 (area 60 yards ahead)"]}
        """#,
       choices: #"""
        {"GATHER": "Step over and harvest the Windstone (3 s), then continue",
         "IGNORE": "Keep running to the quest area"}
        """#),
    sc("pull_at_range", "BUFF_THEN_BOLT", state: #"""
        {"target": {"name": "Scrawny Ursera", "level": 4, "hostile": true, "distance_yards": 28, "counts_for": "Scrawny Ursera Claw"},
         "weapon_buff_active": false,
         "other_enemies_within_20_yards_of_target": 0}
        """#,
       choices: #"""
        {"BUFF_THEN_BOLT": "Apply the weapon buff, then open with Lightning Bolt at range",
         "RUN_IN_MELEE": "Run up and auto-attack",
         "BOLT_NO_BUFF": "Bolt immediately without the buff"}
        """#),
    sc("mob_in_melee", "MELEE", state: #"""
        {"in_combat": true,
         "target": {"name": "Scrawny Ursera", "health": 0.55, "distance_yards": 2},
         "note": "each hit taken pushes a cast back about 0.5-1 s, so a 2 s bolt in melee often takes 4 s or is interrupted, wasting its 15% mana; melee costs no mana and hits every swing; a melee mob runs as fast as the character, so backing off only gives it free hits on your back and you cannot get range; Skysight's Elemental Blessing, when active, adds 10% run speed, under 1 yard a second: about 7 s of hits to leave its reach and 30 s to open Lightning Bolt range"}
        """#,
       choices: #"""
        {"MELEE": "Keep auto-attacking in melee",
         "CAST_BOLT": "Stand and cast Lightning Bolt",
         "BACK_OFF": "Walk back to try to get range for bolts (the mob follows at the same speed)"}
        """#),
    sc("facing_error", "TURN_TO_TARGET", state: #"""
        {"in_combat": true,
         "error_text": "You are facing the wrong way!",
         "target": {"name": "Ursera Scavenger", "bearing_from_facing_degrees": 140, "distance_yards": 3}}
        """#,
       choices: #"""
        {"TURN_TO_TARGET": "Turn until the target is in front, then attack",
         "RECAST": "Press the attack again",
         "TAB_NEW": "Tab to a different enemy"}
        """#),
    sc("tapped_mob", "SKIP_GREY", state: #"""
        {"seen": [{"name": "Ursera Scavenger", "plate": "grey health bar", "fighting": "another player"}, {"name": "Ursera Scavenger", "plate": "red", "distance_yards": 25, "alone": true}],
         "objectives": ["Foul Matriarch 3/8 Ursera Scavenger"]}
        """#,
       choices: #"""
        {"SKIP_GREY": "Leave the grey one to the other player and pull the red one",
         "HELP_GREY": "Attack the grey one to finish it faster"}
        """#),
    sc("caster_mob", "BOLT_THEN_CLOSE", state: #"""
        {"in_combat": true,
         "target": {"name": "Al'Aketh Neophyte", "casting": "Lightning Bolt", "distance_yards": 25, "stays_at_range": true},
         "health": 0.8,
         "mana": 0.6,
         "note": "each Lightning Bolt costs about 15% mana; melee costs none; a duel at range spends your mana while its bolts keep hitting you"}
        """#,
       choices: #"""
        {"BOLT_THEN_CLOSE": "Trade one bolt, then run in to melee so it stops casting",
         "BOLT_DUEL": "Stand and keep casting bolts at range",
         "FLEE": "Run away"}
        """#),
    sc("quest_giver_on_route", "TALK", state: #"""
        {"seen": ["Hanaa Nightwind <Rangers of Thendal Grove> with a yellow ! over her head, 10 yards off the road"],
         "quest_log": "6/40"}
        """#,
       choices: #"""
        {"TALK": "Talk to her and accept her quest",
         "IGNORE": "Keep going; quests only come from the village"}
        """#),
    sc("pack_ahead", "PULL_EDGE", state: #"""
        {"seen": [{"name": "Al'Aketh Brute", "distance_yards": 30}, {"name": "Al'Aketh Brute", "distance_yards": 34}, {"name": "Al'Aketh Neophyte", "distance_yards": 36}],
         "note": "the three stand within 8 yards of each other in ruins",
         "objectives": ["Al'Aketh Thugs 0/6 Brute, 0/4 Neophyte"]}
        """#,
       choices: #"""
        {"PULL_EDGE": "Bolt the nearest one from the edge and fight it back where you stand, away from the others",
         "CHARGE_IN": "Run into the group and fight them together",
         "AVOID_ALL": "Leave the ruins"}
        """#),
    sc("low_mana_pull", "FIGHT", state: #"""
        {"character": {"health": 0.95, "mana": 0.25},
         "target": {"name": "Scrawny Ursera", "level": 3, "alone": true, "distance_yards": 25, "counts_for": "Scrawny Ursera Claw 4/6"},
         "note": "melee does most of the damage against same-level mobs; a fight takes about 10 s and costs 15-30% health; drinking to full takes about 20 s"}
        """#,
       choices: #"""
        {"FIGHT": "Pull it now and finish it mostly in melee",
         "DRINK_FIRST": "Sit and drink to full mana before pulling",
         "WAIT": "Stand and let mana regenerate naturally"}
        """#),
    sc("recover_after_hard_fight", "HEAL_THEN_DRINK", state: #"""
        {"character": {"health": 0.3, "mana": 0.13},
         "enemies_near": 0,
         "bags": ["Refreshing Spring Water x5", "Tough Hunk of Bread x4"],
         "note": "Healing Wave costs about 25% mana and heals about 60%; sitting to drink and eat restores both in about 20 s; natural regeneration takes minutes"}
        """#,
       choices: #"""
        {"HEAL_THEN_DRINK": "Cast Healing Wave, then sit and drink/eat to full",
         "PULL_NEXT": "Pull the next quest mob now",
         "STAND_REGEN": "Stand still until health and mana come back naturally"}
        """#),
    sc("distance_band", "BOLT_NOW", state: #"""
        {"target": {"name": "Scrawny Ursera", "alone": true, "counts_for": "Scrawny Ursera Claw 2/6"},
         "weapon_buff_active": true,
         "hotkey_range": {"1 Attack (melee, 5 yd)": "red: out of range", "3 Earth Shock (20 yd)": "red: out of range", "2 Lightning Bolt (30 yd)": "white: in range"},
         "note": "a hotkey's digit turns red while the target is beyond that spell's range"}
        """#,
       choices: #"""
        {"BOLT_NOW": "Cast Lightning Bolt now",
         "APPROACH": "Walk closer first",
         "EARTH_SHOCK": "Cast Earth Shock now"}
        """#),
]

func body(_ s: Scenario) -> JSON {
    .object([("model", .string("jev-1.13.0")), ("state", s.state),
             ("questions", .object([("action", .object([("type", .string("choice")), ("instructions", .string(s.instructions)),
                                                        ("criteria", s.choices)]))]))])
}

func check() -> String? {
    let names = scenarios.map(\.name)
    if Set(names).count != names.count { return "scenario names repeat" }
    for s in scenarios {
        guard let choices = s.choices.pairs, choices.count >= 2, choices.contains(where: { $0.0 == s.human }),
              choices.allSatisfy({ !($0.1.string ?? "").isEmpty }), s.state.isFinite else { return s.name }
    }
    print("tabletop scenarios checked: \(scenarios.count)")
    return nil
}

func ask(_ s: Scenario, key: String) async throws -> JSON {
    var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/systemone")!, timeoutInterval: 20)
    request.httpMethod = "POST"
    request.httpBody = Data(body(s).text().utf8)
    request.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var last: Error = URLError(.unknown)
    for _ in 0..<3 {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? false else {
                throw URLError(.badServerResponse)
            }
            return try JSON.parse(String(decoding: data, as: UTF8.self))
        } catch {
            last = error
        }
    }
    throw last
}

@main
struct Tabletop {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        if let failed = check() { fail("scenario check failed: " + failed) }
        if args == ["--check"] { exit(0) }
        if !args.isEmpty { fail("usage: tabletop [--check]") }
        guard let key = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !key.isEmpty else { fail("TYPESAFE_API_KEY missing") }
        var agree = 0
        for s in scenarios {
            do {
                guard let answer = try await ask(s, key: key)["answers"]?["action"] else { fail("no answers.action from Jev") }
                let probs = answer["probabilities"]?.pairs ?? []
                // The most probable option, else the reply's choice (null when it gives neither, as Python's None).
                let pick = probs.isEmpty ? answer["choice"] ?? .null
                    : .string(probs.reduce(probs[0]) { ($1.1.number ?? 0) > ($0.1.number ?? 0) ? $1 : $0 }.0)
                let match = pick == .string(s.human)
                if match { agree += 1 }
                // Python's round(p, 2): a whole number stays whole.
                let p = JSON.object(probs.map { pair in
                    guard case let .double(d) = pair.1 else { return pair }
                    return (pair.0, .double(JSON.round(d, 2)))
                })
                print(JSON.object([("scenario", .string(s.name)), ("jev", pick), ("owner", .string(s.human)),
                                   ("match", .bool(match)), ("p", p)]).text())
            } catch {
                fail("Jev request failed: \(error)")
            }
        }
        print("agreement \(agree)/\(scenarios.count)")
    }

    static func fail(_ why: String) -> Never {
        FileHandle.standardError.write(Data((why + "\n").utf8))
        exit(1)
    }
}
