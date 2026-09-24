// One physical input owner, with revocable scopes for nested skills.
import Foundation

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

/// One store serialises all posts, including a child fight. Each LiveKeys is a
/// capability for one skill; only the active capability may press/lift/grant.
/// The root's releaseAll is global cancellation. A child's releaseAll retires only
/// that child, and the parent must explicitly resume after confirmed release.
final class LiveKeys {
    private final class Store {
        let sink: KeySink
        let clock: () -> Double
        var emit: Emit
        let lock = NSLock()
        var held: Set<UInt16> = []
        var grants: [UInt16: HeldKey] = [:]
        var releasing: Set<UInt16> = []
        var cancelled = false
        var active = 0, serial = 0
        var retired: Set<Int> = []
        var parents: [Int: Int] = [:]
        var releaseCodes: [Int: [UInt16]]
        var posted: [Int: [UInt16]] = [:]
        var pending: [(String, [String: Any])] = []

        init(sink: KeySink, releaseCodes: [UInt16], clock: @escaping () -> Double, emit: @escaping Emit) {
            self.sink = sink; self.clock = clock; self.emit = emit
            self.releaseCodes = [0: releaseCodes]
        }
        func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            let value = body(), events = pending
            pending.removeAll()
            lock.unlock()
            for (event, fields) in events { emit(event, fields) }
            return value
        }
        func note(_ event: String, _ fields: [String: Any]) { pending.append((event, fields)) }
        func up(_ code: UInt16) -> Bool {
            guard confirmKeyUp(code, sink: sink, emit: note) else {
                releasing.insert(code)
                grants[code] = HeldKey(code: code, until: -.infinity)
                return false
            }
            held.remove(code); releasing.remove(code); grants[code] = nil
            return true
        }
        func sweep(_ codes: [UInt16]) {
            var seen: Set<UInt16> = []
            for code in codes + held.sorted() where seen.insert(code).inserted { _ = up(code) }
        }
    }
    private let store: Store
    private let scope: Int
    var emit: Emit { get { store.emit } set { store.emit = newValue } } // set before concurrent use

    init(sink: KeySink, releaseCodes: [UInt16], clock: @escaping () -> Double, emit: @escaping Emit = { _, _ in }) {
        store = Store(sink: sink, releaseCodes: releaseCodes, clock: clock, emit: emit)
        scope = 0
    }
    private init(store: Store, scope: Int) { self.store = store; self.scope = scope }
    private var active: Bool { !store.cancelled && store.active == scope && !store.retired.contains(scope) } // locked
    var holding: Bool { store.locked { !store.held.isEmpty || !store.releasing.isEmpty } }
    var codesPosted: [UInt16] { store.locked { store.posted[scope] ?? [] } }
    func isDown(_ code: UInt16) -> Bool { store.locked { active && store.held.contains(code) } }

    @discardableResult func press(_ code: UInt16) -> Bool {
        store.locked {
            guard active else { return false }
            store.held.insert(code); store.releasing.remove(code)
            do { try store.sink.post(code, down: true) }
            catch { store.note("key_down_failed", ["code": Int(code), "error": "\(error)"]) }
            store.posted[scope, default: []].append(code)
            return true
        }
    }
    func lift(_ code: UInt16, listed: Bool = false) {
        store.locked {
            guard active, store.held.contains(code) || listed else { return }
            _ = store.up(code)
        }
    }
    func grant(_ code: UInt16, seconds: Double) {
        store.locked {
            guard active, !store.releasing.contains(code) else { return }
            var grant = HeldKey(code: code, until: 0)
            grant.refresh(now: store.clock(), hold: seconds)
            store.grants[code] = grant
        }
    }
    func sweepExpired() {
        let now = store.clock()
        let released: [UInt16] = store.locked {
            var out: [UInt16] = []
            for (code, grant) in store.grants where grant.expired(now: now) {
                guard store.held.contains(code) || store.releasing.contains(code) else { store.grants[code] = nil; continue }
                if store.up(code) { out.append(code) }
            }
            return out
        }
        for code in released { store.emit("watchdog", ["released": Int(code)]) }
    }
    func releaseAll() {
        store.locked {
            store.retired.insert(scope)
            if scope == 0 {
                store.cancelled = true
                store.sweep(store.releaseCodes.keys.sorted().flatMap { store.releaseCodes[$0]! })
            } else if store.active == scope {
                store.sweep(store.releaseCodes[scope] ?? [])
            }
        }
    }
    // A stale parent/child cannot dispatch a mouse operation around the keyboard owner.
    // The synchronous transport operation must not call back into LiveKeys or await.
    func withControl<T>(_ effect: () -> T) -> T? { store.locked { active ? effect() : nil } }

    func takeChild(releaseCodes: [UInt16]) -> LiveKeys? {
        store.locked {
            guard active else { return nil }
            store.sweep(store.releaseCodes[scope] ?? [])
            guard store.held.isEmpty && store.releasing.isEmpty else { return nil }
            store.serial += 1
            let child = store.serial
            store.parents[child] = scope
            store.releaseCodes[child] = releaseCodes
            store.active = child
            store.note("input_handoff", ["from": scope, "to": child])
            return LiveKeys(store: store, scope: child)
        }
    }
    @discardableResult func resume(after child: LiveKeys) -> Bool {
        store.locked {
            guard child.store === store, !store.cancelled, !store.retired.contains(scope),
                  store.parents[child.scope] == scope, store.active == child.scope,
                  store.retired.contains(child.scope), store.held.isEmpty, store.releasing.isEmpty else { return false }
            store.active = scope
            store.note("input_resumed", ["from": child.scope, "to": scope])
            return true
        }
    }
}
