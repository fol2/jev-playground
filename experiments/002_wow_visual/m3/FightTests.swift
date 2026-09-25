// Offline M3 checks with synthetic RGBA, a simulated fight and a scripted Jev. They prove
// detectors, admissibility, episode rules and choice parsing: SIMULATION ONLY. Nothing here
// shows that WoW applies the keys, that HUD calibration matches a live frame, or that Jev
// would pick the same actions.
import Foundation

@main
struct FightTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }
    static func fails(_ body: () throws -> Void) -> Bool {
        do { try body(); return false } catch { return true }
    }

    static func main() async {
        print("M3 fight checks: synthetic HUD, simulated fight, scripted Jev.")
        print("SIMULATION-ONLY proof: not live capture, OS input or a TypeSafe call.")
        detectors()
        casts()
        admissibility()
        skills()
        episode()
        choices()
        names()
        packets()
        arguments()
        await watchdog()
        liveKeys()
        await sim()
        tactics()
        await chains()
        print("fight checks passed: \(checks)")
    }

    static func blank() -> RGBA {
        RGBA(width: HUD.width, height: HUD.height,
             pixels: [UInt8](repeating: 0, count: HUD.width * HUD.height * 4))
    }

    static func paint(_ image: inout RGBA, x0: Int, x1: Int, y0: Int, y1: Int, r: UInt8, g: UInt8, b: UInt8) {
        var pixels = image.pixels
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * image.width + x) * 4
                pixels[i] = r; pixels[i + 1] = g; pixels[i + 2] = b; pixels[i + 3] = 255
            }
        }
        image = RGBA(width: image.width, height: image.height, pixels: pixels)
    }

    static func detectors() {
        let empty = observe(blank(), plates: false)
        check(empty.player == 0 && empty.target == 0 && empty.mana == 0 && !empty.combat && !empty.casting
              && empty.castFill == 0 && !empty.rangeRed && !empty.buff && !empty.errorRed && empty.plate == nil,
              "absent HUD: every detector is off on a black frame")

        var health = blank()
        paint(&health, x0: HUD.playerX0, x1: HUD.playerX1, y0: HUD.playerY, y1: HUD.playerY + 1, r: 20, g: 200, b: 20)
        check(abs(observe(health, plates: false).player - 1) < 1e-9, "player health present: a full green row reads 1")

        var tgt = blank()
        paint(&tgt, x0: HUD.targetX0, x1: HUD.targetX0 + HUD.targetSpan / 2, y0: HUD.targetY, y1: HUD.targetY + 1,
              r: 20, g: 200, b: 20)
        check(abs(observe(tgt, plates: false).target - 0.5) < 1e-9, "target health present: a half green row reads 0.5")

        var mana = blank()
        paint(&mana, x0: HUD.manaX0, x1: HUD.manaX0 + HUD.manaSpan, y0: HUD.manaY, y1: HUD.manaY + 1, r: 20, g: 20, b: 180)
        check(abs(observe(mana, plates: false).mana - 1) < 1e-9, "mana present: a full blue row reads 1")
        var texted = blank()
        paint(&texted, x0: HUD.manaX0, x1: HUD.manaX0 + 78, y0: HUD.manaY, y1: HUD.manaY1, r: 30, g: 60, b: 200)
        paint(&texted, x0: HUD.manaX0 + 40, x1: HUD.manaX0 + 90, y0: HUD.manaY, y1: HUD.manaY1, r: 235, g: 235, b: 235)
        paint(&texted, x0: HUD.manaX0 + 90, x1: HUD.manaX0 + 97, y0: HUD.manaY, y1: HUD.manaY1, r: 30, g: 60, b: 200)
        check(abs(observe(texted, plates: false).mana - 97.0 / 130) < 1e-9,
              "mana under the owner's number text: the fill's right end counts, not the blue pixels")

        var ring = blank()
        paint(&ring, x0: HUD.combatX0, x1: HUD.combatX1, y0: HUD.combatY0, y1: HUD.combatY0 + 4, r: 200, g: 0, b: 0)
        check(observe(ring, plates: false).combat, "combat present: red ring pixels above the threshold")
        var faint = blank()
        paint(&faint, x0: HUD.combatX0, x1: HUD.combatX0 + 2, y0: HUD.combatY0, y1: HUD.combatY0 + 2, r: 200, g: 0, b: 0)
        check(!observe(faint, plates: false).combat, "combat absent: too few red pixels")

        var bar = blank()
        paint(&bar, x0: HUD.castX0, x1: HUD.castX1, y0: HUD.castY0, y1: HUD.castY0 + 2, r: 100, g: 100, b: 100)
        paint(&bar, x0: HUD.castX0, x1: HUD.castX1, y0: HUD.castFillY, y1: HUD.castFillY + 1, r: 200, g: 180, b: 50)
        let casting = observe(bar, plates: false)
        check(casting.casting && abs(casting.castFill - 1) < 1e-9, "cast bar present: track and a full yellow fill row")

        var digit = blank()
        paint(&digit, x0: HUD.rangeX0, x1: HUD.rangeX0 + 6, y0: HUD.rangeY0, y1: HUD.rangeY0 + 2, r: 160, g: 40, b: 40)
        check(observe(digit, plates: false).rangeRed, "range present: dark-red slot-2 digit")
        var white = blank()
        paint(&white, x0: HUD.rangeX0, x1: HUD.rangeX0 + 6, y0: HUD.rangeY0, y1: HUD.rangeY0 + 2, r: 220, g: 220, b: 220)
        check(!observe(white, plates: false).rangeRed, "range absent: a white digit is not the dark-red rule")

        var glow = blank()
        paint(&glow, x0: HUD.buffX0, x1: HUD.buffX0 + 20, y0: HUD.buffY0, y1: HUD.buffY0 + 10, r: 40, g: 180, b: 40)
        check(observe(glow, plates: false).buff, "buff present: green icon pixels above the threshold")
        check(!observe(blank(), plates: false).buff, "buff absent")

        var err = blank()
        paint(&err, x0: HUD.errorX0, x1: HUD.errorX0 + 20, y0: HUD.errorY0, y1: HUD.errorY0 + 2, r: 220, g: 80, b: 80)
        check(observe(err, plates: false).errorRed, "error text present: red pixels above the threshold")
        check(!observe(blank(), plates: false).errorRed, "error text absent")

        let plated = observe(blank(), plates: true)
        check(plated.plate == nil && plated.ground == nil, "plates on a blank frame find nothing")
        var named = blank()
        paint(&named, x0: 1200, x1: 1333, y0: 400, y1: 403, r: 235, g: 235, b: 235)
        paint(&named, x0: 1200, x1: 1333, y0: 403, y1: 413, r: 200, g: 200, b: 40)
        paint(&named, x0: 1200, x1: 1333, y0: 413, y1: 416, r: 235, g: 235, b: 235)
        check(observe(named, plates: true).plate != nil, "plates: true finds a white-outlined nameplate")
        check(observe(named, plates: false).plate == nil, "plates: false never searches for a nameplate")
    }

    static func casts() {
        var watch = CastWatch(pre: Obs(casting: false, castFill: 0))
        check(watch.sawGap && !watch.seen, "a gap is already open when the bar is empty")
        watch.feed(Obs(casting: true, castFill: 0.8))
        check(watch.seen && watch.reached75, "a fresh bar after a gap that reaches 75 % is a finished cast")

        var chain = CastWatch(pre: Obs(casting: true, castFill: 0.9))
        check(!chain.sawGap, "a bar already filling is not a fresh cast yet")
        chain.feed(Obs(casting: true, castFill: 0.5))
        check(chain.sawGap && chain.seen && !chain.reached75, "a fill drop of more than 0.3 starts the next cast")
        chain.feed(Obs(casting: true, castFill: 0.8))
        check(chain.reached75, "the chained cast then reaching 75 % counts")
        var tiny = CastWatch(pre: Obs(casting: true, castFill: 0.9))
        tiny.feed(Obs(casting: true, castFill: 0.7))
        check(!tiny.sawGap, "a fill drop of 0.2 is not a new cast")
    }

    static func has(_ actions: [FightAction], _ wanted: FightAction) -> Bool { actions.contains(wanted) }

    static func admissibility() {
        let none = admissible(Obs(), Episode())
        check(has(none, .selectTarget) && has(none, .wait) && has(none, .stop) && !has(none, .lootCorpse)
              && !has(none, .castLightningBolt) && has(none, .buffWeapon),
              "no target: SELECT_TARGET (and BUFF), never CAST or LOOT")

        let plate = Plate(x0: 1214, x1: 1346, top: 400, bottom: 413)
        let unlooted = Episode(engaged: true, killed: true)
        let dead = admissible(Obs(combat: true), unlooted)
        check(has(dead, .lootCorpse) && !has(dead, .selectTarget),
              "unlooted kill: LOOT_CORPSE and no SELECT_TARGET")

        check(!has(admissible(Obs(buff: true), Episode()), .buffWeapon), "buff present: no BUFF_WEAPON")
        check(has(admissible(Obs(buff: false), Episode()), .buffWeapon), "buff absent: BUFF_WEAPON")

        let out = admissible(Obs(target: 1, rangeRed: true, plate: plate), Episode())
        check(has(out, .approachToRange) && !has(out, .castLightningBolt),
              "range red: APPROACH_TO_RANGE and no CAST")
        let inn = admissible(Obs(target: 1, rangeRed: false, plate: plate), Episode())
        check(has(inn, .castLightningBolt) && !has(inn, .approachToRange),
              "in range: CAST and no APPROACH")

        check(!has(admissible(Obs(target: 1, plate: plate), Episode(meleeOn: true)), .startMelee),
              "melee on: no START_MELEE")
        check(has(admissible(Obs(target: 1, plate: plate), Episode(meleeOn: false)), .startMelee),
              "melee off: START_MELEE")

        check(has(admissible(Obs(player: 0.8), Episode()), .heal), "hurt: HEAL")
        check(!has(admissible(Obs(player: 1), Episode()), .heal), "full health: no HEAL")

        let left = Plate(x0: 900, x1: 1032, top: 400, bottom: 413)
        check(has(admissible(Obs(target: 1, plate: left), Episode()), .faceTarget),
              "a nameplate left of centre admits FACE_TARGET")
        check(!has(admissible(Obs(target: 1, plate: plate), Episode()), .faceTarget),
              "a centred nameplate does not admit FACE_TARGET")
        // 24 Sept live: a second creature hit from behind; with no nameplate FACE_TARGET was never offered.
        check(has(admissible(Obs(target: 1), Episode()), .faceTarget), "a live target with no nameplate in view admits FACE_TARGET")
        check(!has(admissible(Obs(target: 0), Episode()), .faceTarget), "a dead target: no FACE_TARGET")
    }

    /// Tooltip lines as Vision read them live on 24 Sept (top to bottom), one per main-bar slot.
    static let bar24Sept: [[String]] = [
        ["Attack", "Press F6 to submit an issue for this Spell"],
        ["Lightning Bolt", "Rank 1", "15 Mana", "30 yd range", "1.5 sec cast", "Casts a bolt of lightning at the target for",
         "14 to 17 Nature damage.", "Press F6 to submit an issue for this Spell"],
        ["Earth Shock", "Rank 1", "30 Mana", "20 yd range", "6 sec cooldown", "Instant", "Instantly shocks the target with",
         "concussive force, causing 17 to 20", "Nature damage. It also interrupts", "Press F6 to submit an issue for this Spell"],
        ["Rank 1", "Healing Wave", "25 Mana", "40 yd range", "1.5 sec cast", "Heals a friendly target for 36 to 47.",
         "Press F6 to submit an issue for this Spell"],
        [], [], [],
        ["Rockbiter Weapon", "Rank 1", "15 Mana", "Instant", "Imbue the Shaman's weapon,", "increasing melee attack power by 45",
         "Lasts for 60 minutes.", "weapon.", "Press F6 to submit an issue for this Spell"],
        ["Racial", "Skysight", "0.5 sec cast", "2 min cooldown", "Attempt to draw power from a", "its blessing, increasing your movement",
         "Press F6 to submit an issue for this Spell"],
        ["Racial", "Walk on Air", "2 min cooldown", "Instant", "Glide downward through the air for 10",
         "Press F6 to submit an issue for this Spell"],
        ["Refreshing Spring Water", "Use: Restores 145 mana over 18 sec.", "Must remain seated while drinking.", "Sell Price: 5",
         "Press F6 to submit an issue for this Item"],
        ["Tough Jerky", "Use: Restores 58 health over 18 sec.", "Must remain seated while eating.", "Sell Price: 3",
         "Press F6 to submit an issue for this Item"],
    ]

    static func skills() {
        let bar = bar24Sept.map(parseTooltip)
        check(bar.map { $0?.name } == ["Attack", "Lightning Bolt", "Earth Shock", "Healing Wave", nil, nil, nil, "Rockbiter Weapon",
                                       "Skysight", "Walk on Air", "Refreshing Spring Water", "Tough Jerky"], "tooltip names, empty slots nil")
        check(bar[1]?.cast == 1.5 && bar[2]?.cast == nil && bar[8]?.cast == 0.5, "cast times; instant is nil")
        check(bar.map { $0.flatMap(role) } == [.melee, .bolt, .shock, .heal, nil, nil, nil, .buff, nil, nil, .drink, .food],
              "roles: Earth Shock is the shock (instant damage with a cooldown); Skysight and Walk on Air have none")
        let (keys, problems) = assignRoles(bar)
        check(assignRoles(Array(bar.prefix(9)), required: fightRoles).problems.isEmpty,
              "a fight needs no food or drink on the bar")
        check(assignRoles(Array(bar.prefix(9))).problems == ["no drink skill on the bar", "no food skill on the bar"],
              "a hunt does")
        check(problems.isEmpty && keys == [.melee: 18, .bolt: 19, .shock: 20, .heal: 21, .buff: 28, .drink: 27, .food: 24],
              "24 Sept bar: heal is key 4 and the enchant key 8, not the 23 Sept 3 and 4")
        check(assignRoles(bar.enumerated().map { $0.offset == 3 ? nil : $0.element }).problems == ["no heal skill on the bar"],
              "a missing heal holds a live run")
        check(assignRoles(bar.enumerated().map { $0.offset == 4 ? bar[1] : $0.element }).problems.first?.contains("two slots") == true,
              "one tooltip on two slots holds a live run (the pointer was contested)")
        check(parseTooltip(["Earth Shock", "30 Mana"]) == nil, "no tooltip footer: not a tooltip")
        // Slot 8 live: the edge of a "Juvenile Vuldren" nameplate sat above the tooltip, inside the crop.
        let boxes: [(text: String, x: Double, y: Double)] = [
            ("e Vuldren", 0, 40), ("Rockbiter Weapon", 29, 74), ("Rank 1", 251, 75), ("15 Mana", 29, 91), ("Instant", 29, 107),
            ("Imbue the Shaman's weapon,", 29, 119), ("Lasts for 60 minutes.", 93, 173), ("Press F6 to submit an issue for this Spell", 31, 203)]
        check(parseTooltip(tooltipLines(boxes))?.name == "Rockbiter Weapon", "world text above the tooltip is not its name")
        check(tooltipLines(boxes.filter { !$0.text.hasPrefix("Press") }).isEmpty, "no footer: no tooltip lines")
        check(parseTooltip(tooltipLines(boxes.reversed()))?.name == "Rockbiter Weapon" && tooltipLines(boxes.reversed()).first == "Rockbiter Weapon",
              "Vision's order does not matter: lines are sorted top to bottom")
        check(facingError("Target needs to be in front of you.") && facingError("You are facing the wrong way!")
              && !facingError("Out of range.") && !facingError(nil), "the game's facing errors, and only those, trigger the F9 turn")
        let saved = (FightLimits.bolt, HUD.rangeX0)
        applyRoles([.bolt: 20])
        check(FightLimits.bolt == 20 && HUD.rangeX0 == 758, "the range digit box follows the bolt's slot")
        applyRoles([.bolt: saved.0])
        check(HUD.rangeX0 == saved.1, "and returns with it")
    }

    static func episode() {
        var e = Episode()
        e.update(Obs(target: 0, combat: true))
        check(e.engaged && e.killed, "kill while the combat ring is still red counts")
        var mid = Episode()
        mid.update(Obs(target: 0.5))
        check(mid.engaged && !mid.killed, "a living target below 99 % engages and is not a kill")
        var full = Episode()
        full.update(Obs(target: 1.0, plate: Plate(x0: 1214, x1: 1346, top: 400, bottom: 413)))
        check(!full.engaged && !full.killed, "a full-health selected target is not yet engaged")
        var after = Episode(engaged: true)
        after.update(Obs(target: 0))
        check(after.killed, "an engaged target that disappears is a kill even without the ring")
    }

    static func body(model: String = FightLimits.model, choice: String = "WAIT",
                     confidence: Double = 0.9, probabilities: [String: Double]? = nil,
                     answers: Bool = true, action: Bool = true) -> [String: Any] {
        let probs: [String: Double] = probabilities ?? ["WAIT": 0.6, "STOP": 0.4]
        var inner: [String: Any] = ["choice": choice, "confidence": confidence, "probabilities": probs]
        if !action { inner = [:] }
        var root: [String: Any] = ["model": model]
        if answers { root["answers"] = ["action": inner] as [String: Any] }
        return root
    }

    static func choices() {
        let allowed: [FightAction] = [.wait, .stop]
        check(parseChoice(body(), admissible: allowed, model: FightLimits.model)?.action == .wait,
              "parseChoice accepts a well-formed answer over exactly the admissible keys")
        check(parseChoice(body(model: "jev-0"), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects the wrong model")
        check(parseChoice(body(answers: false), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects a missing answer")
        check(parseChoice(body(action: false), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects a missing action object")
        check(parseChoice(body(choice: "HEAL"), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects a choice that is not admissible")
        check(parseChoice(body(choice: "NOPE"), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects an unknown choice name")
        check(parseChoice(body(probabilities: ["WAIT": 1]), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects probabilities missing an admissible key")
        check(parseChoice(body(probabilities: ["WAIT": 0.5, "STOP": 0.4, "HEAL": 0.1]), admissible: allowed,
                          model: FightLimits.model) == nil,
              "parseChoice rejects probabilities with an extra key")
        check(parseChoice(body(probabilities: ["WAIT": 1.01, "STOP": 0]), admissible: allowed,
                          model: FightLimits.model) == nil,
              "parseChoice rejects a probability above 1 (sum within slack)")
        check(parseChoice(body(probabilities: ["WAIT": 1.0, "STOP": -0.01]), admissible: allowed,
                          model: FightLimits.model) == nil,
              "parseChoice rejects a probability below 0")
        check(parseChoice(body(probabilities: ["WAIT": 0.4, "STOP": 0.4]), admissible: allowed,
                          model: FightLimits.model) == nil,
              "parseChoice rejects a probability sum off by more than 0.02")
        check(parseChoice(body(confidence: 1.1), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects confidence above 1")
        check(parseChoice(body(confidence: -0.01), admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects confidence below 0")
        var missingConf = body()
        if var answers = missingConf["answers"] as? [String: Any],
           var action = answers["action"] as? [String: Any] {
            action.removeValue(forKey: "confidence")
            answers["action"] = action
            missingConf["answers"] = answers
        }
        check(parseChoice(missingConf, admissible: allowed, model: FightLimits.model) == nil,
              "parseChoice rejects a missing confidence")
        check(parseChoice(body(probabilities: ["WAIT": 0.5, "STOP": 0.51]), admissible: allowed,
                          model: FightLimits.model)?.action == .wait,
              "parseChoice allows a probability sum within 0.02")
    }

    static func names() {
        check(fuzzyNameMatch("Xypenil Uuldren", ["juvenile vuldren"]),
              "Xypenil Uuldren matches juvenile vuldren by a 4-letter run")
        check(!fuzzyNameMatch("Pesky Cirrusfly", ["juvenile vuldren"]),
              "Pesky Cirrusfly does not match juvenile vuldren")
        check(fuzzyNameMatch("Pesky Cirrusfly", ["pesky cirrusfly"]),
              "a known Cirrusfly name matches itself")
        check(!fuzzyNameMatch("XP: 15", ["juvenile vuldren", "pesky cirrusfly"]),
              "floating XP text is not a corpse name")
        check(!fuzzyNameMatch("Yala Windwatcher", ["roiling wind"]) && fuzzyNameMatch("Rolling Wlnd", ["roiling wind"]),
              "one shared run (wind) is not a Roiling Wind; a noisy Roiling Wind still is")
    }

    static func keyLike(_ object: Any) -> Bool {
        if let d = object as? [String: Any] {
            for (k, v) in d {
                let n = k.lowercased()
                if n.contains("key") || n.contains("auth") || n.contains("secret") || n.contains("token")
                    || n.contains("bearer") || n.contains("password") { return true }
                if keyLike(v) { return true }
            }
        } else if let a = object as? [Any] {
            return a.contains { keyLike($0) }
        } else if let s = object as? String {
            let n = s.lowercased()
            return n.contains("api_key") || n.contains("typesafe") || n.contains("bearer ")
        }
        return false
    }

    static func packets() {
        let o = Obs(player: 0.9, mana: 0.8, target: 0.5, combat: true,
                    plate: Plate(x0: 1214, x1: 1346, top: 400, bottom: 413))
        let state = statePacket(obs: o, episode: Episode(engaged: true, meleeOn: true),
                                lastAction: "CAST_LIGHTNING_BOLT", lastResult: "cast at 75 %",
                                events: ["target lost 10% health since the last decision"])
        check(!keyLike(state), "statePacket has no API key or key-like field")
        let text = String(decoding: try! JSONSerialization.data(withJSONObject: state), as: UTF8.self).lowercased()
        check(!text.contains("api_key") && !text.contains("typesafe") && !text.contains("authorization"),
              "statePacket JSON never contains the API key")
        let q = actionQuestion([FightAction.wait, .stop, .heal])
        check(q["type"] as? String == "choice", "the action question is a choice")
        let criteria = q["criteria"] as? [String: String] ?? [:]
        check(Set(criteria.keys) == ["WAIT", "STOP", "HEAL"] && criteria["BUFF_WEAPON"] == nil,
              "question criteria cover only the admissible actions")
        let facts = FightAction.allCases.map(\.facts).joined(separator: " ").lowercased()
        check(!facts.contains("for example") && !facts.contains("heal only") && !facts.contains("enchant first"),
              "criteria state facts, not coaching")
        let ev = events(previous: Obs(player: 1, target: 1), current: Obs(player: 0.8, target: 0.6, errorRed: true),
                        errorText: "Out of range")
        check(ev.contains(where: { $0.contains("character lost") }) && ev.contains(where: { $0.contains("target lost") })
              && ev.contains(where: { $0.contains("Out of range") }),
              "events mention health drops and the OCR error text")
    }

    static func arguments() {
        check(try! parseFight([]).mode == .preflight, "no arguments is the read-only preflight")
        check(try! parseFight(["--preflight"]).mode == .preflight, "--preflight parses")
        check(try! parseFight(["--dry-run"]).mode == .dryRun, "--dry-run parses")
        let exe = try! parseFight(["--execute", "--keys", "wqe"])
        check(exe.mode == .execute && exe.profile == .wqe, "--execute --keys wqe parses")
        let refused: [[String]] = [
            ["--bogus"], ["--dry-run", "x"], ["--preflight", "extra"], ["--execute"],
            ["--execute", "--keys", "arrows"], ["--execute", "--keys", "wasd"],
            ["--execute", "--keys", "wqe", "extra"], ["--execute", "--keys", "wqe", "--keys", "wqe"],
            ["--execute", "--look", "x"], ["--execute", "--keys"], ["--execute", "--keys", "-wqe"],
            ["--dry-run", "--keys", "wqe"], ["--preflight", "--keys", "wqe"],
        ]
        for bad in refused {
            check(fails { _ = try parseFight(bad) }, "refused before any effect: \(bad)")
        }
        check(FightLimits.maxDecisions == 40 && FightLimits.maxSeconds == 150
              && FightLimits.playerSafety == 0.3 && FightLimits.walkBudgetMs == 3500
              && FightLimits.turnBudgetMs == 2500 && FightLimits.watchdogSeconds == 4
              && FightLimits.jevTimeout == 4 && FightLimits.lootPolls == 6
              && FightLimits.lootPollSeconds == 0.5 && FightLimits.model == "jev-1.13.0",
              "FightLimits match the live envelope")
    }

    static func sim() async {
        let clock = FightClock()
        let world = SimFight(clock: clock)
        let result = await runFight(host: world, jev: ScriptedJev())
        check(result.outcome == "KILLED_AND_LOOTED", "SimFight + ScriptedJev reaches KILLED_AND_LOOTED")
        check(result.decisions <= FightLimits.maxDecisions && result.decisions > 0,
              "the simulated episode stays within the decision cap")
        check(clock.now() < FightLimits.maxSeconds, "the simulated episode stays within the time cap")
        check(!result.holdingKeys && world.down.isEmpty && !world.boltHeld,
              "every simulated key is released at the end")
        check(result.episode.killed && result.episode.looted, "the episode records the kill and the loot")
        check(result.jevCalls == result.decisions, "each decision is one Jev call")

        let wisp = SimFight(clock: FightClock())
        wisp.leavesCorpse = false
        let vanished = await runFight(host: wisp, jev: ScriptedJev())
        check(vanished.outcome == "KILLED_NO_CORPSE" && vanished.episode.killed && !vanished.holdingKeys,
              "a kill that leaves no corpse label ends the fight after one loot attempt")

        // 24 Sept live: after the loot click the capture went quiet and the empty frame read as 0 % health.
        let blip = SimFight(clock: FightClock())
        blip.stalls = 5
        let waited = await runFight(host: blip, jev: ScriptedJev())
        check(waited.outcome == "KILLED_AND_LOOTED",
              "a half-second capture stall is waited out, not read as 0 % health")
        let frozen = SimFight(clock: FightClock())
        frozen.stalls = 1_000
        let dark = await runFight(host: frozen, jev: ScriptedJev())
        check(dark.outcome == "NO_FRESH_FRAME" && dark.decisions == 0 && !dark.holdingKeys,
              "no fresh frame at all: NO_FRESH_FRAME, never a false SAFETY_STOP or HOLD_PLAYER_HEALTH")
        let lost = SimFight(clock: FightClock())
        var seen = 0
        lost.emitHandler = { event, _ in if event == "decision" { seen += 1; if seen == 3 { lost.stalls = 1_000 } } }
        let mid = await runFight(host: lost, jev: ScriptedJev())
        check(mid.outcome == "NO_FRESH_FRAME" && mid.decisions == 3, "a capture lost mid-fight: NO_FRESH_FRAME")

        let clock2 = FightClock()
        let hurt = SimFight(clock: clock2)
        hurt.player = 0.2
        let stop = await runFight(host: hurt, jev: ScriptedJev())
        check(stop.outcome == "HOLD_PLAYER_HEALTH" && stop.decisions == 0 && !stop.holdingKeys,
              "player health below 90 % at start is a HOLD with no decisions")

        let attacked = SimFight(clock: FightClock())
        attacked.player = 0.5
        let back = await runFight(host: attacked, jev: ScriptedJev(), startHealth: 0)
        check(back.outcome != "HOLD_PLAYER_HEALTH" && back.decisions > 0, "a lower start health lets an attacked hunt fight back")

        var low = Obs()
        low.player = 0.2
        low.mana = 0.5
        low.combat = true
        low.target = 0.6
        check(admissible(low, Episode()) == [.heal], "below 30 % in combat with mana: HEAL alone, the fight goes on")
        low.casting = true
        check(admissible(low, Episode()) == [.wait], "and while that cast runs, WAIT")
        low.casting = false
        low.mana = 0.1
        check(admissible(low, Episode()).contains(.castLightningBolt) || admissible(low, Episode()).contains(.startMelee),
              "without mana for a heal the fight's own actions return")
        let bleeding = SimFight(clock: FightClock())
        bleeding.player = 0.2
        bleeding.combat = true
        let kept = await runFight(host: bleeding, jev: ScriptedJev(), startHealth: 0)
        check(kept.outcome != "SAFETY_STOP_PLAYER_BELOW_30" && bleeding.performed.first == .heal,
              "a fight below 30 % in combat is not stopped: it heals first")

        let clock3 = FightClock()
        let notice = SimFight(clock: clock3)
        notice.refreshOpen = true
        let held = await runFight(host: notice, jev: ScriptedJev())
        check(held.outcome == "HOLD_REFRESH_NOTICE" && held.decisions == 0,
              "an open world-refresh notice sends nothing")

        let boom = SimFight(clock: FightClock())
        boom.holdBolt()
        let err = await runFight(host: boom, jev: ThrowingJev())
        check(err.outcome == "JEV_ERROR" && err.decisions == 0 && boom.performed.isEmpty
              && !err.holdingKeys && boom.down.isEmpty,
              "a throwing Jev client is JEV_ERROR: no perform, keys released")

        let reject = SimFight(clock: FightClock())
        let stopped = await runFight(host: reject, jev: ReplyJev(choice: "CAST_LIGHTNING_BOLT"))
        check(stopped.outcome == "JEV_STOP" && reject.performed.isEmpty && stopped.decisions == 1
              && !stopped.holdingKeys,
              "a well-typed non-admissible choice is JEV_STOP and never performed")
    }

    static let knowledge = "experiments/002_wow_visual/learning/knowledge/"
    static let fightGraph = URL(fileURLWithPath: "experiments/002_wow_visual/runtime/skyborne-fight.graph.json")

    /// M3b's pure parts: the bar's cards, the chain book, a chain's steps and breaks, offers and numbers.
    static func tactics() {
        let bar = bar24Sept.map(parseTooltip)
        check(bar[1]?.rank == 1 && bar[3]?.rank == 1 && bar[8]?.rank == nil, "a tooltip's rank is kept, before or after the name")
        let slots = bar.enumerated().compactMap { i, skill in skill.map { (slot: SkillHUD.names[i], skill: $0) } }
        guard let dictionary = try? SkillEntry.dictionary(String(contentsOfFile: knowledge + "shaman-skills.jsonl", encoding: .utf8)),
              let book = try? FightChain.book(String(contentsOfFile: knowledge + "fight-chains.jsonl", encoding: .utf8)) else {
            return check(false, "the skills dictionary and the chain book load")
        }
        check(dictionary.count == 44 && book.count == 5, "the dictionary's 44 rows and the book's 5 chains load")
        let kit = FightKit(bar: slots, dictionary: dictionary, book: book, className: "shaman", level: nil)
        let shock = kit.cards[.shock], bolt = kit.cards[.bolt]
        check(Set(kit.cards.keys) == [.melee, .bolt, .shock, .heal, .buff, .drink, .food] && shock?.slot == "3" && bolt?.slot == "2",
              "each role's card comes from its first slot on the bar")
        check(bolt?.mana == 15 && bolt?.range == 30 && bolt?.cooldown == nil && shock?.mana == 30 && shock?.range == 20
              && shock?.cooldown == 6 && shock?.learnedAt == 4, "numbers from the live tooltip; the level learned from the dictionary")
        check(bolt?.note?.contains("14 to 17") == true, "the dictionary's disagreement with the live tooltip reaches the card")
        check(tooltipNumber("2 min cooldown", #"([0-9.]+) min cooldown"#) == 2, "minutes are read too")
        check(kit.chains.map(\.id) == ["bolt-pull-melee", "melee-to-kill", "bolt-to-kill", "shock-melee"],
              "only accepted chains are offered, in book order: the candidate waits for review")
        check(FightKit(bar: slots, dictionary: dictionary, book: book, className: "shaman", level: 12).chains.map(\.id)
              == ["bolt-pull-melee", "melee-to-kill", "shock-melee"], "a chain outside its levels is left out")
        check(FightKit(bar: slots.filter { $0.skill.name != "Earth Shock" }, dictionary: dictionary, book: book, className: "shaman",
                       level: nil).chains.allSatisfy { !$0.requires.contains("shock") }, "a chain needing a skill not on the bar is left out")
        check(FightKit(bar: slots, dictionary: dictionary, book: book, className: "warrior", level: 6).chains.isEmpty,
              "another class's book rows are not this one's")
        let row = #"{"id":"x","class":"shaman","levels":[1,20],"requires":["bolt"],"steps":[{"do":"bolt","until":"dead"}],"summary":"s","source":"t","status":"accepted"}"#
        check((try? FightChain.book(row))?.count == 1, "a well-formed chain loads")
        for bad in [row + "\n" + row, row.replacingOccurrences(of: #""until":"dead""#, with: #""until":"soon""#),
                    row.replacingOccurrences(of: #"["bolt"]"#, with: #"["totem"]"#), row.replacingOccurrences(of: "[1,20]", with: "[20,1]"),
                    row.replacingOccurrences(of: #"[{"do":"bolt","until":"dead"}]"#, with: "[]"),
                    row.replacingOccurrences(of: #""do":"bolt""#, with: #""do":"fireball""#),
                    row.replacingOccurrences(of: "accepted", with: "promoted")] {
            check(fails { _ = try FightChain.book(bad) }, "a malformed chain book is refused at load: \(bad.prefix(60))")
        }

        var e = Episode()
        let melee = FightChain.Step(skill: "melee", until: "dead", max: nil)
        check(stepAction(melee, e) == .startMelee, "a melee step presses Interact With Target once")
        e.meleeOn = true
        check(stepAction(melee, e) == .wait, "then waits while the swings land")

        let pull = kit.chains[0]
        var run = ChainRun(pull, at: 0, health: 1)
        var a = Obs(), b = Obs()
        a.player = 1; a.target = 1; b.player = 1; b.target = 0.7
        run.observe(before: a, after: b, killed: false)
        check(run.stage == 0 && run.uses == 1, "a bolt that lands with no hit taken: the creature has not arrived")
        run.observe(before: a, after: b, killed: false)
        check(run.stage == 1, "at most two bolts: then melee, even unhit")
        var hitRun = ChainRun(pull, at: 0, health: 1)
        b.player = 0.9
        hitRun.observe(before: a, after: b, killed: false)
        check(hitRun.stage == 1, "a hit on the character is contact: melee next")
        var dead = ChainRun(pull, at: 0, health: 1)
        dead.observe(before: a, after: b, killed: true)
        check(dead.step == nil, "a kill ends the chain")
        var closing = ChainRun(kit.chains[3], at: 0, health: 1)  // shock-melee: melee until contact first
        b.player = 1
        closing.observe(before: a, after: b, killed: false)
        check(closing.stage == 1, "for melee, the creature losing health to the swings is contact too")

        var o = Obs()
        o.player = 1; o.target = 0.8; o.combat = true
        let fresh = ChainRun(pull, at: 0, health: 1)
        let allowed = admissible(o, Episode(), kit: kit, now: 0)
        check(chainBreak(fresh, o, Episode(), allowed: allowed, lastResult: "episode start", now: 1) == nil,
              "a fresh chain whose step can be done runs without a call")
        var ran = fresh
        ran.ran = 1
        check(chainBreak(ran, o, Episode(), allowed: allowed, lastResult: "Lightning Bolt did not start (key released)", now: 1)?
              .contains("did not work") == true, "a failed step returns the chain to Jev")
        check(chainBreak(fresh, o, Episode(), allowed: allowed, lastResult: "Lightning Bolt did not start (key released)", now: 1) == nil,
              "but not a failure from before the chain began")
        var far = o
        far.rangeRed = true
        check(chainBreak(fresh, far, Episode(), allowed: admissible(far, Episode(), kit: kit), lastResult: "", now: 1)?
              .contains("out of Lightning Bolt range") == true, "a step that cannot be done now returns it, saying why")
        var hurt = o
        hurt.player = 0.75
        check(chainBreak(fresh, hurt, Episode(), allowed: allowed, lastResult: "", now: 1)?.contains("lost 25%") == true,
              "a fast health loss returns it")
        check(chainBreak(fresh, o, Episode(), allowed: allowed, lastResult: "", now: ChainLimits.checkIn)?.hasPrefix("check-in") == true,
              "and so does the check-in")
        var low = o
        low.player = 0.2; low.mana = 0.5
        check(chainBreak(fresh, low, Episode(), allowed: admissible(low, Episode(), kit: kit), lastResult: "", now: 1)?
              .contains("healing comes first") == true, "below 30% in combat the safety rule outranks any chain")
        var killed = Episode()
        killed.killed = true
        check(chainBreak(fresh, o, killed, allowed: allowed, lastResult: "", now: 1)?.contains("target died") == true, "a kill returns it")

        check(allowed.contains(.castShock) && !admissible(o, Episode()).contains(.castShock),
              "the shock is offered with the bar's kit, never to the legacy policy")
        var shocked = Episode()
        shocked.lastShock = 10
        check(!admissible(o, shocked, kit: kit, now: 15).contains(.castShock) && admissible(o, shocked, kit: kit, now: 16).contains(.castShock),
              "the shock's 6 s cooldown, from its tooltip, is respected")
        var shortRange = o
        shortRange.shockRangeRed = true
        check(!admissible(shortRange, Episode(), kit: kit).contains(.castShock), "its hotkey digit red: out of shock range")

        let offers = fightOffers(o, Episode(), allowed: allowed, kit: kit, running: nil)
        check(offers.filter { $0.chain != nil }.map(\.name) == ["CHAIN_1", "CHAIN_2", "CHAIN_3", "CHAIN_4"] && !offers.contains { $0.name == "CONTINUE" },
              "four chain slots, and no CONTINUE without a running chain")
        check(Set(offers.compactMap(\.action)) == Set(allowed), "every admissible skill is offered on its own too")
        check(offers.first { $0.name == "CAST_SHOCK" }?.text.contains("Earth Shock rank 1: 30 mana, instant, 20 yd, 6 s cooldown") == true,
              "a single skill's offer states its live tooltip numbers")
        let farOffers = fightOffers(far, Episode(), allowed: admissible(far, Episode(), kit: kit), kit: kit, running: fresh)
        check(!farOffers.contains { $0.name == "CONTINUE" } && !farOffers.contains { $0.chain?.steps[0].skill == "bolt" },
              "out of bolt range: no CONTINUE into a bolt, and no chain that starts with one")
        check(fightOffers(o, Episode(), allowed: allowed, kit: kit, running: fresh).first?.name == "CONTINUE",
              "a running chain whose next step can be done offers CONTINUE")

        var tally = FightTally()
        var before = Obs(), after = Obs()
        before.target = 1; before.mana = 1; after.target = 0.7; after.mana = 0.93
        tally.record(.castLightningBolt, before: before, after: after, seconds: 2, meleeOn: false)
        tally.record(.castLightningBolt, before: before, after: after, seconds: 2, meleeOn: false)
        after.stamp = ObservationStamp(stream: "s", geometry: "g", capturedAt: 1, target: "another")
        tally.record(.castLightningBolt, before: before, after: after, seconds: 2, meleeOn: false)
        var now = Obs()
        now.target = 0.4; now.mana = 0.86; now.player = 1
        let calc = fightCalculations(now, Episode(), kit: kit, tally: tally, now: 5)
        let boltRow = (calc["skills"] as? [String: Any])?["CAST_LIGHTNING_BOLT"] as? [String: Any]
        check(boltRow?["uses_this_fight"] as? Int == 2, "a step on a different target cue is not counted")
        check(boltRow?["target_percent_per_use"] as? Int == 30 && boltRow?["mana_percent_per_use"] as? Int == 7
              && boltRow?["uses_affordable"] as? Int == 12 && boltRow?["uses_to_kill"] as? Int == 2,
              "per use: 30% of the target and 7% mana, so 12 affordable and 2 to kill")
        let shockRow = (calc["skills"] as? [String: Any])?["CAST_SHOCK"] as? [String: Any]
        check(shockRow?["uses_this_fight"] as? Int == 0 && shockRow?["target_percent_per_use"] is NSNull,
              "a skill not yet used this fight has no measured effect: null, not a guess")
    }

    /// M3b fights in SimFight through the real fight graph, with canned graph replies.
    static func chains() async {
        guard let tactics = try? FightTactics.load(fightGraph, bar: simBar, level: nil) else {
            return check(false, "the fight graph and its data files load")
        }
        check(tactics.graph.id == "skyborne-fight-v1" && tactics.kit.chains.count == 4 && tactics.references["mechanics"] != nil
              && tactics.references["owner_fighting"] != nil, "the fight graph names its dictionary, chain book and references")
        func world(closes: Int? = 1, hit: Double = 0.05, scale: Double = 1) -> SimFight {
            let w = SimFight(clock: FightClock())
            w.closesAfterBolts = closes; w.hitPerStep = hit; w.spendsMana = true; w.damageScale = scale
            return w
        }
        let plain = world()
        let legacy = await runFight(host: world(), jev: ScriptedJev())
        let fought = await runFight(host: plain, jev: ScriptedGraphJev.dryRun, tactics: tactics)
        check(fought.outcome == "KILLED_AND_LOOTED" && !fought.holdingKeys && plain.down.isEmpty,
              "a chain fight kills and loots with every key released")
        check(fought.chainSteps >= 3 && fought.decisions < legacy.decisions,
              "its chain ran steps without a call: fewer Jev decisions than the legacy policy in the same world")
        let bolt = plain.performed.firstIndex(of: .castLightningBolt), melee = plain.performed.firstIndex(of: .startMelee)
        check(bolt != nil && melee != nil && bolt! < melee!, "bolt-pull-melee: melee once the creature reached the character")
        check(fought.jevRecords.contains { ($0["asked_because"] as? String)?.contains("target died") == true },
              "the kill returned the chain to Jev, which chose the loot")
        let chosen = fought.jevRecords.compactMap { $0["chosen"] as? String }
        check(chosen.contains("CHAIN_1") && chosen.last == "LOOT_CORPSE", "Jev chose the chain and the loot")

        let bruiser = world(hit: 0.12)
        let broke = await runFight(host: bruiser, jev: HealOnceJev(), tactics: tactics)
        check(broke.jevRecords.contains { ($0["asked_because"] as? String)?.contains("health since the last decision") == true
                  && $0["chosen"] as? String == "HEAL" }, "a fast health loss broke the chain, and Jev chose to heal")
        check(broke.outcome == "KILLED_AND_LOOTED", "and the fight went on to the kill")

        let tough = world(closes: nil, scale: 0.15)
        let long = await runFight(host: tough, jev: ScriptedGraphJev.dryRun, tactics: tactics)
        check(long.jevRecords.contains { ($0["asked_because"] as? String)?.hasPrefix("check-in") == true && $0["chosen"] as? String == "CONTINUE" },
              "a long chain checks in, and Jev can go on with it")

        let crusher = world(hit: 0.3)
        let saved = await runFight(host: crusher, jev: ScriptedGraphJev.dryRun, tactics: tactics)
        check(saved.jevRecords.contains { ($0["asked_because"] as? String)?.contains("healing comes first") == true
                  && $0["offers"] as? [String] == ["HEAL"] }, "below 30% in combat only HEAL is offered, whatever the chain")

        let nonsense = world()
        let invalid = await runFight(host: nonsense, jev: ReplyJev(choice: "DO:NOT_OFFERED"), tactics: tactics)
        check(invalid.outcome == "JEV_STOP" && nonsense.performed.isEmpty && !invalid.holdingKeys,
              "a reply naming nothing offered is JEV_STOP, and nothing is done")
        let down = world()
        let err = await runFight(host: down, jev: ThrowingJev(), tactics: tactics)
        check(err.outcome == "JEV_ERROR" && down.performed.isEmpty, "a throwing client is JEV_ERROR in a chain fight too")
    }

    static func watchdog() async {
        var grant = HeldKey(code: FightLimits.bolt, until: 0)
        grant.refresh(now: 0)
        check(!grant.expired(now: FightLimits.watchdogSeconds)
              && grant.expired(now: FightLimits.watchdogSeconds + 0.001),
              "HeldKey expires only after 4 s without a refresh")
        grant.refresh(now: 3)
        check(!grant.expired(now: 7) && grant.expired(now: 7.001),
              "refresh extends the watchdog from the new now")

        let sink = FailUpSink()
        var rows: [(String, [String: Any])] = []
        let emit: Emit = { name, fields in rows.append((name, fields)) }
        sink.failUps = 1
        check(confirmKeyUp(FightLimits.bolt, sink: sink, emit: emit) && sink.ups == [FightLimits.bolt]
              && rows.contains(where: { $0.0 == "key_up_failed" }),
              "a failed key-up is retried and then confirmed")
        sink.failUps = Limits.releaseAttempts
        sink.ups = []
        check(!confirmKeyUp(FightLimits.forward, sink: sink, emit: emit) && sink.ups.isEmpty
              && rows.contains(where: { $0.0 == "release_unconfirmed" }),
              "persistent key-up failure keeps the grant")

        let world = SimFight(clock: FightClock())
        world.holdBolt()
        await world.sleep(FightLimits.watchdogSeconds)
        check(world.holdingKeys && world.down.contains(FightLimits.bolt),
              "watchdog does not fire at exactly 4 s")
        await world.sleep(0.001)
        check(!world.holdingKeys && world.down.isEmpty,
              "a fake-time host holding bolt past 4 s gets a key-up")

        let swept = SimFight(clock: FightClock())
        swept.holdBolt()
        swept.releaseAll()
        let postedBeforeSweep = swept.codesPosted.count
        swept.holdBolt()
        var sweptEpisode = Episode()
        _ = await swept.perform(.selectTarget, observation: swept.observe(plates: false), episode: &sweptEpisode)
        check(!swept.holdingKeys && swept.down.isEmpty && swept.codesPosted.count == postedBeforeSweep,
              "after releaseAll (the SIGINT sweep) no key goes down again, by hold or by tap")
    }
}

extension FightTests {
    /// The shared live key state (M3 LiveHost, M4 LiveNavBody) on a fake sink and a fake clock.
    static func liveKeys() {
        var t = 0.0
        var rows: [String] = []
        let sink = FailUpSink()
        let keys = LiveKeys(sink: sink, releaseCodes: [12, 13, 14], clock: { t }) { name, _ in rows.append(name) }
        check(keys.press(13) && keys.isDown(13) && keys.holding && sink.downs == [13] && keys.codesPosted == [13],
              "LiveKeys press posts the down and holds the key")
        keys.grant(13, seconds: 1.5)
        t = 1.5
        keys.sweepExpired()
        check(keys.isDown(13), "LiveKeys watchdog does not fire at exactly the grant")
        keys.grant(13, seconds: 1.5)
        t = 2.9
        keys.sweepExpired()
        check(keys.isDown(13), "a refreshed grant keeps the key held")
        t = 3.1
        keys.sweepExpired()
        check(!keys.isDown(13) && sink.ups == [13] && rows.contains("watchdog"),
              "an expired grant is lifted by sweepExpired and logged")

        keys.press(14)
        keys.grant(14, seconds: 1)
        t = 5
        sink.failUps = Limits.releaseAttempts
        keys.sweepExpired()
        check(keys.isDown(14) && rows.contains("release_unconfirmed"),
              "an unconfirmed watchdog key-up keeps the key held")
        keys.sweepExpired()
        check(!keys.isDown(14) && sink.ups.last == 14, "the next sweep retries and lifts it")

        keys.press(12)
        keys.lift(12)
        check(!keys.holding && sink.ups.last == 12, "lift posts the key-up of a held key")
        let upsBefore = sink.ups.count
        keys.lift(13)
        check(sink.ups.count == upsBefore, "lift of a key not held posts nothing")

        keys.press(13)
        keys.releaseAll()
        check(!keys.holding && Set(sink.ups.suffix(3)) == [12, 13, 14],
              "releaseAll sweeps every listed code with a key-up")
        let downsBefore = sink.downs.count
        check(!keys.press(13) && sink.downs.count == downsBefore && !keys.holding,
              "after releaseAll no key goes down again")

        let stuck = FailUpSink()
        let pulse = LiveKeys(sink: stuck, releaseCodes: [12, 13], clock: { 10 })
        pulse.press(12)
        stuck.failUps = Limits.releaseAttempts
        pulse.lift(12)
        check(pulse.isDown(12), "a turn pulse whose key-up failed every attempt stays held")
        pulse.sweepExpired()
        check(!pulse.isDown(12) && stuck.ups.last == 12, "the next sweep retries it, though the pulse took no grant")
        pulse.press(13)
        pulse.grant(13, seconds: 5)
        stuck.failUps = Limits.releaseAttempts
        pulse.lift(13)
        pulse.grant(13, seconds: 5)
        pulse.sweepExpired()
        check(!pulse.isDown(13), "a grant after a failed key-up does not postpone the retry")

        // The watchdog's key-up event blocks in the log (a full stdout pipe); the exit sweep must still run.
        let entered = DispatchSemaphore(value: 0), gate = DispatchSemaphore(value: 0), done = DispatchSemaphore(value: 0)
        let first = NSLock()
        var blocked = false
        let jammed = LiveKeys(sink: FailUpSink(), releaseCodes: [13], clock: { 10 }) { _, _ in
            first.lock()
            let block = !blocked
            blocked = true
            first.unlock()
            if block { entered.signal(); gate.wait() }
        }
        jammed.press(13)
        jammed.grant(13, seconds: -1)
        DispatchQueue.global().async { jammed.sweepExpired() }
        _ = entered.wait(timeout: .now() + 2)
        DispatchQueue.global().async { jammed.releaseAll(); done.signal() }
        let swept = done.wait(timeout: .now() + 1) == .success
        gate.signal()
        check(swept && !jammed.holding, "the exit sweep does not wait on a blocked log write")

        // As live: every event goes through one log lock, and the watchdog's write holds it, blocked on stdout.
        let logLock = NSLock(), entered3 = DispatchSemaphore(value: 0), gate3 = DispatchSemaphore(value: 0)
        let once = NSLock()
        var stalled = false
        let three = LiveKeys(sink: FailUpSink(), releaseCodes: [12, 13, 14], clock: { 10 }) { _, _ in
            logLock.lock()
            once.lock()
            let stall = !stalled
            stalled = true
            once.unlock()
            if stall { entered3.signal(); gate3.wait() }
            logLock.unlock()
        }
        for code: UInt16 in [12, 13, 14] { three.press(code) }
        three.grant(12, seconds: -1)
        DispatchQueue.global().async { three.sweepExpired() }
        _ = entered3.wait(timeout: .now() + 2)
        DispatchQueue.global().async { three.releaseAll() }
        usleep(300_000)
        let allUp = !three.holding
        gate3.signal()
        check(allUp, "with the log lock held by a blocked write, releaseAll still posts every key-up (W and E too)")
    }
}

final class FailUpSink: KeySink {
    var failUps = 0
    var ups: [UInt16] = []
    var downs: [UInt16] = []
    func post(_ code: UInt16, down: Bool) throws {
        if !down && failUps > 0 { failUps -= 1; throw ProbeError("fake key-up failure") }
        if down { downs.append(code) } else { ups.append(code) }
    }
}

struct ThrowingJev: JevClient {
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        throw ProbeError("jev down")
    }
}

/// The dry-run's replies, except that the first time HEAL is offered it is chosen: Jev breaking a chain.
final class HealOnceJev: JevClient {
    var healed = false
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let offered = (question["criteria"] as? [String: Any] ?? [:]).keys
        if !healed && offered.contains("DO:HEAL") {
            healed = true
            return try await ScriptedGraphJev(preference: ["DO:HEAL"]).ask(state: state, question: question)
        }
        return try await ScriptedGraphJev.dryRun.ask(state: state, question: question)
    }
}

struct ReplyJev: JevClient {
    let choice: String
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let criteria = question["criteria"] as? [String: Any] ?? [:]
        var probabilities: [String: Any] = [:]
        let n = Double(max(1, criteria.count))
        for key in criteria.keys { probabilities[key] = 1 / n }
        let action: [String: Any] = ["choice": choice, "confidence": 1.0, "probabilities": probabilities]
        return ["model": FightLimits.model, "answers": ["action": action]]
    }
}
