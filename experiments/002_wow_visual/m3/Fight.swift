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
    static let castX0 = 1172, castX1 = 1388, castY0 = 1200, castY1 = 1210
    static let castFillY = 1205, castFillSpan = 216, castTrackMin = 300
    /// Slot-2 hotkey digit: dark-red when Lightning Bolt is out of range.
    static let rangeX0 = 708, rangeX1 = 734, rangeY0 = 1270, rangeY1 = 1292, rangeMin = 4
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
    static func buffGreen(_ r: Int, _ g: Int, _ b: Int) -> Bool { g > 120 && g > r + 20 && g > b + 20 }
    static func errorRed(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 180 && r > g + 70 && r > b + 70 && g > 50 }
}

enum FightLimits {
    static let maxDecisions = 40
    static let maxSeconds = 150.0
    static let playerSafety = 0.3
    static let healMana = 0.15  // below playerSafety in combat, HEAL alone is offered while mana lasts
    static let startHealth = 0.9
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
    static let melee: UInt16 = 18
    static let bolt: UInt16 = 19
    static let heal: UInt16 = 20
    static let buff: UInt16 = 21
    static let turnLeft: UInt16 = 12
    static let forward: UInt16 = 13
    static let turnRight: UInt16 = 14
    static let releaseCodes: [UInt16] = [48, 18, 19, 20, 21, 12, 13, 14]
}

/// Watchdog grant for one held key. Refresh while the skill still needs it; expired(now:)
/// is the timer's only decision. The grant stays until a confirmed key-up.
struct HeldKey: Equatable {
    var code: UInt16
    var until: Double

    mutating func refresh(now: Double, hold: Double = FightLimits.watchdogSeconds) {
        until = now + hold
    }

    func expired(now: Double) -> Bool { now > until }
}

/// Key-up with M0's retry-and-keep-held rule. False means the caller keeps the grant.
func confirmKeyUp(_ code: UInt16, sink: KeySink, emit: Emit) -> Bool {
    for attempt in 1...Limits.releaseAttempts {
        do {
            try sink.post(code, down: false)
            emit("key_up", ["code": Int(code), "attempt": attempt])
            return true
        } catch {
            emit("key_up_failed", ["code": Int(code), "attempt": attempt, "error": "\(error)"])
        }
    }
    emit("release_unconfirmed", ["code": Int(code)])
    return false
}

/// Key state of the live shells (M3 fight, M4 walk; SimNav drives it with a fake sink). The grant
/// is taken before the post, as InputLease does, so a partly delivered down is still released;
/// posts happen under one lock and stop once releaseAll has run, so a down cannot land after the
/// SIGINT sweep; a held key with a watchdog grant is lifted by sweepExpired once the grant lapses.
/// A key-up that failed every attempt is retried by the next sweep, and no grant can postpone that.
/// Events are emitted after the lock is released: a blocked log write never holds up the exit sweep.
final class LiveKeys {
    private let sink: KeySink
    private let releaseCodes: [UInt16]
    private let clock: () -> Double
    var emit: Emit  // set once, before any other thread can release
    private let lock = NSLock()
    private var held: Set<UInt16> = []
    private var grants: [UInt16: HeldKey] = [:]
    private var releasing: Set<UInt16> = []  // key-ups that failed; the sweep retries them
    private var cancelled = false
    private var posted: [UInt16] = []
    private var pending: [(String, [String: Any])] = []  // events noted under the lock

    init(sink: KeySink, releaseCodes: [UInt16], clock: @escaping () -> Double, emit: @escaping Emit = { _, _ in }) {
        self.sink = sink
        self.releaseCodes = releaseCodes
        self.clock = clock
        self.emit = emit
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        let value = body()
        let events = pending
        pending.removeAll()
        lock.unlock()
        for (event, fields) in events { emit(event, fields) }
        return value
    }

    private func note(_ event: String, _ fields: [String: Any]) { pending.append((event, fields)) }  // under the lock

    /// Key-up under the lock. A failure leaves the key held with an expired grant, so the next sweep retries it.
    private func up(_ code: UInt16) -> Bool {
        guard confirmKeyUp(code, sink: sink, emit: note) else {
            releasing.insert(code)
            grants[code] = HeldKey(code: code, until: -.infinity)
            return false
        }
        held.remove(code)
        releasing.remove(code)
        grants[code] = nil
        return true
    }

    var holding: Bool { locked { !held.isEmpty } }
    var codesPosted: [UInt16] { locked { posted } }
    func isDown(_ code: UInt16) -> Bool { locked { held.contains(code) } }

    /// False once releaseAll has run: nothing was posted.
    @discardableResult
    func press(_ code: UInt16) -> Bool {
        locked {
            guard !cancelled else { return false }
            held.insert(code)
            releasing.remove(code)
            do { try sink.post(code, down: true) } catch {
                note("key_down_failed", ["code": Int(code), "error": "\(error)"])
            }
            posted.append(code)
            return true
        }
    }

    /// Keep the key and its grant until a key-up posts. `listed` posts the up even if not held.
    func lift(_ code: UInt16, listed: Bool = false) {
        locked {
            guard held.contains(code) || listed else { return }
            _ = up(code)
        }
    }

    /// Start or refresh the watchdog for a held key; not for one whose key-up is being retried.
    func grant(_ code: UInt16, seconds: Double) {
        locked {
            guard !releasing.contains(code) else { return }
            var grant = HeldKey(code: code, until: 0)
            grant.refresh(now: clock(), hold: seconds)
            grants[code] = grant
        }
    }

    /// The watchdog's tick: lift every held key whose grant has lapsed. Decided and lifted under
    /// the lock, so a refresh cannot slip in between.
    func sweepExpired() {
        let now = clock()
        let released: [UInt16] = locked {
            var out: [UInt16] = []
            for (code, grant) in grants where grant.expired(now: now) {
                guard held.contains(code) else { grants[code] = nil; continue }
                if up(code) { out.append(code) }
            }
            return out
        }
        for code in released { emit("watchdog", ["released": Int(code)]) }
    }

    /// The exit sweep: no key goes down afterwards, and every listed code gets a key-up. All the key-ups
    /// post under one hold of the lock before any event is logged: a log write blocked on stdout must
    /// not keep W down behind Q's event.
    func releaseAll() {
        locked {
            cancelled = true
            for code in releaseCodes { _ = up(code) }
        }
    }
}

struct Obs {
    var player = 0.0, mana = 0.0, target = 0.0
    var combat = false, casting = false, castFill = 0.0, rangeRed = false, buff = false, errorRed = false
    var plate: Plate? = nil
    var ground: Int? = nil
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
            return "Turn on the spot until the selected target is centred ahead. Spells need the target in front of the character."
        case .approachToRange:
            return "Walk towards the target in short steps and stop as soon as it is within Lightning Bolt range, at the farthest distance the spell can be cast from."
        case .castLightningBolt:
            return "Cast Lightning Bolt at the target: about a 2-second cast from up to its range, roughly a third of a level-1 beast's health, costs about 15% mana. Once the target is adjacent, each hit taken pushes the cast back about 0.5-1 s, so a bolt in melee often takes 4 s or breaks and its mana is wasted. Choosing it while a cast is finishing queues the next cast without a gap."
        case .startMelee:
            return "Turn on automatic weapon swings at the target. Swings land only while the target is adjacent to the character, continue with no further key presses, and with the weapon enchant each takes about a quarter of a level-1 beast's health. Costs no mana. A melee creature runs as fast as the character, so walking away from it only gives it free hits; Skysight's Elemental Blessing, when active, adds 10% run speed, under 1 yard a second: about 7 s of hits to leave its reach and 30 s to open Lightning Bolt range."
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
        .castLightningBolt, .startMelee, .heal, .lootCorpse, .wait, .stop,
    ]
}

struct Episode: Equatable {
    var engaged = false
    var killed = false
    var looted = false
    var meleeOn = false
    var oldCorpse = false

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
func admissible(_ o: Obs, _ e: Episode) -> [FightAction] {
    if o.combat && o.player < FightLimits.playerSafety && o.mana >= FightLimits.healMana {
        return o.casting ? [.wait] : [.heal]
    }
    var out: [FightAction] = [.wait, .stop]
    if !o.buff { out.append(.buffWeapon) }
    let alive = Episode.alive(o)
    if !alive && !e.killed { out.append(.selectTarget) }  // a kill must be looted first
    if alive {
        if let dx = offset(o), abs(dx) > FightLimits.faceTolerance { out.append(.faceTarget) }
        if o.rangeRed { out.append(.approachToRange) } else { out.append(.castLightningBolt) }
        if !e.meleeOn { out.append(.startMelee) }
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

func parseChoice<A: JevAction>(_ body: [String: Any], admissible: [A], model: String) -> JevChoice<A>? {
    guard let got = body["model"] as? String, got == model else { return nil }
    guard let answers = body["answers"] as? [String: Any],
          let a = answers["action"] as? [String: Any],
          let name = a["choice"] as? String else { return nil }
    guard let action = A(rawValue: name), admissible.contains(action) else { return nil }
    guard let rawConfidence = a["confidence"], let confidence = jsonDouble(rawConfidence),
          (0...1).contains(confidence) else { return nil }
    guard let raw = jsonMap(a["probabilities"]) else { return nil }
    let allowed = Set(admissible.map(\.rawValue))
    guard Set(raw.keys) == allowed else { return nil }
    var probabilities: [String: Double] = [:]
    var sum = 0.0
    for (key, value) in raw {
        guard let p = jsonDouble(value), (0...1).contains(p) else { return nil }
        probabilities[key] = p
        sum += p
    }
    guard abs(sum - 1) <= FightLimits.probabilitySlack else { return nil }
    return JevChoice(action: action, confidence: confidence, probabilities: probabilities)
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
        guard mode == .execute else { throw ProbeError("\(mode.rawValue) takes no arguments") }
        guard seen.insert(option).inserted, let value = rest.popFirst(), !value.hasPrefix("-") else {
            throw ProbeError("'\(option.prefix(40))' is repeated or has no value")
        }
        switch option {
        case "--keys":
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
}

func latencyPercentile(_ values: [Double], _ fraction: Double) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    let i = min(sorted.count - 1, Int((Double(sorted.count) * fraction).rounded(.down)))
    return sorted[i]
}

/// `startHealth`: the least health a fight may start with. A hunt that is attacked passes 0.
func runFight(host: FightHost, jev: JevClient, startHealth: Double = FightLimits.startHealth) async -> FightResult {
    var episode = Episode()
    var lastAction = "none", lastResult = "episode start"
    var decisions = 0, jevCalls = 0
    var latencies: [Double] = []
    var records: [[String: Any]] = []
    var outcome = "DECISION_LIMIT"

    func finish(_ outcome: String) -> FightResult {
        host.releaseBolt()
        host.releaseAll()
        return FightResult(outcome: outcome, decisions: decisions, jevCalls: jevCalls, latencies: latencies,
                           episode: episode, walkedMs: host.walkedMs, turnedMs: host.turnedMs,
                           holdingKeys: host.holdingKeys, codesPosted: host.codesPosted, jevRecords: records)
    }

    if host.refreshNotice() { return finish("HOLD_REFRESH_NOTICE") }
    if host.startCorpseVisible() { episode.killed = true; episode.oldCorpse = true }

    var prev = host.observe(plates: true)
    if prev.player < startHealth { return finish("HOLD_PLAYER_HEALTH") }
    episode.update(prev)

    loop: while decisions < FightLimits.maxDecisions && host.now() < FightLimits.maxSeconds {
        if host.wowFrontmost() { outcome = "OWNER_TOOK_FOCUS"; break }
        let o = host.observe(plates: true)
        episode.update(o)
        if o.player < FightLimits.playerSafety && !o.combat { outcome = "SAFETY_STOP_PLAYER_BELOW_30"; break }

        let ev = events(previous: prev, current: o, errorText: o.errorRed ? host.errorText() : nil)
        let allowed = admissible(o, episode)
        let state = statePacket(obs: o, episode: episode, lastAction: lastAction, lastResult: lastResult, events: ev)
        let question = actionQuestion(allowed)
        let asked = host.now()
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
        let action = parsed?.action ?? .stop
        if parsed == nil { lastResult = "Jev answer failed validation" }
        let record: [String: Any] = [
            "decision": decisions, "t": asked, "state": state, "question": question,
            "admissible": allowed.map(\.rawValue), "response": reply, "latency_s": latency,
        ]
        records.append(record)
        host.emit("decision", record)
        prev = o
        lastAction = action.rawValue
        if action != .castLightningBolt { host.releaseBolt() }
        if parsed == nil { outcome = "JEV_STOP"; break }
        lastResult = await host.perform(action, observation: o, episode: &episode)
        host.emit("acted", ["action": action.rawValue, "result": lastResult])
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
        var o = Obs()
        o.player = player
        o.mana = mana
        o.target = selected ? targetHP : 0
        o.combat = combat
        o.casting = casting
        o.castFill = castFill
        o.rangeRed = selected && targetHP > 0.005 && rangeRed
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
        targetHP = max(0, targetHP - amount)
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
            let dx = offset(observation) ?? -0.1
            await hold(dx < 0 ? FightLimits.turnLeft : FightLimits.turnRight, 80)
            plateX = Double(HUD.width) / 2
            return "target centred"
        case .approachToRange:
            await hold(FightLimits.forward, 250)
            rangeRed = false
            return "within Lightning Bolt range"
        case .castLightningBolt:
            holdBolt()
            strike(1.0 / 3)
            return "Lightning Bolt cast at 75 %; the key stays held, so the next cast follows unless another action is chosen"
        case .startMelee:
            await tap(FightLimits.melee)
            episode.meleeOn = true
            strike(0.25)
            return "automatic swings on"
        case .heal:
            await tap(FightLimits.heal)
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
