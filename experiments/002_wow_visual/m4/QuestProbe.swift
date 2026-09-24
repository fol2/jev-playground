// M4c native shell for issue #5: `--turn-in --keys wqe --quest NAME`, run at the quest's NPC. Scripts
// find the "?", right-click the NPC, read each reward's tooltip, apply the owner's reward rule, click the
// reward and Complete Quest, then equip an upgrade with /equip. No Jev call: every step is a RULE.
// Layout measured on 24 Sept PNG captures at 2560x1320, zoomed fully out.
import AppKit
import Vision

enum QuestHUD {
    static let dialog = CGRect(x: 0, y: 140, width: 400, height: 580)  // the quest dialogue, left edge
    static let tooltip = CGRect(x: 150, y: 100, width: 850, height: 560)  // a reward's tooltip and the equipped one
    static let chatInput = CGRect(x: 30, y: 1160, width: 700, height: 44)  // "Say:" once Enter opens it
    static let world = (300, 100, 2100, 950)  // where quest marks are looked for
    static let rewardX = [130.0, 274.0], firstRow = 37.0, rowGap = 44.0  // reward names below "Choose your reward:"
    static let buttonCentre = 56.0  // "Complete Quest": from the text's left edge to the button's centre
    static let enter: UInt16 = 36
    static let escape: UInt16 = 53
    static let characterPane: UInt16 = 8  // C
    /// Character pane slots (C). Chest was read live on 24 Sept; the others follow the standard layout.
    static let paneSlots: [String: (x: Double, y: Double)] = [
        "Head": (62, 258), "Neck": (62, 304), "Shoulder": (62, 350), "Back": (62, 398), "Chest": (62, 444), "Shirt": (62, 490),
        "Tabard": (62, 536), "Wrist": (62, 584), "Hands": (404, 258), "Waist": (404, 304), "Legs": (404, 350), "Feet": (404, 398),
        "Finger": (404, 444), "Trinket": (404, 536), "Main Hand": (166, 620), "One-Hand": (166, 620), "Two-Hand": (166, 620),
        "Off Hand": (212, 620), "Held In Off-hand": (212, 620), "Ranged": (258, 620)]
    static let paneTooltip = CGRect(x: 60, y: 200, width: 460, height: 460)
    static let mapKey: UInt16 = 37  // L, the Map & Quest Log
    static let questList = CGRect(x: 775, y: 225, width: 345, height: 560)
    static let mapRight = 770.0  // pin tooltips are read left of this: the quest list repeats every title
}

final class QuestRun {
    let body: LiveNavBody
    let routed: RoutedClickTarget
    let bounds: CGRect

    init(body: LiveNavBody) throws {
        self.body = body
        bounds = body.session.window.frame
        routed = try routedTarget(pid: body.session.app.processIdentifier, window: body.session.window.windowID, bounds: bounds)
    }

    func image() -> CGImage? {
        guard let frame = body.feed.latestFrame, hostNow() - frame.pts <= FightLimits.maxFrameAge else { return nil }
        return frame.image
    }

    /// A fresh frame, waiting up to 2.5 s: each background move or click first sends WoW a focus record,
    /// and the capture then went quiet for 1-2 s (24 Sept: a false safety stop after looting, an empty
    /// minimap scan). The wait is logged, and nil is reported by the caller, never skipped silently.
    func frame() async -> CGImage? {
        let start = hostNow()
        while hostNow() - start < 2.5 {
            if let image = image() {
                if hostNow() - start > 0.05 { body.emit("frame_wait", ["seconds": hostNow() - start]) }
                return image
            }
            await sleep(0.1)
        }
        body.emit("frame_wait", ["seconds": hostNow() - start, "fresh": false])
        return nil
    }

    /// OCR lines of a box in capture pixels, each flagged red when its text is drawn red.
    func lines(_ box: CGRect, _ image: CGImage?) -> [TipLine] {
        guard let crop = image?.cropping(to: box) else { return [] }
        let px = rgba(crop)
        return ocr(crop).map { text, b in
            let x0 = Int(b.minX * box.width), y0 = Int((1 - b.maxY) * box.height)
            let x1 = Int(b.maxX * box.width), y1 = Int((1 - b.minY) * box.height)
            var red = 0
            for y in max(0, y0)..<min(px.height, y1) {
                for x in max(0, x0)..<min(px.width, x1) {
                    let i = (y * px.width + x) * 4
                    if px.pixels[i] > 170 && px.pixels[i + 1] < 90 && px.pixels[i + 2] < 90 { red += 1 }
                }
            }
            return TipLine(text: text, x: box.minX + Double(x0), y: box.minY + Double(y0), red: red > 15)
        }
    }

    func at(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: bounds.minX + bounds.width * x / Double(HUD.width), y: bounds.minY + bounds.height * y / Double(HUD.height))
    }

    func hover(_ x: Double, _ y: Double) { try? NativeBackgroundClickTransport().move(target: routed, point: at(x, y)) }

    func click(_ x: Double, _ y: Double, right: Bool = false) -> Bool {
        let request = NativeBackgroundClickDispatchRequest(target: routed, eventTapPointTopLeft: at(x, y), appKitPoint: at(x, y),
                                                           clickCount: 1, mouseButton: right ? .right : .left)
        return (try? NativeBackgroundClickTransport().dispatch(request).dispatchSuccess) ?? false
    }

    func sleep(_ seconds: Double) async { try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000)) }

    func tap(_ code: UInt16) async {
        body.keys.press(code)
        await sleep(0.06)
        body.keys.lift(code)
    }

    func tapEnter() async { await tap(QuestHUD.enter) }

    /// As a human checks: open the character pane, rest the pointer on the slot, read its name, close it.
    /// (/run print(...) raised the client's "Allow custom scripts?" prompt on 24 Sept: that is the
    /// owner's security choice, so the engine uses no /run.)
    func wearing(_ name: String, slot: String) async -> Bool? {
        guard let point = QuestHUD.paneSlots[slot] else { return nil }
        await tap(QuestHUD.characterPane)
        await sleep(1.0)
        hover(point.x, point.y)
        await sleep(0.8)
        let read = lines(QuestHUD.paneTooltip, await frame()).map(\.text)
        await tap(QuestHUD.characterPane)
        body.emit("pane_slot", ["slot": slot, "lines": Array(read.prefix(4))])
        return read.contains { nameKey($0) == nameKey(name) }
    }

    /// A chat command: Enter, and only once the edit box shows, the text and Enter. Typed letters are
    /// never sent without the box: outside it they are game keys.
    func command(_ text: String) async -> Bool {
        await tapEnter()
        await sleep(0.5)
        guard let shown = await frame(), upscaledText(shown, QuestHUD.chatInput).contains(where: { $0.hasPrefix("Say") }) else {
            body.emit("chat_not_open", ["command": text])
            return false
        }
        let source = CGEventSource(stateID: .privateState)
        for unit in text.utf16 {
            for down in [true, false] {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: 0x31, keyDown: down) else { continue }
                var c = unit
                event.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
                event.postToPid(body.session.app.processIdentifier)
                await sleep(0.015)
            }
        }
        await sleep(0.2)
        await tapEnter()
        body.emit("chat_command", ["command": text])
        return true
    }

    func has(_ lines: [TipLine], _ text: String) -> TipLine? { lines.first { $0.text.contains(text) } }

    /// M4d: the quest log and the world map's pins, read-only. L opens the map; the pointer rests on each
    /// pin and its tooltip names the quest; a pin can hide under the player's arrow, so that spot too.
    /// `missing`: names the minimap's tooltips showed that the log read lacks; the plan must not be trusted.
    func readQuests() async -> (quests: [PlannedQuest], player: MapPoint?, missing: [String]) {
        let player = (await frame()).flatMap { parseCoords(coordsText($0)) }
        hover(1280, 60)  // off every pin: a tooltip left showing reads as yellow pins
        await sleep(0.4)
        let scanned = await frame()
        if let scanned { write(scanned, to: body.directory.appendingPathComponent("minimap-scan.png"), type: .png) }
        let nearby = player == nil ? [] : scanned.map { minimapPins(rgba($0)) } ?? []
        body.emit("minimap_scan", ["player": player != nil, "icons": nearby.count])
        var minimapNames: [(names: [String], at: MapPoint)] = []
        var tooltips: [String] = []
        for spot in nearby {
            hover(spot.x, spot.y)
            await sleep(0.7)
            let box = CGRect(x: 1850, y: max(0, spot.y - 120), width: 710, height: 160)  // the tip runs over the minimap
            let read = lines(box, await frame()).map(\.text)
            body.emit("minimap_pin", ["at": [Int(spot.x), Int(spot.y)], "read": read])
            minimapNames.append((read.map(nameKey), minimapPoint(spot.x, spot.y, player: player!)))
            tooltips += read
        }
        await tap(QuestHUD.mapKey)
        await sleep(1.2)
        let listed = await frame()
        if let listed { write(listed, to: body.directory.appendingPathComponent("quest-log.png"), type: .png) }  // what the plan rests on
        var quests = parseQuestLog(lines(QuestHUD.questList, listed))
        for i in quests.indices {
            quests[i].pin = minimapNames.first { $0.names.contains(nameKey(quests[i].title)) }?.at
        }
        hover(1280, 60)
        await sleep(0.4)
        var spots = (await frame()).map { mapPins(rgba($0)) } ?? []
        body.emit("map_scan", ["pins": spots.count])
        if let player { spots.append(mapPixel(player)) }
        for spot in spots {
            hover(spot.x, spot.y)
            await sleep(0.7)
            let x0 = max(0, spot.x - 40), box = CGRect(x: x0, y: max(0, spot.y - 140), width: QuestHUD.mapRight - x0, height: 180)
            let read = lines(box, await frame()).map { nameKey($0.text) }
            for i in quests.indices where quests[i].pin == nil && read.contains(nameKey(quests[i].title)) {
                quests[i].pin = zonePoint(spot.x, spot.y)
            }
        }
        await tap(QuestHUD.mapKey)
        let missing = missingFromLog(tooltips, quests)
        body.emit("quest_log", ["player": orNull(player.map { [$0.x, $0.y] }), "missing": missing, "quests": quests.map {
            ["title": $0.title, "level": $0.level, "objective": $0.objective, "kind": questKind($0).rawValue,
             "pin": orNull($0.pin.map { [($0.x * 10).rounded() / 10, ($0.y * 10).rounded() / 10] })] }])
        return (quests, player, missing)
    }

    func turnIn(_ quest: String) async -> String {
        func ours(_ lines: [TipLine]) -> TipLine? { lines.first { nameKey($0.text) == nameKey(quest) } }
        /// A delivery shows its progress page first ("Continue", live 24 Sept for Call of Earth).
        func pastContinue(_ dialog: [TipLine]) async -> [TipLine] {
            guard has(dialog, "Complete Quest") == nil, ours(dialog) != nil, let next = has(dialog, "Continue") else { return dialog }
            body.emit("continue", ["quest": quest])
            guard click(next.x + 30, next.y + 7) else { return dialog }
            await sleep(1.5)
            return lines(QuestHUD.dialog, await frame())
        }
        var dialog = await pastContinue(lines(QuestHUD.dialog, await frame()))
        if has(dialog, "Complete Quest") == nil || ours(dialog) == nil {
            guard let image = await frame() else { return "NO_FRESH_FRAME" }
            // A hub's NPCs stand close together (24 Sept: three "?" in Thendal Village): try the nearest
            // three; a dialogue for someone else's quest is closed with Esc (only when one is open: Esc
            // with nothing open is the Game Menu).
            var marks = questMarks(rgba(image), box: QuestHUD.world)
            body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
            guard !marks.isEmpty else {
                write(image, to: body.directory.appendingPathComponent("no-marks.png"), type: .png)  // for calibration
                return "NO_QUEST_MARK_IN_VIEW"
            }
            var opened = false
            for _ in 0..<3 {
                guard let mark = marks.first else { break }
                guard click(mark.x, mark.body, right: true) else { return "CLICK_FAILED" }
                await sleep(2.5)
                dialog = lines(QuestHUD.dialog, await frame())
                if has(dialog, "Complete Quest") == nil, let entry = ours(dialog) {  // an NPC with several quests lists them
                    guard click(entry.x + 40, entry.y + 7) else { return "CLICK_FAILED" }
                    await sleep(1.5)
                    dialog = lines(QuestHUD.dialog, await frame())
                }
                dialog = await pastContinue(dialog)
                if has(dialog, "Complete Quest") != nil, ours(dialog) != nil { opened = true; break }
                if has(dialog, "Continue") != nil, ours(dialog) != nil { return "CONTINUE_DID_NOT_ADVANCE" }
                body.emit("other_dialogue", ["mark": [Int(mark.x), Int(mark.y)], "lines": dialog.prefix(4).map(\.text)])
                if !dialog.isEmpty {  // someone else's quest: close it and try the next mark
                    await tap(QuestHUD.escape)
                    await sleep(0.8)
                    marks.removeFirst()
                } else if let again = await frame() {  // nothing opened: Click-to-Move walked towards it; look again
                    marks = questMarks(rgba(again), box: QuestHUD.world)
                    body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
                }
            }
            guard opened else { return "DIALOGUE_NOT_OPEN" }
        }
        guard dialog.contains(where: { nameKey($0.text) == nameKey(quest) }) else { return "OTHER_QUEST_IN_DIALOGUE" }

        var equip: (name: String, slot: String)? = nil
        if let choose = has(dialog, "Choose your reward") {
            var rewards: [(x: Double, y: Double, reward: Reward)] = []
            for i in 0..<6 {
                let x = QuestHUD.rewardX[i % 2], y = choose.y + QuestHUD.firstRow + QuestHUD.rowGap * Double(i / 2)
                hover(x, y)
                await sleep(0.8)
                guard let reward = parseReward(lines(QuestHUD.tooltip, await frame())), !rewards.contains(where: { $0.reward.name == reward.name })
                else { break }
                rewards.append((x, y, reward))
            }
            body.emit("rewards", ["rewards": rewards.map { ["name": $0.reward.name, "slot": orNull($0.reward.slot), "usable": $0.reward.usable,
                                                            "change": $0.reward.change, "sell_copper": $0.reward.sell] }])
            guard let pick = chooseReward(rewards.map(\.reward)) else { return "REWARDS_UNREADABLE" }
            let chosen = rewards[pick.index]
            body.emit("reward_choice", ["controller": "RULE", "name": chosen.reward.name, "equip": pick.equip,
                                        "rule": "owner, 24 Sept: an upgrade is taken and equipped, otherwise the highest sell price"])
            guard click(chosen.x, chosen.y) else { return "CLICK_FAILED" }
            await sleep(0.6)
            if pick.equip, let slot = chosen.reward.slot { equip = (chosen.reward.name, slot) }
        }
        guard let button = has(dialog, "Complete Quest") else { return "COMPLETE_BUTTON_MISSING" }
        let before = Set((await frame()).map(chatLines) ?? [])
        guard click(button.x + QuestHUD.buttonCentre, button.y + 7) else { return "CLICK_FAILED" }
        await sleep(2.0)
        let fresh = ((await frame()).map(chatLines) ?? []).filter { !before.contains($0) }
        body.emit("after_complete", ["chat": fresh])
        let after = lines(QuestHUD.dialog, await frame())
        guard has(after, "Complete Quest") == nil else { return "STILL_OPEN_AFTER_COMPLETE" }
        // The owner: always accept quests. A follow-up offered on completion shows an "Accept" button.
        if let accept = acceptButton(after) {
            body.emit("accept", ["controller": "RULE", "rule": "owner: always accept quests", "dialog": after.prefix(3).map(\.text)])
            let before = Set((await frame()).map(chatLines) ?? [])
            if click(accept.x + 30, accept.y + 7) {
                await sleep(1.5)
                body.emit("accepted", ["chat": ((await frame()).map(chatLines) ?? []).filter { !before.contains($0) }])
            }
        }
        guard let equip else { return "COMPLETED" }

        guard await command("/equip " + equip.name.replacingOccurrences(of: "\u{2019}", with: "'")) else { return "COMPLETED_EQUIP_NOT_TYPED" }
        await sleep(1.0)
        switch await wearing(equip.name, slot: equip.slot) {
        case true?: return "COMPLETED_AND_EQUIPPED"
        case false?: return "COMPLETED_EQUIP_UNCONFIRMED"
        case nil: return "COMPLETED_EQUIP_SLOT_UNKNOWN"
        }
    }
}

/// The live side of `runQuests`: the log read of M4d, an M4a walk to the pin (Jev's moves) and M4c's
/// hand-in (RULE). Each walk gets its own keys: runNav's exit sweep ends a key set for good (live,
/// 24 Sept: the second walk of a run pressed nothing for ten decisions).
final class LiveQuestHost: QuestHost {
    let quester: QuestRun
    let key: String
    let walk: () -> LiveNavBody
    var walker: LiveNavBody?
    init(quester: QuestRun, key: String, walk: @escaping () -> LiveNavBody) { self.quester = quester; self.key = key; self.walk = walk }

    func readQuests() async -> QuestRead? {
        let (quests, player, missing) = await quester.readQuests()
        return player.map { QuestRead(quests: quests, player: $0, missing: missing) }
    }

    func handIn(_ quest: PlannedQuest) async -> String {
        // Walk even a short way: walking faces the NPC, so its "?" is in view (live, 24 Sept: 1.0 away and
        // behind the camera, no mark was found).
        if let pin = quest.pin, let at = quester.body.look(), distance((at.x, at.y), pin) > 0.5 {
            guard distance((at.x, at.y), pin) <= QuestLimits.maxLeg else { return "TOO_FAR_NEEDS_ROADS" }
            // A key set whose release is unconfirmed is never dropped (its watchdog would stop retrying),
            // and a walk that ends so ends the run: WALK_ outcomes stop runQuests.
            if walker?.holding == true { return "WALK_KEYS_HELD" }
            let legs = walk()
            walker = legs
            let walked = await runNav(body: legs, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout),
                                      destination: NavDestination(label: String(quest.title.prefix(60)), x: pin.x, y: pin.y, arrive: 0.5))
            guard !legs.holding else { return "WALK_KEYS_HELD" }
            guard walked.outcome == "ARRIVED" else { return "WALK_" + walked.outcome }
        }
        let outcome = await quester.turnIn(quest.title)
        emit("quest_done", ["quest": quest.title, "outcome": outcome])
        return outcome
    }

    func now() -> Double { hostNow() }
    func ownerTookFocus() -> Bool { quester.body.ownerTookFocus() }
    func emit(_ event: String, _ fields: [String: Any]) { quester.body.emit(event, fields) }
}

/// `--quests --graph PATH --keys wqe`: Jev chooses each quest step through the quest graph; local code
/// offers only hand-ins within one walk and stops on the run envelope's limits (M4f).
@MainActor
func questsExecute(graph: GraphSession) async throws -> Int32 {
    let key = try apiKey()
    let session = try await wowSession(input: true, full: true)
    guard session.config.width == HUD.width, session.config.height == HUD.height else {
        throw ProbeError("capture is \(session.config.width)x\(session.config.height); M4 is calibrated for \(HUD.width)x\(HUD.height)")
    }
    let run = try runDirectory("m4_quests")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    _ = await Task.detached { first.image.cropping(to: QuestHUD.questList).map(ocr) }.value
    guard await warmJev(key) != nil else {
        try? await stream.stopCapture()
        throw ProbeError("Jev did not answer a warm-up question within 30 s")
    }
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    let host = LiveQuestHost(quester: try QuestRun(body: body), key: key) {
        LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    }
    defer { body.releaseAll(); host.walker?.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll(); host.walker?.releaseAll() },
                              holding: { body.holding || (host.walker?.holding ?? false) })
    await zoomOut(body.keys, log)
    body.emit("start", ["run_id": run.id, "mode": "quests", "decision_graph": graph.graph.id])
    let result = await runQuests(host: host, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: 0), graph: graph)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    body.emit("summary", ["outcome": result.outcome, "steps": result.steps.map { ["quest": $0.quest, "outcome": $0.outcome] },
                          "graph_requests": result.graphRecords.count, "run_directory": run.url.path])
    for s in result.steps { print("\(s.quest): \(s.outcome)") }
    print("run: \(result.outcome)")
    return body.holding || (host.walker?.holding ?? false) ? 3 : 0
}

/// `--plan --keys wqe`: read the log and the pins, and print the owner's zone-first order. Read-only.
@MainActor
func planExecute() async throws -> Int32 {
    let session = try await wowSession(input: true, full: true)
    let run = try runDirectory("m4_plan")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    _ = await Task.detached { first.image.cropping(to: QuestHUD.questList).map(ocr) }.value
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    let (quests, player, missing) = await (try QuestRun(body: body)).readQuests()
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    guard let player else { throw ProbeError("the minimap's coordinates were unreadable") }
    let plan = questPlan(quests, from: player)
    body.emit("plan", ["controller": "RULE", "rule": "owner, 24 Sept: finish the player's zone first, nearest first; then the next zone",
                       "order": plan.map { "\($0.title) [\(questKind($0).rawValue)]" }, "this_zone": thisZone(plan, from: player).map(\.title)])
    if !missing.isEmpty { print("LOG_INCOMPLETE: the minimap shows \(missing.joined(separator: ", ")); see quest-log.png") }
    for (i, q) in plan.enumerated() {
        print("\(i + 1). [\(q.level)] \(q.title): \(questKind(q).rawValue) at \(q.pin.map { "\($0.x), \($0.y)" } ?? "no pin")")
    }
    return body.holding ? 3 : 0
}

@MainActor
func questExecute(_ command: NavCommand) async throws -> Int32 {
    guard let quest = command.quest else { throw ProbeError("--quest missing") }
    let session = try await wowSession(input: true, full: true)
    guard session.config.width == HUD.width, session.config.height == HUD.height else {
        throw ProbeError("capture is \(session.config.width)x\(session.config.height); M4 is calibrated for \(HUD.width)x\(HUD.height)")
    }
    let run = try runDirectory("m4_quest")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    guard let first = await firstFrame(feed), first.image.width == HUD.width else {
        try? await stream.stopCapture()
        throw ProbeError("no \(HUD.width)-wide frame within \(Limits.firstFrameWait) s")
    }
    _ = await Task.detached { first.image.cropping(to: QuestHUD.dialog).map(ocr) }.value  // Vision's first OCR takes ~30 s
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    await zoomOut(body.keys, log)
    body.emit("start", ["run_id": run.id, "mode": "turn-in", "quest": quest])
    let outcome = await (try QuestRun(body: body)).turnIn(quest)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    let manifest: [String: Any] = [
        "schema": "m4-quest-run/v1", "run_id": run.id, "mode": "turn-in", "quest": quest, "outcome": outcome,
        "started_utc": ISO8601DateFormatter().string(from: Date()), "machine": machineFacts(),
        "source": ["git_head": orNull(git("rev-parse", "HEAD")), "git_dirty": orNull(git("status", "--porcelain").map { !$0.isEmpty })],
        "controller": "RULE: no Jev call", "holding": body.holding,
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        .write(to: run.url.appendingPathComponent("manifest.json"))
    body.emit("summary", ["outcome": outcome, "run_directory": run.url.path])
    return body.holding ? 3 : (outcome.hasPrefix("COMPLETED") ? 0 : 2)
}
