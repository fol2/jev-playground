// The world model: typed beliefs with confidence, capture time and source, and entity tracks.
// Pure Foundation. No capture, provider, clock, file or input effects. Linux and macOS.
//
// Readers (pixels, OCR, learned models, the judge, knowledge files, memory) write readings.
// The engine reads beliefs. An unknown is a value here, never a guess and never completion.
import Foundation

/// One reading of one fact from one reader at one capture time.
struct Reading<Value: Equatable>: Equatable {
    var value: Value
    /// The reader's own estimate in 0...1. An exact validated read (two OCR masks agreeing, a
    /// parsed number that passed its grammar) is 1; a learned model's class probability is itself.
    var confidence: Double
    /// Capture time of the frame the reading came from, on the session's monotonic clock.
    var capturedAt: Double
    /// Who read it: "pixels:hud", "ocr:coordinates", "learned:facing", "judge", "knowledge:wiki", "memory".
    var source: String
}

/// What the engine believes about one fact: a reading, or an explicit unknown with its reason.
enum Belief<Value: Equatable>: Equatable {
    case known(Reading<Value>)
    case unknown(since: Double?, reason: String)

    static var never: Belief<Value> { .unknown(since: nil, reason: "never read") }

    var reading: Reading<Value>? {
        if case let .known(r) = self { return r }
        return nil
    }
    var value: Value? { reading?.value }
    var confidence: Double { reading?.confidence ?? 0 }

    func isFresh(at now: Double, maximumAge: Double) -> Bool {
        guard let r = reading, maximumAge > 0 else { return false }
        return now >= r.capturedAt && now - r.capturedAt <= maximumAge
    }

    /// The merge policy, in one place, so every field of the world model ages the same way.
    /// - A reading from an older frame never replaces a newer one (reordered capture).
    /// - Within `window` seconds, a markedly less confident reading does not replace a confident one:
    ///   one misread frame does not overturn a settled belief.
    /// - A miss (`unknown`) erases a belief only once the belief is older than `keep` seconds at the
    ///   time of the miss: a nameplate covering the coordinates for a second is not a lost position.
    func merged(_ incoming: Belief<Value>, window: Double = 1.0, keep: Double = 3.0) -> Belief<Value> {
        switch (self, incoming) {
        case (.unknown, .known):
            return incoming
        case let (.known(old), .known(new)):
            if new.capturedAt < old.capturedAt { return self }
            if new.capturedAt - old.capturedAt <= window && new.confidence + 0.2 < old.confidence { return self }
            return incoming
        case let (.known(old), .unknown(since, _)):
            guard let since else { return self }
            return since - old.capturedAt > keep ? incoming : self
        case let (.unknown(oldSince, _), .unknown(newSince, _)):
            return (newSince ?? -.infinity) >= (oldSince ?? -.infinity) ? incoming : self
        }
    }
}

/// A point on the zone map, in the game's map coordinates (0-100 each way).
struct WorldPoint: Equatable {
    var x: Double
    var y: Double
    /// Ground distance in y units: the zone map is 3:2, so one x unit covers 1.5 y units (M4a).
    func distance(to other: WorldPoint) -> Double {
        let dx = (x - other.x) * 1.5, dy = y - other.y
        return (dx * dx + dy * dy).squareRoot()
    }
}

/// The identity of the frame a belief came from: stream, geometry and capture time (as `ObservationStamp`).
struct FrameIdentity: Equatable {
    var stream: String
    var geometry: String
    var capturedAt: Double
}

enum EntityKind: String, Equatable {
    case creature, npc, player, object, corpse
}

enum Hostility: String, Equatable {
    case hostile, neutral, friendly, unknown
}

/// One look at one thing: what a plate, a red name, a tooltip, a detector or the target frame saw.
/// (`Sighting` is M1's; this one carries confidence, capture time and source.)
struct EntitySighting: Equatable {
    var nameKey: String
    var kind: EntityKind
    var hostility: Hostility
    var bearing: Double?  // compass degrees, 0 north, 90 east; nil when the reader has no bearing
    var near: Bool
    var alive: Bool?
    var confidence: Double
    var capturedAt: Double
    var source: String
}

/// One thing in the world, followed across frames. Identity is name plus bearing, never a raw OCR
/// string: OCR tails ("Pesky Cirrusfly 4845") change every frame and must not make a new creature.
struct EntityTrack: Equatable {
    let id: Int
    var nameKey: String
    var kind: EntityKind
    var hostility: Hostility
    var bearing: Double?
    var near: Bool
    var alive: Bool?
    var firstSeen: Double
    var lastSeen: Double
    var sightings: Int
    var confidence: Double
}

/// The Latin letters of a name, lower-cased: what two OCR readings of one creature share. OCR tails on this
/// English client are digits and Cyrillic look-alikes ("Pesky Cirrusfly Л Л4О", live run 48), so only ASCII
/// letters count; another client's language would need its own key.
func worldNameKey(_ text: String) -> String {
    String(text.lowercased().filter { $0.isASCII && $0.isLetter })
}

/// Two name keys of one thing, as OCR renders it frame to frame: equal; or one a prefix of the other
/// (an OCR tail such as "Pesky Cirrusfly 4845" or "Pesky Cirrusfly АОРAU", live runs 37 and 48); or, for
/// names of eight letters or more, within two edits ("Cirrusfiy"). Anything looser is the judge's question.
func nameSimilar(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    let shorter = min(a.count, b.count)
    if shorter >= 6 && (a.hasPrefix(b) || b.hasPrefix(a)) { return true }
    guard shorter >= 8, abs(a.count - b.count) <= 2 else { return false }
    return editDistance(a, b) <= 2
}

/// Levenshtein distance on characters.
func editDistance(_ a: String, _ b: String) -> Int {
    let x = Array(a), y = Array(b)
    if x.isEmpty { return y.count }
    if y.isEmpty { return x.count }
    var previous = Array(0...y.count)
    for i in 1...x.count {
        var current = [i] + Array(repeating: 0, count: y.count)
        for j in 1...y.count {
            let substitution = previous[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1)
            current[j] = min(previous[j] + 1, current[j - 1] + 1, substitution)
        }
        previous = current
    }
    return previous[y.count]
}

/// The smallest signed turn from one bearing to another, in degrees.
func bearingError(_ from: Double, _ to: Double) -> Double {
    var d = (to - from).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return d
}

struct EntityTracker: Equatable {
    private(set) var tracks: [EntityTrack] = []
    private var nextID = 1

    /// Fold this frame's sightings into the tracks. A sighting matches a track of a similar name
    /// (`nameSimilar`: OCR tails and a misread letter are one creature) whose bearing lies within
    /// `sameBearing` degrees (or when either has none). A track unseen for `forget` seconds is dropped:
    /// out of view is not gone, but forgotten is safer than stale.
    mutating func observe(_ sightings: [EntitySighting], at now: Double, sameBearing: Double = 20, forget: Double = 30) {
        for s in sightings {
            let match = tracks.indices.first { i in
                let t = tracks[i]
                guard t.kind == s.kind, nameSimilar(t.nameKey, s.nameKey) else { return false }
                guard let tb = t.bearing, let sb = s.bearing else { return true }
                return abs(bearingError(tb, sb)) <= sameBearing
            }
            if let i = match {
                // The shorter key is the cleaner read: a tail only ever adds characters.
                if s.nameKey.count < tracks[i].nameKey.count { tracks[i].nameKey = s.nameKey }
                tracks[i].bearing = s.bearing ?? tracks[i].bearing
                tracks[i].near = s.near
                tracks[i].alive = s.alive ?? tracks[i].alive
                tracks[i].hostility = s.hostility == .unknown ? tracks[i].hostility : s.hostility
                tracks[i].lastSeen = max(tracks[i].lastSeen, s.capturedAt)
                tracks[i].sightings += 1
                tracks[i].confidence = max(tracks[i].confidence, s.confidence)
            } else {
                tracks.append(EntityTrack(id: nextID, nameKey: s.nameKey, kind: s.kind, hostility: s.hostility,
                                          bearing: s.bearing, near: s.near, alive: s.alive, firstSeen: s.capturedAt,
                                          lastSeen: s.capturedAt, sightings: 1, confidence: s.confidence))
                nextID += 1
            }
        }
        tracks.removeAll { now - $0.lastSeen > forget }
    }

    func hostiles(near: Bool? = nil) -> [EntityTrack] {
        tracks.filter { $0.hostility == .hostile && $0.alive != false && (near == nil || $0.near == near!) }
    }

    /// Hostile tracks within `degrees` of a heading: what stops a walk (M4h, M4t) as one rule.
    func hostilesAhead(of heading: Double, within degrees: Double = 30) -> [EntityTrack] {
        hostiles().filter { t in t.bearing.map { abs(bearingError(heading, $0)) <= degrees } ?? false }
    }
}

enum ObjectiveKind: String, Equatable {
    case kill, collect, useAt, talk, travel, handIn, unknown
}

struct ObjectiveBelief: Equatable {
    var text: String
    var done: Int?
    var need: Int?
    var kind: ObjectiveKind
    /// Finished only when the line itself says so. A vanished line stays unfinished (M4b).
    var finished: Bool {
        guard let done, let need else { return false }
        return need > 0 && done >= need
    }
}

struct QuestBelief: Equatable {
    var title: String
    var level: Int?
    var objectives: [ObjectiveBelief]
    var readyToHandIn: Bool
    var pin: WorldPoint?
    var ender: String?  // from knowledge (the wiki), when the map shows no pin
    var inThisZone: Bool
}

/// What stopped a walk, by the Tab target after a red name ahead (M4ah, M4ai): its name key, its level from the unit
/// tooltip (nil unread), the other hostile names or plates in view with it, those among them that may attack (nil unread;
/// M4am), and whether knowledge says it does not attack first. The host fills it; the reflex table reads it (M4am, M4ak).
struct AheadBelief: Equatable {
    var nameKey: String
    var level: Int? = nil
    var company = 0
    var threats: Int? = nil
    var unaggressive = false
}

struct CharacterBelief: Equatable {
    var health: Belief<Double> = .never   // 0...1
    var mana: Belief<Double> = .never     // 0...1
    var level: Belief<Int> = .never
    var inCombat: Belief<Bool> = .never
    var casting: Belief<Bool> = .never
    var dead: Belief<Bool> = .never
    var position: Belief<WorldPoint> = .never
    var facing: Belief<Double> = .never   // compass degrees
    var zone: Belief<String> = .never
    var money: Belief<Int> = .never       // copper
    var weaponBuffActive: Belief<Bool> = .never
}

struct TargetBelief: Equatable {
    var selected: Belief<Bool> = .never
    var nameKey: Belief<String> = .never
    var alive: Belief<Bool> = .never
    var health: Belief<Double> = .never
    var inBoltRange: Belief<Bool> = .never
    var trackID: Int?
}

/// The blackboard. One per session; every reader writes into it and every decision reads from it.
struct WorldState: Equatable {
    var frame: FrameIdentity?
    var character = CharacterBelief()
    var target = TargetBelief()
    var entities = EntityTracker()
    var ahead: Belief<AheadBelief> = .never  // what stopped the last walk, while that stop stands
    var quests: Belief<[QuestBelief]> = .never
    var bagItems: Belief<[String]> = .never
    var barSkills: Belief<[String]> = .never
    var openPanel: Belief<String> = .never  // "none", "quest", "gossip", "merchant", "trainer", "map", "bags", "game_menu"
    var lastLookAround: Belief<Double> = .never  // capture time of the last full turn

    /// Write one reading through the merge policy, so no caller can overwrite a settled belief with a
    /// stale or weak one by mistake.
    mutating func update<V>(_ path: WritableKeyPath<WorldState, Belief<V>>, _ incoming: Belief<V>,
                            window: Double = 1.0, keep: Double = 3.0) {
        self[keyPath: path] = self[keyPath: path].merged(incoming, window: window, keep: keep)
    }

    mutating func note(frame: FrameIdentity) {
        if let old = frame.capturedAt < (self.frame?.capturedAt ?? -.infinity) ? self.frame : nil { self.frame = old; return }
        self.frame = frame
    }

    /// Seconds since the newest frame; infinite when none was ever seen.
    func visionAge(at now: Double) -> Double {
        guard let frame else { return .infinity }
        return max(0, now - frame.capturedAt)
    }

    func visionStale(at now: Double, maximumAge: Double) -> Bool {
        visionAge(at: now) > maximumAge
    }

    var unfinishedObjectives: [(quest: String, objective: ObjectiveBelief)] {
        (quests.value ?? []).flatMap { q in q.objectives.filter { !$0.finished }.map { (q.title, $0) } }
    }

    /// The compact danger summary the reflexes and the planner read.
    func danger(heading: Double? = nil) -> (hostilesNear: Int, hostilesAhead: Int) {
        (entities.hostiles(near: true).count, heading.map { entities.hostilesAhead(of: $0).count } ?? 0)
    }
}
