// M4c native shell for issue #5: `--turn-in --keys wqe --quest NAME`, run at the quest's NPC. Scripts
// find the "?", right-click the NPC, read each reward's tooltip, apply the owner's reward rule, click the
// reward and Complete Quest, then equip an upgrade with /equip. No Jev call: every step is a RULE.
// Layout measured on 24 Sept PNG captures at 2560x1320, zoomed fully out.
import AppKit
import Vision

enum QuestHUD {
    static let dialog = CGRect(x: 0, y: 140, width: 400, height: 580)  // the quest dialogue, left edge
    // The unit under the pointer: the game's tooltip, bottom right, growing upwards (25 Sept: a player's four
    // lines at x 2278-2545, y 1150-1248).
    static let unitTip = CGRect(x: 2200, y: 1000, width: 360, height: 260)
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
    static let zone = CGRect(x: 2290, y: 24, width: 230, height: 30)  // the zone's name above the minimap, beside the clock
    static let logMemory = URL(fileURLWithPath: "runs/002_wow_visual/memory/quest-log.json")  // private, under runs/
}

final class QuestRun {
    let body: LiveNavBody
    let routed: RoutedClickTarget
    let bounds: CGRect
    private var clicks = 0  // click1.jpg, click2.jpg: the frame each NPC click was chosen on

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

    /// A frame captured after `t`, waiting up to 2.5 s: a read right after a pointer move must not see the
    /// frame from before it.
    func frame(after t: Double) async -> CGImage? {
        let start = hostNow()
        while hostNow() - start < 2.5 {
            if let latest = body.feed.latestFrame, latest.pts > t { return latest.image }
            await sleep(0.05)
        }
        body.emit("frame_wait", ["seconds": hostNow() - start, "fresh": false, "after": t])
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
    /// `missing`: names the minimap's "?" tooltips showed that the log read lacks; the plan must not be trusted.
    /// `givers`: the minimap's "!", quests to take, which the log cannot hold yet.
    func readQuests() async -> (quests: [PlannedQuest], player: MapPoint?, missing: [String], givers: [Giver]) {
        let player = (await frame()).flatMap { readCoords($0).at }
        hover(1280, 60)  // off every pin: a tooltip left showing reads as yellow pins
        await sleep(0.4)
        let scanned = await frame()
        if let scanned { write(scanned, to: body.directory.appendingPathComponent("minimap-scan.png"), type: .png) }
        let nearby = player == nil ? [] : scanned.map { minimapPins(rgba($0)) } ?? []
        body.emit("minimap_scan", ["player": player != nil, "icons": nearby.count])
        var icons: [(at: MapPoint, offer: Bool, read: [String])] = []
        for spot in nearby {
            hover(spot.x, spot.y)
            await sleep(0.7)
            let box = CGRect(x: 1850, y: max(0, spot.y - 120), width: 710, height: 160)  // the tip runs over the minimap
            let read = lines(box, await frame()).map(\.text)
            body.emit("minimap_pin", ["at": [Int(spot.x), Int(spot.y)], "read": read, "offer": spot.offer])
            icons.append((minimapPoint(spot.x, spot.y, player: player!), spot.offer, read))
        }
        let (givers, minimapNames, tooltips) = sortIcons(icons)
        // Working memory: the same zone and tracker text as the last map read keep its quests and pins; the
        // minimap's givers above are read each time, as they change with where the player stands.
        // The key is read on the frame taken with the pointer parked, before any icon's tooltip could cover the
        // zone's name (review, 26 Sept), and after a x3 upscale: at 1x a count such as "0/6" read as "Oyo".
        let now = Date().timeIntervalSince1970
        let zoneText = scanned.map { upscaledText($0, QuestHUD.zone) } ?? [], trackerText = scanned.map { upscaledText($0, HuntHUD.tracker) } ?? []
        let key = logKey(zone: zoneText, tracker: trackerText)
        let remembered = (try? Data(contentsOf: QuestHUD.logMemory)).flatMap { try? JSONDecoder().decode(LogMemory.self, from: $0) }
        var quests: [PlannedQuest]
        if let kept = keptLog(remembered, key: key, at: now) {
            quests = kept
            body.emit("quest_log_memory", ["quests": kept.count, "age_s": Int(now - remembered!.readAt)])
        } else {
            await tap(QuestHUD.mapKey)
            await sleep(1.2)
            let listed = await frame()
            if let listed { write(listed, to: body.directory.appendingPathComponent("quest-log.png"), type: .png) }  // what the plan rests on
            quests = parseQuestLog(lines(QuestHUD.questList, listed))
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
            if !key.isEmpty, trackerShows(quests, trackerText) {  // a collapsed, filtered or overflowing tracker is no key
                try? FileManager.default.createDirectory(at: QuestHUD.logMemory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(LogMemory(key: key, quests: quests.map(LogMemory.Quest.init), readAt: now)).write(to: QuestHUD.logMemory)
            }
        }
        let missing = missingFromLog(tooltips, quests)
        body.emit("quest_log", ["player": orNull(player.map { [$0.x, $0.y] }), "missing": missing,
                                "givers": givers.map { ["tooltip": $0.names, "at": [$0.pin.x, $0.pin.y]] }, "quests": quests.map {
            ["title": $0.title, "level": $0.level, "objective": $0.objective, "kind": questKind($0).rawValue,
             "pin": orNull($0.pin.map { [($0.x * 10).rounded() / 10, ($0.y * 10).rounded() / 10] })] }])
        return (quests, player, missing, givers)
    }

    enum Page { case wanted([TipLine]), other([TipLine]), failed(String) }

    /// After a right-click, Click-to-Move walks to the NPC and the dialogue opens on arrival: the box is read
    /// until a panel shows or the character has stood still (live, 25 Sept: a fixed 2.5 s read Dalia's box
    /// mid-walk). nil: attacked on the way, which is a walk's combat (M4i).
    func arrive() async -> [TipLine]? {
        var track: [(t: Double, at: MapPoint?)] = []
        let start = hostNow()
        var seen: [TipLine] = []
        while hostNow() - start < QuestLimits.clickWalk {
            await sleep(QuestLimits.clickPoll)
            guard let image = await frame() else { continue }
            seen = lines(QuestHUD.dialog, image)
            if panelOpen(seen) { break }
            // The portrait ring is read even when the coordinates are not (a name can cover them).
            if observe(rgba(image), plates: false).combat { return nil }
            track.append((hostNow(), readCoords(image).at))
            if stoodStill(track, for: QuestLimits.standStill) { break }
        }
        body.emit("click_walk", ["seconds": hostNow() - start, "panel": panelOpen(seen)])
        return seen
    }

    /// As a human does before clicking: rest the pointer on the NPC and read the game's unit tooltip (bottom
    /// right) until it names the NPC whose green name is under the mark. nil: no point did, or the name was
    /// unreadable (live, 25 Sept: three clicks below Dalia's "?" found the ground beside her).
    func onUnit(_ mark: QuestMark, in image: CGImage) async -> (x: Double, y: Double)? {
        let bottom = mark.body - 2.4 * mark.h
        let box = CGRect(x: mark.nameX - 160, y: mark.nameTop - 6, width: 320, height: bottom - mark.nameTop + 12)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let name = nameLine(lines(box, image), nameX: mark.nameX, nameTop: mark.nameTop)?.text else { return nil }
        let start = hostNow()
        /// Whether the tooltip names the NPC once the pointer rests at `p`, on a frame captured after the move:
        /// a frame from before it must not answer for this point. Any line of the box may (the box can hold
        /// other text above the tooltip); only a line that is the name matches. nil: no fresh frame.
        func shows(at p: (x: Double, y: Double), again: Bool = false) async -> Bool? {
            hover(p.x, p.y)
            let moved = hostNow()
            await sleep(0.4)
            guard let seen = await frame(after: moved + 0.3) else { return nil }
            let read = lines(QuestHUD.unitTip, seen).map(\.text)
            body.emit("hover", ["at": [Int(p.x), Int(p.y)], "tooltip": Array(read.prefix(3)), "name": name, "again": again])
            return read.contains { sameUnit($0, name) }
        }
        /// Off every unit until the tooltip has gone: two fresh reads in a row without the name, at most ten
        /// (live run 5: Dalia's tooltip faded for about 2 s, four reads, after the pointer left her).
        func cleared() async -> Bool {
            var reads: [Bool?] = []
            for _ in 0..<10 {
                reads.append(await shows(at: (1280, 60)))
                if tooltipGone(reads) { return true }
            }
            return false
        }
        guard await cleared() else { return nil }
        for point in hoverPoints(mark) where hostNow() - start < QuestLimits.hoverSeconds {
            guard await shows(at: point) == true else { continue }
            // Confirmed only if it goes when the pointer leaves and comes back when it returns: this point's own,
            // not one still fading from the point before.
            guard await cleared() else { return nil }
            if await shows(at: point, again: true) == true { return point }
        }
        return nil
    }

    /// Right-click the NPCs under the quest marks in view, nearest the centre first, at most three, until
    /// `page` takes the dialogue that opens (it may click on through an NPC's quest list). A hub's NPCs stand
    /// close together (24 Sept: three "?" in Thendal Village). Someone else's dialogue is closed with Esc,
    /// only when a panel is open: Esc with nothing open is the Game Menu.
    func openAtMark(_ page: ([TipLine]) async -> Page) async -> (dialog: [TipLine]?, failure: String?) {
        guard var image = await frame() else { return (nil, "NO_FRESH_FRAME") }
        var marks = questMarks(rgba(image), box: QuestHUD.world)
        body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
        guard !marks.isEmpty else {
            write(image, to: body.directory.appendingPathComponent("no-marks.png"), type: .png)  // for calibration
            return (nil, "NO_QUEST_MARK_IN_VIEW")
        }
        var blind: (x: Double, y: Double)? = nil  // the last click the tooltip did not confirm
        for _ in 0..<3 {
            guard let mark = marks.first else { break }
            clicks += 1
            write(image, to: body.directory.appendingPathComponent(String(format: "click%d.jpg", clicks)), type: .jpeg)  // what it was chosen on
            // Where the last unconfirmed click went, the hover already failed: no second sweep, no second click.
            if repeatsClick((mark.x, mark.body), blind, h: mark.h) { marks.removeFirst(); continue }
            let confirmed = await onUnit(mark, in: image)
            body.emit("unit", ["mark": [Int(mark.x), Int(mark.y)], "at": confirmed.map { [Int($0.x), Int($0.y)] } as Any? ?? NSNull()])
            let point = confirmed ?? (mark.x, mark.body)
            if confirmed == nil { blind = point }
            guard click(point.x, point.y, right: true) else { return (nil, "CLICK_FAILED") }
            guard let arrived = await arrive() else { return (nil, "WALK_COMBAT") }
            let seen: [TipLine]
            switch await page(arrived) {
            case .wanted(let dialog): return (dialog, nil)
            case .failed(let code): return (nil, code)
            case .other(let dialog): seen = dialog
            }
            body.emit("other_dialogue", ["mark": [Int(mark.x), Int(mark.y)], "lines": seen.prefix(4).map(\.text), "panel": panelOpen(seen)])
            if panelOpen(seen) {  // someone else's: close it and try the next mark
                await tap(QuestHUD.escape)
                await sleep(0.8)
                marks.removeFirst()
            } else if let again = await frame() {  // nothing opened: Click-to-Move walked towards it; look again
                image = again
                marks = questMarks(rgba(again), box: QuestHUD.world)
                body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
            }
        }
        return (nil, "DIALOGUE_NOT_OPEN")
    }

    /// Take the quest a giver offers: its dialogue's "Accept" button (the owner: always accept quests).
    /// A giver with several quests lists them; an entry is clicked only when the minimap's tooltip named it.
    /// The chat's "accepted" line confirms it; the next log read is the proof.
    func accept(_ giver: Giver) async -> String {
        func listed(_ dialog: [TipLine]) -> TipLine? { dialog.first { l in giver.names.contains { nameKey($0) == nameKey(l.text) } } }
        var dialog = lines(QuestHUD.dialog, await frame())
        if acceptButton(dialog) != nil && listed(dialog) == nil {  // an offer already open, not known to be this giver's
            await tap(QuestHUD.escape)
            await sleep(0.8)
            dialog = []
        }
        if acceptButton(dialog) == nil {
            let opened = await openAtMark { page in
                var page = page
                if acceptButton(page) == nil, let entry = listed(page) {
                    guard self.click(entry.x + 40, entry.y + 7) else { return .failed("CLICK_FAILED") }
                    await self.sleep(1.5)
                    page = self.lines(QuestHUD.dialog, await self.frame())
                }
                return acceptButton(page) == nil ? .other(page) : .wanted(page)
            }
            guard let open = opened.dialog else { return opened.failure! }
            dialog = open
        }
        guard let button = acceptButton(dialog) else { return "NO_ACCEPT_BUTTON" }
        body.emit("accept", ["controller": "RULE", "rule": "owner: always accept quests", "dialog": dialog.prefix(3).map(\.text)])
        let before = Set((await frame()).map(chatLines) ?? [])
        guard click(button.x + 30, button.y + 7) else { return "CLICK_FAILED" }
        await sleep(1.5)
        let chat = ((await frame()).map(chatLines) ?? []).filter { !before.contains($0) }
        body.emit("accepted", ["chat": chat])
        guard acceptButton(lines(QuestHUD.dialog, await frame())) == nil else { return "STILL_OPEN_AFTER_ACCEPT" }
        return chat.contains { $0.lowercased().contains("accepted") } ? "ACCEPTED" : "ACCEPTED_UNCONFIRMED"
    }

    func turnIn(_ quest: String) async -> String {
        func ours(_ lines: [TipLine]) -> TipLine? { lines.first { sameTitle($0.text, quest) } }
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
            let opened = await openAtMark { page in
                var page = page
                if self.has(page, "Complete Quest") == nil, let entry = ours(page) {  // an NPC with several quests lists them
                    guard self.click(entry.x + 40, entry.y + 7) else { return .failed("CLICK_FAILED") }
                    await self.sleep(1.5)
                    page = self.lines(QuestHUD.dialog, await self.frame())
                }
                page = await pastContinue(page)
                if self.has(page, "Complete Quest") != nil, ours(page) != nil { return .wanted(page) }
                if self.has(page, "Continue") != nil, ours(page) != nil { return .failed("CONTINUE_DID_NOT_ADVANCE") }
                return .other(page)
            }
            guard let open = opened.dialog else { return opened.failure! }
            dialog = open
        }
        guard dialog.contains(where: { sameTitle($0.text, quest) }) else { return "OTHER_QUEST_IN_DIALOGUE" }

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
    let newWalker: (URL) -> LiveNavBody  // each walk's frames in its own folder, as a fight's
    let newFighter: (URL, LiveKeys) -> LiveHost  // M3's host on a child key set, its frames in the folder
    var walker: LiveNavBody?
    var walkedFrom: MapPoint?
    private let lock = NSLock()
    private var fighting: LiveHost?  // read by the signal handler's thread
    private var fights = 0, walks = 0
    let tactics: FightTactics?  // M3b's chains for a fight back; nil: the legacy flat policy
    init(quester: QuestRun, key: String, newWalker: @escaping (URL) -> LiveNavBody, newFighter: @escaping (URL, LiveKeys) -> LiveHost,
         tactics: FightTactics? = nil) {
        self.quester = quester; self.key = key; self.newWalker = newWalker; self.newFighter = newFighter; self.tactics = tactics
    }

    var holding: Bool { (walker?.holding ?? false) || lock.withLock { fighting?.holdingKeys ?? false } }

    /// The exit sweep over the walk's and the fight's key sets.
    func releaseAll() {
        walker?.releaseAll()
        lock.withLock { fighting }?.releaseAll()
    }

    /// Attacked on a walk: one M3 episode, in combat, on a child of the run's own key set, as the hunt's
    /// fights. Not the walk's: runNav's exit sweep has retired it, and no child can be taken from it (the
    /// 25 Sept review; M4i had not run live). The run's set only taps, and stays active until the run ends.
    /// A fight that ends with keys held stays tracked for the exit sweep, and its handoff fails the run.
    func fightBack() async -> String {
        guard walker?.holding != true else { return "WALK_KEYS_HELD" }
        let parent = quester.body
        fights += 1
        let folder = quester.body.directory.appendingPathComponent(String(format: "fight%d", fights))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let child = parent.keys.takeChild(releaseCodes: FightLimits.releaseCodes) else { return "INPUT_HANDOFF_FAILED" }
        let host = newFighter(folder, child)
        lock.withLock { fighting = host }
        emit("fight_start", ["fight": fights, "in_combat": true, "controller": "SAFETY"])
        let result = await runFight(host: host, jev: LiveJev(key: key, timeout: FightLimits.jevTimeout), startHealth: 0, tactics: tactics)
        emit("fight_end", ["fight": fights, "outcome": result.outcome, "decisions": result.decisions])
        guard parent.keys.resume(after: child) else { return "INPUT_HANDOFF_FAILED" }
        lock.withLock { fighting = nil }
        return result.outcome
    }

    func readQuests() async -> QuestRead? {
        let (quests, player, missing, givers) = await quester.readQuests()
        return player.map { QuestRead(quests: quests, player: $0, missing: missing, givers: givers) }
    }

    /// Walk even a short way: walking faces the NPC, so its mark is in view (live, 24 Sept: 1.0 away and
    /// behind the camera, no mark was found). nil when there, else the outcome that ends the step.
    func walk(to pin: MapPoint, label: String, retreating: Bool = false) async -> String? {
        guard let at = quester.body.look() else { return "WALK_HUD_UNREADABLE" }  // never "arrived" unseen
        guard distance((at.x, at.y), pin) > 0.5 else { return nil }
        guard distance((at.x, at.y), pin) <= QuestLimits.maxLeg else { return "TOO_FAR_NEEDS_ROADS" }
        if !retreating { walkedFrom = (at.x, at.y) }  // the way back from danger: this walk came through it
        // A key set whose release is unconfirmed is never dropped (its watchdog would stop retrying),
        // and a walk that ends so ends the run: WALK_ outcomes stop runQuests.
        if walker?.holding == true { return "WALK_KEYS_HELD" }
        walks += 1
        let folder = quester.body.directory.appendingPathComponent(String(format: "walk%d", walks))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legs = newWalker(folder)
        walker = legs
        let walked = await runNav(body: legs, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout),
                                  destination: NavDestination(label: String(label.prefix(60)), x: pin.x, y: pin.y, arrive: 0.5))
        guard !legs.holding else { return "WALK_KEYS_HELD" }
        return walked.outcome == "ARRIVED" ? nil : "WALK_" + walked.outcome
    }

    /// A hand-in or a quest taken changes the log: its memory goes, though the tracker would show it too.
    func forgetLog(_ outcome: String) {
        if outcome.hasPrefix("COMPLETED") || outcome.hasPrefix("ACCEPTED") { try? FileManager.default.removeItem(at: QuestHUD.logMemory) }
    }

    func handIn(_ quest: PlannedQuest) async -> String {
        if let pin = quest.pin, let stop = await walk(to: pin, label: quest.title) { return stop }
        let outcome = await quester.turnIn(quest.title)
        emit("quest_done", ["quest": quest.title, "outcome": outcome])
        forgetLog(outcome)
        return outcome
    }

    /// Back to where the last walk began, which that walk had just passed: the owner, survive first.
    func retreat() async -> String {
        guard let back = walkedFrom else { return "NO_WAY_BACK" }
        emit("retreat", ["to": [back.x, back.y]])
        return await walk(to: back, label: "retreat", retreating: true) ?? "RETREATED"
    }

    func accept(_ giver: Giver) async -> String {
        if let stop = await walk(to: giver.pin, label: "quest giver") { return stop }
        let outcome = await quester.accept(giver)
        emit("quest_taken", ["tooltip": giver.names, "outcome": outcome])
        forgetLog(outcome)
        return outcome
    }

    func now() -> Double { hostNow() }
    func ownerTookFocus() -> Bool { quester.body.ownerTookFocus() }
    func emit(_ event: String, _ fields: [String: Any]) { quester.body.emit(event, fields) }
}

/// `--quests --graph PATH --keys wqe`: Jev chooses each quest step through the quest graph; local code
/// offers only hand-ins within one walk and stops on the run envelope's limits (M4f).
@MainActor
func questsExecute(graph: GraphSession, fightGraph: String? = nil) async throws -> Int32 {
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
    // A fight back presses the bar's keys, so they come from its tooltips, as a hunt's: the defaults were
    // the 23 Sept bar, where key 3 was the heal (Earth Shock by 24 Sept) and key 4 the buff (Healing Wave).
    let bar = try await readSkillBar(session, feed, log, required: fightRoles)
    applyRoles(bar.keys)
    let tactics = try fightTactics(fightGraph, bar, log)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    let host = LiveQuestHost(quester: try QuestRun(body: body), key: key,
                             newWalker: { LiveNavBody(session: session, feed: feed, sink: sink, directory: $0, log: log) },
                             newFighter: { LiveHost(session: session, feed: feed, sink: sink, directory: $0, log: log, input: $1) },
                             tactics: tactics)
    defer { body.releaseAll(); host.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll(); host.releaseAll() },
                              holding: { body.holding || host.holding })
    body.emit("start", ["run_id": run.id, "mode": "quests", "decision_graph": graph.graph.id])
    let result = await runQuests(host: host, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: 0), graph: graph)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    body.emit("summary", ["outcome": result.outcome, "steps": result.steps.map { ["quest": $0.quest, "outcome": $0.outcome] },
                          "graph_requests": result.graphRecords.count, "run_directory": run.url.path])
    for s in result.steps { print("\(s.quest): \(s.outcome)") }
    print("run: \(result.outcome)")
    return body.holding || host.holding ? 3 : 0
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
    let (quests, player, missing, givers) = await (try QuestRun(body: body)).readQuests()
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
    for g in givers { print("! \(g.names.isEmpty ? "(tooltip unread)" : g.names.joined(separator: ", ")) at \(g.key)") }
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
