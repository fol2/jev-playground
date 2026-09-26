// M4, roads learned from people's play (the owner, 24 Sept: "first put higher priority to walk on road, especially
// zone to zone travel"). A trail is the zone coordinates under the minimap, read frame by frame from a published
// video (m5-perceive --trails); the trails of several players make a graph of places and the ways between them
// (m5-perceive --roads, learning/knowledge/zephras-roads.json); a quest run walks a route by it from one zone's
// quests to the next. Pure: no capture, no OCR, no keys.
import Foundation

enum RoadLimits {
    // Frames are 2 or 3 s apart and a y unit is about 5 s of running, so one step is under a unit. A reading
    // further than `maxStep` from the one before is a jump (a flight, a hearthstone, a misread, frames lost to
    // the OCR) and the trail breaks there: no way is learned across it.
    static let maxStep = 2.0
    static let cell = 1.0  // one place: a square y unit of ground; players on one road share its places
    static let reach = 3.0  // a route starts and ends at places within this of the player and of the goal
    static let bend = 0.3  // a waypoint is kept where the road leaves the straight line by more than this
}

/// The learned roads. A place is the mean of the readings in its square; a way joins the places of two readings
/// in a row of one trail and is directed, as walked: a drop from a ledge may not climb back.
struct RoadGraph: Codable, Equatable {
    var sources: [String]  // the videos the trails came from
    var subzones: [String]  // the names read above the minimap on them: where the coordinates hold
    var places: [[Double]]  // x, y
    var ways: [[Int]]  // from, to, how many sources walked it

    static let file = "experiments/002_wow_visual/learning/knowledge/zephras-roads.json"

    func point(_ i: Int) -> MapPoint { (places[i][0], places[i][1]) }

    /// The committed roads, or nil when there are none. A file that does not decode, or a way to a place it does not
    /// have, throws: the run stops before any walk.
    static func load(_ path: String = file) throws -> RoadGraph? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        let g = try JSONDecoder().decode(RoadGraph.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        guard g.places.allSatisfy({ $0.count == 2 }), g.ways.allSatisfy({ $0.count == 3 && g.places.indices.contains($0[0]) && g.places.indices.contains($0[1]) }) else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: path])
        }
        return g
    }
}

/// One source's readings in time order, cut into trails where a reading lies more than `maxStep` from the one
/// before it. A trail of one reading has no way and is dropped.
func trailPieces<T>(_ readings: [T], at point: (T) -> MapPoint, maxStep: Double = RoadLimits.maxStep) -> [[T]] {
    var pieces: [[T]] = [], piece: [T] = []
    for r in readings {
        if let last = piece.last, distance(point(last), point(r)) > maxStep {
            if piece.count > 1 { pieces.append(piece) }
            piece = []
        }
        piece.append(r)
    }
    if piece.count > 1 { pieces.append(piece) }
    return pieces
}

/// The trails on the map most readings lie on. The map changes only across a jump (a portal, a flight, a
/// hearthstone), which breaks a trail, so the subzones one trail walks through share a map. Joined trail by trail,
/// the subzones with most readings are this map's; a trail through none of them is on another map (a video's
/// last hour in Dalaran) or unknown, and is left out. A name read fewer than `minReadings` times is an OCR slip
/// and joins nothing.
func oneMap<T>(_ trails: [[T]], subzone: (T) -> String?, minReadings: Int = 20) -> [[T]] {
    let counts = Dictionary(grouping: trails.joined().compactMap(subzone), by: { $0 }).mapValues(\.count)
    func named(_ r: T) -> String? { subzone(r).flatMap { counts[$0, default: 0] >= minReadings ? $0 : nil } }
    var parent: [String: String] = [:]
    func root(_ s: String) -> String { parent[s].map { $0 == s ? s : root($0) } ?? s }
    for t in trails {
        let names = Set(t.compactMap(named)).sorted()
        for n in names.dropFirst() where root(n) != root(names[0]) { parent[root(n)] = root(names[0]) }
    }
    let weight = Dictionary(grouping: trails.joined().compactMap(named), by: root).mapValues(\.count)
    guard let home = weight.max(by: { ($0.value, $1.key) < ($1.value, $0.key) })?.key else { return [] }
    return trails.filter { t in t.contains { named($0).map(root) == home } }
}

/// The roads of many sources' trails. Places are squares of `cell` y units of ground (an x unit is `mapAspect` y
/// units); a way counts each source that walked it once.
func buildRoads(_ trails: [(source: String, points: [MapPoint])], subzones: [String] = [], cell: Double = RoadLimits.cell) -> RoadGraph {
    func square(_ p: MapPoint) -> String { "\(Int((p.x * mapAspect / cell).rounded(.down))),\(Int((p.y / cell).rounded(.down)))" }
    var index: [String: Int] = [:], sums: [(x: Double, y: Double, n: Double)] = [], walked: [String: Set<String>] = [:]
    for (source, points) in trails {
        var before: Int?
        for p in points {
            let key = square(p)
            let i = index[key] ?? sums.count
            if i == sums.count { index[key] = i; sums.append((0, 0, 0)) }
            sums[i] = (sums[i].x + p.x, sums[i].y + p.y, sums[i].n + 1)
            if let b = before, b != i { walked["\(b) \(i)", default: []].insert(source) }
            before = i
        }
    }
    let ways = walked.map { key, by -> [Int] in let e = key.split(separator: " ").map { Int($0)! }; return [e[0], e[1], by.count] }
        .sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }
    return RoadGraph(sources: Array(Set(trails.map(\.source))).sorted(), subzones: Array(Set(subzones)).sorted(),
                     places: sums.map { [roundTo($0.x / $0.n, 100), roundTo($0.y / $0.n, 100)] }, ways: ways)
}

/// The shortest walk by road from `from` to `to`: onto any place within `reach` of `from`, along ways as walked,
/// and off at a place within `reach` of `to`. The places on the way, simplified to where the road bends, then the
/// goal. nil when no place is within reach of either end or no way joins them.
// ponytail: Dijkstra by linear scan, O(places²); a heap if a graph grows past some thousands of places.
func route(_ g: RoadGraph, from: MapPoint, to: MapPoint, reach: Double = RoadLimits.reach) -> [MapPoint]? {
    let n = g.places.count
    var cost = (0..<n).map { distance(from, g.point($0)) <= reach ? distance(from, g.point($0)) : Double.infinity }
    var previous = [Int?](repeating: nil, count: n), done = [Bool](repeating: false, count: n)
    var next: [Int: [Int]] = [:]
    for w in g.ways { next[w[0], default: []].append(w[1]) }
    while let u = (0..<n).filter({ !done[$0] && cost[$0] < .infinity }).min(by: { cost[$0] < cost[$1] }) {
        done[u] = true
        for v in next[u] ?? [] where cost[u] + distance(g.point(u), g.point(v)) < cost[v] {
            cost[v] = cost[u] + distance(g.point(u), g.point(v))
            previous[v] = u
        }
    }
    guard let end = (0..<n).filter({ cost[$0] < .infinity && distance(g.point($0), to) <= reach })
        .min(by: { cost[$0] + distance(g.point($0), to) < cost[$1] + distance(g.point($1), to) }) else { return nil }
    var path = [end]
    while let p = previous[path[0]] { path.insert(p, at: 0) }
    return simplified(path.map(g.point) + [to])
}

/// The points where a walked line bends by more than `tolerance` (Douglas-Peucker): a straight road is one leg.
func simplified(_ points: [MapPoint], tolerance: Double = RoadLimits.bend) -> [MapPoint] {
    guard points.count > 2, let a = points.first, let b = points.last else { return points }
    func off(_ p: MapPoint) -> Double {  // ground distance from p to the line a-b, in y units
        let (ax, ay, bx, by, px, py) = (a.x * mapAspect, a.y, b.x * mapAspect, b.y, p.x * mapAspect, p.y)
        let dx = bx - ax, dy = by - ay, length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return ((px - ax) * (px - ax) + (py - ay) * (py - ay)).squareRoot() }
        return abs(dy * (px - ax) - dx * (py - ay)) / length
    }
    let inner = points.indices.dropFirst().dropLast()
    guard let far = inner.max(by: { off(points[$0]) < off(points[$1]) }), off(points[far]) > tolerance else { return [a, b] }
    return simplified(Array(points[...far]), tolerance: tolerance).dropLast() + simplified(Array(points[far...]), tolerance: tolerance)
}

/// A held-out source's trails against roads learned without it: the share of its readings within `near` of a
/// learned place, and, of its walks longer than `longer` from end to end, how many the roads give a route for.
func heldOutRoads(_ trails: [[MapPoint]], roads g: RoadGraph, near: Double = RoadLimits.cell, longer: Double = QuestLimits.maxLeg)
    -> (readings: Int, covered: Int, walks: Int, routed: Int) {
    let points = trails.flatMap { $0 }
    let covered = points.filter { p in g.places.indices.contains { distance(p, g.point($0)) <= near } }.count
    let long = trails.filter { distance($0.first!, $0.last!) > longer }
    return (points.count, covered, long.count, long.filter { route(g, from: $0.first!, to: $0.last!) != nil }.count)
}
