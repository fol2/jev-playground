// M4c native shell for issue #5: `--turn-in --keys wqe --quest NAME`, run at the quest's NPC. Scripts
// find the "?", right-click the NPC, read each reward's tooltip, apply the owner's reward rule, click the
// reward and Complete Quest; an upgrade is then put on from the bags (wearUpgrades, M4x). No Jev call: every step is a RULE.
// Layout measured on 24 Sept PNG captures at 2560x1320, zoomed fully out.
import AppKit
import Vision

enum QuestHUD {
    static let dialog = CGRect(x: 0, y: 140, width: 400, height: 580)  // the quest dialogue, left edge
    // A popup at top centre (27 Sept: "Release Spirit" at x 1153-1265, y 216-227; the Spirit Healer's Accept at y 242-257).
    static let popup = CGRect(x: 900, y: 120, width: 760, height: 260)
    static let healer = CGRect(x: 512, y: 60, width: 1536, height: 640)  // the view's upper middle: a Spirit Healer's name over it
    // The unit under the pointer: the game's tooltip, bottom right, growing upwards (25 Sept: a player's four
    // lines at x 2278-2545, y 1150-1248).
    static let unitTip = unitTooltipBox
    static let tooltip = CGRect(x: 150, y: 100, width: 850, height: 560)  // a reward's tooltip and the equipped one
    static let world = (300, 100, 2100, 950)  // where quest marks are looked for
    static let rewardX = [130.0, 274.0], firstRow = 37.0, rowGap = 44.0  // reward names below "Choose your reward:"
    static let buttonCentre = 56.0  // "Complete Quest": from the text's left edge to the button's centre
    static let enter: UInt16 = 36
    static let escape: UInt16 = 53
    static let targetSelf: UInt16 = 122  // F1, the default Target Self (M4w: a heal goes to the selected unit)
    static let bags: UInt16 = 11  // B, the backpack (the default binding; M4m)
    /// The character select screen's "Enter World" button (27 Sept), below the selected character's name, which is left out.
    static let enterWorld = CGRect(x: 1100, y: 1205, width: 360, height: 60)
    /// The Combined Backpack (27 Sept): its title is read in this box; the first slot's centre lies (-142, +94) from the
    /// title's left top, 10 slots a row, 45 px apart each way. An item's tooltip is drawn just above its slot.
    static let bagTitle = CGRect(x: 1900, y: 900, width: 660, height: 260)
    static let bagSlot = (dx: -142.0, dy: 94.0, pitch: 45.0, columns: 10, count: 20)
    // Down to the action bar: the stat changes under a bottom row's equipped item stood at y 1181 (live, 27 Sept).
    static let bagTooltip = CGRect(x: 1200, y: 600, width: 1360, height: 700)
    /// A quest's tracking checkbox in the Map & Quest Log's list: x 1082, 7 px below its title line's top (27 Sept: title tops
    /// 252, 296, 336, 422; boxes centred 261, 301, 342, 429).
    static let trackX = 1082.0, trackDy = 7.0
    static let questCount = CGRect(x: 990, y: 178, width: 135, height: 30)  // "Quests: 3/40" above the list (27 Sept)
    static let mapKey: UInt16 = 37  // L, the Map & Quest Log
    static let mapTitle = CGRect(x: 450, y: 150, width: 300, height: 34)  // "Map & Quest Log" in its title bar (26 Sept)
    static let mapCursor = CGRect(x: 80, y: 688, width: 300, height: 24)  // "Cursor: 42.3, 22.9" at the map's bottom left
    static let questList = CGRect(x: 775, y: 225, width: 345, height: 560)
    static let mapRight = 770.0  // pin tooltips are read left of this: the quest list repeats every title
    static let zone = CGRect(x: 2290, y: 24, width: 230, height: 30)  // the zone's name above the minimap, beside the clock
    static let logMemory = URL(fileURLWithPath: "runs/002_wow_visual/memory/quest-log.json")  // private, under runs/
    // M4u: the town stop, from the live frames of 27 Sept (direct observation). Each window part is placed from its title
    // line's left-top as OCR reads it (the merchant's and the trainer's windows open at the left, where the quest dialogue does).
    // Private: the level last trained (M4u) and the steps' records across runs (M4y).
    static let characterMemory = URL(fileURLWithPath: "runs/002_wow_visual/memory/character.json")
    // Private: where quest walks stopped against the ground (M4z), the world's and not a character's: a new character keeps it.
    static let stuckMemory = URL(fileURLWithPath: "runs/002_wow_visual/memory/stuck.json")
    // Where an NPC's name is sought, read at twice its size: the view but the tracker at the right (live run 73: Windshaper
    // Boro's name stood at x 2130-2270, outside the first box, 512-2048, and the visit ended NPC_NOT_OPENED).
    static let townView = CGRect(x: 100, y: 200, width: 2160, height: 640)
    static let portrait = (x: 764.0, y: 995.0)  // the character's own portrait: its unit tooltip names its level
    static let junkButton = (dx: 12.0, dy: 411.0)  // Sell All Junk Items, the coin bag under the merchant's grid
    static let junkTip = (dx: 20.0, dy: 355.0, width: 240.0, height: 40.0)  // its tooltip, just above it
    static let merchantMoney = (dx: 140.0, dy: 430.0, width: 120.0, height: 40.0)
    static let trainerList = (dx: -96.0, dy: 66.0, width: 316.0, height: 340.0)  // name and requirement lines; a hovered spell's tooltip starts right of it
    static let trainButton = (dx: 174.0, dy: 437.0)
}

/// A hand-in or a quest taken changes the log: its memory goes, though the tracker would show it too, in
/// `--quests` and `--turn-in` alike.
func forgetLog(_ outcome: String) {
    if outcome.hasPrefix("COMPLETED") || outcome.hasPrefix("ACCEPTED") || outcome.hasPrefix("USED") { try? FileManager.default.removeItem(at: QuestHUD.logMemory) }
}

final class QuestRun {
    let body: LiveNavBody
    let routed: RoutedClickTarget
    let bounds: CGRect
    private var clicks = 0  // click1.jpg, click2.jpg: the frame each NPC click was chosen on
    /// The learned mark reader (M5) in shadow: it reads each frame questMarks reads, on a queue of its own, and is
    /// logged, never acted on and never waited for. The run's clicks and retries keep questMarks' timing (review, #50).
    private let shadowQueue = DispatchQueue(label: "m5.shadow", qos: .utility)
    private var shadow: MarkReader?, shadowTried = false  // touched on shadowQueue only
    private let shadowLock = NSLock()
    private var shadowBusy = false  // a read still running: the next frame is skipped, never queued behind it
    /// The learned reader's own instance for click targets (not the shadow's, which its queue owns): marks the rules
    /// miss are clicked only once a hover confirms an NPC under them (live run 21: a near "?" the rules missed).
    private lazy var clickReader: MarkReader? = try? MarkReader()
    private var learnedOnly: [(x: Double, y: Double)] = []  // the click targets only the learned reader found
    private var logTitles: [String] = []  // the last log read's quests: a greeting's "?" entry for one of them is a hand-in

    /// The rules' marks, then the learned reader's that the rules did not find, as click targets.
    /// `want`: only marks of that kind ("question" to hand in, "exclamation" to take), as the learned reader names them;
    /// a mark it cannot name, or too small to name (kindMinHeight), stays. Live run 31, 27 Sept: a hand-in clicked a giver's "!".
    func clickMarks(_ image: CGImage, _ pixels: RGBA, want: String? = nil) -> [QuestMark] {
        var rules = questMarks(pixels, box: QuestHUD.world)
        var learned = (try? clickReader?.marks(image, pixels)) ?? []
        if let want, let reader = clickReader {
            let before = rules.count
            rules = rules.filter { m in
                m.h < QuestLimits.kindMinHeight || ((try? reader.glyphKind(image, box: glyphBox(m))) ?? nil).map { $0.label == want } ?? true
            }
            learned = learned.filter { Double($0.box[3]) < QuestLimits.kindMinHeight || $0.kind == want }
            if rules.count < before { body.emit("other_kind", ["want": want, "dropped": before - rules.count]) }
        }
        let extra = extraMarks(learned.map { learnedMark($0.box) }, beside: rules)
        learnedOnly = extra.map { ($0.x, $0.y) }
        if !extra.isEmpty { body.emit("learned_targets", ["count": extra.count, "marks": extra.prefix(3).map { [Int($0.x), Int($0.y), Int($0.h)] }]) }
        return rules + extra
    }

    init(body: LiveNavBody) throws {
        self.body = body
        bounds = body.session.window.frame
        routed = try routedTarget(pid: body.session.app.processIdentifier, window: body.session.window.windowID, bounds: bounds)
    }

    /// What the learned reader sees on a frame questMarks has just read: a `learned_marks` event for the audit. The
    /// models load on the first read (`learned_reader`: loaded or not, and how long); errors are logged, and change
    /// nothing. The caller returns at once.
    func shadowMarks(_ image: CGImage, _ pixels: RGBA, at place: String) {
        shadowLock.lock()
        let busy = shadowBusy
        shadowBusy = true
        shadowLock.unlock()
        if busy {
            body.emit("learned_marks", ["at": place, "skipped": "busy"])
            return
        }
        shadowQueue.async { [self] in
            defer {
                shadowLock.lock()
                shadowBusy = false
                shadowLock.unlock()
            }
            if !shadowTried {
                shadowTried = true
                let began = hostNow()
                do {
                    shadow = try MarkReader()
                    body.emit("learned_reader", ["loaded": true, "ms": Int((hostNow() - began) * 1000)])
                } catch {
                    body.emit("learned_reader", ["loaded": false, "error": "\(error)"])
                }
            }
            guard let shadow else { return }
            let began = hostNow()
            do {
                let read = try shadow.marks(image, pixels)
                body.emit("learned_marks", ["at": place, "count": read.count, "ms": Int((hostNow() - began) * 1000),
                                            "marks": read.prefix(5).map { [$0.kind, $0.box, ($0.confidence * 100).rounded() / 100] as [Any] }])
            } catch {
                body.emit("learned_marks", ["at": place, "error": "\(error)"])
            }
        }
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
        body.keys.grant(code, seconds: 1.0)  // the watchdog lifts it if this task stalls (review of #53)
        body.keys.press(code)
        await sleep(0.06)
        body.keys.lift(code)
    }

    func tapEnter() async { await tap(QuestHUD.enter) }

    /// The Combined Backpack's title, opening the backpack with B when it is not in view. `opened`: B was pressed here, so
    /// closeBags presses it again.
    func openBags() async -> (title: TipLine, opened: Bool)? {
        func title(_ image: CGImage?) -> TipLine? { lines(QuestHUD.bagTitle, image).first { nameKey($0.text).contains("backpack") } }
        if let shown = title(await frame()) { return (shown, false) }
        let pressed = hostNow()
        await tap(QuestHUD.bags)
        await sleep(0.8)
        guard let shown = title(await frame(after: pressed + 0.6)) else {
            await tap(QuestHUD.bags)  // whatever B opened, it is closed again
            return nil
        }
        return (shown, true)
    }

    /// The backpack's items (M4m): each slot, placed from the title, is hovered and its tooltip read (bagItemName), in the
    /// order the bag fills, until two empty slots in a row. Live recon, 27 Sept: seven items from the first slot on.
    /// A worn item's tooltip also gives its slot and the game's comparison with what is equipped (parseReward, M4x).
    // ponytail: every read hovers each filled slot (about 0.9 s a slot); keep the names between reads if runs grow.
    func readBags(close: Bool = true) async -> [(name: String, at: (x: Double, y: Double), reward: Reward?)]? {
        guard let bags = await openBags() else { return nil }
        let s = QuestHUD.bagSlot
        var items: [(name: String, at: (x: Double, y: Double), reward: Reward?)] = [], empty = 0
        for slot in 0..<s.count where empty < 2 {
            let at = (x: bags.title.x + s.dx + s.pitch * Double(slot % s.columns), y: bags.title.y + s.dy + s.pitch * Double(slot / s.columns))
            hover(at.x, at.y)
            let moved = hostNow()
            await sleep(0.45)
            let tip = lines(QuestHUD.bagTooltip, await frame(after: moved + 0.3))
            let name = bagItemName(tip), reward = parseReward(tip).flatMap { $0.slot == nil ? nil : $0 }
            body.emit("bag_slot", ["slot": slot, "at": [Int(at.x), Int(at.y)], "item": orNull(name), "gear": orNull(reward?.slot),
                                   "change": orNull(reward?.change), "usable": orNull(reward?.usable)])
            if let name { items.append((name, at, reward)); empty = 0 } else { empty += 1 }
        }
        hover(1280, 60)
        if close && bags.opened { await tap(QuestHUD.bags) }
        return items
    }

    /// Use a bag item, as a human does: open the bags, right-click it, and close what it opened (M4m). An item "to read"
    /// opens a text panel titled with its name at the left, which Esc closes; Esc is pressed only when that panel is read,
    /// as Esc with nothing open is the Game Menu. The next log read shows what it did. USED, or why not.
    func useItem(_ item: String) async -> String {
        guard let items = await readBags(close: false) else { return "BAGS_UNREAD" }
        func close() async { if lines(QuestHUD.bagTitle, await frame()).contains(where: { nameKey($0.text).contains("backpack") }) { await tap(QuestHUD.bags) } }
        guard let found = items.first(where: { sameTitle($0.name, item) }) else {
            await close()
            return "ITEM_NOT_FOUND"
        }
        // Click-to-Move is on: a right-click that misses the slot walks the character there. The slot is hovered again,
        // and clicked only while its tooltip still names the item (review of #54).
        hover(found.at.x, found.at.y)
        let moved = hostNow()
        await sleep(0.45)
        guard let under = bagItemName(lines(QuestHUD.bagTooltip, await frame(after: moved + 0.3))), sameTitle(under, item) else {
            await close()
            return "ITEM_NOT_UNDER_POINTER"
        }
        body.emit("use_item", ["item": found.name, "at": [Int(found.at.x), Int(found.at.y)], "controller": "RULE"])
        guard click(found.at.x, found.at.y, right: true) else {
            await close()
            return "CLICK_FAILED"
        }
        let used = hostNow()
        await sleep(1.2)
        let after = await frame(after: used + 1.0)
        if let after { write(after, to: body.directory.appendingPathComponent("use-\(clicks).png"), type: .png) }
        let panel = lines(QuestHUD.dialog, after)
        body.emit("item_panel", ["lines": panel.prefix(4).map(\.text)])
        // The use counts only with its evidence, the panel it opened (review of #54: USED was returned whatever happened).
        let opened = panel.contains(where: { nameKey($0.text).contains(nameKey(item)) })
        if opened {
            await tap(QuestHUD.escape)
            await sleep(0.6)
        }
        hover(1280, 60)
        await close()
        return opened ? "USED" : "ITEM_NO_EFFECT"
    }

    /// Put on the bags' upgrades (M4x; the owner, 27 Sept: "you can right click on the inventory to quick equip/swap gears").
    /// equipChoices picks them from readBags' tooltips; each is hovered again and right-clicked only while its tooltip still
    /// names it (Click-to-Move, as useItem), and counts as worn when its slot then shows another item (the one it replaced)
    /// or none. Never with an NPC's window open: a right-click there sells the item. The outcome, what was worn, and the
    /// bags' names when nothing was (the caller need not read them again).
    // ponytail: an item that binds when equipped asks first and stays unworn (its popup is left); answer it when one drops.
    func wearUpgrades() async -> (outcome: String, worn: [String], items: [String]?) {
        guard !npcWindowShown(lines(QuestHUD.dialog, await frame())) else { return ("NPC_WINDOW_OPEN", [], nil) }
        guard let bags = await readBags(close: false) else { return ("BAGS_UNREAD", [], nil) }
        func named(_ at: (x: Double, y: Double)) async -> String? {
            hover(1280, 60)
            await sleep(0.2)
            hover(at.x, at.y)
            let moved = hostNow()
            await sleep(0.45)
            return bagItemName(lines(QuestHUD.bagTooltip, await frame(after: moved + 0.3)))
        }
        var worn: [String] = []
        let choices = equipChoices(bags.compactMap { b in b.reward.map { (b.name, $0) } })
        for name in choices {
            guard let item = bags.first(where: { $0.name == name }) else { continue }
            let under = await named(item.at)
            guard under.map({ sameTitle($0, name) }) == true, click(item.at.x, item.at.y, right: true) else {
                body.emit("equip_item", ["item": name, "worn": false, "under_pointer": orNull(under)])
                continue
            }
            await sleep(0.8)
            let now = await named(item.at)
            let on = now.map { !sameTitle($0, name) } ?? true
            body.emit("equip_item", ["item": name, "slot": orNull(item.reward?.slot), "change": orNull(item.reward?.change),
                                     "now_in_bag_slot": orNull(now), "worn": on])
            if on { worn.append(name) }
        }
        hover(1280, 60)
        if lines(QuestHUD.bagTitle, await frame()).contains(where: { nameKey($0.text).contains("backpack") }) { await tap(QuestHUD.bags) }
        return (choices.isEmpty ? "NO_UPGRADE" : worn.count < choices.count ? "NOT_WORN" : "WORN", worn, worn.isEmpty ? bags.map(\.name) : nil)
    }


    /// At the character select screen, enter the world with the character it has selected, the one last played, as the
    /// owner authorised (26 Sept: "open, close, reopen, login, enter character"). Live, 27 Sept: after 70 min idle the game
    /// had logged out to that screen. Enter, then wait up to 90 s for the minimap's coordinates. The selected character's
    /// name is never read or logged. true: in the world (already, or now).
    func enterWorldIfAtSelect() async -> Bool {
        // Enter only where the world's minimap does not read and the button does: Enter in the world opens the chat, and W, Q
        // and E would then type (review of #54). No frame is not known to be the world.
        guard let shown = await frame() else { return false }
        if readCoords(shown, tracked: false).at != nil { return true }
        guard lines(QuestHUD.enterWorld, shown).contains(where: { nameKey($0.text) == "enterworld" }) else { return true }
        body.emit("character_select", ["action": "Enter World"])
        await tapEnter()
        let start = hostNow()
        while hostNow() - start < 90 {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if let seen = await frame(), readCoords(seen, tracked: false).at != nil {
                body.emit("entered_world", ["seconds": Int(hostNow() - start)])
                return true
            }
        }
        body.emit("entered_world", ["failed": true])
        return false
    }

    func has(_ lines: [TipLine], _ text: String) -> TipLine? { lines.first { $0.text.contains(text) } }

    /// M4d: the quest log and the world map's pins; `turnIfUnread` as `position(turn:)`, else read-only. L opens the map;
    /// the pointer rests on each pin and its tooltip names the quest; a pin can hide under the player's arrow, so that spot too.
    /// `missing`: names the minimap's "?" tooltips showed that the log read lacks; the plan must not be trusted.
    /// `givers`: the minimap's "!", quests to take, which the log cannot hold yet.
    func readQuests(turnIfUnread: Bool = false) async -> (quests: [PlannedQuest], player: MapPoint?, missing: [String], givers: [Giver]) {
        let player = await position(turn: turnIfUnread)
        return await readQuests(at: player)
    }

    /// The character's place, from the coordinates under the minimap. One frame's OCR can lose a glyph of them (live run
    /// 28: POSITION_UNREADABLE on "44.9.2314"), so up to five fresh frames are read, as a walk bears six unreadable ones.
    /// A creature's nameplate can sit over them, and a standing creature's plate does not move (live runs 46 and 47,
    /// 27 Sept: a Pesky Cirrusfly's plate ended a quest read POSITION_UNREADABLE and a walk's start WALK_HUD_UNREADABLE).
    /// So with `turn` the character then turns in place, 45° at a time, up to three times, reading after each turn, as a
    /// human turns the camera. A turn is only for live coordinates under a plate: never without a fresh frame (stale vision
    /// pauses), in combat (the fight answers it) or once the owner has taken over (review of #57). `--plan` does not turn:
    /// it moves nothing; nor does a retreat, beside a danger.
    func position(turn: Bool) async -> MapPoint? {
        var seen = await frame()
        var player = seen.flatMap { readCoords($0).at }
        for _ in 0..<4 where player == nil {
            let asked = hostNow()
            seen = await frame(after: asked + 0.2)
            player = seen.flatMap { readCoords($0).at }
        }
        if turn, player == nil, let pulse = turnPulse(45) {
            for turn in 1...3 where player == nil {
                guard let last = seen, !observe(rgba(last), plates: false).combat, !body.ownerTookFocus() else {
                    body.emit("position_turn", ["turn": turn, "skipped": seen == nil ? "no_fresh_frame" : "combat_or_owner"])
                    break
                }
                body.keys.grant(pulse.code, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)  // lifted if this stalls
                guard body.keys.press(pulse.code) else { break }
                await sleep(Double(pulse.ms) / 1000)
                body.keys.lift(pulse.code)
                for _ in 0..<3 where player == nil {
                    let asked = hostNow()
                    seen = await frame(after: asked + 0.3)
                    player = seen.flatMap { readCoords($0).at }
                }
                body.emit("position_turn", ["turn": turn, "read": player != nil])
            }
        }
        return player
    }

    func readQuests(at player: MapPoint?) async -> (quests: [PlannedQuest], player: MapPoint?, missing: [String], givers: [Giver]) {
        hover(1280, 60)  // off every pin: a tooltip left showing reads as yellow pins
        let parked = hostNow()
        await sleep(0.4)
        let scanned = await frame(after: parked + 0.3)  // never a frame from before the pointer left an icon
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
        let (found, minimapNames, tooltips) = sortIcons(icons)
        var givers = found
        // A giver a few yards away is drawn under the player's arrow (live, 26 Sept: 20 yards from Windshaper
        // Boro only its "!"'s dot showed). With no "!" on the minimap, a yellow mark in view is offered instead.
        let scannedPixels = scanned.map(rgba)
        let inView = scannedPixels.map { questMarks($0, box: QuestHUD.world).count } ?? 0
        if let scanned, let scannedPixels { shadowMarks(scanned, scannedPixels, at: "view") }
        if givers.isEmpty && inView > 0, let player { givers.append(Giver(names: [], pin: player, inView: true)) }
        body.emit("view_marks", ["count": inView])
        // Working memory: the same zone and tracker text as the last map read keep its quests and pins; the
        // minimap's givers above are read each time, as they change with where the player stands.
        // The key is read on the frame taken with the pointer parked, before any icon's tooltip could cover the
        // zone's name (review, 26 Sept), and after a x3 upscale: at 1x a count such as "0/6" read as "Oyo".
        let now = Date().timeIntervalSince1970
        let zoneText = scanned.map { upscaledText($0, QuestHUD.zone) } ?? [], trackerText = scanned.map { upscaledText($0, HuntHUD.tracker) } ?? []
        let key = logKey(zone: zoneText, tracker: trackerText)
        let remembered = (try? Data(contentsOf: QuestHUD.logMemory)).flatMap { try? JSONDecoder().decode(LogMemory.self, from: $0) }
        var quests: [PlannedQuest], uiFault: [String] = []
        if let kept = keptLog(remembered, key: key, at: now) {
            quests = kept
            for i in quests.indices where quests[i].pin == nil {  // a pin the last read missed, from this read's minimap
                quests[i].pin = minimapNames.first { $0.names.contains(nameKey(quests[i].title)) }?.at
            }
            body.emit("quest_log_memory", ["quests": kept.count, "age_s": Int(now - remembered!.readAt)])
        } else {
            if !(await setMap(open: true)) { body.emit("map_toggle_failed", ["open": true]); uiFault.append("the Map & Quest Log did not open") }
            let listed = await frame()
            if let listed { write(listed, to: body.directory.appendingPathComponent("quest-log.png"), type: .png) }  // what the plan rests on
            let listLines = lines(QuestHUD.questList, listed)
            let shown = questCount(lines(QuestHUD.questCount, listed).map(\.text))
            let log = readQuestLog(listLines, shown: shown)
            quests = log.quests
            if log.bare { body.emit("quest_titles_bare", ["read": quests.count]) }
            if let shown, shown != quests.count {
                body.emit("quest_count", ["shown": shown, "read": quests.count])
                uiFault.append("the log read \(quests.count) of its \(shown) quests")  // LOG_INCOMPLETE: no plan on a partial log
            }
            // Every quest is tracked, as a player keeps them: the hunt reads its objectives from the tracker (live run 42).
            if let listed {
                let pixels = rgba(listed)
                for line in listLines where questTitle(line.text.trimmingCharacters(in: .whitespaces), bare: log.bare) != nil {
                    let box = (x: QuestHUD.trackX, y: line.y + QuestHUD.trackDy)
                    guard !questTracked(pixels, x: box.x, y: box.y) else { continue }
                    body.emit("track_quest", ["line": line.text, "at": [Int(box.x), Int(box.y)], "controller": "RULE"])
                    _ = click(box.x, box.y)
                    await sleep(0.4)
                }
            }
            for i in quests.indices {
                quests[i].pin = minimapNames.first { $0.names.contains(nameKey(quests[i].title)) }?.at
            }
            hover(1280, 60)
            let offPins = hostNow()
            await sleep(0.4)
            var spots = (await frame(after: offPins + 0.3)).map { mapPins(rgba($0)) } ?? []  // no tooltip read as pins
            body.emit("map_scan", ["pins": spots.count])
            if let player { spots.append(mapPixel(player)) }
            for spot in spots {
                hover(spot.x, spot.y)
                await sleep(0.7)
                let x0 = max(0, spot.x - 40), box = CGRect(x: x0, y: max(0, spot.y - 140), width: QuestHUD.mapRight - x0, height: 180)
                let shown = await frame()
                let read = lines(box, shown).map { nameKey($0.text) }
                let cursorText = shown.map { upscaledText($0, QuestHUD.mapCursor) } ?? []
                let at = mapCursor(cursorText)
                body.emit("map_pin", ["at": [Int(spot.x), Int(spot.y)], "cursor": orNull(at.map { [$0.x, $0.y] }), "cursor_text": cursorText, "read": read])
                for i in quests.indices where quests[i].pin == nil && read.contains(nameKey(quests[i].title)) {
                    quests[i].pin = at  // unread, no pin: the fixed transform held on one map only (review of #47)
                }
            }
            if !(await setMap(open: false)) { body.emit("map_toggle_failed", ["open": false]); uiFault.append("the Map & Quest Log did not close") }
            if rememberLog(quests, tracker: trackerText, key: key, missing: missingFromLog(tooltips, quests) + uiFault) {
                try? FileManager.default.createDirectory(at: QuestHUD.logMemory.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? JSONEncoder().encode(LogMemory(key: key, quests: quests.map(LogMemory.Quest.init), readAt: now)).write(to: QuestHUD.logMemory)
            }
        }
        // Park the pointer: a minimap icon's tooltip left showing covers the player's arrow, and the next walk's first
        // look reads no facing (live run 16, 26 Sept: "Coming of Age" over the arrow, WALK_HUD_UNREADABLE).
        hover(1280, 60)
        let missing = missingFromLog(tooltips, quests) + uiFault  // a map not known to be open or shut stops the run: LOG_INCOMPLETE
        body.emit("quest_log", ["player": orNull(player.map { [$0.x, $0.y] }), "missing": missing,
                                "givers": givers.map { ["tooltip": $0.names, "at": [$0.pin.x, $0.pin.y]] }, "quests": quests.map {
            ["title": $0.title, "level": $0.level, "objective": $0.objective, "kind": questKind($0).rawValue,
             "pin": orNull($0.pin.map { [($0.x * 10).rounded() / 10, ($0.y * 10).rounded() / 10] })] }])
        logTitles = quests.map(\.title)
        return (quests, player, missing, givers)
    }

    /// L toggles the Map & Quest Log, so it is pressed only while the panel is known not to be as wanted (live run
    /// 12, 26 Sept: the run ended with the map open, and the next run's L would have closed it). Open is its title
    /// read; closed is two fresh frames in a row without it. No frame proves either (review of #47: an empty read
    /// had passed for closed). false: not known to be as wanted after three presses.
    func setMap(open: Bool) async -> Bool {
        func titled(_ image: CGImage) -> Bool {
            lines(QuestHUD.mapTitle, image).contains { $0.text.lowercased().filter { !$0.isWhitespace }.contains("questlog") }
        }
        for press in 0...3 {
            guard let first = await frame() else { return false }
            var shown = titled(first)
            if !shown && !open {
                guard let second = await frame(after: hostNow() + 0.2) else { return false }
                shown = titled(second)
            }
            if shown == open { return true }
            if press == 3 { break }
            await tap(QuestHUD.mapKey)
            await sleep(1.2)
        }
        return false
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
    /// right) until it names the NPC whose green name is under the mark, or shows an NPC (npcTip). nil: no point did,
    /// or the name was unreadable (live, 25 Sept: three clicks below Dalia's "?" found the ground beside her).
    /// `declined`: NPCs whose dialogue this search has opened and closed as someone else's; a mark over one is skipped
    /// (`declined` true), never clicked blind (live run 40, 27 Sept: Windshaper Boro's "?", the only mark in view, opened
    /// his panel instead of the hand-in's NPC).
    func onUnit(_ mark: QuestMark, in image: CGImage, declined: [String] = [], known: String? = nil) async -> (point: (x: Double, y: Double)?, declined: Bool) {
        let bottom = mark.body - 2.4 * mark.h
        let box = CGRect(x: mark.nameX - 160, y: mark.nameTop - 6, width: 320, height: bottom - mark.nameTop + 12)
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // An unread name leaves the NPC's own tooltip to confirm it (npcTip). A town NPC's name is known (M4u).
        let name = known ?? nameLine(lines(box, image), nameX: mark.nameX, nameTop: mark.nameTop)?.text ?? ""
        let met = { (line: String) in declined.contains { sameUnit(line, $0) } }
        if met(name) { return (nil, true) }
        var metOne = false
        let start = hostNow()
        /// Whether the tooltip names the NPC once the pointer rests at `p`, on a frame captured after the move:
        /// a frame from before it must not answer for this point. Any line of the box may (the box can hold
        /// other text above the tooltip); only a line that is the name matches. nil: no fresh frame.
        func shows(at p: (x: Double, y: Double), again: Bool = false, clearing: Bool = false) async -> Bool? {
            hover(p.x, p.y)
            let moved = hostNow()
            await sleep(0.4)
            guard let seen = await frame(after: moved + 0.3) else { return nil }
            let read = lines(QuestHUD.unitTip, seen).map(\.text)
            // A player's tooltip (the character's own included) is not logged by name (review of #77).
            let logged = read.contains { $0.lowercased().contains("(player)") } ? ["(a player)"] : Array(read.prefix(3))
            body.emit("hover", ["at": [Int(p.x), Int(p.y)], "tooltip": logged, "name": name, "again": again])
            switch unitCheck(read, name: name, declined: clearing ? [] : declined) {  // a fading tooltip is not this unit's
            case .declined: metOne = true; return false
            case .confirmed: return true
            case .other: return false
            }
        }
        /// Off every unit until the tooltip has gone: two fresh reads in a row without the name, at most ten
        /// (live run 5: Dalia's tooltip faded for about 2 s, four reads, after the pointer left her).
        func cleared() async -> Bool {
            var reads: [Bool?] = []
            for _ in 0..<10 {
                reads.append(await shows(at: (1280, 60), clearing: true))
                if tooltipGone(reads) { return true }
            }
            return false
        }
        guard await cleared() else { return (nil, metOne) }
        for point in hoverPoints(mark) where hostNow() - start < QuestLimits.hoverSeconds && !metOne {
            guard await shows(at: point) == true else { continue }
            // Confirmed only if it goes when the pointer leaves and comes back when it returns: this point's own,
            // not one still fading from the point before.
            guard await cleared() else { return (nil, metOne) }
            if await shows(at: point, again: true) == true { return (point, false) }
        }
        return (nil, metOne)
    }

    /// OCR lines of `box` read at twice their size, placed in capture pixels: an NPC's green name over its head is too small
    /// for the full-size read (live, 27 Sept: "Windshaper Boro" read only so).
    func upscaledLines(_ box: CGRect, _ image: CGImage?) -> [TipLine] {
        guard let crop = image?.cropping(to: box),
              let context = CGContext(data: nil, width: Int(box.width) * 2, height: Int(box.height) * 2, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: 0, y: 0, width: context.width, height: context.height))
        guard let scaled = context.makeImage() else { return [] }
        return ocr(scaled).map { text, b in
            TipLine(text: text, x: box.minX + b.minX * box.width, y: box.minY + (1 - b.maxY) * box.height)
        }
    }

    /// Open a town NPC's window by its name (M4u), as a human does: find the name over its head, turning in place if it is
    /// not in view; rest the pointer on its body until the game's tooltip names it (onUnit, two reads, tooltipGone); then
    /// right-click and wait for the window. The dialogue box's lines, or nil.
    func openByName(_ name: String, until deadline: Double = .infinity) async -> [TipLine]? {
        func found(_ image: CGImage?) -> TipLine? {
            let read = upscaledLines(QuestHUD.townView, image)
            let hit = read.first { townNameHit($0.text, name) }
            body.emit("town_search", ["name": name, "lines": read.count, "found": hit != nil])  // what each look read (live run 73)
            return hit
        }
        var image = await frame()
        var line = found(image)
        if line == nil, let pulse = turnPulse(45) {
            for _ in 0..<8 where line == nil {
                guard !body.ownerTookFocus(), hostNow() < deadline else { return nil }
                body.keys.grant(pulse.code, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)
                guard body.keys.press(pulse.code) else { return nil }
                await sleep(Double(pulse.ms) / 1000)
                body.keys.lift(pulse.code)
                image = await frame(after: hostNow() + 0.3)
                line = found(image)
            }
        }
        guard let line, let image else { return nil }
        // The name's line, read at twice its size, is about 11 px high here; its body stands under it and its title.
        let h = 2.5 * 12.0
        let centre = line.x + 3 * Double(line.text.count)  // about 6 px a letter at this size ("Windshaper Boro", 90 px)
        let mark: QuestMark = (x: centre, y: line.y - h, h: h, body: line.y + 12 + 2.4 * h, nameX: centre, nameTop: line.y)
        body.emit("town_npc", ["name": name, "read": line.text, "at": [Int(line.x), Int(line.y)]])
        guard let point = (await onUnit(mark, in: image, known: name)).point, !body.ownerTookFocus(), hostNow() < deadline else { return nil }
        guard click(point.x, point.y, right: true) else { return nil }
        return await arrive()
    }

    /// The merchant's window is open (its title the vendor's name): Sell All Junk Items, as a human does (M4u). Its tooltip is
    /// read before the click; the game's confirmation ("…sell all junk items…") is answered Yes; the money after is the
    /// evidence. The window is closed with Esc. SOLD n (copper), NO_JUNK (no confirmation came: nothing grey to sell), or why not.
    func sellJunk(_ vendor: String, until deadline: Double = .infinity) async -> String {
        guard let title = lines(QuestHUD.dialog, await frame()).first(where: { sameUnit($0.text, vendor) || likeName($0.text, vendor) }) else {
            return "MERCHANT_NOT_OPEN"
        }
        defer { hover(1280, 60) }
        func money() async -> Int? {
            let m = QuestHUD.merchantMoney
            return copper(lines(CGRect(x: title.x + m.dx, y: title.y + m.dy, width: m.width, height: m.height), await frame()).map(\.text).joined(separator: " "))
        }
        let b = QuestHUD.junkButton, t = QuestHUD.junkTip
        hover(title.x + b.dx, title.y + b.dy)
        await sleep(0.6)
        let tip = lines(CGRect(x: title.x + t.dx, y: title.y + t.dy, width: t.width, height: t.height), await frame(after: hostNow() + 0.2))
        guard tip.contains(where: { nameKey($0.text).contains(nameKey("Sell All Junk")) }) else { await close(vendor); return "NO_SELL_JUNK_BUTTON" }
        let before = await money()
        guard !body.ownerTookFocus(), hostNow() < deadline else { await close(vendor); return "OWNER_OR_TIME" }
        guard click(title.x + b.dx, title.y + b.dy) else { await close(vendor); return "CLICK_FAILED" }
        await sleep(1.0)
        let popup = lines(QuestHUD.popup, await frame(after: hostNow() + 0.2))
        guard popup.contains(where: { nameKey($0.text).contains(nameKey("sell all junk")) }),
              let yes = popup.first(where: { nameKey($0.text) == nameKey("Yes") }) else { await close(vendor); return "NO_JUNK" }
        body.emit("sell_junk", ["controller": "RULE", "vendor": vendor, "money_before": orNull(before)])
        guard !body.ownerTookFocus(), hostNow() < deadline else { await close(vendor); return "OWNER_OR_TIME" }
        guard click(yes.x + 12, yes.y + 7) else { await close(vendor); return "CLICK_FAILED" }
        await sleep(1.5)
        let after = await money()
        body.emit("sold", ["money_before": orNull(before), "money_after": orNull(after)])
        await close(vendor)
        if let before, let after, after > before { return "SOLD \(after - before)" }
        return "SOLD_UNCONFIRMED"
    }

    /// The trainer's gossip is open (M4u): "I'd like training!", then each spell row the level allows, top to bottom (trainerRows),
    /// is clicked and Train pressed, at most TownLimits.trainRows times. A row the game does not allow leaves Train grey, and
    /// the press does nothing. The chat's "You have learned a new spell" is the evidence; the list is read again after each.
    func train(_ trainer: String, level: Int, until deadline: Double) async -> (outcome: String, learned: [String]) {
        var dialog = lines(QuestHUD.dialog, await frame())
        if let option = dialog.first(where: { nameKey($0.text).contains(nameKey("like training")) }) {
            guard !body.ownerTookFocus(), hostNow() < deadline else { await close(trainer); return ("OWNER_OR_TIME", []) }
            guard click(option.x + 40, option.y + 6) else { await close(trainer); return ("CLICK_FAILED", []) }
            await sleep(1.5)
            dialog = lines(QuestHUD.dialog, await frame())
        }
        // The trainer's own window, not its gossip, before any row or Train click (review of #77).
        guard trainerOpen(dialog, trainer: trainer),
              let title = dialog.first(where: { sameUnit($0.text, trainer) || likeName($0.text, trainer) }) else {
            await close(trainer)
            return ("TRAINER_NOT_OPEN", [])
        }
        let l = QuestHUD.trainerList, b = QuestHUD.trainButton
        let list = CGRect(x: title.x + l.dx, y: title.y + l.dy, width: l.width, height: l.height)
        var tried: Set<String> = [], learned: [String] = []
        for _ in 0..<TownLimits.trainRows where hostNow() < deadline && !body.ownerTookFocus() {
            let shown = await frame()
            guard trainerOpen(lines(QuestHUD.dialog, shown), trainer: trainer),
                  let row = trainerRows(lines(list, shown), level: level).first(where: { !tried.contains(nameKey($0.text)) }) else { break }
            tried.insert(nameKey(row.text))
            let before = Set((await frame()).map(chatLines) ?? [])
            guard click(row.x + 40, row.y + 6) else { break }
            await sleep(0.5)
            // The row's click keeps the window; it is read once more before Train (review of #77).
            guard trainerOpen(lines(QuestHUD.dialog, await frame()), trainer: trainer), !body.ownerTookFocus(), hostNow() < deadline else { break }
            guard click(title.x + b.dx, title.y + b.dy) else { break }
            await sleep(1.2)
            let fresh = ((await frame(after: hostNow() + 0.2)).map(chatLines) ?? []).filter { !before.contains($0) && $0.contains("learned") }
            body.emit("train_row", ["controller": "RULE", "row": row.text, "chat": fresh])
            learned += fresh
        }
        hover(1280, 60)
        await close(trainer)
        return (learned.isEmpty ? "NOTHING_TO_TRAIN" : "TRAINED \(learned.count)", learned)
    }

    /// Esc, only while the NPC's window still shows its title at the left: Esc with nothing open is the Game Menu, and a
    /// world name can stand in that box.
    func close(_ name: String) async {
        if npcWindowOpen(lines(QuestHUD.dialog, await frame()), name: name) {
            await tap(QuestHUD.escape)
            await sleep(0.6)
        }
    }

    /// The character's level (M4u): the pointer rests on its own portrait, and its unit tooltip reads "Level N". Nil when unread.
    func readLevel() async -> Int? {
        hover(QuestHUD.portrait.x, QuestHUD.portrait.y)
        let moved = hostNow()
        await sleep(0.4)
        let tip = lines(QuestHUD.unitTip, await frame(after: moved + 0.3)).map(\.text)
        hover(1280, 60)
        // Only the level's line is logged: the tooltip's first line is the character's name (live, 27 Sept: "Level 3
        // Windshaper Skyborne (Player)" under it).
        body.emit("level_read", ["line": orNull(tip.first { $0.lowercased().hasPrefix("level ") }), "level": orNull(tooltipLevel(tip))])
        return tooltipLevel(tip)
    }

    /// Turn to face `pin`, as a human turns to the NPC on arriving: a walk ends facing the way it went (live run 31, 27 Sept:
    /// at the ramp's foot the hand-in's "?" was 90° left, out of view, and a giver's "!" ahead was clicked). A pulse turns at
    /// most 105°, so up to three, each on a fresh reading.
    func face(_ pin: MapPoint) async {
        for _ in 0..<3 {
            guard let o = body.look(), let pulse = turnPulse(angleError(bearing(from: o.point, to: pin), o.facing)) else { return }
            body.emit("face", ["pin": [pin.x, pin.y], "at": [o.x, o.y], "facing": Int(o.facing.rounded())])
            body.keys.grant(pulse.code, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)  // lifted if this stalls (review of #53)
            guard body.keys.press(pulse.code) else { return }
            await sleep(Double(pulse.ms) / 1000)
            body.keys.lift(pulse.code)
            await sleep(0.4)
        }
    }

    /// Turn in place in 45° steps, one turn at most, until a quest mark is in view, as a human looks round: after a
    /// click-walk the camera can sit against a wall with the NPC beside or behind (live run 18, 26 Sept: Rorian's
    /// tent, the camera behind the character's head, Rorian targeted and out of sight). nil: no mark in a whole turn.
    func lookAround(want: String? = nil) async -> (CGImage, [QuestMark])? {
        guard let pulse = turnPulse(45) else { return nil }
        for _ in 0..<8 {
            body.keys.grant(pulse.code, seconds: Double(pulse.ms) / 1000 + NavLimits.forwardWatchdog)  // lifted if this stalls (review of #53)
            guard body.keys.press(pulse.code) else { return nil }
            await sleep(Double(pulse.ms) / 1000)
            body.keys.lift(pulse.code)
            let turned = hostNow()
            guard let seen = await frame(after: turned + 0.3) else { continue }
            let pixels = rgba(seen), marks = clickMarks(seen, pixels, want: want)
            shadowMarks(seen, pixels, at: "around")
            body.emit("look_around", ["marks": marks.count])
            if !marks.isEmpty { return (seen, marks) }
        }
        return nil
    }

    /// Right-click the NPCs under the quest marks in view, nearest the centre first, at most three, until
    /// `page` takes the dialogue that opens (it may click on through an NPC's quest list). A hub's NPCs stand
    /// close together (24 Sept: three "?" in Thendal Village). Someone else's dialogue is closed with Esc,
    /// only when a panel is open: Esc with nothing open is the Game Menu.
    func openAtMark(want: String? = nil, _ page: ([TipLine]) async -> Page) async -> (dialog: [TipLine]?, failure: String?) {
        guard var image = await frame() else { return (nil, "NO_FRESH_FRAME") }
        let pixels = rgba(image)
        var marks = clickMarks(image, pixels, want: want)
        shadowMarks(image, pixels, at: "open")
        body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
        if marks.isEmpty, let around = await lookAround(want: want) { (image, marks) = around }
        guard !marks.isEmpty else {
            write(image, to: body.directory.appendingPathComponent("no-marks.png"), type: .png)  // for calibration
            return (nil, "NO_QUEST_MARK_IN_VIEW")
        }
        var blind: (x: Double, y: Double)? = nil  // the last click the tooltip did not confirm
        var declined: [String] = []  // NPCs whose panel opened here and was someone else's: never clicked again in this search
        for _ in 0..<3 {
            guard let mark = marks.first else { break }
            clicks += 1
            write(image, to: body.directory.appendingPathComponent(String(format: "click%d.jpg", clicks)), type: .jpeg)  // what it was chosen on
            // Where the last unconfirmed click went, the hover already failed: no second sweep, no second click.
            if repeatsClick((mark.x, mark.body), blind, h: mark.h) { marks.removeFirst(); continue }
            let unit = await onUnit(mark, in: image, declined: declined)
            let confirmed = unit.point
            body.emit("unit", ["mark": [Int(mark.x), Int(mark.y)], "at": confirmed.map { [Int($0.x), Int($0.y)] } as Any? ?? NSNull(), "declined": unit.declined])
            if unit.declined { marks.removeFirst(); continue }
            // A target only the learned reader found is clicked only where a hover confirmed an NPC, never blind.
            if confirmed == nil, learnedOnly.contains(where: { $0.x == mark.x && $0.y == mark.y }) { marks.removeFirst(); continue }
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
            if panelOpen(seen) {  // someone else's: close it and try the next mark, or look round for one (live run 40)
                if let who = seen.first?.text { declined.append(who) }
                await tap(QuestHUD.escape)
                await sleep(0.8)
                marks.removeFirst()
                if marks.isEmpty, let around = await lookAround(want: want) { (image, marks) = around }
            } else {  // nothing opened: Click-to-Move walked towards it; look again, over a few frames while the
                // view settles (live run 12, 26 Sept: beside Ailee Farheart the first frame found no mark; a later one did)
                for _ in 0..<3 {
                    let looked = hostNow()
                    guard let again = await frame(after: looked + 0.3) else { continue }
                    image = again
                    let againPixels = rgba(again)
                    marks = clickMarks(again, againPixels, want: want)
                    shadowMarks(again, againPixels, at: "again")
                    body.emit("marks", ["count": marks.count, "marks": marks.prefix(3).map { [Int($0.x), Int($0.y), Int($0.body)] }])
                    if !marks.isEmpty { break }
                    await sleep(0.4)
                }
                if marks.isEmpty, let around = await lookAround(want: want) { (image, marks) = around }
                if marks.isEmpty { write(image, to: body.directory.appendingPathComponent("no-marks-after.png"), type: .png) }
            }
        }
        return (nil, "DIALOGUE_NOT_OPEN")
    }

    /// Take the quest a giver offers: its dialogue's "Accept" button (the owner: always accept quests).
    /// A giver that greets first lists its quests: the entry the minimap's tooltip named is clicked, else the first one
    /// to take (offeredEntry; a mark in view has no tooltip).
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
            let opened = await openAtMark(want: "exclamation") { page in
                var page = page
                if acceptButton(page) == nil, let entry = namedEntry(page, names: giver.names) ?? offeredEntry(page, ours: self.logTitles) {
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

    func turnIn(_ quest: String, ender: String? = nil, until deadline: Double = .infinity) async -> String {
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
        /// What an opened dialogue is: this quest's completion page (through its entry and Continue), another's, or a failure.
        func page(_ page: [TipLine]) async -> Page {
            var page = page
            if has(page, "Complete Quest") == nil, let entry = ours(page) {  // an NPC with several quests lists them
                guard click(entry.x + 40, entry.y + 7) else { return .failed("CLICK_FAILED") }
                await sleep(1.5)
                page = lines(QuestHUD.dialog, await frame())
            }
            page = await pastContinue(page)
            if has(page, "Complete Quest") != nil, ours(page) != nil { return .wanted(page) }
            if has(page, "Continue") != nil, ours(page) != nil { return .failed("CONTINUE_DID_NOT_ADVANCE") }
            return .other(page)
        }
        // M4v: an ender known by name is opened by its name first (openByName, the M4u rule); its "?" is sought only after.
        if has(dialog, "Complete Quest") == nil || ours(dialog) == nil, let ender, let opened = await openByName(ender, until: deadline) {
            body.emit("ender_open", ["quest": quest, "ender": ender, "lines": opened.prefix(4).map(\.text)])
            switch await page(opened) {
            case .wanted(let d): dialog = d
            case .failed(let code): return code
            case .other(let seen):  // another quest's page (Complete Quest, Accept), or its greeting without this quest
                if panelOpen(seen) || npcWindowOpen(seen, name: ender) {  // review of #78: a quest page has no "Goodbye"
                    await tap(QuestHUD.escape)
                    await sleep(0.6)
                }
            }
        }
        if has(dialog, "Complete Quest") == nil || ours(dialog) == nil {
            guard hostNow() < deadline, !body.ownerTookFocus() else { return "OWNER_OR_TIME" }  // review of #78
            let opened = await openAtMark(want: "question") { await page($0) }
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
        var after = lines(QuestHUD.dialog, await frame())
        guard has(after, "Complete Quest") == nil else { return "STILL_OPEN_AFTER_COMPLETE" }
        // The owner: always accept quests. On completion the NPC shows a follow-up's offer ("Accept"), or its greeting again
        // with the quests it now offers (live run 32, 27 Sept: "Elemental Unrest" and "Embracing the Elements" after Harmony
        // in Balance, left open). Each is taken in turn, at most three; an entry whose page shows no Accept ends it.
        for _ in 0..<3 {
            if acceptButton(after) == nil, let entry = offeredEntry(after, ours: logTitles) {
                guard click(entry.x + 40, entry.y + 7) else { break }
                await sleep(1.5)
                after = lines(QuestHUD.dialog, await frame())
            }
            guard let accept = acceptButton(after) else { break }
            body.emit("accept", ["controller": "RULE", "rule": "owner: always accept quests", "dialog": after.prefix(3).map(\.text)])
            let before = Set((await frame()).map(chatLines) ?? [])
            guard click(accept.x + 30, accept.y + 7) else { break }
            await sleep(1.5)
            body.emit("accepted", ["chat": ((await frame()).map(chatLines) ?? []).filter { !before.contains($0) }])
            after = lines(QuestHUD.dialog, await frame())
        }
        // The character pane is read where the dialogue stands (run 32: the greeting's lines were read as the slot's tooltip).
        if panelOpen(after) {
            await tap(QuestHUD.escape)
            await sleep(0.8)
        }
        guard let equip else { return "COMPLETED" }
        // The upgrade is put on from the bags by the host's right-click RULE (M4x). It was typed as "/equip NAME" in chat;
        // live run 77 read no "Say:" after Enter, and the chat box left open took the map's key and the walk's.
        body.emit("reward_to_wear", ["item": equip.name, "slot": orNull(equip.slot)])
        return "COMPLETED_TO_WEAR"
    }
}

/// The character's memory (M4u, M4y), private under runs/; empty when there is none.
func characterMemory() -> [String: Any] {
    (try? Data(contentsOf: QuestHUD.characterMemory)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
}

/// The live side of `runQuests`: the log read of M4d, an M4a walk to the pin (Jev's moves) and M4c's
/// hand-in (RULE). Each walk gets its own keys: runNav's exit sweep ends a key set for good (live,
/// 24 Sept: the second walk of a run pressed nothing for ten decisions).
final class LiveQuestHost: QuestHost {
    let quester: QuestRun
    let key: String
    let newWalker: (URL) -> LiveNavBody  // each walk's frames in its own folder, as a fight's
    let newFighter: (URL, LiveKeys) -> LiveHost  // M3's host on a child key set, its frames in the folder
    let newHunter: (URL) -> LiveHuntHost  // M4b's host on its own key set, as a walk's
    let huntGraph: URL?  // each hunt's own session of the hunt graph; nil: the legacy flat hunt
    var walker: LiveNavBody?
    var walkedFrom: MapPoint?
    var roads: RoadGraph?  // its stands give where to walk before an NPC is clicked (approach)
    var runDeadline = Double.infinity  // the quest run's: no leg of a walk round a gap starts after it (review of #69)
    var town: [TownNPC] = []  // M4u: the villages' vendors and trainers (learning/knowledge/zephras-town.json)
    var enders: [QuestEnder] = []  // M4v: who takes each quest in, and where (learning/knowledge/zephras-quests.json)
    /// From the character's memory (private, under runs/): the level at the last visit to the trainer (M4u), and each step's
    /// record across runs (M4y).
    var trainedAt: Int? = characterMemory()["trained_at_level"] as? Int
    var history: [String: StepMemory] = stepHistory(characterMemory())
    var abilities: [String: UInt16] = [:]  // the bar's skills with no fight role, by name, and their keys (M4m)
    /// M4z: where quest walks stopped (NO_PROGRESS), from the memory; a straight walk passing one goes by road.
    var stuck: [MapPoint] = ((try? Data(contentsOf: QuestHUD.stuckMemory)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [[Double]] } ?? [])
        .compactMap { $0.count == 2 ? ($0[0], $0[1]) : nil }
    private let lock = NSLock()
    private var fighting: LiveHost?  // read by the signal handler's thread
    private var hunting: LiveHuntHost?  // the same
    private var fights = 0, walks = 0, hunts = 0
    private var gearUnchecked = true  // M4x: the bags are looked over for upgrades at the start and after a fight, hunt or hand-in
    private var upgradeInBags = false, unworn = 0  // M4x: a check left an upgrade unworn; how many checks did
    /// M4ab: the reads a step made stale (all at the start), and the last of each.
    private var stale: Set<StaleRead> = [.log, .bags, .level]
    private var lastLog: (quests: [PlannedQuest], missing: [String], givers: [Giver], at: MapPoint)?
    private var lastItems: [String]?, lastLevel: Int?
    let tactics: FightTactics?  // M3b's chains for a fight back; nil: the legacy flat policy
    init(quester: QuestRun, key: String, newWalker: @escaping (URL) -> LiveNavBody, newFighter: @escaping (URL, LiveKeys) -> LiveHost,
         newHunter: @escaping (URL) -> LiveHuntHost, huntGraph: URL? = nil, tactics: FightTactics? = nil) {
        self.quester = quester; self.key = key; self.newWalker = newWalker; self.newFighter = newFighter
        self.newHunter = newHunter; self.huntGraph = huntGraph; self.tactics = tactics
    }

    var holding: Bool {
        (walker?.holding ?? false) || lock.withLock { (fighting?.holdingKeys ?? false) || (hunting?.holding ?? false) }
    }

    /// The exit sweep over the walk's, the fight's and the hunt's key sets.
    func releaseAll() {
        walker?.releaseAll()
        lock.withLock { fighting }?.releaseAll()
        lock.withLock { hunting }?.releaseAll()
    }

    /// Attacked on a walk: one M3 episode, in combat, on a child of the run's own key set, as the hunt's
    /// fights. Not the walk's: runNav's exit sweep has retired it, and no child can be taken from it (the
    /// 25 Sept review; M4i had not run live). The run's set only taps, and stays active until the run ends.
    /// A fight that ends with keys held stays tracked for the exit sweep, and its handoff fails the run.
    func fightBack() async -> String { await fight(inCombat: true) }

    /// FIGHT_AHEAD (M4p, Jev's choice after a red name stopped the walk): the same fight from out of combat, started only
    /// at the fight's own start health; the fight's Jev selects the creature (Tab) and pulls it.
    /// A creature that has come to the character since the stop makes it a fight back (start health 0); one that Jev left
    /// fighting it after a JEV_STOP is fought back at once, as SAFETY's, not handed to a quest decision (review of #66).
    /// A fight in combat returns "BACK_" + its outcome, so the run treats it as M4i treats a fight back: only a kill goes on.
    /// Combat is read from the latest frame's HUD alone, however the place reads: a place under a plate is not "out of
    /// combat" (third review of #66). No fresh frame counts as combat.
    func fightAhead() async -> String {
        if combatNow() != false { return "BACK_" + (await fight(inCombat: true)) }
        let outcome = await fight(inCombat: false)
        guard outcome == "JEV_STOP", combatNow() != false else { return outcome }
        emit("quest_step", ["controller": "SAFETY", "skill": "FIGHT_BACK", "step": "fight back after a fight ahead Jev stopped"])
        return "BACK_" + (await fight(inCombat: true))
    }

    /// The HUD on a frame no older than the fight's age limit; nil without one.
    private func vitalsNow() -> Obs? {
        guard let frame = runtimeFrame(quester.body.session, quester.body.feed),
              frame.stamp.isFresh(at: hostNow(), maximumAge: FightLimits.maxFrameAge) else { return nil }
        return observe(rgba(frame.image), plates: false)
    }

    /// Out of combat and hurt, heal before walking on (RULE; recover): F1 (the default Target Self) selects the character, the
    /// bar's heal is cast on it, and Esc drops the selection after, only while a target shows (Esc with none is the Game Menu).
    func healBeforeWalking() async {
        guard !ownerTookFocus() else { return }
        let outcome = await recover(read: { self.vitalsNow() }, aim: {
            await self.quester.tap(QuestHUD.targetSelf)
            await self.quester.sleep(0.3)
        }, cast: {
            guard !self.ownerTookFocus() else { return false }
            await self.quester.tap(FightLimits.heal)
            await self.quester.sleep(RecoverLimits.castSeconds)
            return true
        }, clear: {
            if (self.vitalsNow()?.target ?? 0) > 0, !self.ownerTookFocus() { await self.quester.tap(QuestHUD.escape) }
        })
        if outcome != "NOT_HURT" { emit("recover", ["controller": "RULE", "rule": "the owner: heal when needed", "outcome": outcome]) }
    }

    /// The HUD's combat (the ring and the bars) on a frame no older than the fight's age limit; nil without one.
    private func combatNow() -> Bool? {
        guard let frame = runtimeFrame(quester.body.session, quester.body.feed),
              frame.stamp.isFresh(at: hostNow(), maximumAge: FightLimits.maxFrameAge) else { return nil }
        return observe(rgba(frame.image), plates: false).combat
    }

    private func fight(inCombat: Bool) async -> String {
        guard walker?.holding != true else { return "WALK_KEYS_HELD" }
        let parent = quester.body
        fights += 1
        let folder = quester.body.directory.appendingPathComponent(String(format: "fight%d", fights))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let child = parent.keys.takeChild(releaseCodes: FightLimits.releaseCodes) else { return "INPUT_HANDOFF_FAILED" }
        let host = newFighter(folder, child)
        lock.withLock { fighting = host }
        emit("fight_start", ["fight": fights, "in_combat": inCombat, "controller": inCombat ? "SAFETY" : "JEV"])
        let result = await runFight(host: host, jev: LiveJev(key: key, timeout: FightLimits.jevTimeout),
                                    startHealth: inCombat ? 0 : FightLimits.startHealth, tactics: tactics)
        emit("fight_end", ["fight": fights, "outcome": result.outcome, "decisions": result.decisions])
        gearUnchecked = true
        stale.formUnion([.log, .bags, .level])  // M4ab: a fight back or ahead, as staleAfter's fight ahead: kills, loot, experience
        guard parent.keys.resume(after: child) else { return "INPUT_HANDOFF_FAILED" }
        lock.withLock { fighting = nil }
        return result.outcome
    }

    func readQuests() async -> QuestRead? {
        // M4ab: the log, the bags and the level are read again only when a step made them stale (staleAfter), or the log when
        // the character has walked `rereadMove` since; the place is read each time.
        var quests: [PlannedQuest], missing: [String], givers: [Giver], player: MapPoint
        if !stale.contains(.log), let last = lastLog, let here = await quester.position(turn: true),
           distance(here, last.at) < QuestLimits.rereadMove {
            (quests, missing, givers, player) = (last.quests, last.missing, last.givers, here)
            emit("read_kept", ["log": true, "moved": roundTo(distance(here, last.at))])
        } else {
            let (read, at, lost, found) = await quester.readQuests(turnIfUnread: true)
            guard let at else { return nil }
            (quests, missing, givers, player) = (withEnders(read, enders), lost, found, at)  // M4v: each quest's ender
            lastLog = (quests, missing, givers, at)
            stale.remove(.log)
        }
        let checked = await wearUpgrades()
        if let checked { lastItems = checked; stale.remove(.bags) }
        // The bags are read only when a use-at quest might name an item in them (M4m), and not again after M4x's read or while
        // the last read stands (M4ab).
        var items: [String] = []
        if quests.contains(where: { questKind($0) == .useAt }) {
            if !stale.contains(.bags), let kept = lastItems {
                items = kept
            } else {
                items = (await quester.readBags())?.map(\.name) ?? []
                lastItems = items
                stale.remove(.bags)
            }
        }
        if !items.isEmpty { emit("bags", ["items": items]) }
        // M4u: the level, for the trainer; the level last trained, from the character's memory (a lower level read is a new
        // character with the same name: the memory is forgotten); the bags' filled slots when they were read.
        var level = town.isEmpty ? nil : lastLevel
        if !town.isEmpty && (stale.contains(.level) || lastLevel == nil) {
            level = await quester.readLevel()
            lastLevel = level
            if level != nil { stale.remove(.level) }
        }
        if let level, let known = ([trainedAt] + history.values.map(\.level)).compactMap({ $0 }).max(), level < known {
            trainedAt = nil
            history = [:]
            try? FileManager.default.removeItem(at: QuestHUD.characterMemory)
        }
        return QuestRead(quests: quests, player: player, missing: missing, givers: givers, items: items, abilities: Array(abilities.keys),
                         level: level, trainedAt: trainedAt, bagsUsed: items.isEmpty ? nil : items.count,
                         gearSettled: !gearUnchecked && !upgradeInBags, history: history)
    }

    /// M4x, a RULE (the owner, 27 Sept: "we should always wear better gear first when non-battle"): out of combat, before the
    /// next step, the bags' upgrades are put on; before a town stop too, so Sell All Junk never sells a grey upgrade. The
    /// bags' names when they were read and nothing was worn.
    private func wearUpgrades() async -> [String]? {
        guard gearUnchecked, combatNow() == false, !ownerTookFocus() else { return nil }
        let (outcome, worn, items) = await quester.wearUpgrades()
        if !worn.isEmpty { stale.insert(.bags) }  // M4ab: what was worn left the bags, and what it replaced went in
        // An upgrade left in the bags (a tooltip or a click that failed, a bind prompt) is tried once more; until it is worn no
        // junk is sold (visit).
        upgradeInBags = outcome == "NOT_WORN"
        if upgradeInBags { unworn += 1 }
        gearUnchecked = outcome == "NPC_WINDOW_OPEN" || outcome == "BAGS_UNREAD" || (upgradeInBags && unworn < 2)
        emit("equip", ["controller": "RULE", "rule": "the owner: always wear better gear first when non-battle", "outcome": outcome,
                       "worn": worn])
        return items
    }

    /// A town stop (M4u): walk to where the NPC is talked to, open its window by its name, then sell the junk or train.
    /// A trainer's window seen at a level is remembered (character.json, private): TRAIN is offered again only at a higher one.
    func visit(_ npc: TownNPC) async -> String {
        // M4x: no junk is sold while an upgrade may lie in the bags unworn (review of #80: Sell All Junk sells grey gear). The
        // read offers no vendor then (gearSettled); this holds should the gear change between the read and the visit.
        if npc.role == "vendor" && (gearUnchecked || upgradeInBags) { return "GEAR_UNSETTLED" }
        if let stop = await walk(to: npc.point, label: npc.name, arrive: 0.3) { return stop }
        guard !ownerTookFocus() else { return "OWNER_TOOK_FOCUS" }
        guard hostNow() < runDeadline else { return "TOWN_TIME_LIMIT" }  // the window's work starts only inside the run
        guard let opened = await quester.openByName(npc.name, until: runDeadline) else { return "NPC_NOT_OPENED" }
        emit("town_open", ["npc": npc.name, "lines": opened.prefix(4).map(\.text)])
        if npc.role == "vendor" {
            let outcome = await quester.sellJunk(npc.name, until: runDeadline)
            stale.formUnion(staleAfter(.town(npc), outcome))
            emit("town_done", ["npc": npc.name, "outcome": outcome])
            return outcome
        }
        let level = await quester.readLevel()
        let (outcome, learned) = await quester.train(npc.name, level: level ?? 1, until: runDeadline)
        emit("town_done", ["npc": npc.name, "outcome": outcome, "learned": learned, "level": orNull(level)])
        // Remembered only when a spell was learnt: a visit short of money is offered again at the same level (review of #77).
        if let level, !learned.isEmpty {
            trainedAt = level
            saveMemory()
        }
        return outcome
    }

    /// M4y: a step's outcome into its record (recordStep), and the memory written when the record changed.
    func remember(_ key: String, outcome: String, level: Int?) {
        let updated = recordStep(history, key: key, outcome: outcome, level: level)
        guard updated != history else { return }
        history = updated
        emit("step_memory", ["step": key, "outcome": outcome, "fails": orNull(updated[key]?.fails)])
        saveMemory()
    }

    /// The character's memory, written whole: the level last trained and the steps' records.
    private func saveMemory() {
        let steps = history.mapValues { ["fails": $0.fails, "last": $0.last, "level": orNull($0.level)] as [String: Any] }
        try? FileManager.default.createDirectory(at: QuestHUD.characterMemory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: ["trained_at_level": orNull(trainedAt), "steps": steps], options: [.sortedKeys])
            .write(to: QuestHUD.characterMemory)
    }

    /// A bar ability ("Skysight") is used where the quest asks, its pin when its objective says "near": the walk first, then
    /// its key, and time for its cast. With no pin (FROM_HERE, Jev's choice after a walk stopped near it) there is no walk. A bag item is right-clicked where the character stands (QuestRun.useItem).
    func useItem(_ quest: PlannedQuest, item: String) async -> String {
        let outcome: String
        if let key = abilities[item] {
            if usesNear(quest), let pin = quest.pin, let stop = await walk(to: pin, label: quest.title) { return stop }
            emit("use_ability", ["ability": item, "key": Int(key), "controller": "RULE"])
            await quester.tap(key)
            await quester.sleep(2.5)  // its cast (0.5 s for Skysight) and the blessing that follows
            // No evidence here that it took (review of #54): not a use that makes the quest a hand-in. A quest it completes reads
            // "Ready for turn-in" at the next log read, and is handed in as any other.
            outcome = "USED_ABILITY"
        } else {
            outcome = await quester.useItem(item)
        }
        emit("item_used", ["quest": quest.title, "item": item, "outcome": outcome])
        stale.formUnion(staleAfter(.use(quest, item: item), outcome))
        forgetLog(outcome)
        return outcome
    }

    /// Walk even a short way: walking faces the NPC, so its mark is in view (live, 24 Sept: 1.0 away and
    /// behind the camera, no mark was found). nil when there, else the outcome that ends the step.
    /// A leg of a learned road (`road`) may be longer than one walk: walkStart.
    func walk(to pin: MapPoint, label: String, retreating: Bool = false, road: Bool = false, arrive: Double = 0.5) async -> String? {
        // A key set whose release is unconfirmed is never dropped (its watchdog would stop retrying),
        // and a walk that ends so ends the run: WALK_ outcomes stop runQuests. Checked before any turn to read the place.
        if walker?.holding == true { return "WALK_KEYS_HELD" }
        if !retreating { await healBeforeWalking() }  // a retreat leaves the danger first; a heal would stand in it
        // A plate over the coordinates must not refuse the walk (live run 47); a retreat does not turn beside the danger.
        // Only the coordinates are read here: the arrow is the walk's own first look (runNav).
        let at = await quester.position(turn: !retreating)
        switch walkStart(at: at, to: pin, road: road, arrive: arrive) {
        case .refused(let outcome): return outcome
        case .there: return nil
        case .walk: break
        }
        if !retreating, let at { walkedFrom = at }  // the way back from danger: this walk came through it
        // A straight line that leaves the learned roads is walked by them, leg by leg (the owner, 27 Sept: obstacles and
        // cliffs), and so is one that passes where a walk stopped before (M4z), to the road's place nearest the pin. A retreat
        // goes straight back over the ground it crossed; a road's own leg is already on the road.
        let stuckAhead = !retreating && !road && at.map { passesStuck($0, pin, stuck) } == true
        if !retreating, !road, let roads, let at, stuckAhead || straightLeavesRoads(at, pin, roads),
           let legs = route(roads, from: at, to: pin, avoid: stuckAhead ? stuck : []) {
            let length = zip([at] + legs, legs).map { distance($0, $1) }.reduce(0, +)
            emit("road_gap", ["pin": [pin.x, pin.y], "straight": roundTo(distance(at, pin)), "legs": legs.count, "road": roundTo(length),
                              "stuck_ahead": stuckAhead])
            return await roadGapWalk(legs, arrive: arrive, until: min(runDeadline, hostNow() + QuestLimits.roadGapSeconds), now: now) { i, leg, reach in
                await walk(to: leg, label: "\(label) by road, leg \(i + 1) of \(legs.count)", road: true, arrive: reach)
            }
        }
        walks += 1
        let folder = quester.body.directory.appendingPathComponent(String(format: "walk%d", walks))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let legs = newWalker(folder)
        walker = legs
        let walked = await runNav(body: legs, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout),
                                  destination: NavDestination(label: String(label.prefix(60)), x: pin.x, y: pin.y, arrive: arrive))
        guard !legs.holding else { return "WALK_KEYS_HELD" }
        if walked.outcome == "NO_PROGRESS", !retreating, let end = walked.end { rememberStuck(end.point) }
        return walked.outcome == "ARRIVED" ? nil : "WALK_" + walked.outcome
    }

    /// M4z: a place where a quest walk stopped, kept for the walks after (the latest `stuckKept`), and written.
    private func rememberStuck(_ at: MapPoint) {
        stuck = Array((stuck + [at]).suffix(RoadLimits.stuckKept))
        emit("stuck_point", ["at": [at.x, at.y], "kept": stuck.count])
        try? FileManager.default.createDirectory(at: QuestHUD.stuckMemory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONSerialization.data(withJSONObject: stuck.map { [$0.x, $0.y] }).write(to: QuestHUD.stuckMemory)
    }

    /// At a run's end, the way to the nearest safe place (safePlace, leaveDangerRounds), SAFETY's: its walks' moves are a
    /// fixed preference (straight, then detours), with no model call, so a run that ended on a failed Jev call walks too.
    /// It ends inside the run envelope's 30 minutes (the run stops new steps at 20). No fresh HUD counts as combat.
    func leaveDanger(after outcome: String) async {
        guard leavesDanger(outcome), walker?.holding != true, !ownerTookFocus(), let at = await quester.position(turn: false),
              let safe = safePlace(from: at) else { return }
        emit("leave_danger", ["controller": "SAFETY", "after": outcome, "from": [at.x, at.y], "to": [safe.x, safe.y]])
        let preference: [NavAction] = [.goToward, .detourRight45, .detourLeft45, .detourRight90, .detourLeft90, .backTrack]
        // Its end leaves death recovery its time (M4s).
        let envelopeEnd = runDeadline - QuestLimits.runSeconds + QuestLimits.envelopeSeconds - QuestLimits.reviveSeconds
        let end = await leaveDangerRounds(QuestLimits.safeWalks, until: envelopeEnd, now: now,
                                          inCombat: { self.combatNow() != false }, fightBack: { await self.fightBack() }) { seconds in
            guard !self.ownerTookFocus(), self.walker?.holding != true else { return "OWNER_OR_KEYS" }
            let healing = hostNow()
            await self.healBeforeWalking()  // live run 70: it set off under 30% health, got stuck, and died
            let seconds = seconds - (hostNow() - healing)  // the heal's time comes out of this walk's (review of #79)
            self.walks += 1
            let folder = self.quester.body.directory.appendingPathComponent(String(format: "walk%d", self.walks))
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let legs = self.newWalker(folder)
            self.walker = legs
            let walked = await runNav(body: legs, jev: ScriptedJev(preference: preference),
                                      destination: NavDestination(label: "a safe place", x: safe.x, y: safe.y, arrive: QuestLimits.safeArrive,
                                                                  toSafety: true, seconds: seconds))
            return walked.outcome
        }
        emit("leave_danger_end", ["controller": "SAFETY", "outcome": end])
    }

    /// M4s: resurrect at the Spirit Healer when the screen shows death (SAFETY's; nil when it does not). Each read is on a
    /// frame captured after the last click. After Release Spirit it waits up to 10 s for the gossip, which opened by itself
    /// after run 65 but not after run 66: then the Spirit Healer is right-clicked (TALK).
    func reviveIfDead() async -> String? {
        func texts(_ box: CGRect, _ image: CGImage) -> [ScreenText] {
            guard let crop = image.cropping(to: box) else { return [] }
            return ocr(crop).map { ($0.0, box.minX + $0.1.midX * box.width, box.minY + (1 - $0.1.midY) * box.height) }
        }
        func names(_ box: CGRect, _ image: CGImage) -> [WorldName] {
            guard let crop = image.cropping(to: box) else { return [] }
            return ocr(crop).map { ($0.0, box.minX + $0.1.midX * box.width, box.minY + (1 - $0.1.minY) * box.height, $0.1.height * box.height) }
        }
        func shown(_ image: CGImage?, _ last: DeathStep?) -> DeathClick? {
            image.flatMap { deathStep(popup: texts(QuestHUD.popup, $0), dialog: texts(QuestHUD.dialog, $0), world: names(QuestHUD.healer, $0), last: last) }
        }
        // No click while any of the run's keys is held (review of #73: a hunt that ended with keys held).
        guard !ownerTookFocus(), !holding, let first = shown(await quester.frame(after: hostNow()), nil) else { return nil }
        emit("death", ["controller": "SAFETY", "shown": first.step.rawValue])
        let end = await revive(first, clicks: QuestLimits.reviveClicks, click: { c in
            guard !self.ownerTookFocus() else { return false }
            self.emit("revive_click", ["controller": "SAFETY", "step": c.step.rawValue, "at": [Int(c.x), Int(c.y)]])
            return c.step == .talk ? self.quester.click(c.x, c.y, right: true) : self.quester.click(c.x, c.y)
        }) { step in
            let start = hostNow(), wait = step == .release ? QuestLimits.reviveWait : QuestLimits.reviveWait / 2
            var reads: [DeathClick?] = []
            while true {
                if let seen = deathSeen(after: step, reads, timedOut: hostNow() - start >= wait) { return seen }
                guard let image = await self.quester.frame(after: hostNow() + 0.3) else { continue }  // no frame: no read
                reads.append(shown(image, step))
            }
        }
        emit("revive_end", ["controller": "SAFETY", "outcome": end ?? ""])
        return end
    }

    func handIn(_ quest: PlannedQuest) async -> String {
        // No pin: the map hid it under the player's arrow, so its NPC may stand here, perhaps above or below.
        let pin = quest.pin ?? quester.body.look().map { (x: $0.x, y: $0.y) }
        if let pin, let stop = await walkBeside(pin, label: quest.title) { return stop }
        if let pin = quest.pin { await quester.face(pin) }
        let outcome = await quester.turnIn(quest.title, ender: quest.ender, until: runDeadline)
        emit("quest_done", ["quest": quest.title, "outcome": outcome])
        stale.formUnion(staleAfter(.handIn(quest), outcome))
        if outcome.hasPrefix("COMPLETED") { gearUnchecked = true }  // a reward is in the bags (M4x)
        forgetLog(outcome)
        return outcome
    }

    /// A route of the learned roads, leg by leg (walkLegs); the first leg that does not arrive is the step's outcome.
    func walkRoad(to quest: PlannedQuest, by legs: [MapPoint], until deadline: Double) async -> String {
        emit("road", ["quest": quest.title, "legs": legs.map { [$0.x, $0.y] }])
        return await walkLegs(legs, until: deadline, now: now) { i, leg in
            await walk(to: leg, label: "road to \(quest.title), leg \(i + 1) of \(legs.count)", road: true)
        }
    }

    /// Walk to where players came from to stand beside the NPC at `pin` (approach), to within approachArrive, else to
    /// the pin. A straight Click-to-Move from that side climbs to a platform's NPC instead of ending under it.
    func walkBeside(_ pin: MapPoint, label: String) async -> String? {
        guard let from = approach(to: pin, in: roads) else { return await walk(to: pin, label: label) }
        emit("approach", ["pin": [pin.x, pin.y], "from": [from.x, from.y]])
        return await walk(to: from, label: label, arrive: RoadLimits.approachArrive)
    }

    /// Back to where the last walk began, which that walk had just passed: the owner, survive first.
    func retreat() async -> String {
        guard let back = walkedFrom else { return "NO_WAY_BACK" }
        emit("retreat", ["to": [back.x, back.y]])
        return await walk(to: back, label: "retreat", retreating: true) ?? "RETREATED"
    }

    func accept(_ giver: Giver) async -> String {
        if let stop = await (giver.inView ? walk(to: giver.pin, label: "quest giver") : walkBeside(giver.pin, label: "quest giver")) { return stop }
        if !giver.inView { await quester.face(giver.pin) }
        let outcome = await quester.accept(giver)
        emit("quest_taken", ["tooltip": giver.names, "outcome": outcome])
        stale.formUnion(staleAfter(.accept(giver), outcome))
        forgetLog(outcome)
        return outcome
    }

    /// Walk to the quest's area (from here when the map showed none, or when Jev chose FROM_HERE), then one M4b hunt, as `--hunt` runs
    /// it, in its own folder, with what is left to the deadline after the walk (review of #47: a walk of up to
    /// 180 s came before the budget). A hunt that ends with keys held stays tracked for the exit sweep.
    func hunt(_ quest: PlannedQuest, until deadline: Double) async -> String {
        if let pin = quest.pin, let stop = await walk(to: pin, label: quest.title) { return stop }  // FROM_HERE: Jev's choice
        let seconds = min(HuntLimits.maxSeconds, deadline - hostNow())
        guard seconds > 0 else { return "HUNT_TIME_LIMIT" }
        guard walker?.holding != true else { return "WALK_KEYS_HELD" }
        let graph: GraphSession?
        do { graph = try huntGraph.map { try GraphSession.load($0) } } catch { return "HUNT_GRAPH_UNREADABLE" }
        hunts += 1
        let folder = quester.body.directory.appendingPathComponent(String(format: "hunt%d", hunts))
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let hunter = newHunter(folder)
        lock.withLock { hunting = hunter }
        emit("hunt_start", ["hunt": hunts, "quest": quest.title, "seconds": Int(seconds), "decision_graph": graph?.graph.id as Any? ?? NSNull()])
        let result = await runHunt(host: hunter, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: graph == nil ? 2 : 0),
                                   graph: graph, seconds: seconds)
        let outcome = huntOutcome(result.outcome, start: result.start, end: result.end)
        if !result.fights.isEmpty { gearUnchecked = true }  // M4ab: only a hunt that fought looted (live run 81: none, a bag read)
        emit("hunt_end", ["hunt": hunts, "quest": quest.title, "code": result.outcome, "outcome": outcome,
                          "fights": result.fights.map(\.outcome), "decisions": result.decisions])
        stale.formUnion(staleAfter(.hunt(quest), outcome))
        guard !hunter.holding else { return "HUNT_KEYS_HELD" }
        lock.withLock { hunting = nil }
        return outcome
    }

    func now() -> Double { hostNow() }
    func ownerTookFocus() -> Bool { quester.body.ownerTookFocus() }
    func emit(_ event: String, _ fields: [String: Any]) { quester.body.emit(event, fields) }
}

/// `--quests --graph PATH --keys wqe`: Jev chooses each quest step through the quest graph; local code
/// offers only hand-ins within one walk and stops on the run envelope's limits (M4f).
@MainActor
func questsExecute(graph: GraphSession, fightGraph: String? = nil, huntGraph: String? = nil) async throws -> Int32 {
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
    // An idle logout leaves the game at the character select screen: the world is entered before the bar is read.
    let entry = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    let entered = await (try QuestRun(body: entry)).enterWorldIfAtSelect()
    entry.releaseAll()
    guard entered else {
        try? await stream.stopCapture()
        throw ProbeError("not in the world: no fresh frame, or Enter World did not load it")
    }
    // A fight back presses the bar's keys, so they come from its tooltips, as a hunt's: the defaults were
    // the 23 Sept bar, where key 3 was the heal (Earth Shock by 24 Sept) and key 4 the buff (Healing Wave).
    let bar = try await readSkillBar(session, feed, log, required: fightRoles)
    applyRoles(bar.keys)
    HuntLimits.drink = bar.keys[.drink] ?? HuntLimits.drink  // a hunt eats and drinks from the bar, as --hunt
    HuntLimits.eat = bar.keys[.food] ?? HuntLimits.eat
    let tactics = try fightTactics(fightGraph, bar, log)
    let hunting = huntGraph.map { URL(fileURLWithPath: $0) }  // read at start, so a bad file stops the run before any walk
    if let hunting { _ = try GraphSession.load(hunting) }
    let roads = try RoadGraph.load()  // the roads learned from players' videos; none: a run ends at its zone's edge
    log.emit("roads", ["places": roads?.places.count ?? 0, "ways": roads?.ways.count ?? 0, "sources": roads?.sources ?? []])
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    let host = LiveQuestHost(quester: try QuestRun(body: body), key: key,
                             newWalker: { LiveNavBody(session: session, feed: feed, sink: sink, directory: $0, log: log) },
                             newFighter: { LiveHost(session: session, feed: feed, sink: sink, directory: $0, log: log, input: $1) },
                             newHunter: { LiveHuntHost(session: session, feed: feed, sink: sink, directory: $0, log: log, fightJev: LiveJev(key: key),
                                                       fightTactics: tactics) },
                             huntGraph: hunting, tactics: tactics)
    host.roads = roads
    host.town = (try? TownNPC.load()) ?? []  // M4u: the vendor and the trainer of the villages learnt so far
    host.enders = (try? QuestEnder.load()) ?? []  // M4v: the quest enders from the wiki
    log.emit("town", ["npcs": host.town.map(\.name)])
    host.runDeadline = hostNow() + QuestLimits.runSeconds
    // The bar's other skills ("Skysight", from a quest) are abilities a use-at quest may name (M4m).
    host.abilities = Dictionary(bar.slots.compactMap { slot, skill in
        role(skill) == nil ? SkillHUD.names.firstIndex(of: slot).map { (skill.name, SkillHUD.keys[$0]) } : nil }, uniquingKeysWith: { a, _ in a })
    defer { body.releaseAll(); host.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll(); host.releaseAll() },
                              holding: { body.holding || host.holding })
    await setZoom(body.keys, log)  // the engine's zoom, not whatever the camera had (owner, 26 Sept)
    body.emit("start", ["run_id": run.id, "mode": "quests", "decision_graph": graph.graph.id])
    // Dead at the start (live, 27 Sept: it died between runs 56 and 57): resurrected first, or the run does not start.
    let revivedFirst = await host.reviveIfDead()
    var result = QuestResult()
    if let revivedFirst, revivedFirst != "REVIVED" { result.outcome = revivedFirst }
    else { result = await runQuests(host: host, jev: LiveJev(key: key, timeout: HuntLimits.jevTimeout, retries: 0), graph: graph, roads: roads,
                                    seconds: host.runDeadline - hostNow(), town: host.town) }  // what setup and a revive left of the window
    await host.leaveDanger(after: result.outcome)
    let revived = await host.reviveIfDead()  // died in the run or on the way to safety
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    body.emit("summary", ["outcome": result.outcome, "steps": result.steps.map { ["quest": $0.quest, "outcome": $0.outcome] },
                          "graph_requests": result.graphRecords.count, "run_directory": run.url.path,
                          "revived": [revivedFirst, revived].compactMap { $0 }])
    for s in result.steps { print("\(s.quest): \(s.outcome)") }
    print("run: \(result.outcome)")
    for end in [revivedFirst, revived].compactMap({ $0 }) { print("death: \(end)") }
    return body.holding || host.holding ? 3 : 0
}

/// `--zoom --keys wqe [--seconds S]`: set the engine's zoom (F11 held S s back from the widest view) and save
/// the frame after it as zoom.png, to calibrate `zoomInSeconds` against the owner's zoom.
@MainActor
func zoomExecute(_ inSeconds: Double) async throws -> Int32 {
    let session = try await wowSession(input: true, full: true)
    let run = try runDirectory("m4_zoom")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    await setZoom(body.keys, log, inSeconds: inSeconds)
    let set = hostNow()
    try? await Task.sleep(nanoseconds: 700_000_000)  // the camera eases to its new distance
    let after = await (try QuestRun(body: body)).frame(after: set + 0.5)
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    guard let after else { throw ProbeError("no frame after the zoom") }
    write(after, to: run.url.appendingPathComponent("zoom.png"), type: .png)
    print("zoom: in \(inSeconds) s; \(run.url.appendingPathComponent("zoom.png").path)")
    return body.holding ? 3 : 0
}

/// `--bags --keys wqe`: read the backpack's items (readBags: B, a hover on each filled slot, B) and print them (M4m).
/// From the character select screen it enters the world first. Nothing is clicked.
@MainActor
func bagsExecute() async throws -> Int32 {
    let session = try await wowSession(input: true, full: true)
    let run = try runDirectory("m4_bags")
    let log = try Log(file: run.url.appendingPathComponent("events.jsonl"))
    let feed = FrameFeed()
    let stream = try capture(session, into: feed)
    try await stream.startCapture()
    let sink = PidKeySink(pid: session.app.processIdentifier)
    let body = LiveNavBody(session: session, feed: feed, sink: sink, directory: run.url, log: log)
    defer { body.releaseAll() }
    let dummy = InputLease(profile: .wqe, sink: sink, clock: hostNow, emit: { _, _ in })
    let signals = trapSignals(dummy, log, also: { body.releaseAll() }, holding: { body.holding })
    let quester = try QuestRun(body: body)
    guard await quester.enterWorldIfAtSelect() else { throw ProbeError("not in the world: no fresh frame, or Enter World did not load it") }
    let items = await quester.readBags()
    try? await stream.stopCapture()
    withExtendedLifetime(signals) {}
    guard let items else { throw ProbeError("the backpack did not open") }
    for (i, item) in items.enumerated() { print("\(i + 1). \(item.name)") }
    return body.holding ? 3 : 0
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
    let quester = try QuestRun(body: body)
    let outcome = await quester.turnIn(quest)
    if outcome == "COMPLETED_TO_WEAR" {  // M4x: the chosen upgrade from the bags, as the quest run's RULE puts it on
        let (wear, worn, _) = await quester.wearUpgrades()
        body.emit("equip", ["controller": "RULE", "outcome": wear, "worn": worn])
    }
    forgetLog(outcome)
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
