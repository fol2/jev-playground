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
        episode()
        choices()
        names()
        packets()
        arguments()
        await watchdog()
        liveKeys()
        await sim()
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

        let clock2 = FightClock()
        let hurt = SimFight(clock: clock2)
        hurt.player = 0.2
        let stop = await runFight(host: hurt, jev: ScriptedJev())
        check(stop.outcome == "HOLD_PLAYER_HEALTH" && stop.decisions == 0 && !stop.holdingKeys,
              "player health below 90 % at start is a HOLD with no decisions")

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
