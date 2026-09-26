// M3 fight core for issue #5: calibrated HUD, admissibility, episode rules, Jev choice
// parsing and a simulated fight. Pure Foundation with injected time, observations and
// input, so the same loop runs offline against SimFight and live against the native shell.
// FightProbe.swift supplies capture, pid keys, OCR, the loot click and the TypeSafe call.
import Foundation

enum HUD {
    static let width = 2560
    static let height = 1320
    /// Player health: green fill of the character health bar, one row above the owner's "81 / 81" text.
    static let playerX0 = 801, playerX1 = 931, playerY = 990, playerSpan = 130
    /// Target health: green fill of the target health bar, one row above the "55 / 55" text.
    static let targetX0 = 1630, targetX1 = 1760, targetY = 990, targetSpan = 130
    /// Player mana: the right end of the blue fill across the mana bar's rows. The "148 / 148" text covers
    /// the bar's full height, so a count would read a full bar as half; the fill's end is off by at most a glyph.
    static let manaX0 = 801, manaX1 = 931, manaY = 1010, manaY1 = 1018, manaSpan = 130
    /// Combat ring: red pixels around the character portrait.
    static let combatX0 = 720, combatX1 = 810, combatY0 = 950, combatY1 = 1045, combatMin = 300
    /// Cast bar: grey/yellow track (x 1172-1388, y 1200-1210) and yellow fill on row 1205 / 216.
    static let castX0 = 1172, castX1 = 1388, castY0 = 1165, castY1 = 1173  // 24 Sept: the swing timer pushed it up 36 px
    static let castFillY = 1169, castFillSpan = 216, castTrackMin = 300
    /// The bolt slot's hotkey digit: dark-red when Lightning Bolt is out of range (x for key 2; applyRoles moves it).
    /// The digit's own columns only: the slot's left edge, which a held key lights orange, read as red.
    static var rangeX0 = 716, rangeX1 = 732
    static let rangeY0 = 1270, rangeY1 = 1292, rangeMin = 4
    /// The shock slot's hotkey digit, read the same way (the owner, 23 Sept: each spell's digit gives a range band);
    /// x for key 3, Earth Shock's slot since 24 Sept (on the 23 Sept bar key 3 was Healing Wave).
    static var shockRangeX0 = 766, shockRangeX1 = 782
    /// Weapon-buff icon: green glow on the top-right buff row.
    static let buffX0 = 2215, buffX1 = 2300, buffY0 = 30, buffY1 = 75, buffMin = 100
    /// Red error text: the floating red game-error line.
    static let errorX0 = 1000, errorX1 = 1560, errorY0 = 140, errorY1 = 200, errorMin = 20

    static func green(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 110 && g > r + 40 && g > b + 60 }
    static func blue(_ r: Int, _ g: Int, _ b: Int) -> Bool { b > 100 && b > r + 60 && b > g + 40 }  // incl. the dim left end
    static func combatRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 150 && g < 70 && b < 70 }
    static func castYellow(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 150 && g > 120 && b < 100 }
    static func castTrack(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        castYellow(r, g, b) || (abs(r - g) < 15 && abs(g - b) < 15 && r > 70 && r < 150)
    }
    static func darkRedDigit(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 80 && r > g + 60 && r > b + 60 }
    /// Earth Shock's digit, 24 Sept: a muted red (about 125, 80, 75) over a yellow icon, which darkRedDigit misses;
    /// its green and blue stay level, the icon's yellows and browns' do not. On the 24 Sept frames it counts
    /// at most 1 pixel on the 407 without a target, and 0-2 or 13-14 on the 518 with one.
    static func mutedRedDigit(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 80 && r > g + 30 && abs(g - b) < 20 }
    static func buffGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 120 && g > r + 20 && g > b + 20 }
    static func errorRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 180 && r > g + 70 && r > b + 70 && g > 50 }
}

enum FightLimits {
    static let maxDecisions = 40
    static let maxSteps = 120  // Jev's decisions plus the steps its chains run without a call
    static let maxSeconds = 150.0
    static let playerSafety = 0.3
    static let healMana = 0.15  // below playerSafety in combat, HEAL alone is offered while mana lasts
    static let startHealth = 0.9
    // ponytail: 1 s at 30 fps capture; WoW's scene always animates, so an older newest frame is a stall.
    static let maxFrameAge = 1.0
    static let freshWait = 2.0  // how long a fight waits for a fresh frame before NO_FRESH_FRAME
    static let walkBudgetMs = 3500
    static let turnBudgetMs = 2500
    static let watchdogSeconds = 4.0
    static let jevTimeout = 4.0
    static let lootPolls = 6
    static let lootPollSeconds = 0.5
    static let model = "jev-1.13.0"
    static let faceTolerance = 0.05
    static let healthDrop = 0.02
    static let probabilitySlack = 0.02
    static let boltFill = 0.75
    static let fillDrop = 0.3
    static let tab: UInt16 = 48
    // ponytail: set once from the bar's tooltips before a live run (applyRoles); sims keep these defaults,
    // the 24 Sept bar (keys 2, 3, 4 and 8).
    static var bolt: UInt16 = 19
    static var shock: UInt16 = 20
    static var heal: UInt16 = 21
    static var buff: UInt16 = 28
    static let turnLeft: UInt16 = 12
    static let forward: UInt16 = 13
    static let turnRight: UInt16 = 14
    static let interact: UInt16 = 101  // F9, Interact With Target (owner-consented bind): turns, walks, auto-attacks
    static let interactTurnSeconds = 0.4  // calibration knob: the turn before a forward tap cancels the walk
    // F10 and F11, Camera Zoom Out and In (owner-consented binds, 24 Sept). The widest view hid the NPCs' "?"
    // and "!" (owner, 25 Sept), and a new character starts at the client's near default (owner, 26 Sept: "our
    // default should be farer"). So a run sets its own zoom: F10 held to the widest view, from any zoom, then
    // F11 held `zoomInSeconds` back in (setZoom).
    static let zoomOut: UInt16 = 109, zoomIn: UInt16 = 103
    static let zoomOutSeconds = 2.5  // the widest view from any zoom (24 Sept)
    static var zoomInSeconds = 0.5  // calibration knob: set against the owner's zoom of 25-26 Sept
    static var releaseCodes: [UInt16] { [tab, bolt, heal, buff, shock, turnLeft, forward, turnRight, interact, zoomOut, zoomIn] }
}


struct Obs {
    var stamp: ObservationStamp? = nil
    var player = 0.0, mana = 0.0, target = 0.0
    var combat = false, casting = false, castFill = 0.0, rangeRed = false, buff = false, errorRed = false
    var shockRangeRed = false
    var plate: Plate? = nil
    var ground: Int? = nil
    var fresh = true  // false: no frame newer than maxFrameAge, so nothing above was seen
}

func hudCount(_ image: RGBA, x0: Int, x1: Int, y0: Int, y1: Int, _ pass: (Int, Int, Int) -> Bool) -> Int {
    guard image.pixels.count == image.width * image.height * 4 else { return 0 }
    let x0 = max(0, min(x0, image.width)), x1 = max(0, min(x1, image.width))
    let y0 = max(0, min(y0, image.height)), y1 = max(0, min(y1, image.height))
    var n = 0
    image.pixels.withUnsafeBufferPointer { pixels in
        for y in y0..<y1 {
            for x in x0..<x1 {
                let i = (y * image.width + x) * 4
                if pass(Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2])) { n += 1 }
            }
        }
    }
    return n
}

func observe(_ image: RGBA, plates: Bool) -> Obs {
    var o = Obs()
    o.player = Double(hudCount(image, x0: HUD.playerX0, x1: HUD.playerX1, y0: HUD.playerY, y1: HUD.playerY + 1, HUD.green))
        / Double(HUD.playerSpan)
    o.target = Double(hudCount(image, x0: HUD.targetX0, x1: HUD.targetX1, y0: HUD.targetY, y1: HUD.targetY + 1, HUD.green))
        / Double(HUD.targetSpan)
    let manaEnd = (HUD.manaX0..<HUD.manaX1).last { hudCount(image, x0: $0, x1: $0 + 1, y0: HUD.manaY, y1: HUD.manaY1, HUD.blue) > 0 }
    o.mana = manaEnd.map { Double($0 + 1 - HUD.manaX0) / Double(HUD.manaSpan) } ?? 0
    o.combat = hudCount(image, x0: HUD.combatX0, x1: HUD.combatX1, y0: HUD.combatY0, y1: HUD.combatY1, HUD.combatRed) > HUD.combatMin
    let yellow = hudCount(image, x0: HUD.castX0, x1: HUD.castX1, y0: HUD.castFillY, y1: HUD.castFillY + 1, HUD.castYellow)
    let track = hudCount(image, x0: HUD.castX0, x1: HUD.castX1, y0: HUD.castY0, y1: HUD.castY1, HUD.castTrack)
    o.casting = track > HUD.castTrackMin
    o.castFill = o.casting ? Double(yellow) / Double(HUD.castFillSpan) : 0
    o.rangeRed = hudCount(image, x0: HUD.rangeX0, x1: HUD.rangeX1, y0: HUD.rangeY0, y1: HUD.rangeY1, HUD.darkRedDigit) > HUD.rangeMin
    o.shockRangeRed = hudCount(image, x0: HUD.shockRangeX0, x1: HUD.shockRangeX1, y0: HUD.rangeY0, y1: HUD.rangeY1,
                               HUD.mutedRedDigit) > HUD.rangeMin
    o.buff = hudCount(image, x0: HUD.buffX0, x1: HUD.buffX1, y0: HUD.buffY0, y1: HUD.buffY1, HUD.buffGreen) > HUD.buffMin
    o.errorRed = hudCount(image, x0: HUD.errorX0, x1: HUD.errorX1, y0: HUD.errorY0, y1: HUD.errorY1, HUD.errorRed) > HUD.errorMin
    if plates {
        o.plate = findTargetPlate(image)
        o.ground = o.plate.flatMap { findGround(image, below: $0) }
    }
    return o
}

/// A move Jev can be offered: its name is the choice key and `facts` the criterion text.
protocol JevAction: RawRepresentable, CaseIterable, Equatable where RawValue == String {
    var facts: String { get }
}

enum FightAction: String, JevAction {
    case buffWeapon = "BUFF_WEAPON"
    case selectTarget = "SELECT_TARGET"
    case faceTarget = "FACE_TARGET"
    case approachToRange = "APPROACH_TO_RANGE"
    case castLightningBolt = "CAST_LIGHTNING_BOLT"
    case castShock = "CAST_SHOCK"
    case startMelee = "START_MELEE"
    case heal = "HEAL"
    case lootCorpse = "LOOT_CORPSE"
    case wait = "WAIT"
    case stop = "STOP"

    /// Copied verbatim from the live scratch's actionFacts.
    var facts: String {
        switch self {
        case .buffWeapon:
            return "Apply the character's weapon enchant (instant, costs mana). It adds damage to every melee swing and lasts 60 minutes once applied."
        case .selectTarget:
            return "Press Tab to select the nearest enemy creature in front of the character."
        case .faceTarget:
            return "Press Interact With Target: the game turns the character to face the selected target at once, even one behind it, and turns on automatic weapon swings; the walk it starts is cancelled, so the character stays put. Spells need the target in front of the character."
        case .approachToRange:
            return "Walk towards the target in short steps and stop as soon as it is within Lightning Bolt range, at the farthest distance the spell can be cast from."
        case .castLightningBolt:
            return "Cast Lightning Bolt at the target: about a 2-second cast from up to its range, roughly a third of a level-1 beast's health, costs about 15% mana. Once the target is adjacent, each hit taken pushes the cast back about 0.5-1 s, so a bolt in melee often takes 4 s or breaks and its mana is wasted. Choosing it while a cast is finishing queues the next cast without a gap."
        case .castShock:
            return "Cast the bar's shock spell at the target: instant, so hits cannot push it back; a shorter range than Lightning Bolt, and a cooldown after each use."
        case .startMelee:
            return "Press Interact With Target: turn on automatic weapon swings at the target, walking up to it if it is not adjacent. Swings land only while the target is adjacent to the character, continue with no further key presses, and with the weapon enchant each takes about a quarter of a level-1 beast's health. Costs no mana. A melee creature runs as fast as the character, so walking away from it only gives it free hits; Skysight's Elemental Blessing, when active, adds 10% run speed, under 1 yard a second: about 7 s of hits to leave its reach and 30 s to open Lightning Bolt range."
        case .heal:
            return "Cast Healing Wave on the character: about a 2-second cast that restores most of its health, costs mana, and is delayed by melee hits like any cast."
        case .lootCorpse:
            return "Right-click the dead target's corpse to collect its loot."
        case .wait:
            // For example while automatic swings or a cast in flight do their work.
            return "Do nothing for one second."
        case .stop:
            return "End the episode and return control to the owner: the goal is complete, or the situation is unsafe or unclear."
        }
    }

    static let preference: [FightAction] = [
        .buffWeapon, .selectTarget, .faceTarget, .approachToRange,
        .castLightningBolt, .castShock, .startMelee, .heal, .lootCorpse, .wait, .stop,
    ]
}

struct Episode: Equatable {
    var engaged = false
    var killed = false
    var looted = false
    var meleeOn = false
    var oldCorpse = false
    var lastShock: Double?  // when the shock was last cast: its cooldown runs from there

    static func alive(_ o: Obs) -> Bool { o.target > 0.005 || o.plate != nil }

    mutating func update(_ o: Obs) {
        if o.combat || (o.target > 0 && o.target < 0.99) { engaged = true }
        if engaged && !Self.alive(o) { killed = true }  // the combat ring lingers after a kill
    }
}

func offset(_ o: Obs) -> Double? {
    o.plate.map { ($0.centre - Double(HUD.width) / 2) / Double(HUD.width) }
}

/// Below playerSafety in combat the fight goes on and healing comes first (the owner, 23 Sept: a stop
/// there handed a fight to an owner who was away, and the character died standing still).
/// `kit` (the chain policy's bar) adds the shock while it is in range and its cooldown has run; the legacy
/// policy passes none and is offered what it always was.
func admissible(_ o: Obs, _ e: Episode, kit: FightKit? = nil, now: Double = 0) -> [FightAction] {
    if o.combat && o.player < FightLimits.playerSafety && o.mana >= FightLimits.healMana {
        return o.casting ? [.wait] : [.heal]
    }
    var out: [FightAction] = [.wait, .stop]
    if !o.buff && kit?.has(.buff) != false { out.append(.buffWeapon) }  // the legacy policy: always, as before
    let alive = Episode.alive(o)
    if !alive && !e.killed { out.append(.selectTarget) }  // a kill must be looted first
    if alive {
        if offset(o).map({ abs($0) > FightLimits.faceTolerance }) ?? true { out.append(.faceTarget) }  // no plate: maybe behind
        if o.rangeRed { out.append(.approachToRange) } else { out.append(.castLightningBolt) }
        if !e.meleeOn { out.append(.startMelee) }
        if let card = kit?.cards[.shock], !o.shockRangeRed, e.lastShock.map({ now - $0 >= card.cooldown ?? 6 }) ?? true {
            out.append(.castShock)
        }
    }
    if o.player < 0.95 { out.append(.heal) }
    if e.killed && !e.looted { out.append(.lootCorpse) }
    return out
}

func events(previous: Obs, current: Obs, errorText: String?) -> [String] {
    var out: [String] = []
    if current.player < previous.player - FightLimits.healthDrop {
        out.append("character lost \(Int((previous.player - current.player) * 100))% health since the last decision")
    }
    if current.target < previous.target - FightLimits.healthDrop {
        out.append("target lost \(Int((previous.target - current.target) * 100))% health since the last decision")
    }
    if current.errorRed {
        if let errorText, !errorText.isEmpty {
            out.append("game error message: \"\(errorText)\"")
        } else {
            out.append("a red game error message is showing")
        }
    }
    return out
}

func statePacket(obs o: Obs, episode e: Episode, lastAction: String, lastResult: String, events: [String]) -> [String: Any] {
    let character: [String: Any] = [
        "health_percent": Int(o.player * 100), "mana_percent": Int(o.mana * 100), "in_combat": o.combat,
        "casting_now": o.casting, "cast_progress_percent": Int(o.castFill * 100),
        "weapon_enchant_active": o.buff, "automatic_melee_swings_on": e.meleeOn,
    ]
    let target: [String: Any]
    if Episode.alive(o) {
        let position: String
        if let dx = offset(o) {
            position = abs(dx) <= FightLimits.faceTolerance ? "centred ahead" : (dx < 0 ? "left of centre" : "right of centre")
        } else {
            position = "nameplate not visible"
        }
        target = ["selected": true, "alive": true, "health_percent": Int(o.target * 100),
                  "within_lightning_bolt_range": !o.rangeRed, "position_in_view": position,
                  "nameplate_visible": o.plate != nil]
    } else {
        target = ["selected": false, "last_target_killed": e.killed, "corpse_looted": e.looted]
    }
    let last: [String: Any] = ["name": lastAction, "result": lastResult]
    let state: [String: Any] = [
        "goal": "Defeat one hostile creature with this shaman, collect its loot, and stay alive. Loot any corpse already waiting first. The owner is supervising.",
        "character": character, "target": target, "last_action": last, "events_since_last_decision": events,
    ]
    return state
}

let fightInstructions = "Choose the character's next action in this fight, using `character`, `target`, `last_action` and `events_since_last_decision`."

func actionQuestion<A: JevAction>(_ admissible: [A], instructions: String = fightInstructions) -> [String: Any] {
    var criteria: [String: String] = [:]
    for action in admissible { criteria[action.rawValue] = action.facts }
    let question: [String: Any] = [
        "type": "choice",
        "instructions": instructions,
        "criteria": criteria,
    ]
    return question
}

struct JevChoice<A: JevAction>: Equatable {
    let action: A
    let confidence: Double
    let probabilities: [String: Double]
}

func jsonDouble(_ value: Any) -> Double? {
    if let d = value as? Double { return d }
    if let i = value as? Int { return Double(i) }
    if let i = value as? Int64 { return Double(i) }
    return nil
}

func jsonMap(_ value: Any?) -> [String: Any]? {
    if let m = value as? [String: Any] { return m }
    if let m = value as? [String: Double] {
        var out: [String: Any] = [:]
        for (k, v) in m { out[k] = v }
        return out
    }
    if let m = value as? [String: Int] {
        var out: [String: Any] = [:]
        for (k, v) in m { out[k] = v }
        return out
    }
    return nil
}

struct NamedJevChoice {
    let name: String
    let confidence: Double
    let probabilities: [String: Double]
}

func parseNamedChoice(_ body: [String: Any], candidates: [String], model: String) -> NamedJevChoice? {
    guard let got = body["model"] as? String, got == model else { return nil }
    guard let answers = body["answers"] as? [String: Any],
          let a = answers["action"] as? [String: Any],
          let name = a["choice"] as? String else { return nil }
    guard candidates.contains(name) else { return nil }
    guard let rawConfidence = a["confidence"], let confidence = jsonDouble(rawConfidence),
          (0...1).contains(confidence) else { return nil }
    guard let raw = jsonMap(a["probabilities"]) else { return nil }
    let allowed = Set(candidates)
    guard Set(raw.keys) == allowed else { return nil }
    var probabilities: [String: Double] = [:]
    var sum = 0.0
    for (key, value) in raw {
        guard let p = jsonDouble(value), (0...1).contains(p) else { return nil }
        probabilities[key] = p
        sum += p
    }
    guard abs(sum - 1) <= FightLimits.probabilitySlack else { return nil }
    return NamedJevChoice(name: name, confidence: confidence, probabilities: probabilities)
}

func parseChoice<A: JevAction>(_ body: [String: Any], admissible: [A], model: String) -> JevChoice<A>? {
    guard let parsed = parseNamedChoice(body, candidates: admissible.map(\.rawValue), model: model),
          let action = A(rawValue: parsed.name) else { return nil }
    return JevChoice(action: action, confidence: parsed.confidence, probabilities: parsed.probabilities)
}

/// True when the text shares two 4-letter runs with a name (one for a 4-letter name). OCR read a
/// Juvenile Vuldren corpse as "Xypenil Uuldren"; a single shared run let "Yala Windwatcher" pass for
/// a Roiling Wind.
func fuzzyNameMatch(_ text: String, _ names: [String]) -> Bool {
    let letters = text.lowercased().filter(\.isLetter)
    return names.contains { name in
        let n = Array(name.lowercased().filter(\.isLetter))
        guard n.count >= 4 else { return false }
        let runs = (0...(n.count - 4)).filter { letters.contains(String(n[$0..<$0 + 4])) }.count
        return runs >= min(2, n.count - 3)
    }
}

struct CastWatch {
    var sawGap: Bool
    var seen = false
    var lastFill: Double

    init(pre: Obs) {
        sawGap = !pre.casting
        lastFill = pre.castFill
    }

    mutating func feed(_ o: Obs) {
        if !o.casting || o.castFill < lastFill - FightLimits.fillDrop { sawGap = true }
        lastFill = o.castFill
        if o.casting && sawGap { seen = true }
    }

    var reached75: Bool { seen && lastFill >= FightLimits.boltFill }
}

struct FightCommand: Equatable {
    enum Mode: String {
        case preflight = "--preflight", dryRun = "--dry-run", execute = "--execute"
    }
    let mode: Mode
    var profile: KeyProfile?
    var graph: String?  // the fight graph (M3b); none: the legacy flat policy
}

/// Parses everything before any effect. Missing or unknown arguments never default to input.
func parseFight(_ arguments: [String]) throws -> FightCommand {
    guard let first = arguments.first else { return FightCommand(mode: .preflight) }
    guard let mode = FightCommand.Mode(rawValue: first) else {
        throw ProbeError("unknown mode '\(first.prefix(40))'")
    }
    var command = FightCommand(mode: mode)
    var seen: Set<String> = []
    var rest = arguments.dropFirst()
    while let option = rest.popFirst() {
        guard mode != .preflight else { throw ProbeError("\(mode.rawValue) takes no arguments") }
        guard seen.insert(option).inserted, let value = rest.popFirst(), !value.hasPrefix("-") else {
            throw ProbeError("'\(option.prefix(40))' is repeated or has no value")
        }
        switch option {
        case "--graph":
            command.graph = value
        case "--keys" where mode == .execute:
            guard value == "wqe", let profile = KeyProfile(rawValue: value) else {
                throw ProbeError("--keys needs wqe, confirmed in-game")
            }
            command.profile = profile
        default:
            throw ProbeError("unexpected option '\(option.prefix(40))'")
        }
    }
    if mode == .execute {
        guard command.profile != nil else { throw ProbeError("--execute requires --keys wqe, confirmed in-game") }
    }
    return command
}

protocol FightHost: AnyObject {
    func now() -> Double
    func sleep(_ seconds: Double) async
    func observe(plates: Bool) -> Obs
    func perform(_ action: FightAction, observation: Obs, episode: inout Episode) async -> String
    func releaseBolt()
    func releaseAll()
    var holdingKeys: Bool { get }
    var walkedMs: Int { get }
    var turnedMs: Int { get }
    var codesPosted: [UInt16] { get }
    func wowFrontmost() -> Bool
    func refreshNotice() -> Bool
    func startCorpseVisible() -> Bool
    func errorText() -> String?
    func emit(_ event: String, _ fields: [String: Any])
}

extension FightHost {
    func readObservation() -> Observation<Obs> {
        let o = observe(plates: true)
        guard o.fresh, let stamp = o.stamp,
              stamp.isFresh(at: now(), maximumAge: FightLimits.maxFrameAge) else { return .unavailable("no_fresh_frame") }
        return .observed(o, stamp)
    }
}

protocol JevClient {
    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any]
}

struct FightResult {
    var outcome: String
    var decisions: Int
    var jevCalls: Int
    var latencies: [Double]
    var episode: Episode
    var walkedMs: Int
    var turnedMs: Int
    var holdingKeys: Bool
    var codesPosted: [UInt16]
    var jevRecords: [[String: Any]]
    var runtime: SkillResult? = nil
    var chainSteps = 0  // steps a chain Jev chose ran without a call (M3b)
}

func latencyPercentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let i = min(sorted.count - 1, Int((Double(sorted.count) * fraction).rounded(.down)))
    return sorted[i]
}

/// A missing frame is neither calm nor low health: on 24 Sept, twice, the capture went quiet after the
/// background loot click and the empty observation read as 0 % health. Wait for a fresh frame; nil if none.
func freshObservation(_ host: FightHost) async -> Obs? {
    var observation = host.readObservation()
    let start = host.now()
    while observation.value == nil && host.now() - start < FightLimits.freshWait {
        await host.sleep(0.1)
        observation = host.readObservation()
    }
    if host.now() > start { host.emit("frame_wait", ["seconds": host.now() - start, "fresh": observation.value != nil]) }
    return observation.value
}

/// A fight-graph failure as the fight's outcome, as the legacy policy names its own.
func fightGraphOutcome(_ error: Error) -> String {
    guard let error = error as? GraphError else { return "JEV_ERROR" }
    switch error {
    case .ownerStop: return "OWNER_TOOK_FOCUS"
    case .deadline: return "DECISION_EXPIRED"
    case .invalidReply: return "JEV_STOP"
    case .callLimit: return "DECISION_LIMIT"
    default: return "GRAPH_\(error)"
    }
}

/// `startHealth`: the least health a fight may start with. A hunt that is attacked passes 0.
/// `tactics` (M3b): Jev chooses a chain, a single skill or CONTINUE through the fight graph, and a chain's
/// steps then run without a call until a break returns it to Jev (Tactics.swift). Without it, the legacy
/// flat policy asks Jev before every step, as before. Both share every safety rule and check below.
func runFight(host: FightHost, jev: JevClient, startHealth: Double = FightLimits.startHealth,
              tactics: FightTactics? = nil) async -> FightResult {
    var episode = Episode()
    var lastAction = "none", lastResult = "episode start"
    var decisions = 0, jevCalls = 0, steps = 0, chainSteps = 0
    var latencies: [Double] = []
    var records: [[String: Any]] = []
    var outcome = "DECISION_LIMIT"
    var executive = RuntimeExecutive(goal: "one supervised fight")
    executive.begin("combat")
    var lastStamp: ObservationStamp?
    var running: ChainRun?            // the chain Jev chose, while it runs
    var tally = FightTally()
    var recent: [[String: Any]] = []  // this fight's steps, for READ:recent
    var ranOn: (obs: Obs, action: FightAction, at: Double)?  // the last step, until a newer frame shows what it did

    func finish(_ outcome: String) -> FightResult {
        host.releaseBolt()
        host.releaseAll()
        let skill = SkillResult(skill: "combat", status: skillStatus(outcome), code: outcome,
                                evidence: lastStamp, holdingInput: host.holdingKeys)
        executive.finish(skill)
        host.emit("skill_result", skill.json)
        return FightResult(outcome: outcome, decisions: decisions, jevCalls: jevCalls, latencies: latencies,
                           episode: episode, walkedMs: host.walkedMs, turnedMs: host.turnedMs,
                           holdingKeys: host.holdingKeys, codesPosted: host.codesPosted, jevRecords: records, runtime: skill,
                           chainSteps: chainSteps)
    }

    let graph: GraphSession?
    do { graph = try tactics?.session() } catch { return finish("GRAPH_DEFINITION") }
    if host.refreshNotice() { return finish("HOLD_REFRESH_NOTICE") }
    if host.startCorpseVisible() { episode.killed = true; episode.oldCorpse = true }

    guard var prev = await freshObservation(host) else { return finish("NO_FRESH_FRAME") }
    if prev.player < startHealth { return finish("HOLD_PLAYER_HEALTH") }
    episode.update(prev)

    loop: while decisions < FightLimits.maxDecisions && steps < FightLimits.maxSteps && host.now() < FightLimits.maxSeconds {
        if host.wowFrontmost() { outcome = "OWNER_TOOK_FOCUS"; break }
        guard let o = await freshObservation(host) else { outcome = "NO_FRESH_FRAME"; break }
        lastStamp = o.stamp
        episode.update(o)
        if let step = ranOn {  // what the last step did, now that a newer frame shows it
            tally.record(step.action, before: step.obs, after: o, seconds: host.now() - step.at, meleeOn: episode.meleeOn)
            running?.observe(before: step.obs, after: o, killed: episode.killed)
            ranOn = nil
        }
        tally.engage(o, now: host.now())
        if o.player < FightLimits.playerSafety && !o.combat { outcome = "SAFETY_STOP_PLAYER_BELOW_30"; break }

        let ev = events(previous: prev, current: o, errorText: o.errorRed ? host.errorText() : nil)
        let allowed = admissible(o, episode, kit: tactics?.kit, now: host.now())
        let action: FightAction
        let context: DecisionContext
        var controller = "JEV"
        var invalid = false
        let asked = host.now()
        let deadline = min(asked + FightLimits.jevTimeout, FightLimits.maxSeconds)
        if let tactics, let graph {
            guard let stamp = o.stamp else { return finish("NO_FRESH_FRAME") }
            let reason = running.flatMap { chainBreak($0, o, episode, allowed: allowed, lastResult: lastResult, now: asked) }
            if let run = running, reason == nil, let step = run.step {
                // Jev's chain goes on: the script runs its next step without a call.
                action = stepAction(step, episode)
                controller = "CHAIN"
                guard let c = executive.request(stamp: stamp, candidates: allowed.map(\.rawValue), policy: "chain:" + run.chain.id,
                        now: asked, maximumAge: FightLimits.maxFrameAge, deadline: deadline) else { return finish("NO_FRESH_FRAME") }
                context = c
            } else {
                let offers = fightOffers(o, episode, allowed: allowed, kit: tactics.kit, running: running)
                var state = statePacket(obs: o, episode: episode, lastAction: lastAction, lastResult: lastResult, events: ev)
                state["calculations"] = fightCalculations(o, episode, kit: tactics.kit, tally: tally, now: asked)
                state["chain"] = chainState(running, reason: reason)
                state["skills"] = tactics.kit.cards.values.sorted { $0.slot < $1.slot }.map(\.json)
                state["recent_steps"] = Array(recent.suffix(ChainLimits.recent))
                guard let c = executive.request(stamp: stamp, candidates: allowed.map(\.rawValue), policy: graph.graph.id,
                        now: asked, maximumAge: FightLimits.maxFrameAge, deadline: deadline) else { return finish("NO_FRESH_FRAME") }
                context = c
                let decision: GraphDecision
                do {
                    decision = try await graph.next(state: state, skills: Dictionary(uniqueKeysWithValues: offers.map { ($0.name, $0.text) }),
                                                    jev: jev, now: { host.now() }, deadline: deadline, stopped: { host.wowFrontmost() })
                } catch {
                    jevCalls += graph.lastTrace.count
                    host.emit("graph_error", ["error": "\(error)", "trace": graph.lastTrace])
                    outcome = fightGraphOutcome(error)
                    break
                }
                jevCalls += graph.lastTrace.count
                latencies += graph.lastTrace.compactMap { $0["latency_s"] as? Double }
                decisions += 1
                guard let offer = offers.first(where: { $0.name == decision.action }) else { outcome = "JEV_STOP"; break }
                if offer.name == "CONTINUE" { running?.resume(at: asked, health: o.player) }
                else { running = offer.chain.map { ChainRun($0, at: asked, health: o.player) } }
                guard let chosen = offer.action ?? running?.step.map({ stepAction($0, episode) }) else { outcome = "JEV_STOP"; break }
                action = chosen
                let record: [String: Any] = [
                    "decision": decisions, "t": asked, "offers": offers.map(\.name), "chosen": offer.name, "action": chosen.rawValue,
                    "asked_because": orNull(reason), "admissible": allowed.map(\.rawValue), "trace": graph.lastTrace, "context": c.json,
                ]
                records.append(record)
                host.emit("decision", record)
            }
        } else {
            let state = statePacket(obs: o, episode: episode, lastAction: lastAction, lastResult: lastResult, events: ev)
            let question = actionQuestion(allowed)
            guard let stamp = o.stamp, let c = executive.request(stamp: stamp, candidates: allowed.map(\.rawValue),
                    policy: "fight-legacy-v1", now: asked, maximumAge: FightLimits.maxFrameAge,
                    deadline: deadline) else { return finish("NO_FRESH_FRAME") }
            context = c
            let reply: [String: Any]
            do {
                reply = try await jev.ask(state: state, question: question)
                jevCalls += 1
            } catch {
                jevCalls += 1
                host.emit("jev_error", ["error": "\(error)"])
                outcome = "JEV_ERROR"
                break
            }
            let latency = host.now() - asked
            latencies.append(latency)
            decisions += 1
            let parsed = parseChoice(reply, admissible: allowed, model: FightLimits.model)
            action = parsed?.action ?? .stop
            invalid = parsed == nil
            if invalid { lastResult = "Jev answer failed validation" }
            let record: [String: Any] = [
                "decision": decisions, "t": asked, "state": state, "question": question,
                "admissible": allowed.map(\.rawValue), "response": reply, "latency_s": latency, "context": c.json,
            ]
            records.append(record)
            host.emit("decision", record)
        }
        prev = o
        lastAction = action.rawValue
        if action != .castLightningBolt { host.releaseBolt() }
        if invalid { outcome = "JEV_STOP"; break }
        let current = host.observe(plates: true)
        if current.fresh, current.player < FightLimits.playerSafety, !current.combat {
            return finish("SAFETY_STOP_PLAYER_BELOW_30")
        }
        if let rejection = executive.rejection(DecisionProposal(context: context, action: action.rawValue),
                current: current.fresh ? current.stamp : nil,
                candidates: admissible(current, episode, kit: tactics?.kit, now: host.now()).map(\.rawValue),
                now: host.now(), maximumAge: FightLimits.maxFrameAge, ownerStopped: host.wowFrontmost()) {
            host.releaseBolt()
            host.emit("proposal_rejected", ["reason": rejection, "request": context.request])
            if rejection == "owner_stop" { return finish("OWNER_TOOK_FOCUS") }
            if rejection == "decision_expired" { return finish("DECISION_EXPIRED") }
            lastResult = "not done: " + rejection
            running = nil  // the frame the chain relied on is gone: Jev chooses again on the next one
            continue
        }
        lastStamp = current.stamp
        let started = host.now()
        lastResult = await host.perform(action, observation: current, episode: &episode)
        steps += 1
        if tactics != nil {
            if controller == "CHAIN" { chainSteps += 1 }
            running?.ran += 1
            if action == .castShock && !stepFailed(lastResult) { episode.lastShock = started }
            ranOn = (current, action, started)
            recent.append(["step": action.rawValue, "controller": controller, "chain": orNull(running?.chain.id), "result": lastResult])
            host.emit("acted", ["action": action.rawValue, "result": lastResult, "controller": controller,
                                "chain": orNull(running?.chain.id)])
        } else {
            host.emit("acted", ["action": action.rawValue, "result": lastResult])
        }
        switch action {
        case .lootCorpse:
            if episode.looted { outcome = "KILLED_AND_LOOTED" }
            if episode.looted && episode.oldCorpse {
                episode.oldCorpse = false
                episode.killed = false
                episode.looted = false
                episode.engaged = false
                episode.meleeOn = false
                outcome = "DECISION_LIMIT"
                continue
            }
            if !episode.looted && lastResult.hasPrefix("no corpse") {
                // Our own kill with no corpse label to click (an elemental leaves none; a far corpse's
                // name is too small to read): the kill stands. Live, Jev otherwise tried LOOT 20 times.
                if !episode.oldCorpse { outcome = "KILLED_NO_CORPSE"; break loop }
                episode.killed = false
                episode.oldCorpse = false
            }
            if episode.looted { break loop }
        case .stop:
            outcome = "JEV_STOP"
            break loop
        default: break
        }
    }
    return finish(outcome)
}

/// Injected clock: tests and the dry-run advance instantly; the live shell supplies wall time.
final class FightClock {
    private let live: (() -> Double)?
    private let pace: Double
    var t = 0.0
    /// `pace` adds a short real sleep to each fake sleep, as M0/M1's dry-runs stall their observer:
    /// a SIGINT then lands inside the loop instead of racing the process's normal exit.
    init(live: (() -> Double)? = nil, pace: Double = 0) { self.live = live; self.pace = pace }
    func now() -> Double { live?() ?? t }
    func sleep(_ seconds: Double) async {
        if live != nil {
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        } else {
            t += seconds
            if pace > 0 { try? await Task.sleep(nanoseconds: UInt64(pace * 1_000_000_000)) }
        }
    }
}

/// Deterministic world for tests and the dry-run: target starts out of range, approaches,
/// takes about a third per bolt, melee about a quarter, dies, corpse lootable.
final class SimFight: FightHost {
    let clock: FightClock
    var emitHandler: Emit = { _, _ in }
    var stalls = 0  // observations with no fresh frame still to come
    var player = 1.0
    var mana = 1.0
    var targetHP = 0.0
    var selected = false
    var combat = false
    var casting = false
    var castFill = 0.0
    var rangeRed = false
    var buff = false
    var errorRed = false
    var plateX: Double?
    var groundRow: Int?
    var corpseLootable = false
    var leavesCorpse = true
    var boltHeld = false
    var boltGrant: HeldKey?
    var down: Set<UInt16> = []
    /// SIGINT calls releaseAll on the signal queue while the loop presses keys: key state is locked,
    /// as in LiveHost (an unlocked Set mutated from two threads crashed the dry-run on CI, exit -11).
    private let keyLock = NSLock()
    private var cancelled = false  // set by releaseAll: no key goes down after the exit sweep
    private func withKeys<T>(_ body: () -> T) -> T { keyLock.lock(); defer { keyLock.unlock() }; return body() }
    var performed: [FightAction] = []
    var walkedMs = 0
    var turnedMs = 0
    var codesPosted: [UInt16] = []
    var wowIsFront = false
    var refreshOpen = false
    var startCorpse = false
    var errorMessage: String?
    // M3b's fights, off by default so the legacy checks keep their world: the creature reaches the
    // character after this many bolts and then hits it each step, and casts spend mana.
    var closesAfterBolts: Int?
    var hitPerStep = 0.05
    var spendsMana = false
    var damageScale = 1.0  // below 1: a tougher creature, for a chain that must check in
    private var bolts = 0

    init(clock: FightClock) { self.clock = clock }

    func now() -> Double { clock.now() }
    func sleep(_ seconds: Double) async {
        await clock.sleep(seconds)
        expireWatchdog()
    }

    func expireWatchdog() {
        let t = now()
        guard let grant = withKeys({ boltGrant }), grant.expired(now: t) else { return }
        releaseBolt()
        emit("watchdog", ["released": Int(grant.code)])
    }

    func holdBolt() {
        var grant = HeldKey(code: FightLimits.bolt, until: 0)
        grant.refresh(now: now())
        let pressed: Bool = withKeys {
            guard !cancelled else { return false }
            boltHeld = true
            down.insert(FightLimits.bolt)
            boltGrant = grant
            return true
        }
        if pressed { codesPosted.append(FightLimits.bolt) }
    }
    func emit(_ event: String, _ fields: [String: Any]) { emitHandler(event, fields) }
    var holdingKeys: Bool { withKeys { boltHeld || !down.isEmpty } }
    func wowFrontmost() -> Bool { wowIsFront }
    func refreshNotice() -> Bool { refreshOpen }
    func startCorpseVisible() -> Bool { startCorpse }
    func errorText() -> String? { errorMessage }

    func observe(plates: Bool) -> Obs {
        if stalls > 0 { stalls -= 1; return Obs(fresh: false) }
        var o = Obs()
        o.stamp = ObservationStamp(stream: "sim-fight", geometry: "sim-layout", capturedAt: now())
        o.player = player
        o.mana = mana
        o.target = selected ? targetHP : 0
        o.combat = combat
        o.casting = casting
        o.castFill = castFill
        o.rangeRed = selected && targetHP > 0.005 && rangeRed
        o.shockRangeRed = o.rangeRed  // ponytail: one distance band; the shock's shorter reach is not simulated
        o.buff = buff
        o.errorRed = errorRed
        if plates, selected, targetHP > 0.005, let x = plateX {
            let half = 66
            o.plate = Plate(x0: Int(x) - half, x1: Int(x) + half, top: 400, bottom: 413)
            o.ground = groundRow
        }
        return o
    }

    func releaseBolt() {
        withKeys {
            boltHeld = false
            down.remove(FightLimits.bolt)
            boltGrant = nil
        }
    }

    func releaseAll() {
        withKeys {
            cancelled = true
            boltHeld = false
            down.removeAll()
            boltGrant = nil
        }
    }

    private func press(_ code: UInt16) -> Bool {
        withKeys {
            guard !cancelled else { return false }
            down.insert(code)
            return true
        }
    }

    private func tap(_ code: UInt16) async {
        guard press(code) else { return }
        codesPosted.append(code)
        await sleep(0.06)
        withKeys { _ = down.remove(code) }
    }

    private func hold(_ code: UInt16, _ ms: Int) async {
        guard press(code) else { return }
        codesPosted.append(code)
        if code == FightLimits.forward { walkedMs += ms } else { turnedMs += ms }
        await sleep(Double(ms) / 1000)
        withKeys { _ = down.remove(code) }
    }

    private func strike(_ amount: Double) {
        targetHP = max(0, targetHP - amount * damageScale)
        combat = true
        if targetHP <= 0.005 {
            targetHP = 0
            selected = false
            plateX = nil
            corpseLootable = leavesCorpse
        }
    }

    func perform(_ action: FightAction, observation: Obs, episode: inout Episode) async -> String {
        performed.append(action)
        let result = await act(action, &episode)
        if let n = closesAfterBolts, bolts >= n, selected, targetHP > 0, action != .stop { player = max(0, player - hitPerStep) }
        return result
    }

    private func spend(_ amount: Double) { if spendsMana { mana = max(0, mana - amount) } }

    private func act(_ action: FightAction, _ episode: inout Episode) async -> String {
        switch action {
        case .buffWeapon:
            await tap(FightLimits.buff)
            await sleep(0.2)
            buff = true
            return "enchant active"
        case .selectTarget:
            await tap(FightLimits.tab)
            await sleep(0.2)
            episode.meleeOn = false
            selected = true
            targetHP = 1.0
            rangeRed = true
            plateX = 1000
            groundRow = 700
            return "a target is selected"
        case .faceTarget:
            await tap(FightLimits.interact)
            episode.meleeOn = true
            plateX = Double(HUD.width) / 2
            return "faced the target; automatic swings on"
        case .approachToRange:
            await hold(FightLimits.forward, 250)
            rangeRed = false
            return "within Lightning Bolt range"
        case .castLightningBolt:
            holdBolt()
            bolts += 1
            spend(0.07)
            strike(1.0 / 3)
            return "Lightning Bolt cast at 75 %; the key stays held, so the next cast follows unless another action is chosen"
        case .castShock:
            await tap(FightLimits.shock)
            spend(0.14)
            strike(0.2)
            return "the shock spell was cast"
        case .startMelee:
            await tap(FightLimits.interact)
            episode.meleeOn = true
            strike(0.25)
            return "automatic swings on"
        case .heal:
            await tap(FightLimits.heal)
            spend(0.11)
            player = 1.0
            return "Healing Wave cast at 75 % and finishing"
        case .lootCorpse:
            if corpseLootable {
                episode.looted = true
                corpseLootable = false
                return "looted: You loot 1 copper"
            }
            return "no corpse label visible"
        case .wait:
            await sleep(1)
            if episode.meleeOn && selected && targetHP > 0 { strike(0.25) }
            return "waited one second"
        case .stop:
            return "stop"
        }
    }
}

struct ScriptedJev<A: JevAction>: JevClient {
    var preference: [A]

    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let criteria = question["criteria"] as? [String: Any] ?? [:]
        let allowed = A.allCases.filter { criteria[$0.rawValue] != nil }
        guard let choice = preference.first(where: allowed.contains) ?? allowed.first else {
            throw ProbeError("no admissible action offered")
        }
        var probabilities: [String: Any] = [:]
        let n = Double(max(1, allowed.count))
        for action in allowed { probabilities[action.rawValue] = 1 / n }
        let action: [String: Any] = ["choice": choice.rawValue, "confidence": 1.0, "probabilities": probabilities]
        let answers: [String: Any] = ["action": action]
        let body: [String: Any] = ["model": FightLimits.model, "answers": answers]
        return body
    }
}

extension ScriptedJev where A == FightAction {
    init() { preference = FightAction.preference }
}

/// Canned fight-graph replies for the dry-run and the checks: the first preferred option on offer.
struct ScriptedGraphJev: JevClient {
    var preference: [String]

    func ask(state: [String: Any], question: [String: Any]) async throws -> [String: Any] {
        let offered = (question["criteria"] as? [String: Any] ?? [:]).keys.sorted()
        guard let choice = preference.first(where: offered.contains) ?? offered.first else { throw ProbeError("nothing offered") }
        let p = 1 / Double(offered.count)
        let action: [String: Any] = ["choice": choice, "confidence": 1.0,
                                     "probabilities": Dictionary(uniqueKeysWithValues: offered.map { ($0, p) })]
        return ["model": FightLimits.model, "answers": ["action": action]]
    }

    /// Buff, target, close in, then the first chain, going on with it at every break that allows.
    static let dryRun = ScriptedGraphJev(preference: ["READ:skills", "DO:LOOT_CORPSE", "DO:BUFF_WEAPON", "DO:SELECT_TARGET",
                                                      "DO:APPROACH_TO_RANGE", "DO:CONTINUE", "DO:CHAIN_1", "DO:WAIT"])
}

/// One main-bar slot, read from its tooltip. The owner, 24 Sept: the engine sees and organises the
/// skills as a human does, never a hard-coded slot (3 was Earth Shock and 4 Healing Wave by level 5).
struct Skill: Equatable {
    var name: String
    var text: String
    var cast: Double?  // seconds; nil when instant or an item
    var rank: Int? = nil  // matches the skills dictionary's row
}

enum SkillRole: String, CaseIterable { case melee, bolt, shock, heal, buff, drink, food }

enum SkillHUD {
    static let keys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29, 27, 24]  // 1-9, 0, -, =
    static let names = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-", "="]
    static let slot1X = 660.0, pitch = 50.3, slotY = 1290.0  // slot centres, 24 Sept bar
}

// MARK: - Working memory: the skill bar (the owner, 25 Sept: remember what was read, to cut rescans)

extension Skill: Codable {}

/// Each slot's icon as a 3 x 3 grid of mean colours (27 values), from the 30 px square at its centre.
/// Reading the whole bar hovers twelve tooltips, about 8 s a run (live, 25 Sept).
struct BarPrint: Codable, Equatable {
    var slots: [[Int]]
}

func barPrint(_ image: RGBA) -> BarPrint {
    BarPrint(slots: SkillHUD.names.indices.map { i in
        let cx = Int(SkillHUD.slot1X + SkillHUD.pitch * Double(i)), cy = Int(SkillHUD.slotY)
        var cells: [Int] = []
        for gy in 0..<3 {
            for gx in 0..<3 {
                var sum = [0, 0, 0], n = 0
                for y in (cy - 15 + 10 * gy)..<(cy - 5 + 10 * gy) where y >= 0 && y < image.height {
                    for x in (cx - 15 + 10 * gx)..<(cx - 5 + 10 * gx) where x >= 0 && x < image.width {
                        let p = (y * image.width + x) * 4
                        for c in 0..<3 { sum[c] += Int(image.pixels[p + c]) }
                        n += 1
                    }
                }
                cells += sum.map { n > 0 ? $0 / n : 0 }
            }
        }
        return cells
    })
}

/// The slots whose icon differs from the remembered one by more than `tolerance` per value on average (a
/// cooldown's shade or the pointer's highlight counts as a change: the slot is read again, never wrongly kept).
func changedSlots(_ old: BarPrint, _ new: BarPrint, tolerance: Int = 12) -> [Int] {
    new.slots.indices.filter { i in
        guard i < old.slots.count, old.slots[i].count == new.slots[i].count else { return true }
        return zip(old.slots[i], new.slots[i]).map { abs($0 - $1) }.reduce(0, +) > tolerance * new.slots[i].count
    }
}

/// What was read of the bar, how it looked then, and when (seconds since 1970).
struct BarMemory: Codable {
    var print: BarPrint
    var skills: [Skill?]
    var readAt: Double
}

/// How long a memory is trusted: a rank learnt at a trainer keeps its icon, so an instant spell's card
/// (rank, mana, damage) could stay old for good (review, 26 Sept). After an hour the whole bar is read.
let barMemoryAge = 3600.0

/// The slots to hover first: every changed one, and every remembered spell with a cast time (the bolt's and
/// the heal's roles come from their cast, and those cards matter most). No memory, a memory an hour old or
/// a bar of another size: all twelve.
func slotsToRead(_ memory: BarMemory?, _ now: BarPrint, at time: Double) -> [Int] {
    guard let memory, memory.skills.count == now.slots.count, time - memory.readAt < barMemoryAge, time >= memory.readAt
    else { return Array(now.slots.indices) }
    let changed = Set(changedSlots(memory.print, now))
    return now.slots.indices.filter { changed.contains($0) || memory.skills[$0]?.cast != nil }
}

/// When a saved memory counts from: the hour runs from the last full read, so a memory kept run after run
/// still expires.
func memoryReadAt(full: Bool, now: Double, previous: Double?) -> Double { full ? now : previous ?? now }

/// Whether the memory still holds: every checked slot that kept its icon read as remembered. Otherwise the
/// whole bar is read again.
func memoryHolds(_ memory: BarMemory, read: [Int: Skill?], changed: Set<Int>) -> Bool {
    read.allSatisfy { i, skill in changed.contains(i) || memory.skills[i] == skill }
}

/// The owner, 24 Sept: "should detect 'you are not face the mob' to trigger F9". Zoomed out, an adjacent
/// creature's nameplate sits mid-screen whichever way the character faces, so the game's own error is
/// the signal. Turning is a reflex inside the cast, not one of Jev's decisions.
func facingError(_ errorText: String?) -> Bool {
    guard let text = errorText?.lowercased() else { return false }
    return text.contains("in front of you") || text.contains("facing")
}

/// Both casts' rule for that reflex: a cast that did not go off (no 75 % bolt, no shock mana spent) while the
/// game's facing error is on screen turns with F9 and tries once more.
func turnAndRetry(_ result: String, _ errorText: String?) -> Bool {
    !(result.contains("cast at 75") || result.contains("cast (mana")) && facingError(errorText)
}

/// The beta client's tooltip footer ("Press F6 to submit an issue for this Item"); OCR once read "Press Forto".
func isTooltipFooter(_ text: String) -> Bool { text.contains("submit an issue") }

/// OCR boxes (text, left x, top y, in pixels) to tooltip lines, top to bottom: only lines aligned with
/// the "Press F6" footer's left edge or in the right-hand column, so world text above the tooltip (a
/// nameplate read as slot 8's name, 24 Sept) is dropped.
func tooltipLines(_ boxes: [(text: String, x: Double, y: Double)]) -> [String] {
    guard let foot = boxes.first(where: { isTooltipFooter($0.text) }) else { return [] }
    return boxes.filter { $0.y <= foot.y && (abs($0.x - foot.x) <= 8 || $0.x >= foot.x + 150) }
        .sorted { ($0.y, $0.x) < ($1.y, $1.x) }.map(\.text)
}

/// Tooltip lines top to bottom (a rank or "Racial" sits beside the name); nil for an empty slot.
func parseTooltip(_ lines: [String]) -> Skill? {
    guard lines.contains(where: isTooltipFooter) else { return nil }
    let body = lines.filter { !isTooltipFooter($0) && !$0.hasPrefix("Rank ") && $0 != "Racial" }
    guard let name = body.first else { return nil }
    let text = body.dropFirst().joined(separator: " ")
    let cast = text.range(of: #"[0-9.]+(?= sec cast)"#, options: .regularExpression).flatMap { Double(text[$0]) }
    let rank = lines.first { $0.hasPrefix("Rank ") }.flatMap { Int($0.dropFirst(5)) }
    return Skill(name: name, text: text, cast: cast, rank: rank)
}

// ponytail: Shaman level-5 keywords; other classes add theirs here.
func role(_ s: Skill) -> SkillRole? {
    let t = s.text.lowercased()
    if s.name == "Attack" { return .melee }
    if t.contains("use: restores") { return t.contains(" mana") ? .drink : t.contains(" health") ? .food : nil }
    if s.cast != nil && t.contains("heals") { return .heal }
    if s.cast != nil && t.contains("damage") && t.contains("yd range") { return .bolt }
    if s.cast == nil && t.contains("damage") && t.contains("yd range") && t.contains("cooldown") { return .shock }
    if t.contains("imbue") { return .buff }
    return nil
}

/// Interact With Target (F9) turns, attacks and walks, so a fight needs no Attack slot; a hunt adds food and drink.
// A weapon enchant is not required: a level-1 Shaman has none (live, 26 Sept). Without it on the bar the
// chain policy is not offered BUFF_WEAPON, and no chain that needs it.
let fightRoles: [SkillRole] = [.bolt, .heal]
let huntRoles = fightRoles + [.drink, .food]

/// The first slot of each role; problems name what a live run must not start without.
func assignRoles(_ bar: [Skill?], required: [SkillRole] = huntRoles) -> (keys: [SkillRole: UInt16], problems: [String]) {
    var keys: [SkillRole: UInt16] = [:], problems: [String] = []
    let names = bar.compactMap { $0?.name }
    if Set(names).count != names.count { problems.append("one tooltip on two slots (was the pointer moved?)") }
    for (i, skill) in bar.enumerated() where i < SkillHUD.keys.count {
        if let skill, let r = role(skill), keys[r] == nil { keys[r] = SkillHUD.keys[i] }
    }
    problems += required.filter { keys[$0] == nil }.map { "no \($0.rawValue) skill on the bar" }
    return (keys, problems)
}

func applyRoles(_ keys: [SkillRole: UInt16]) {
    FightLimits.bolt = keys[.bolt] ?? FightLimits.bolt
    FightLimits.heal = keys[.heal] ?? FightLimits.heal
    FightLimits.buff = keys[.buff] ?? FightLimits.buff
    FightLimits.shock = keys[.shock] ?? FightLimits.shock
    if let i = SkillHUD.keys.firstIndex(of: FightLimits.bolt) {
        HUD.rangeX0 = 716 + Int((Double(i - 1) * SkillHUD.pitch).rounded())
        HUD.rangeX1 = HUD.rangeX0 + 16
    }
    if let i = SkillHUD.keys.firstIndex(of: FightLimits.shock) {
        HUD.shockRangeX0 = 716 + Int((Double(i - 1) * SkillHUD.pitch).rounded())
        HUD.shockRangeX1 = HUD.shockRangeX0 + 16
    }
}
