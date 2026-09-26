// Offline M4b checks: the tracker, minimap-ring and nameplate readers, objective matching,
// admissibility, the targeting keys, walks and looks, and hunts on SimHunt with scripted Jev replies.
// SIMULATION ONLY: SimHunt does not fight, and nothing here shows that WoW's Tab, Esc, plates or tracker
// behave as simulated, or that Jev would choose these actions.
import Foundation

extension NavTests {
    static func hunts() async {
        tracker()
        minimapRings()
        plateBars()
        redNameStamps()
        huntRules()
        await targeting()
        await attackedFromBehind()
        await huntEpisodes()
        await questGraph()
    }

    static func tracker() {
        let read = parseTracker(["那事場", "Agitators", "- 0/7 AI' Aketh Convert slain", "-0/6 Roiling Winds destroyed",
                                 "Infestation Investigation", "-5/8 Pesky Cirrusfly slain"])
        check(read == [Objective(quest: "Agitators", done: 0, need: 7, text: "AI' Aketh Convert slain"),
                       Objective(quest: "Agitators", done: 0, need: 6, text: "Roiling Winds destroyed"),
                       Objective(quest: "Infestation Investigation", done: 5, need: 8, text: "Pesky Cirrusfly slain")],
              "the tracker's OCR lines parse into quests and objective counts")
        check(parseTracker(["Agitators", "Oyo Roiling Winds destroyed"]).isEmpty, "a misread count is not an objective")
        check(parseTracker(["- 0/6 Roiling Winds destroyed"]).isEmpty, "an objective with no quest title above is dropped")
        check(parseTracker(["Agitators", "6/6 Roiling Winds destroyed"]).first?.unfinished == false, "6/6 is finished")
        // The owner's demo tracker (23 Sept): finished quests show "Ready for turn-in" instead of objectives.
        let demo = parseTracker(["Quests", "Aggressive Encroachment", "Ready for turn-in", "Harvesting Windstones",
                                 "- 3/15 Windstone Cluster", "Call of Earth", "adyfor turnien"])
        check(demo == [Objective(quest: "Aggressive Encroachment", done: 1, need: 1, text: Objective.ready),
                       Objective(quest: "Harvesting Windstones", done: 3, need: 15, text: "Windstone Cluster"),
                       Objective(quest: "Call of Earth", done: 1, need: 1, text: Objective.ready)],
              "\"Ready for turn-in\" under a title, as OCR reads it, finishes that quest")
        check(parseTracker(["Agitators", "- 2/7 Al'Aketh Convert slain", "Ready for turn-in"]).count == 1,
              "\"Ready for turn-in\" under an objective line (its own title missed) finishes nothing")
        check(parseTracker(["Waiting for Turnips", "- 0/5 Turnip"]).first?.quest == "Waiting for Turnips",
              "a title containing \"for turn\" is still a title")
    }

    /// A minimap-sized frame with ring outlines: (centre offset from the character, radius, colour).
    static func rings(_ list: [(dx: Int, dy: Int, r: Int, rgb: (UInt8, UInt8, UInt8))]) -> RGBA {
        let w = 2560, h = 320
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for ring in list {
            for step in 0..<720 {
                let a = Double(step) * .pi / 360
                for t in 0..<3 {
                    let x = MinimapHUD.cx + ring.dx + Int((Double(ring.r + t) * cos(a)).rounded())
                    let y = MinimapHUD.cy + ring.dy + Int((Double(ring.r + t) * sin(a)).rounded())
                    guard (x - MinimapHUD.cx) * (x - MinimapHUD.cx) + (y - MinimapHUD.cy) * (y - MinimapHUD.cy)
                            <= MinimapHUD.radius * MinimapHUD.radius else { continue }
                    let i = (y * w + x) * 4
                    (px[i], px[i + 1], px[i + 2], px[i + 3]) = (ring.rgb.0, ring.rgb.1, ring.rgb.2, 255)
                }
            }
        }
        return RGBA(width: w, height: h, pixels: px)
    }

    /// A game-view frame with plate bars: (x0, y0, colour, outline colour).
    static func bars(_ list: [(x: Int, y: Int, rgb: (UInt8, UInt8, UInt8), outline: (UInt8, UInt8, UInt8))], width: Int = 186,
                     noise: Bool = false) -> RGBA {
        let w = 2560, h = 1320
        var px = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) { let i = (y * w + x) * 4; (px[i], px[i + 1], px[i + 2]) = c }
        for y in 0..<h / 2 { for x in 0..<w / 2 { put(x, y, (40, 62, 22)) } }  // forest floor, greener than red
        for bar in list {
            for x in bar.x - 2..<bar.x + width + 2 {
                for y in bar.y - 2..<bar.y { put(x, y, bar.outline) }
                for y in bar.y + 15..<bar.y + 17 { put(x, y, bar.outline) }
            }
            for x in bar.x..<bar.x + width { for y in bar.y..<bar.y + 15 { put(x, y, bar.rgb) } }
        }
        if noise {  // a red-orange creature body: patchy, no outline
            for y in 600..<612 { for x in 1200..<1300 where (x / 3 + y) % 4 != 0 { put(x, y, (150, 60, 30)) } }
        }
        return RGBA(width: w, height: h, pixels: px)
    }

    static func plateBars() {
        let dark: (UInt8, UInt8, UInt8) = (18, 18, 4)
        let seen = nameplates(bars([(x: 800, y: 220, rgb: (95, 30, 25), outline: dark),
                                    (x: 1700, y: 170, rgb: (62, 60, 20), outline: dark)], noise: true))
        check(seen.count == 2 && seen.contains { $0.hostile && abs($0.centre - 893) < 3 }
              && seen.contains { !$0.hostile && abs($0.centre - 1793) < 3 },
              "a dim red and a dim yellow plate bar are found with their colours and centres; a patchy body is not")
        check(nameplates(bars([(x: 800, y: 220, rgb: (95, 30, 25), outline: (230, 230, 230))])).isEmpty,
              "the white-outlined (targeted) plate is left to findTargetPlate")
        check(nameplates(bars([(x: 800, y: 220, rgb: (95, 30, 25), outline: dark)], width: 100)).isEmpty,
              "a bar narrower than a plate is not one")
    }

    /// A name drawn as real ones measure (24 Sept): 3 px strokes, 11 px tall, on the dark forest floor.
    static func redText(_ rgb: (UInt8, UInt8, UInt8), at x0: Int, y0: Int, floor: (UInt8, UInt8, UInt8) = (22, 26, 18)) -> RGBA {
        let w = 2560, h = 1320
        var px = [UInt8](repeating: 0, count: w * h * 4)
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8)) { let i = (y * w + x) * 4; (px[i], px[i + 1], px[i + 2]) = c }
        for y in 0..<h { for x in 0..<w { put(x, y, floor) } }
        for glyph in 0..<16 {  // "Cirrusfly Soldier": a letter every 7 px, strokes 3 px wide
            let gx = x0 + glyph * 7
            for y in y0..<y0 + 11 { for x in gx..<gx + 3 { put(x, y, rgb) } }
            if glyph % 2 == 0 { for x in gx..<gx + 6 { put(x, y0, rgb); put(x, y0 + 10, rgb) } }
        }
        return RGBA(width: w, height: h, pixels: px)
    }

    static func redNameStamps() {
        let found = redNames(redText((196, 48, 44), at: 848, y0: 220))
        check(found.count == 1 && abs(found[0].centre - 904) < 12 && abs(viewBearing(found[0].centre, facing: 122, width: 2560) - 109) < 2,
              "a red name with its dark outline is found; its bearing is the facing plus its angle off centre (the nest walk, f128)")
        check(redNames(bars([(x: 800, y: 220, rgb: (150, 30, 25), outline: (18, 18, 4))])).isEmpty,
              "a red plate bar is solid, not text: it is left to nameplates")
        check(redNames(redText((126, 52, 30), at: 1600, y0: 220)).isEmpty && redNames(redText((196, 48, 44), at: 1600, y0: 220, floor: (150, 150, 140))).isEmpty,
              "the Juvenile Vuldren's red-brown (green well above blue) is not a name, nor red strokes with no dark outline")
    }

    static func minimapRings() {
        let bright: (UInt8, UInt8, UInt8) = (165, 205, 250), dim: (UInt8, UInt8, UInt8) = (105, 125, 165)
        let ne = questArea(rings([(dx: 40, dy: -40, r: 20, rgb: bright)]))
        check(ne.map { abs(angleError(45, $0.bearing)) <= 3 && abs($0.distance - 56.6 / MinimapHUD.unitPx) < 0.2 && !$0.inside } ?? false,
              "a bright ring to the north-east reads at 45° and its centre's distance, the character outside")
        let both = questArea(rings([(dx: 40, dy: -40, r: 20, rgb: bright), (dx: -30, dy: 50, r: 25, rgb: dim)]))
        check(both.map { abs(angleError(45, $0.bearing)) <= 3 } ?? false, "a dim ring (another quest's area) is ignored")
        check(questArea(rings([(dx: -30, dy: 50, r: 25, rgb: dim)])) == nil, "only dim rings: no selected area on the minimap")
        check(questArea(rings([(dx: 10, dy: -5, r: 45, rgb: bright)]))?.inside == true, "a bright ring around the character: inside")
        check(questArea(RGBA(width: 100, height: 100, pixels: [UInt8](repeating: 0, count: 40_000))) == nil,
              "a frame too small for the minimap reads nothing")
    }

    static func huntRules() {
        let objectives = SimHunt.field(clock: FightClock()).objectives
        check(objective(for: "Roiling Wind", in: objectives)?.text == "Roiling Winds destroyed", "a singular name counts for its plural")
        check(objective(for: "Al'Aketh Convert", in: objectives)?.need == 7, "OCR's I for l still matches")
        check(objective(for: "Yala Windwatcher", in: objectives) == nil, "a partial word does not count (Yala is not a Roiling Wind)")
        check(objective(for: "Juvenile Vuldren", in: objectives) == nil && objective(for: nil, in: objectives) == nil,
              "a creature no objective names does not count")
        var done = objectives
        done[1].done = 6
        check(objective(for: "Roiling Wind", in: done) == nil, "a finished objective no longer counts")
        check(remaining(objectives, in: done).count == 2, "an objective read at done >= need is no longer remaining")
        let lines = ["Agitators", "- 0/7 Al'Aketh Convert slain", "- 0/6 Roiling Winds destroyed",
                     "Infestation Investigation", "- 5/8 Pesky Cirrusfly slain"]
        check(remaining(objectives, in: parseTracker(lines.filter { !$0.contains("Roiling") })).count == 3,
              "a row lost among several stays remaining: an OCR miss is not a completion")
        check(remaining(objectives, in: parseTracker(["Agitators", "Infestation Investigation"])).count == 3
              && remaining(objectives, in: parseTracker(["All Objectives"])).count == 3 && remaining(objectives, in: []).count == 3,
              "title-only OCR, a collapsed tracker or nothing read: every objective stays remaining")
        check(remaining(objectives, in: parseTracker(lines)).count == 3, "a line that reappears unfinished is still remaining")
        check(remaining(objectives, in: parseTracker(["Agitators", "Ready for turn-in", "Infestation Investigation", "- 8/8 Pesky Cirrusfly slain"])).isEmpty,
              "completion: a quest's \"Ready for turn-in\" or a line read at 8/8")
        check(remaining(objectives, in: parseTracker(["Agitators", "Ready for turn-in", "- 2/7 Al'Aketh Convert slain",
                                                       "- 2/6 Roiling Winds destroyed"])).count == 3,
              "\"Ready for turn-in\" beside unfinished lines of the same quest is a misread: nothing finishes")
        check(remaining(objectives, in: parseTracker(["Agitators", "Infestation Investigation", "Ready for turn-in",
                                                       "- 5/8 Pesky Cirrusfly slain"])).count == 3,
              "title A, title B, Ready, B's 5/8 (A's lines missed): Ready does not finish B, and A stays remaining")

        let here = NavObs(x: 40, y: 30, facing: 0)
        let wind = HuntObs(objectives: objectives, target: "Roiling Wind", targetAlive: true, facing: 0, here: here)
        let compassAll = HuntAction.compass
        check(huntAdmissible(wind) == [.fight, .nextTarget, .lookAround] + compassAll,
              "a living quest creature at full health may be fought; looks and all eight headings are open; no rest at full")
        var hurt = wind
        hurt.player = 0.8
        check(!huntAdmissible(hurt).contains(.fight) && huntAdmissible(hurt).contains(.rest),
              "below M3's start health no fight starts, and rest is offered")
        check(!huntAdmissible(HuntObs(objectives: objectives, target: "Juvenile Vuldren", targetAlive: true, here: here)).contains(.fight),
              "a creature that counts for nothing is not fought out of combat")
        check(!huntAdmissible(HuntObs(objectives: objectives, target: "Roiling Wind", targetAlive: false, here: here)).contains(.fight),
              "a dead creature is not fought")
        var attacked = hurt
        attacked.combat = true
        check(huntAdmissible(attacked) == [.fight], "in combat the only action is to fight back, at any health")
        attacked.targetAlive = false
        check(huntAdmissible(attacked) == [.lookAround, .fight], "in combat with nothing alive selected: turn and Tab for the attacker, or fight")

        let step = { (action: HuntAction) in HuntStep(action: action, result: "") }
        check(!huntAdmissible(wind, steps: [step(.east)]).contains(.nextTarget) && !huntAdmissible(wind, steps: [step(.lookAround)]).contains(.nextTarget),
              "NEXT_TARGET is not offered right after a walk or a look: both end with a Tab")
        check(!huntAdmissible(wind, steps: [step(.lookAround)]).contains(.lookAround) && huntAdmissible(wind, steps: [step(.rest)]).contains(.nextTarget),
              "a look is not repeated at once; NEXT_TARGET returns after a rest")
        check(!huntAdmissible(wind, steps: Array(repeating: step(.east), count: HuntLimits.repeatCap)).contains(.east),
              "one compass walk at most four times in a row")
        check(!huntAdmissible(wind, steps: Array(repeating: step(.toArea), count: HuntLimits.maxMoves)).contains { $0.isWalk },
              "at most 24 walks per hunt")
        var drained = wind
        drained.mana = 0.5
        drained.mana = 0.2
        check(huntAdmissible(drained).contains(.fight) && huntAdmissible(drained).contains(.eatDrink),
              "low mana does not stop a fight (the owner's demo pulled at 10-30%); eating is offered")
        check(!huntAdmissible(wind).contains(.eatDrink), "no eating at full health and mana")
        var crowded = wind
        crowded.seen = [Seen(name: "Roiling Wind", hostile: true, bearing: 0, near: true), Seen(name: "Roiling Winds", hostile: true, bearing: 90, near: true)]
        check(!huntAdmissible(crowded).contains(.fight), "another hostile creature near: no fight starts")
        crowded.seen.removeLast()
        check(huntAdmissible(crowded).contains(.fight), "the target's own plate is not another creature")
        var weak = wind
        weak.player = 0.5
        check(!huntAdmissible(weak).contains { $0.isWalk } && huntAdmissible(weak).contains(.rest) && huntAdmissible(weak).contains(.eatDrink),
              "below 60% health: rest or eat, no walks")
        var lost = wind
        lost.here = nil
        check(!huntAdmissible(lost).contains { $0.isWalk }, "no walk without a readable position")

        var away = wind
        away.area = QuestArea(bearing: 10, distance: 1.6, inside: false)
        away.seen = [Seen(name: "Rolling WWinds", hostile: true, bearing: 30, near: true),
                     Seen(name: "Juvenile Vuldren", hostile: false, bearing: 200, near: true)]
        check(huntAdmissible(away).contains(.toArea) && huntAdmissible(away).contains(.toCreature) && questCreature(away)?.bearing == 30,
              "GO_TO_QUEST_AREA and GO_TO_QUEST_CREATURE are offered; the creature is the one that counts")
        check(huntAdmissible(away).filter(\.isWalk) == [.toCreature, .toArea] + HuntAction.detours,
              "outside the area the walks are relative to it, as M4a's: towards it, detours and back, no compass")
        let fenced = huntAdmissible(away, blocked: [0])
        check(!fenced.contains(.toArea) && fenced.contains(.detourRight45) && fenced.contains(.detourLeft45) && fenced.contains(.toCreature),
              "a heading blocked near here removes every walk within 25° of it, and only those")
        var within = away
        within.area?.inside = true
        check(!huntAdmissible(within).contains(.toArea) && huntAdmissible(within).filter(\.isWalk) == [.toCreature] + HuntAction.compass,
              "inside the area the walks are compass headings and the way to a creature that counts")

        let state = huntStatePacket(away, recent: [], fights: [], blocked: [0])
        let creatures = state["creatures_in_view"] as? [[String: Any]] ?? []
        check((state["goal"] as? String ?? "").contains("blocked here") && creatures.count == 2
              && creatures.first?["counts_for_objective"] as? String == "Roiling Winds destroyed"
              && state["hostile_creatures_near"] as? Int == 1 && state["blocked_headings_near_here"] as? [Int] == [0],
              "the state gives the area, the creatures in view with what they count for, hostiles near and blocked headings")
        let question = actionQuestion(huntAdmissible(away), instructions: huntInstructions)
        check(Set((question["criteria"] as? [String: Any] ?? [:]).keys) == Set(huntAdmissible(away).map(\.rawValue)),
              "the question offers only the admissible actions")
        check(!HuntAction.allCases.map(\.rawValue).contains("STOP"), "a hunt has no STOP: its ends are local")

        let bar = PlateBar(hostile: true, x0: 1880, x1: 1960, y0: 600, y1: 607)
        let right = sighting(bar, name: "Roiling Winds", facing: 350, width: 2560, height: 1320)
        check(abs(angleError(12.5, right.bearing)) < 0.5 && right.near, "a plate three quarters across the view is 22.5° right; low in view is near")
        let pair = merged([Seen(name: "A", hostile: true, bearing: 10, near: false)], [Seen(name: "A", hostile: true, bearing: 25, near: true)])
        check(pair.count == 1 && pair[0].near, "two sightings of one name within 20° are one creature, the newer kept")
    }

    static func plain(_ mobs: [SimHunt.Mob], objectives: [Objective] = SimHunt.agitators) -> SimHunt {
        SimHunt(world: SimNav(clock: FightClock(), x: 40, y: 30, facing: 0), mobs: mobs, objectives: objectives)
    }

    static func targeting() async {
        let field = SimHunt.field(clock: FightClock())
        field.selected = 1
        _ = await selectNearest(field)
        check(field.keys.codesPosted == [53, 48] && field.selected == 0 && !field.gameMenu,
              "with something selected: Esc clears it, then Tab selects what is in front")
        let clear = SimHunt.field(clock: FightClock())
        let found = await selectNearest(clear)
        check(clear.keys.codesPosted == [48] && clear.selected == 0 && found.contains("counts for no unfinished objective"),
              "with nothing selected: Tab only, and the result says what the creature counts for")
        let menu = SimHunt.field(clock: FightClock())
        menu.gameMenu = true
        _ = await selectNearest(menu)
        check(menu.keys.codesPosted == [53, 48] && !menu.gameMenu, "an open Game Menu is closed with one Esc before Tab")

        let ridge = SimHunt.field(clock: FightClock())
        ridge.world.y = 21.6
        ridge.world.facing = 0
        var walks = NavEpisode()
        let bumped = await walkOn(ridge, heading: 0, episode: &walks)
        check(bumped.hasPrefix("blocked on heading 0°") && walks.attempts.last?.blocked == true && !ridge.keys.holding,
              "a walk into the ridge ends blocked, with W lifted")
        let blocked = walks.blockedHeadings(near: ridge.look()!)
        check(!huntAdmissible(ridge.survey()!, steps: [], blocked: blocked).contains(.toArea),
              "the way to the area, through the ridge, is not offered again from where it was blocked")

        let looker = SimHunt.field(clock: FightClock())
        let look = await lookAround(looker)
        check(look.seen.map(\.name) == ["Juvenile Vuldren"] && abs(angleError(200, looker.world.facing)) <= 20 && !looker.keys.holding,
              "LOOK_AROUND turns a full circle, lists the creature in view and ends facing where it began")

        let hungry = SimHunt.field(clock: FightClock())
        hungry.world.player = 0.3
        hungry.mana = 0.1
        let ate = await eatDrink(hungry)
        check(ate == "ate and drank for 20 s" && hungry.world.player == 1 && hungry.mana == 1 && hungry.keys.codesPosted == [29, 27],
              "EAT_DRINK: water (0), bread (-), 20 s seated restores both to full")

        let stalled = SimHunt.field(clock: FightClock())
        stalled.world.player = 0.5
        stalled.frozen = true
        let stalledRest = await rest(stalled, seconds: HuntLimits.restSeconds)
        check(stalledRest.hasSuffix("no fresh frame") && stalled.clock.t < 1, "a rest stops at once when the capture stalls: no frame is not calm")
        let stalledLook = await lookAround(stalled)
        check(stalledLook.result.hasPrefix("no fresh frame") && stalled.keys.codesPosted.isEmpty && !stalled.keys.holding,
              "a look does not turn without a fresh frame")

        let resting = SimHunt.field(clock: FightClock())
        resting.world.player = 0.5
        let rested = await rest(resting, seconds: HuntLimits.restSeconds)
        check(rested == "rested 20 s" && resting.world.player > 0.85 && resting.keys.codesPosted.isEmpty, "REST waits 20 s without a key")
        let faint = SimHunt.field(clock: FightClock())
        faint.world.player = 0.2
        let faintRest = await rest(faint, seconds: HuntLimits.restSeconds)
        check(faintRest == "rested 20 s" && faint.world.player > 0.55,
              "a rest at 20% health is not cut short: low health is what it is for")

        let released = SimHunt.field(clock: FightClock())
        released.keys.releaseAll()
        var none = NavEpisode()
        _ = await walkOn(released, heading: 90, episode: &none)
        _ = await lookAround(released)
        check(released.keys.codesPosted.isEmpty && released.world.x == 47.3, "no key goes down after releaseAll")
    }

    /// Live hunt 9: a hostile creature attacks from behind, out of Tab's reach in front.
    static func attackedFromBehind() async {
        let behind = plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 30.2)])
        await behind.sleep(0.1)
        check(behind.world.combat && behind.selected == nil, "an attacker behind: in combat with nothing selected")
        let look = await lookAround(behind)
        check(behind.selected == 0 && look.result.contains("Roiling Winds"), "LOOK_AROUND in combat turns and Tabs until it selects the attacker")
        let hunt = await runHunt(host: plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 30.2)]), jev: huntScripted([.fight, .lookAround]))
        check(hunt.fights.count >= 1 && hunt.steps.first?.action == .lookAround && hunt.outcome != "DEAD",
              "a hunt attacked from behind finds the attacker and fights it (\(hunt.outcome))")
    }

    static func huntScripted(_ preference: [HuntAction]) -> ScriptedJev<HuntAction> {
        ScriptedJev(preference: preference)
    }

    static func huntEpisodes() async {
        let hunter: [HuntAction] = [.fight, .rest, .toCreature, .toArea, .nextTarget, .lookAround, .detourRight90, .detourRight45,
                                    .detourLeft90, .detourLeft45, .backTrack] + HuntAction.compass
        let field = SimHunt.field(clock: FightClock())
        let led = await runHunt(host: field, jev: huntScripted(hunter))
        check(led.walks.attempts.contains { $0.blocked } && led.fights.count >= 1 && field.objectives[0].done + field.objectives[1].done >= 1
              && !led.holding,
              "the field: blocked by the ridge on the way to the area, around it and a quest creature fought (\(led.fights.count) fights, \(led.outcome))")

        let last = plain([SimHunt.Mob(name: "Pesky Cirrusfly", x: 40, y: 29.5, hostile: false)],
                         objectives: [Objective(quest: "Infestation Investigation", done: 7, need: 8, text: "Pesky Cirrusfly slain")])
        let finished = await runHunt(host: last, jev: huntScripted([.fight, .nextTarget]))
        check(finished.outcome == "OBJECTIVES_COMPLETE" && finished.fights.count == 1 && finished.decisions == 2,
              "the last creature needed: select, fight, OBJECTIVES_COMPLETE")

        let bystander = plain([SimHunt.Mob(name: "Juvenile Vuldren", x: 40, y: 29.5, hostile: false)])
        let spared = await runHunt(host: bystander, jev: huntScripted([.fight, .nextTarget, .lookAround, .east, .west]))
        check(bystander.fightsRun == 0 && spared.outcome == "NO_TARGET_FOUND" && spared.decisions == HuntLimits.searchLimit,
              "a creature that counts for nothing is never fought; the search ends after \(HuntLimits.searchLimit) decisions")

        let horde = plain((0..<8).map { SimHunt.Mob(name: "Roiling Winds", x: 40 + 0.05 * Double($0 % 3), y: 29.4 - 0.1 * Double($0)) })
        let capped = await runHunt(host: horde, jev: huntScripted([.fight, .rest, .nextTarget, .lookAround, .north]))
        check(capped.outcome == "FIGHT_LIMIT" && capped.fights.count == HuntLimits.maxFights, "at most four fights per hunt (\(capped.outcome))")

        let hurt = plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 29.5)])
        hurt.fightOutcome = "SAFETY_STOP_PLAYER_BELOW_30"
        let fled = await runHunt(host: hurt, jev: huntScripted([.fight, .nextTarget]))
        check(fled.outcome == "FIGHT_SAFETY_STOP_PLAYER_BELOW_30" && fled.fights.count == 1 && !fled.holding,
              "a fight's safety stop ends the hunt")

        let blurred = plain([])
        var reads = 0
        blurred.readLines = { lines in reads += 1; return reads == 1 ? lines : lines.filter { !$0.hasPrefix("-") } }
        let unsure = await runHunt(host: blurred, jev: huntScripted([.nextTarget, .lookAround, .east, .west]))
        check(unsure.outcome == "NO_TARGET_FOUND" && reads > 2,
              "a tracker read later as titles only does not end the hunt as OBJECTIVES_COMPLETE (\(unsure.outcome))")

        let ambushed = plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 31)])
        let ambush = await runHunt(host: ambushed, jev: AmbushJev(world: ambushed, then: huntScripted([.east, .fight, .lookAround])))
        check(ambush.steps.count >= 2 && ambush.steps[0].action == .east && ambush.steps[0].result.hasPrefix("not done")
              && ambush.steps[1].action == .fight,
              "attacked while Jev decided: the walk is not done, and the next decision fights back (\(ambush.outcome))")
        let pulled = plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 29.5)])
        pulled.selected = 0
        let pull = await runHunt(host: pulled, jev: AmbushJev(world: pulled, then: huntScripted([.fight])))
        check(pulled.foughtInCombat.first == true && pull.steps.first?.action == .fight,
              "attacked while Jev chose to pull: the fight starts as one already in combat, not on the stale calm")
        let frozenPull = plain([SimHunt.Mob(name: "Roiling Winds", x: 40, y: 29.5)])
        frozenPull.selected = 0
        let noPull = await runHunt(host: frozenPull, jev: FreezingJev(world: frozenPull, then: huntScripted([.fight])))
        check(frozenPull.fightsRun == 0 && noPull.outcome == "HUD_UNREADABLE" && !noPull.holding,
              "the capture stalls while Jev chose to pull: no fight starts")

        let frozenMid = plain([])
        let stall = await runHunt(host: frozenMid, jev: FreezingJev(world: frozenMid, then: huntScripted([.east])))
        check(stall.outcome == "HUD_UNREADABLE" && stall.steps.first?.result.hasPrefix("not done") == true && frozenMid.world.x == 40
              && !stall.holding, "the capture stalls while Jev decides: nothing is done and the hunt ends unreadable")

        let down = await runHunt(host: SimHunt.field(clock: FightClock()), jev: NavThrowingJev())
        check(down.outcome == "JEV_FAILED" && down.decisions == 0, "a failed Jev call ends the hunt, no fallback")
        let odd = await runHunt(host: SimHunt.field(clock: FightClock()), jev: NavReplyJev(choice: "STOP"))
        check(odd.outcome == "INVALID_REPLY" && odd.decisions == 1, "STOP or any unknown reply is invalid and ends the hunt")

        let stops: [(String, (SimHunt) -> Void)] = [
            ("DEAD", { $0.world.player = 0 }), ("OWNER_TOOK_FOCUS", { $0.world.ownerFront = true }),
            ("HUD_UNREADABLE", { $0.surveyBlind = true }), ("NO_UNFINISHED_OBJECTIVE", { $0.objectives = [] }),
        ]
        for (outcome, setup) in stops {
            let world = SimHunt.field(clock: FightClock())
            setup(world)
            let result = await runHunt(host: world, jev: huntScripted(hunter))
            check(result.outcome == outcome && result.decisions == 0 && !result.holding, "\(outcome) stops before any decision")
        }
    }
}

/// Answers as `then`, but a hostile creature reaches the character while the first question is out.
final class AmbushJev: JevClient {
    let world: SimHunt, then: ScriptedJev<HuntAction>
    var asked = 0
    init(world: SimHunt, then: ScriptedJev<HuntAction>) { self.world = world; self.then = then }
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        asked += 1
        if asked == 1 { world.mobs[0].y = world.world.y + 0.1; world.world.combat = true; world.selected = 0 }
        return try await then.ask(state: state, question: question)
    }
}

/// Answers as `then`, but the capture stalls while the first question is out.
final class FreezingJev: JevClient {
    let world: SimHunt, then: ScriptedJev<HuntAction>
    init(world: SimHunt, then: ScriptedJev<HuntAction>) { self.world = world; self.then = then }
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        world.frozen = true
        return try await then.ask(state: state, question: question)
    }
}

extension NavTests {
    /// Reward tooltips as Vision read them live on 24 Sept (The Cirrusfly Queen): text, left x, top y.
    /// The equipped item's comparison sits to the right, and quest text shows through at x 149-241.
    static func tip(_ rows: [(String, Double, Double)], red: Set<String> = []) -> [TipLine] {
        rows.map { TipLine(text: $0.0, x: $0.1, y: $0.2, red: red.contains($0.0)) }
    }
    static let vest = tip([("Elatrell Featherlight", 149, 159), ("Equipped", 493, 190), ("Exterminator's Vest", 201, 219),
        ("Ragged Leather Vest", 489, 221), ("QUEE", 151, 235), ("Chest", 489, 237), ("Leather", 685, 237),
        ("Binds when picked up", 201, 237), ("31 Armor", 487, 251), ("Leather", 415, 251), ("Chest", 201, 252),
        ("make a fine", 239, 259), ("33 Armor", 203, 267), ("Durability 45 / 45", 487, 267), ("Requires Level 2", 203, 275),
        ("Sell Price: 8", 487, 281), ("Sell Price: 13", 201, 297), ("If you replace this item, the following", 487, 313),
        ("stat changes will occur:", 487, 329), ("Press F6 to submit an issue for this Item", 201, 329), ("ard:", 150, 335),
        ("+2 Armor", 487, 343), ("Gardening", 239, 363)])
    static let pants = tip([("Equipped", 653, 207), ("Gardening Pants", 361, 235), ("Ragged Leather Pants", 649, 235),
        ("Leather", 843, 251), ("Binds when picked up", 359, 251), ("Legs", 647, 253), ("17 Armor", 647, 267), ("Cloth", 589, 267),
        ("Legs", 359, 268), ("\"adventurer\" thing", 169, 269), ("9 Armor", 359, 283), ("Durability 30 / 30", 647, 283),
        ("Sell Price: 2", 647, 297), ("Sell Price: 9", 359, 297), ("If you replace this item, the following", 647, 329),
        ("Press F6 to submit an issue for this Item", 359, 329), ("stat changes will occur:", 647, 343), ("-8 Armor", 648, 357)])
    static let mail = tip([("Equipped", 493, 255), ("Watcher's Mail Chest", 203, 281), ("Ragged Leather Vest", 489, 283),
        ("Chest", 489, 297), ("Leather", 685, 299), ("Binds when picked up", 201, 299), ("Chest", 201, 313), ("31 Armor", 487, 314),
        ("Mail", 435, 315), ("67 Armor", 201, 329), ("Durability 45 / 45", 489, 329), ("Sell Price: 8", 487, 343),
        ("Sell Price: 14 -", 201, 343), ("Gardening,", 241, 361), ("Press Forto submit an issue for this Item", 201, 375),
        ("If you replace this item, the following", 487, 375), ("stat changes will occur:", 487, 389), ("+36 Armor", 487, 403)],
        red: ["Mail"])

    static func quests() {
        let v = parseReward(vest), p = parseReward(pants), m = parseReward(mail)
        check(v == Reward(name: "Exterminator's Vest", slot: "Chest", usable: true, change: 2, sell: 13),
              "reward tooltip: its own lines by alignment, the game's +2 Armor from the equipped comparison")
        check(p == Reward(name: "Gardening Pants", slot: "Legs", usable: true, change: -8, sell: 9), "a worse item: -8 Armor")
        check(m == Reward(name: "Watcher's Mail Chest", slot: "Chest", usable: false, change: 36, sell: 14),
              "red Mail: not usable, whatever the armour; an OCR-garbled footer still ends the tooltip")
        check(parseReward(vest.filter { !$0.text.hasPrefix("Press") }) == nil, "no footer: no reward")
        check(parseReward(mail.filter { !$0.text.hasPrefix("If you replace") }) == Reward(name: "Watcher's Mail Chest", slot: "Chest",
              usable: false, change: 0, sell: 14),
              "live: OCR missed \"If you replace\"; the \"Equipped\" label still bounds the reward's box, and an unread change is 0")
        let all = [v!, p!, m!]
        check(chooseReward(all).map { [$0.index, $0.equip ? 1 : 0] } == [0, 1],
              "owner's rule: the usable upgrade is taken and equipped, not the unusable +36 mail")
        check(chooseReward([p!, m!]).map { [$0.index, $0.equip ? 1 : 0] } == [1, 0],
              "no usable upgrade: the highest sell price is taken to sell, even an unusable item")
        check(chooseReward([]) == nil, "no rewards: no choice")
        var bare = vest.filter { $0.x < 480 }
        bare.removeAll { $0.text == "Leather" && $0.x > 400 }
        check(parseReward(bare)?.change == 33, "an empty slot: the item's own armour is the gain")

        var image = RGBA(width: 400, height: 300, pixels: [UInt8](repeating: 30, count: 400 * 300 * 4))
        func paint(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8) = (250, 210, 40)) {
            var px = image.pixels
            for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { let i = (y * 400 + x) * 4; px[i] = rgb.0; px[i + 1] = rgb.1; px[i + 2] = rgb.2 } }
            image = RGBA(width: 400, height: 300, pixels: px)
        }
        paint(100, 50, 12, 20)
        paint(70, 85, 70, 6, (60, 190, 40))  // the NPC's green name under its "?"
        paint(300, 200, 12, 20)
        paint(270, 235, 70, 6, (60, 190, 40))
        paint(20, 280, 3, 3)
        paint(150, 120, 120, 8)
        paint(200, 20, 12, 20)  // a glowing insect: upright and yellow, no green name
        let marks = questMarks(image, box: (0, 0, 400, 300))
        check(marks.count == 2 && abs(marks[0].x - 305.5) < 1 && abs(marks[0].y - 209.5) < 1 && marks[0].h == 20 && marks[0].body == 240 + 48,
              "two quest marks, the nearer the centre first; a speck, a flat yellow nameplate bar and a nameless glow are not")
        check(questMarks(image, box: (0, 0, 200, 150)).count == 1, "only inside the box")
        check(abs(marks[0].nameX - 304.5) < 0.01 && marks[0].nameTop == 235, "the name's centre and top: where the body stands and the OCR box")
        // Live, 25 Sept: Dalia's "?" (h 33) stood 30 px right of her; the name's centre was nearer her body.
        let dalia: QuestMark = (x: 1906, y: 167, h: 33, body: 313, nameX: 1891, nameTop: 222)
        let points = hoverPoints(dalia), chest = 313 - 2.4 * 33 + 1.4 * 33
        check(points.count == 16 && points[0] == (1891, chest) && points[1] == (1891, 313) && points[3] == (1891 - 16.5, chest)
              && points[9] == (1891 - 33, chest) && points.last! == (1906, 313),
              "the pointer rests below the name's centre first, then half and a whole mark height aside, and below the \"?\" last")
        check(sameUnit("Dalia the Collector", "alia the Collector") && sameUnit("Ventaari Brightwish", "Ventaari Brightwish")
              && !sameUnit("Strogruid Noc", "Dalia the Collector") && !sameUnit("", "Dalia the Collector") && !sameUnit("Noc", "Noc"),
              "the unit tooltip confirms the NPC by its name, a letter lost at an end allowed; never a neighbour or a blank")
        check(!sameUnit("Dalia", "Dalia the Collector") && !sameUnit("Collector", "Dalia the Collector")
              && !sameUnit("Dalia the Collector", "Dalia the Collectors Apprentice"),
              "a part of the name, or a longer name holding it, is someone else")
        let row = tip([("Strogruid Noc", 1905, 224), ("Dalia the Collector", 1858, 225), ("Jolee Brightmeadows", 1700, 223),
                       ("<Cloth & Leather Armor>", 1870, 238)])
        check(nameLine(row, nameX: 1901, nameTop: 224)?.text == "Dalia the Collector" && nameLine(row, nameX: 1850, nameTop: 224)?.text == "Jolee Brightmeadows"
              && nameLine(row, nameX: 1901, nameTop: 300) == nil,
              "the name read is the line level with the green name that starts nearest left of its centre, never a neighbour's")
        check(sameTitle("HARVEStinG WinostonES", "Harvesting Windstones") && sameTitle("The Gift of Skysight", "The Gift of Skysight")
              && !sameTitle("The Gift of Skysight", "Harvesting Windstones") && !sameTitle("Harvesting", "Harvesting Windstones")
              && !sameTitle("Required Items:", "Harvesting Windstones") && !sameTitle("", "Harvesting Windstones") && !sameTitle("Shoal", "Shoals"),
              "the dialogue's decorative title is the quest's with a letter in eight misread (live run 5); another title or a part is not")
        check(tooltipGone([false, false]) && tooltipGone([true, nil, false, false]) && !tooltipGone([false]) && !tooltipGone([nil, false])
              && !tooltipGone([false, nil]) && !tooltipGone([false, true]) && !tooltipGone([]),
              "a tooltip has gone only after two fresh reads in a row without the name; an unreadable frame proves nothing")
        check(repeatsClick((1906, 313), (1907, 313), h: 33) && !repeatsClick((1880, 290), (1906, 313), h: 33)
              && !repeatsClick((1906, 313), nil, h: 33),
              "an unconfirmed click is not repeated at the same point; a new point after Click-to-Move may be tried")
        // 25 Sept, the owner's zoom: a 15 x 19 "?" and its dot 11 px under it, the name 54-63 px below the centre.
        var near = RGBA(width: 400, height: 300, pixels: [UInt8](repeating: 30, count: 400 * 300 * 4))
        func dab(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8)) {
            var px = near.pixels
            for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { let i = (y * 400 + x) * 4; (px[i], px[i + 1], px[i + 2]) = rgb } }
            near = RGBA(width: 400, height: 300, pixels: px)
        }
        dab(200, 40, 15, 19, (250, 210, 40)); dab(198, 69, 5, 4, (250, 210, 40)); dab(160, 107, 100, 9, (60, 190, 40))
        check(questMarks(near, box: (0, 0, 400, 300)).count == 1, "a taller mark at a closer zoom finds its name farther below")
        dab(160, 107, 100, 9, (30, 30, 30)); dab(160, 160, 100, 9, (60, 190, 40))
        check(questMarks(near, box: (0, 0, 400, 300)).isEmpty, "but not a name beyond 2.5 mark heights")
        dab(160, 160, 100, 9, (30, 30, 30)); dab(160, 107, 100, 9, (60, 190, 40))
        check(questMarks(near, box: (0, 0, 400, 105)).isEmpty, "nor a name below the world box, where the HUD is")
        dab(215, 118, 40, 8, (60, 190, 40))  // a subtitle, right of centre, two rows under the name (the search keeps x 156-255)
        let titled = questMarks(near, box: (0, 0, 400, 300))
        check(titled.count == 1 && abs(titled[0].nameX - 207.5) < 0.01 && titled[0].nameTop == 107 && titled[0].body == 125 + 2.4 * titled[0].h,
              "the name's centre is its own line: a subtitle below does not pull it, though the click goes below both")
        // Live run 6, 26 Sept: beside Dalia a 27 x 30 hook had its 11 x 9 dot 18 px below, and no mark was read.
        var close = RGBA(width: 400, height: 400, pixels: [UInt8](repeating: 30, count: 400 * 400 * 4))
        func put(_ x0: Int, _ y0: Int, _ w: Int, _ h: Int, _ rgb: (UInt8, UInt8, UInt8)) {
            var px = close.pixels
            for y in y0..<(y0 + h) { for x in x0..<(x0 + w) { let i = (y * 400 + x) * 4; (px[i], px[i + 1], px[i + 2]) = rgb } }
            close = RGBA(width: 400, height: 400, pixels: px)
        }
        put(180, 40, 27, 30, (250, 210, 40)); put(188, 88, 11, 9, (250, 210, 40)); put(140, 135, 110, 9, (60, 190, 40))
        let beside = questMarks(close, box: (0, 0, 400, 400))
        check(beside.count == 1 && beside[0].h == 57 && beside[0].body == 143 + 2.4 * 57,
              "a near \"?\" joins its dot 18 px below and reads as one mark, 27 px wide")
        put(188, 88, 11, 9, (30, 30, 30))
        check(questMarks(close, box: (0, 0, 400, 400)).isEmpty, "without a dot a blob wider than 24 px is not a mark: a spell's glow has none")
        put(188, 88, 11, 9, (250, 210, 40)); put(140, 135, 110, 9, (30, 30, 30)); put(185, 120, 20, 20, (60, 190, 40))
        check(questMarks(close, box: (0, 0, 400, 400)).isEmpty,
              "the green under a mark must be a line of text, not a round glow (a Cirrusfly's striped body over its glow)")
        put(180, 40, 27, 30, (30, 30, 30)); put(188, 88, 11, 9, (30, 30, 30)); put(185, 120, 20, 20, (30, 30, 30))
        put(180, 40, 26, 50, (250, 210, 40)); put(140, 135, 110, 9, (60, 190, 40))
        check(questMarks(close, box: (0, 0, 400, 400)).isEmpty, "a tall 26 px glow without a dot is not a mark, even over a name (review of #43)")
        let hookBlob: Blob = (810, 0, 0, 180, 206, 40, 69), dotBlob: Blob = (99, 0, 0, 188, 198, 88, 96)
        let stripe: Blob = (400, 0, 0, 175, 210, 88, 100), farDot: Blob = (99, 0, 0, 188, 198, 110, 118)
        check(withDots([hookBlob, dotBlob]).count == 1 && withDots([hookBlob, dotBlob])[0].dotted
              && withDots([hookBlob, stripe]).count == 2 && withDots([hookBlob, farDot]).count == 2,
              "a small round dot within a hook's height below joins it; a wide segment or a far blob does not")
        // The three minimap "?" of 24 Sept, from the live mask: A's dot is 3 rows from C's hook, as from its own.
        let mask = [(161, "..#####"), (162, ".######"), (163, ".##..###"), (164, ".....###"), (165, ".....##"), (166, "....###"),
                    (167, "...###"), (168, "...##"), (171, "...##"), (172, "...##")]
        var gl = RGBA(width: 60, height: 60, pixels: [UInt8](repeating: 30, count: 60 * 60 * 4))
        func stamp(_ dx: Int, _ dy: Int) {
            var px = gl.pixels
            for (row, text) in mask { for (i, c) in text.enumerated() where c == "#" {
                let k = ((row - 155 + dy) * 60 + i + dx) * 4; px[k] = 250; px[k + 1] = 242; px[k + 2] = 57 } }
            gl = RGBA(width: 60, height: 60, pixels: px)
        }
        stamp(10, 0); stamp(25, 7); stamp(5, 14)
        let parts = glyphs(yellowBlobs(gl, box: (0, 0, 60, 60), gap: 0))
        check(parts.count == 3 && parts.allSatisfy { $0.n > 20 }, "three touching \"?\": each hook takes its own dot")
        // A minimap "?" (the mask above) and a "!" as the 23 Sept Thendal frames drew it: a bar 5 px wide at the
        // top narrowing to 3, then a 2-px dot.
        let bang = [(0, ".###."), (1, "#####"), (2, "#####"), (3, "####."), (4, ".###."), (5, ".###."), (6, ".###."), (10, ".##.."), (11, ".##..")]
        var mini = [UInt8](repeating: 30, count: 2560 * 320 * 4)
        func put(_ rows: [(Int, String)], _ x0: Int, _ y0: Int) {
            for (row, text) in rows { for (i, c) in text.enumerated() where c == "#" {
                let k = ((y0 + row) * 2560 + x0 + i) * 4; mini[k] = 250; mini[k + 1] = 242; mini[k + 2] = 57 } }
        }
        put(mask.map { ($0.0 - 161, $0.1) }, MinimapHUD.cx + 20, MinimapHUD.cy - 10)
        put(bang, MinimapHUD.cx - 30, MinimapHUD.cy + 10)
        let icons = minimapPins(RGBA(width: 2560, height: 320, pixels: mini)).sorted { $0.x < $1.x }
        check(icons.count == 2 && icons[0].offer && !icons[1].offer, "a minimap \"!\" (a quest to take) is told from a \"?\" by its width")
        check(markYellow(239, 236, 116) && markYellow(184, 155, 39) && !markYellow(135, 111, 74) && !markYellow(144, 115, 59),
              "yellow by hue: the live minimap \"?\" and a dim NPC \"?\", not parchment or tan land")

        check((try? parseNav(["--turn-in", "--keys", "wqe", "--quest", "The Cirrusfly Queen"]))?.quest == "The Cirrusfly Queen",
              "--turn-in takes the quest's title")
        check((try? parseNav(["--turn-in", "--keys", "wqe"])) == nil, "--turn-in without --quest is refused")
        check((try? parseNav(["--quests", "--graph", "g.json", "--keys", "wqe"]))?.graph == "g.json"
              && (try? parseNav(["--quests", "--keys", "wqe"])) == nil && (try? parseNav(["--quests", "--graph", "g.json"])) == nil,
              "--quests needs a quest graph and the confirmed key profile")
        check((try? parseNav(["--turn-in", "--keys", "wqe", "--quest", "x; rm -rf"])) == nil, "a quest title is letters and simple punctuation")
        let offered = tip([("Accept the Windstones from Boros", 30, 200), ("Accept", 40, 690), ("Decline", 280, 690)])
        check(acceptButton(offered)?.y == 690 && acceptButton(tip([("Accept the Windstones", 30, 200), ("Goodbye", 40, 690)])) == nil,
              "the follow-up's Accept is its button, never quest text starting with \"Accept\"")
        // Live, 25 Sept: with nothing open, a vendor's name in the world beside the box was read as her dialogue.
        check(!panelOpen(tip([("Jolee Brightmeadows", 12, 402), ("«Cloth & Leather Armor>", 20, 420)])) && panelOpen(offered)
              && panelOpen(tip([("The Gift of Skysight", 30, 200), ("Complete Quest", 40, 690)])) && !panelOpen([]),
              "a panel is open only when one of its buttons is read, never a name in the world behind the box")
        // Run 3's pace: a 0.1 step every 0.3 s while walking.
        let walking: [(t: Double, at: MapPoint?)] = (0..<8).map { i in (0.3 * Double(i), (43.0 + 0.1 * Double(i), 24.0)) }
        let stopped = walking + [2.5, 3.0, 3.5, 4.0].map { t -> (t: Double, at: MapPoint?) in (t, (43.7, 24.0)) }  // near 43.7 since t = 1.8
        check(!stoodStill(walking, for: 2) && stoodStill(stopped, for: 2) && !stoodStill(Array(stopped.dropLast()), for: 2),
              "Click-to-Move has ended once the position stays within a step for the whole window, not before")
        let flicker: [(t: Double, at: MapPoint?)] = [0, 0.5, 1.0, 1.5, 2.0].enumerated().map { i, t in (t, (i % 2 == 0 ? 43.3 : 43.2, 24.0)) }
        check(stoodStill(flicker, for: 2), "a reading that flickers by one step while standing is still")
        check(!stoodStill([(0, nil), (1, nil), (2, nil), (3, nil)], for: 2) && !stoodStill([(0, nil), (1, nil), (2.5, (43.3, 24.0))], for: 2)
              && stoodStill([(0, (43.3, 24.0)), (1, nil), (2, nil), (2.5, (43.3, 24.0))], for: 2) && !stoodStill([], for: 2),
              "unreadable reads count neither way; the window needs a readable read at each end")
        plans()
    }

    /// The quest log and world-map pins of 24 Sept, after The Cirrusfly Queen was handed in.
    static let log24Sept = [
        PlannedQuest(title: "Call of Earth", level: 4, ready: true, objective: "Find the Rise of Spirits and drink the Earth Sapta.", pin: (50.1, 23.8)),
        PlannedQuest(title: "Harvesting Windstones", level: 4, ready: false, objective: "- 12/15 Windstone Cluster", pin: (44.2, 25.6)),
        PlannedQuest(title: "The Gift of Skysight", level: 4, ready: false, objective: "- Use Skysight near the Elemental Convergence", pin: (48.9, 20.4)),
        PlannedQuest(title: "The Next Step", level: 5, ready: true, objective: "- Report to Constable Aonda in Shen'dar Village.", pin: (46.1, 45.2)),
        PlannedQuest(title: "The Adventurer", level: 6, ready: true, objective: "- Speak to Raan Wildwind near Shen'dar Village.", pin: (42.0, 44.4)),
    ]

    static func plans() {
        check(log24Sept.map(questKind) == [.useAt, .collect, .useAt, .travel, .travel], "objective text to quest kind")
        check(questKind(PlannedQuest(title: "The Cirrusfly Queen", level: 3, ready: true, objective: "Ready for turn-in", pin: nil)) == .handIn
              && questKind(PlannedQuest(title: "Q", level: 3, ready: false, objective: "- 0/1 Cirrusfly Queen slain", pin: nil)) == .kill,
              "a finished quest is a hand-in; a slain count is a kill")
        let zones = questZones(log24Sept, within: 12)
        check(zones.count == 2 && zones.map(\.count).sorted() == [2, 3], "Thendal's three level-4 quests and Shen'dar's two are two zones")
        let order = questPlan(log24Sept, from: (46.8, 31.5)).map(\.title)
        check(order == ["Harvesting Windstones", "The Gift of Skysight", "Call of Earth", "The Next Step", "The Adventurer"],
              "owner's rule: finish the player's zone, nearest first, before the next zone (not the nearest single pin)")
        let south = questPlan(log24Sept, from: (45.0, 43.0)).map(\.title)
        check(Array(south.prefix(2)).sorted() == ["The Adventurer", "The Next Step"], "standing in Shen'dar, its quests come first")
        var unpinned = log24Sept
        unpinned[0].pin = nil
        check(questPlan(unpinned, from: (46.8, 31.5)).last?.title == "Call of Earth", "a pinless quest that is not finished goes last")
        var lostPin = log24Sept
        lostPin[3].pin = nil
        lostPin[1].objective = "- Ready for turn-in"
        lostPin[1].pin = nil
        let lost = questPlan(lostPin, from: (46.8, 31.5)).map(\.title)
        check(lost.first == "Harvesting Windstones" && lost.last == "The Next Step",
              "live: a finished pinless quest is here; a Shen'dar delivery whose pin was not read is not pulled into this zone")
        let live2 = parseQuestLog(tip([("Zephras Isle", 790, 224), ("[4] Call of Earth", 804, 254), ("Bring the Kough Quartz to", 818, 272),
            ("Windshaper Boros in Thendal", 818, 284), ("Grove.", 816, 296), ("[4] Harvesting Windstones", 804, 320),
            ("- Ready for turn-in", 804, 336), ("[4] The Gift of Skysight", 804, 362), ("- Ready for turn-in", 804, 378)]))
        check(live2.map(questKind) == [.travel, .handIn, .handIn], "live 24 Sept: a dash line at the title's x is an objective; \"Bring\" is a delivery")
        // The log as Vision read it live (24 Sept): the "- " markers are not read; "Zephras" came out "Lephras".
        let rows: [(String, Double, Double)] = [("Lephras Isle", 792, 226), ("[4] Call of Earth", 804, 254),
            ("Find the Rise of Spirits and drink", 816, 270), ("the Earth Sapta.", 816, 284), ("[4] Harvesting Windstones", 804, 308),
            ("12/15 Windstone Cluster", 816, 324), ("[4] The Gift of Skysight", 804, 348), ("Use Skysight near the Elemental", 816, 364),
            ("Convergence", 816, 378), ("[5] The Next Step", 804, 402), ("Report to Constable Aonda in", 814, 418),
            ("Shen' dar Village.", 816, 431), ("Camping", 792, 459), ("[6] The Adventurer", 804, 490),
            ("Speak to Raan Wildwind near", 816, 506), ("Shen'dar Village.", 816, 517)]
        let parsed = parseQuestLog(tip(rows).reversed())
        check(parsed.map(\.title) == ["Call of Earth", "Harvesting Windstones", "The Gift of Skysight", "The Next Step", "The Adventurer"]
              && parsed.map(\.level) == [4, 4, 4, 5, 6], "quest log: titles and levels, in the log's order")
        check(parsed[0].objective == "Find the Rise of Spirits and drink the Earth Sapta." && parsed.map(questKind) == [.useAt, .collect, .useAt, .travel, .travel],
              "objectives join their wrapped lines, and read as the same kinds")
        // Live run 7, 26 Sept: the log after a hand-in read empty, "]" as "1" and the "?" icon as ")".
        let run7 = parseQuestLog(tip([("Lephras Isle", 792, 227), ("[51 The Next Step", 804, 253), ("- Report to Constable Aonda in", 816, 271),
            ("Shen' dar Village.", 816, 283), ("Camping", 792, 312), (") [6] The Adventurer", 792, 341), ("Speak to Raan Wildwind near", 816, 357),
            ("Shen' dar Village.", 816, 369)]))
        check(run7.map(\.title) == ["The Next Step", "The Adventurer"] && run7.map(\.level) == [5, 6] && run7.map(questKind) == [.travel, .travel],
              "a level's bracket misread as 1, and an icon read before it, still start a quest")
        check(questTitle("[12] Rise of the Grove")!.level == 12 && questTitle("[11] Eleven")!.title == "Eleven"
              && questTitle("[151 Fifteen")!.level == 15 && questTitle("[5]The Next Step")!.title == "The Next Step"
              && questTitle("Report to [Boros]") == nil && questTitle("Camping") == nil,
              "two-digit levels read whole; a true bracket needs no space after it; a bracket inside an objective does not start a quest")
        check(questTitle("to [4] Camp") == nil && questTitle("- [5] Phantom") == nil && questTitle(") [6] The Adventurer")!.prefixed
              && !questTitle("[6] The Adventurer")!.prefixed && questTitle("[5] ") == nil,
              "a wrapped objective with a bracket, or a dash line, is not a title; an icon's stray mark is (review of #44)")
        let column = parseQuestLog(tip([("[5] A Quest", 804, 250), ("- one", 816, 266), (") [6] B Quest", 792, 300), ("Speak to X", 816, 316),
            ("6] C Quest", 804, 350), ("obj C", 816, 366)]))
        check(column.map(\.title) == ["A Quest", "B Quest"] && column[1].objective == "Speak to X",
              "a prefixed title keeps the clean titles' column: a garbled title at that column ends the quest above, not joins it")
        // Working memory of the log, keyed by the zone and the tracker (live OCR of runs 5, 6 and 7, 26 Sept).
        let tracked5 = ["All Objectives", "Quests", "The Next Step", "Report to Constable Aonda in", "Shen' dar Village.",
                        "Harvesting Windstones", "Ready for turn-in", "The Adventurer", "Speak to Raan Wildwind near", "Shen' dar Village."]
        var tracked6 = tracked5
        tracked6[4] = "Shen dar Village."
        let tracked7 = ["All Objectives", "Quests", "The Next Step", "Report to Constable Aonda in", "Shen' dar Village.",
                        "The Adventurer", "Speak to Raan Wildwind near", "Shen dar Village."]
        let key5 = logKey(zone: ["12:32", "Thendal Village"], tracker: tracked5)
        check(key5 == logKey(zone: ["12:58", "Thendal Village"], tracker: tracked6) && key5 != logKey(zone: ["12:58", "Thendal Village"], tracker: tracked7)
              && key5 != logKey(zone: ["* Thendal Grove"], tracker: tracked5) && logKey(zone: [], tracker: tracked5).isEmpty
              && logKey(zone: ["Thendal Village"], tracker: []).isEmpty,
              "the log's key: the clock and stray apostrophes drop out; a hand-in, another zone or an unread box change it")
        check(logKey(zone: ["Thendal Village"], tracker: ["- 12/15 Windstone Cluster"]) != logKey(zone: ["Thendal Village"], tracker: ["- 13/15 Windstone Cluster"]),
              "an objective's count is part of the key")
        let saved = LogMemory(key: key5, quests: [LogMemory.Quest(PlannedQuest(title: "The Next Step", level: 5, ready: false,
                              objective: "Report to Constable Aonda in Shen'dar Village.", pin: (46, 45.1)))], readAt: 1000)
        let kept = keptLog(try? JSONDecoder().decode(LogMemory.self, from: JSONEncoder().encode(saved)), key: key5, at: 1000 + logMemoryAge - 1)
        check(kept?.count == 1 && kept?[0].title == "The Next Step" && kept?[0].pin.map { $0 == (46, 45.1) } == true && questKind(kept![0]) == .travel,
              "a remembered log keeps its titles, objectives and pins through its file")
        check(keptLog(saved, key: key5, at: 1000 + logMemoryAge) == nil && keptLog(saved, key: key5, at: 999) == nil
              && keptLog(saved, key: "", at: 1100) == nil && keptLog(saved, key: key5 + "x", at: 1100) == nil && keptLog(nil, key: key5, at: 1100) == nil,
              "the map is read again after an hour, a clock that went back, an unread key, a changed key or no memory")
        let log5 = [PlannedQuest(title: "The Next Step", level: 5, ready: false, objective: "", pin: nil),
                    PlannedQuest(title: "Harvesting Windstones", level: 4, ready: true, objective: "", pin: nil),
                    PlannedQuest(title: "The Adventurer", level: 6, ready: false, objective: "", pin: nil)]
        check(trackerShows(log5, tracked5) && !trackerShows(log5, ["All Objectives", "Quests"]) && !trackerShows(log5, Array(tracked5.prefix(7)))
              && trackerShows([], ["All Objectives"]),
              "a log is remembered only when the tracker shows each of its quests: not collapsed, filtered or cut off by the box")
        // The live log of run 5 against its upscaled tracker (x 2200, y 400): what may be remembered.
        let log5Full = [PlannedQuest(title: "The Next Step", level: 5, ready: false, objective: "Report to Constable Aonda in Shen' dar Village.", pin: nil),
                        PlannedQuest(title: "Harvesting Windstones", level: 4, ready: true, objective: "- Ready for turn-in", pin: nil),
                        PlannedQuest(title: "The Adventurer", level: 6, ready: false, objective: "- Speak to Raan Wildwind near Shen' dar Village.", pin: nil)]
        let tracker5 = Array(tracked5.dropFirst(2))  // the box starts below "All Objectives" and "Quests"
        check(rememberLog(log5Full, tracker: tracker5, key: key5, missing: []),
              "a complete read, agreeing with the tracker both ways, is remembered")
        check(!rememberLog([log5Full[1]], tracker: tracker5, key: key5, missing: []) && !rememberLog([], tracker: tracker5, key: key5, missing: [])
              && !rememberLog(log5Full, tracker: tracker5, key: key5, missing: ["Call of Earth"]) && !rememberLog(log5Full, tracker: tracker5, key: "", missing: [])
              && !rememberLog(log5Full, tracker: [], key: key5, missing: []),
              "one quest parsed of three, an empty parse, a quest the minimap named but the log lacks, no key or no tracker: not remembered (review of #46)")
        let back = zonePoint(mapPixel((46.1, 45.2)).x, mapPixel((46.1, 45.2)).y)
        check(abs(back.x - 46.1) < 1e-9 && abs(back.y - 45.2) < 1e-9 && abs(mapPixel((44.2, 25.6)).x - 348) < 1,
              "map pixels and zone coordinates round-trip; the player arrow at 44.2, 25.6 sat at x 348")
        let thendal: MapPoint = (42.8, 23.5)
        check(thisZone(questPlan(log24Sept, from: thendal), from: thendal).map(\.title).sorted()
              == ["Call of Earth", "Harvesting Windstones", "The Gift of Skysight"], "this zone: the hub's quests, not Shen'dar's")
        let onlyFar = [log24Sept[4]]
        check(thisZone(questPlan(onlyFar, from: thendal), from: thendal).isEmpty,
              "live 24 Sept: with only Shen'dar's quest read, nothing is in this zone (not a 20-unit walk for a cliff)")
        check(missingFromLog([["Harvesting Windstones"], ["The Gift of Skysight"]], onlyFar) == ["Harvesting Windstones", "The Gift of Skysight"]
              && missingFromLog([["18 m", "The Gift of Skysight"], ["Call of Earth", "15m"], ["Call of Earth"]], log24Sept).isEmpty,
              "live 24 Sept: minimap names the log read lacks make it incomplete; distance lines are not names")
        check(missingFromLog([["Dalia the Collector", "Harvesting Windstones"], ["nsana", "Dalia the Collector", "The Gift of Skysight"]],
                             log24Sept).isEmpty, "live 25 Sept: an NPC's name above a quest the log holds is not a missing quest")
        check(missingFromLog([["Dalia the Collector", "Harvesting Windstones"], ["Dalia the Collector", "18 m"]], log24Sept)
              == ["Dalia the Collector"], "a tooltip naming no quest the log holds still counts, NPC name or not")
        check(mapCursor(["Cursor: 42.3, 22.9", "Player: 42.8, 23.3"]).map { $0 == (42.3, 22.9) } == true
              && mapCursor(["Cursor 7.5,60.0"]).map { $0 == (7.5, 60.0) } == true && mapCursor(["Player: 42.8, 23.3"]) == nil && mapCursor([]) == nil,
              "live, 26 Sept: the map's own cursor line gives a pin's zone coordinates on any map; the player's line is not the cursor")
    }

    /// A quest host with scripted reads and hand-in outcomes (every hand-in completes unless listed; every hunt completes unless listed).
    final class FakeQuests: QuestHost {
        var reads: [QuestRead]
        var outcomes: [String: String] = [:]
        var handed: [String] = []
        var clock = 0.0
        init(_ reads: [QuestRead]) { self.reads = reads }
        func readQuests() async -> QuestRead? { reads.isEmpty ? nil : reads.removeFirst() }
        func handIn(_ quest: PlannedQuest) async -> String { handed.append(quest.title); return outcomes[quest.title] ?? "COMPLETED" }
        func accept(_ giver: Giver) async -> String { handed.append("!" + giver.key); return outcomes["!" + giver.key] ?? "ACCEPTED" }
        func retreat() async -> String { handed.append("RETREAT"); return outcomes["RETREAT"] ?? "RETREATED" }
        func fightBack() async -> String { handed.append("FIGHT_BACK"); return outcomes["FIGHT_BACK"] ?? "KILLED_AND_LOOTED" }
        var budgets: [Double] = [], huntTakes = 0.0
        func hunt(_ quest: PlannedQuest, seconds: Double) async -> String {
            handed.append("HUNT " + quest.title); budgets.append(seconds); clock += huntTakes
            return outcomes["HUNT " + quest.title] ?? "HUNTED"
        }
        func now() -> Double { clock += 0.1; return clock }
        func ownerTookFocus() -> Bool { false }
        func emit(_ event: String, _ fields: [String: Any]) {}
    }

    /// Graph replies in order ("READ:owner_rules", "DO:HAND_IN_2"); it keeps what each call offered and sent.
    final class CannedGraph: JevClient {
        var script: [String]
        var offered: [[String]] = []
        var sent: [[String: Any]] = []
        init(_ script: [String]) { self.script = script }
        func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
            let options = Array((question["criteria"] as? [String: String] ?? [:]).keys)
            offered.append(options.sorted()); sent.append(state)
            guard !script.isEmpty else { throw GraphError.noSkills }
            let name = script.removeFirst()
            return ["model": FightLimits.model, "answers": ["action": ["choice": name, "confidence": 1.0,
                "probabilities": Dictionary(uniqueKeysWithValues: options.map { ($0, $0 == name ? 1.0 : 0.0) })]]]
        }
    }

    /// M4f on the live Thendal values of 24 Sept: Jev chooses among the hub's hand-ins; Shen'dar's are not offered.
    static func questGraph() async {
        let path = "experiments/002_wow_visual/runtime/skyborne-quest.graph.json"
        func graph() -> GraphSession? { try? GraphSession.load(URL(fileURLWithPath: path)) }
        check((graph()?.references["owner_rules"]?["text"] as? String)?.contains("Finish every available quest") == true,
              "the quest graph loads, with the owner's quest rules as a reference section")
        let thendal: MapPoint = (42.8, 23.5)
        let hub = [PlannedQuest(title: "Harvesting Windstones", level: 4, ready: true, objective: "- Ready for turn-in", pin: (43.4, 23.9)),
                   PlannedQuest(title: "The Gift of Skysight", level: 4, ready: true, objective: "- Ready for turn-in", pin: (42.7, 24.3))]
        let south = [log24Sept[3], log24Sept[4]]
        let jev = CannedGraph(["READ:owner_rules", "DO:HAND_IN_2", "DO:HAND_IN_1"])
        let host = FakeQuests([QuestRead(quests: hub + south, player: thendal, missing: []),
                               QuestRead(quests: [hub[1]] + south, player: (43.4, 23.9), missing: []),
                               QuestRead(quests: south, player: (42.7, 24.3), missing: [])])
        let result = await runQuests(host: host, jev: jev, graph: graph()!)
        check(jev.offered.first == ["DO:HAND_IN_1", "DO:HAND_IN_2", "READ:owner_rules", "READ:quest_log", "READ:recent"],
              "offered: the hub's two hand-ins and three reads; Shen'dar's quests, 20 units away, are not")
        check(host.handed == ["Harvesting Windstones", "The Gift of Skysight"] && result.outcome == "NEXT_ZONE_NEEDS_ROADS",
              "Jev's choice of the second slot (the owner's order puts Skysight, nearer, first) is handed in first, the log is read again, then the run stops at the zone's edge")
        check(((jev.sent[1]["tool_memory"] as? [String: Any])?["owner_rules"] as? [String: Any])?["text"] as? String != nil
              && jev.sent[0]["quest_log"] == nil && result.graphRecords.count == 3,
              "a READ puts the owner's rules into the next request only; every graph call is recorded")

        let blind = FakeQuests([QuestRead(quests: [log24Sept[4]], player: thendal, missing: ["Harvesting Windstones", "The Gift of Skysight"])])
        let unasked = CannedGraph([])
        let incomplete = await runQuests(host: blind, jev: unasked, graph: graph()!)
        check(incomplete.outcome == "LOG_INCOMPLETE" && unasked.offered.isEmpty && blind.handed.isEmpty,
              "live 24 Sept: the log read one quest while the minimap named two more: stop, no Jev call, no walk")

        let stuck = FakeQuests([QuestRead(quests: hub, player: thendal, missing: []), QuestRead(quests: hub, player: thendal, missing: [])])
        stuck.outcomes = ["Harvesting Windstones": "WALK_NO_PROGRESS", "The Gift of Skysight": "WALK_NO_PROGRESS"]
        let twice = CannedGraph(["DO:HAND_IN_1", "DO:HAND_IN_1"])
        let twiceStuck = await runQuests(host: stuck, jev: twice, graph: graph()!)
        check(twiceStuck.outcome == "NO_PROGRESS_TWICE" && twice.offered[1].filter { $0.hasPrefix("DO:") }.count == 1,
              "a failed hand-in is not offered again, and the second NO_PROGRESS ends the run")
        let attacked = FakeQuests([QuestRead(quests: hub, player: thendal, missing: []), QuestRead(quests: hub, player: thendal, missing: []),
                                   QuestRead(quests: [], player: thendal, missing: [])])
        attacked.outcomes = ["The Gift of Skysight": "WALK_COMBAT"]  // slot 1: nearer
        let fighter = CannedGraph(["DO:HAND_IN_1", "DO:HAND_IN_2"])
        let combat = await runQuests(host: attacked, jev: fighter, graph: graph()!)
        check(attacked.handed == ["The Gift of Skysight", "FIGHT_BACK", "Harvesting Windstones"] && combat.outcome == "NOTHING_TO_HAND_IN_OR_TAKE"
              && fighter.offered.count == 2 && fighter.offered[1].filter { $0.hasPrefix("DO:HAND_IN") }.count == 2,
              "attacked on a walk: an M3 fight at once, with no Jev call; won, the run goes on and the interrupted hand-in is offered again")
        let beaten = FakeQuests([QuestRead(quests: hub, player: thendal, missing: [])])
        beaten.outcomes = ["The Gift of Skysight": "WALK_COMBAT", "FIGHT_BACK": "JEV_STOP"]
        let lost = await runQuests(host: beaten, jev: CannedGraph(["DO:HAND_IN_1"]), graph: graph()!)
        check(lost.outcome == "FIGHT_JEV_STOP" && beaten.handed == ["The Gift of Skysight", "FIGHT_BACK"],
              "a fight that does not end in a kill, even one Jev stopped, ends the quest run: it may still be under attack")
        let danger = FakeQuests([QuestRead(quests: hub, player: thendal, missing: []), QuestRead(quests: hub, player: thendal, missing: []),
                                 QuestRead(quests: hub, player: thendal, missing: []), QuestRead(quests: [], player: thendal, missing: [])])
        danger.outcomes = ["The Gift of Skysight": "WALK_DANGER_AHEAD"]  // slot 1: nearer
        let wary = CannedGraph(["DO:HAND_IN_1", "DO:RETREAT", "DO:HAND_IN_1"])
        let survived = await runQuests(host: danger, jev: wary, graph: graph()!)
        check(danger.handed == ["The Gift of Skysight", "RETREAT", "Harvesting Windstones"] && survived.outcome == "NOTHING_TO_HAND_IN_OR_TAKE"
              && !wary.offered[0].contains("DO:RETREAT") && wary.offered[1].filter { $0.hasPrefix("DO:") } == ["DO:HAND_IN_1", "DO:RETREAT"]
              && !wary.offered[2].contains("DO:RETREAT"),
              "a red name ahead fails only that step: RETREAT is offered next, the step is not offered again, and the run goes on")
        let cornered = FakeQuests([QuestRead(quests: hub, player: thendal, missing: []), QuestRead(quests: hub, player: thendal, missing: [])])
        cornered.outcomes = ["The Gift of Skysight": "WALK_DANGER_AHEAD", "RETREAT": "WALK_DANGER_AHEAD"]
        let trapped = await runQuests(host: cornered, jev: CannedGraph(["DO:HAND_IN_1", "DO:RETREAT"]), graph: graph()!)
        check(trapped.outcome == "RETREAT_WALK_DANGER_AHEAD" && cornered.handed == ["The Gift of Skysight", "RETREAT"],
              "a retreat that meets a red name too ends the run: no other step is walked from there")
        let wrong = FakeQuests([QuestRead(quests: hub, player: thendal, missing: [])])
        let icons = sortIcons([((43.4, 23.9), false, ["Harvesting Windstones", "18 m"]), ((43.2, 22.4), true, ["Windshaper Boros", "9 m"])])
        check(missingFromLog(icons.tooltips, []) == ["Harvesting Windstones"] && icons.givers.map(\.names) == [["Windshaper Boros"]]
              && icons.hints.count == 1,
              "a \"?\" tooltip must be in the log read; a \"!\" tooltip names a giver and never stops the run as LOG_INCOMPLETE")
        let boros = Giver(names: ["Windshaper Boros"], pin: (43.2, 22.4))
        let giving = FakeQuests([QuestRead(quests: [], player: thendal, missing: [], givers: [boros]),
                                 QuestRead(quests: [], player: (43.2, 22.4), missing: [])])
        let taker = CannedGraph(["DO:ACCEPT_1"])
        let took = await runQuests(host: giving, jev: taker, graph: graph()!)
        check(taker.offered.first?.contains("DO:ACCEPT_1") == true && giving.handed == ["!43.2,22.4"] && took.outcome == "NOTHING_TO_HAND_IN_OR_TAKE",
              "a minimap \"!\" is offered as ACCEPT_1; after taking it, nothing is left to do here")
        let near = questOffers(QuestRead(quests: [], player: thendal, missing: [], givers: [Giver(names: [], pin: thendal, inView: true)]), failed: [])
        check(near.map(\.skill) == ["ACCEPT_1"] && near[0].criterion.contains("mark in view") && near[0].criterion.contains("under the player's arrow"),
              "live, 26 Sept: with no minimap \"!\" (under the arrow), a mark in view is offered as ACCEPT_1, saying what it is")
        let refused = FakeQuests([QuestRead(quests: [], player: thendal, missing: [], givers: [boros]),
                                  QuestRead(quests: [], player: thendal, missing: [], givers: [boros])])
        refused.outcomes = ["!43.2,22.4": "NO_ACCEPT_BUTTON"]
        let once = CannedGraph(["DO:ACCEPT_1"])
        let refusal = await runQuests(host: refused, jev: once, graph: graph()!)
        check(refusal.outcome == "NOTHING_TO_HAND_IN_OR_TAKE" && once.offered.count == 1,
              "a giver whose offer could not be accepted is not offered again this run")
        let invalid = await runQuests(host: wrong, jev: CannedGraph(["DO:HAND_IN_3"]), graph: graph()!)
        check(invalid.outcome == "GRAPH_invalidReply" && wrong.handed.isEmpty,
              "a reply naming a step not offered runs nothing: no rules fallback")

        // Kill and collect quests are hunted: within one walk, or from here when the map showed no area.
        let winds = PlannedQuest(title: "Agitators", level: 2, ready: false, objective: "- 0/6 Roiling Winds destroyed", pin: (43.0, 25.0))
        let shards = PlannedQuest(title: "Wind Shards", level: 2, ready: false, objective: "- 2/8 Wind Shard", pin: nil)
        let boars = PlannedQuest(title: "Far Boars", level: 3, ready: false, objective: "- 0/5 Boar slain", pin: (42, 44))
        let offered = questOffers(QuestRead(quests: [winds, shards, boars, hub[0]], player: thendal, missing: []), failed: [])
        let hunted = offered.compactMap { o -> String? in if case .hunt(let q) = o.step { return o.skill + " " + q.title }; return nil }
        check(offered.map(\.skill).filter { $0.hasPrefix("HAND_IN") } == ["HAND_IN_1"]
              && (Set(hunted) == ["HUNT_1 Agitators", "HUNT_2 Wind Shards"] || Set(hunted) == ["HUNT_1 Wind Shards", "HUNT_2 Agitators"]),
              "a kill and a collect quest are hunted; one 20 units away is not, nor the ready quest")
        check(offered.first { $0.skill.hasPrefix("HUNT") && $0.criterion.contains("\"Agitators\"") }?.criterion.contains("units away") == true
              && offered.first { $0.criterion.contains("\"Wind Shards\"") }?.criterion.contains("from here") == true
              && questOffers(QuestRead(quests: [winds], player: thendal, missing: []), failed: ["Agitators"]).isEmpty,
              "a hunt's criterion says where it starts; a failed hunt is not offered again")
        let start = [Objective(quest: "Agitators", done: 0, need: 6, text: "Roiling Winds destroyed")]
        let four = [Objective(quest: "Agitators", done: 4, need: 6, text: "Roiling Winds destroyed")]
        check(huntOutcome("OBJECTIVES_COMPLETE", start: start, end: start) == "HUNTED"
              && huntOutcome("FIGHT_LIMIT", start: start, end: four) == "HUNTED_SOME"
              && huntOutcome("TIME_LIMIT", start: start, end: [Objective(quest: "Agitators", done: 1, need: 1, text: Objective.ready)]) == "HUNTED_SOME"
              && huntOutcome("FIGHT_LIMIT", start: start, end: start) == "HUNT_FIGHT_LIMIT"
              && huntOutcome("FIGHT_LIMIT", start: four, end: [Objective(quest: "Other", done: 5, need: 6, text: "Roiling Winds destroyed")]) == "HUNT_FIGHT_LIMIT"
              && huntOutcome("DEAD", start: start, end: four) == "HUNT_DEAD" && huntOutcome("FIGHT_LOW_HEALTH", start: start, end: four) == "HUNT_FIGHT_LOW_HEALTH",
              "a hunt completes, counts some kills at a limit, or fails; death or a lost fight is never progress")
        let ready = PlannedQuest(title: "Agitators", level: 2, ready: true, objective: "- Ready for turn-in", pin: (43.0, 25.0))
        let camp = FakeQuests([QuestRead(quests: [winds], player: thendal, missing: []), QuestRead(quests: [ready], player: (43.0, 25.0), missing: []),
                               QuestRead(quests: [], player: (43.0, 25.0), missing: [])])
        let hunter = CannedGraph(["DO:HUNT_1", "DO:HAND_IN_1"])
        let done = await runQuests(host: camp, jev: hunter, graph: graph()!)
        check(camp.handed == ["HUNT Agitators", "Agitators"] && done.outcome == "NOTHING_TO_HAND_IN_OR_TAKE"
              && hunter.offered[0].filter { $0.hasPrefix("DO:") } == ["DO:HUNT_1"] && camp.budgets == [HuntLimits.maxSeconds],
              "the quest graph offers HUNT_1; a hunt that completes lets the run go on to hand the quest in; a hunt has its own 15 min")
        let dry = FakeQuests([QuestRead(quests: [winds], player: thendal, missing: []), QuestRead(quests: [winds], player: thendal, missing: [])])
        dry.outcomes = ["HUNT Agitators": "HUNT_NO_TARGET_FOUND"]
        let fruitless = await runQuests(host: dry, jev: CannedGraph(["DO:HUNT_1"]), graph: graph()!)
        check(fruitless.outcome == "NOTHING_TO_HAND_IN_OR_TAKE" && dry.handed == ["HUNT Agitators"],
              "a hunt that found nothing fails its step, which is not offered again")
        let killed = FakeQuests([QuestRead(quests: [winds], player: thendal, missing: []), QuestRead(quests: [winds], player: thendal, missing: [])])
        killed.outcomes = ["HUNT Agitators": "HUNT_DEAD"]
        let died = await runQuests(host: killed, jev: CannedGraph(["DO:HUNT_1", "DO:HUNT_1"]), graph: graph()!)
        check(died.outcome == "HUNT_DEAD" && killed.handed == ["HUNT Agitators"],
              "a hunt that ends in death, or with any code but its limits, ends the run: the envelope stops at one death")
        let slow = FakeQuests(Array(repeating: QuestRead(quests: [winds], player: thendal, missing: []), count: 3))
        slow.outcomes = ["HUNT Agitators": "HUNTED_SOME"]
        slow.huntTakes = 900
        let long = await runQuests(host: slow, jev: CannedGraph(["DO:HUNT_1", "DO:HUNT_1", "DO:HUNT_1"]), graph: graph()!)
        check(slow.handed == ["HUNT Agitators", "HUNT Agitators"] && long.outcome == "TIME_LIMIT"
              && slow.budgets.first == HuntLimits.maxSeconds && slow.budgets.count == 2 && (590...600).contains(slow.budgets[1]),
              "a hunt that counted some kills is offered again; the next gets what is left of the run's 25 min, and none starts after them")
    }
}
