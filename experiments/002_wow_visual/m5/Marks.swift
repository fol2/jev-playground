// M5, learned perception: candidate quest marks, cast wide for a labelling teacher, the crops a learned reader
// sees, and the measures that compare a reader with the audited labels. Pure: no capture, no model. The teacher
// is Teacher.swift, the learned reader Reader.swift, the tool PerceiveTool.swift. The hand-tuned mark rules (m4/Quest.swift, questMarks) failed on each new
// zoom, character and glyph shade (26 Sept); a detector trained on labelled frames replaces them.
import Foundation

enum MarkLabels {
    static let world = (300, 100, 2100, 950)  // where marks are looked for, as QuestHUD.world
    static let teacher = "fm-marks-v2"  // the prompt's version: a cached verdict is reused only under it
    static let heldOutEvery = 5  // one run in five, by name, is held out as the test; one more validates training
}

/// Yellow to orange: a quest mark's glyph shades from its top to its foot (live, 26 Sept: 198,173,44 at the
/// top of a near "!", 190,121,34 at its foot, where markYellow stops).
func markWarm(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 150 && g > 90 && r - b > 100 && g - b > 50 }

/// Candidate glyphs: solid warm parts (a 3 px gap), each joined with a part under it that lies within twice
/// its height and overlaps it across (a "?" or "!" and its dot). Recall matters, not precision: the teacher
/// says what each one is. Sparse flecks, such as tan grass, are not solid and are left out.
func markCandidates(_ image: RGBA, box: (Int, Int, Int, Int) = MarkLabels.world) -> [Blob] {
    func solid(_ b: Blob) -> Bool { b.n >= 6 && 5 * b.n >= (b.x1 - b.x0 + 1) * (b.y1 - b.y0 + 1) }
    var parts = yellowBlobs(image, box: box, gap: 3, colour: markWarm).filter(solid).sorted { $0.y0 < $1.y0 }
    var out: [Blob] = []
    while !parts.isEmpty {
        var glyph = parts.removeFirst()
        let h = glyph.y1 - glyph.y0 + 1
        if let j = parts.firstIndex(where: { p in
            p.y0 > glyph.y1 && p.y0 - glyph.y1 <= 2 * h && p.x0 <= glyph.x1 && p.x1 >= glyph.x0 && 2 * p.n <= glyph.n
        }) {
            let d = parts.remove(at: j)
            glyph = (glyph.n + d.n, glyph.sx + d.sx, glyph.sy + d.sy, min(glyph.x0, d.x0), max(glyph.x1, d.x1), glyph.y0, d.y1)
        }
        let w = glyph.x1 - glyph.x0 + 1, gh = glyph.y1 - glyph.y0 + 1
        if gh >= 4 && gh <= 120 && w <= 80 && gh * 3 >= w { out.append(glyph) }  // upright, at most three times wider than tall
    }
    // Letters, not marks: a chain of three or more parts of a like height on one baseline, each no further from the
    // next than its height, is a line of text. Yellow interface text (settings, "Objective Complete") made most of
    // the first candidates (26 Sept). Marks over different characters stand further apart than that, so three of
    // them in a row are kept.
    func letters(_ a: Blob, _ b: Blob) -> Bool {
        let ha = a.y1 - a.y0 + 1, hb = b.y1 - b.y0 + 1
        let gap = max(a.x0, b.x0) - min(a.x1, b.x1) - 1
        return abs(a.y1 - b.y1) <= 3 && 2 * min(ha, hb) >= max(ha, hb) && gap <= max(ha, hb)
    }
    var chain = Array(out.indices)
    func root(_ i: Int) -> Int { chain[i] == i ? i : root(chain[i]) }
    for i in out.indices { for j in out.indices where j > i && letters(out[i], out[j]) { chain[root(j)] = root(i) } }
    let size = Dictionary(grouping: out.indices, by: root).mapValues(\.count)
    return out.indices.filter { size[root($0), default: 1] < 3 }.map { out[$0] }
}

/// What the teacher sees: the glyph with room for a name under it and beside it. At least 240 x 160 px, so a
/// far mark keeps its context; clamped to the image.
func teacherCrop(_ g: Blob, width: Int, height: Int) -> (x: Int, y: Int, w: Int, h: Int) {
    let gw = g.x1 - g.x0 + 1, gh = g.y1 - g.y0 + 1
    let halfW = max(120, 4 * gw), cx = (g.x0 + g.x1) / 2
    let top = g.y0 - max(20, gh), bottom = g.y1 + max(140, 4 * gh)
    let x0 = max(0, cx - halfW), x1 = min(width, cx + halfW), y0 = max(0, top), y1 = min(height, bottom)
    return (x0, y0, max(0, x1 - x0), max(0, y1 - y0))
}

/// One labelled candidate. `kind` is the teacher's: exclamation, question, none, or refused (the model declined the
/// crop; the auditor decides). `frame` is the path under
/// runs/002_wow_visual; labels stay there with the private frames they describe.
struct MarkLabel: Codable, Equatable {
    var frame: String
    var box: [Int]  // x, y, width, height of the glyph
    var kind: String
    var teacher: String
    var crop: String  // the crop's SHA-256: the teacher's cache key, with the teacher's version
}

enum Split: String, CaseIterable { case train, validation, test }

/// A run's split, by its name, never by frame: frames of one run are near-duplicates, and one on each side would
/// leak (AGENTS: do not tune against the held-out test). One run in five is the test; one in five more validates a
/// model while it trains, and chooses between designs. FNV-1a, so the split never moves.
func runSplit(_ run: String) -> Split {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in run.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
    switch hash % UInt64(MarkLabels.heldOutEvery) {
    case 0: return .test
    case 1: return .validation
    default: return .train
    }
}

func heldOut(run: String) -> Bool { runSplit(run) == .test }

/// The run a saved frame belongs to: its folder under runs/002_wow_visual.
func run(of frame: String) -> String { String(frame.split(separator: "/").first ?? "") }

/// What the learned reader sees of a candidate glyph (`box`: x, y, width, height), as squares inside the image:
/// - `context`: four glyph heights a side (at least 24 px), from half a height above the glyph, so the name under
///   it is in view. It says whether the glyph is a quest mark.
/// - `shape`: 1.6 times the glyph (at least 20 px), centred on it. It says which mark.
/// On the validation runs (26 Sept) the context crop told marks from the rest best, and the shape crop the kind.
/// Neither did both: with the context crop a near "!" read as "?", with the shape crop far marks were missed.
func glyphCrops(_ box: [Int], width: Int, height: Int) -> (context: (x: Int, y: Int, w: Int, h: Int), shape: (x: Int, y: Int, w: Int, h: Int)) {
    func square(_ side: Int, cx: Int, top: Int) -> (x: Int, y: Int, w: Int, h: Int) {
        let s = min(side, width, height)
        return (max(0, min(width - s, cx - s / 2)), max(0, min(height - s, top)), s, s)
    }
    let cx = box[0] + box[2] / 2, cy = box[1] + box[3] / 2, h = box[3]
    let shape = max(20, 16 * max(box[2], h) / 10)
    return (square(max(24, 4 * h), cx: cx, top: box[1] - h / 2), square(shape, cx: cx, top: cy - shape / 2))
}

/// A reader's marks against the audited marks of the same frames. A found mark whose centre lies in a label's box,
/// grown by a quarter each way, is a hit; each label is hit at most once. `wrongKind` counts hits of the other kind
/// ("!" for "?"), where the reader names a kind.
struct MarkScore: Equatable {
    var hits = 0, falseMarks = 0, missed = 0, wrongKind = 0
    var precision: Double? { hits + falseMarks == 0 ? nil : Double(hits) / Double(hits + falseMarks) }
    var recall: Double? { hits + missed == 0 ? nil : Double(hits) / Double(hits + missed) }
    static func + (a: MarkScore, b: MarkScore) -> MarkScore {
        MarkScore(hits: a.hits + b.hits, falseMarks: a.falseMarks + b.falseMarks, missed: a.missed + b.missed, wrongKind: a.wrongKind + b.wrongKind)
    }
}

func score(found: [(x: Double, y: Double)], labels: [[Int]], foundKinds: [String] = [], labelKinds: [String] = []) -> MarkScore {
    var open = Array(labels.indices), s = MarkScore()
    for (n, f) in found.enumerated() {
        if let k = open.firstIndex(where: { i in
            let b = labels[i], gx = Double(b[2]) / 4, gy = Double(b[3]) / 4
            return f.x >= Double(b[0]) - gx && f.x <= Double(b[0] + b[2] - 1) + gx && f.y >= Double(b[1]) - gy && f.y <= Double(b[1] + b[3] - 1) + gy
        }) {
            let i = open.remove(at: k)
            s.hits += 1
            if foundKinds.indices.contains(n) && labelKinds.indices.contains(i) && foundKinds[n] != labelKinds[i] { s.wrongKind += 1 }
        } else {
            s.falseMarks += 1
        }
    }
    s.missed = open.count
    return s
}

/// An auditor's pass over one set of sheets: every label shown is kept, with the auditor's kind where it
/// differs from the teacher's (`corrections`, by the label's place in the sheets) and the teacher's otherwise.
func audited(_ shown: [MarkLabel], corrections: [Int: String]) -> [MarkLabel] {
    shown.enumerated().map { i, l in
        var a = l
        a.kind = corrections[i] ?? l.kind
        a.teacher = "audit"
        return a
    }
}

/// The labels to score or train on: an audited label replaces the teacher's for the same candidate.
func merged(teacher: [MarkLabel], audit: [MarkLabel]) -> [MarkLabel] {
    let checked = Dictionary(audit.map { ("\($0.frame)|\($0.box)", $0) }) { _, last in last }
    return teacher.map { checked["\($0.frame)|\($0.box)"] ?? $0 }
}

/// The ground truth: audited labels only. A teacher's label no auditor has checked is a guess, not a truth.
func truth(teacher: [MarkLabel], audit: [MarkLabel]) -> [MarkLabel] {
    merged(teacher: teacher, audit: audit).filter { $0.teacher == "audit" }
}

/// The teacher as a first filter, candidate by candidate against the auditor: a mark called a mark is a hit (of the
/// wrong kind if "!" and "?" differ), a mark called anything else is missed, and anything else called a mark is false.
func teacherScore(teacher: [MarkLabel], audit: [MarkLabel]) -> MarkScore {
    let isMark = { (k: String) in k == "exclamation" || k == "question" }
    var s = MarkScore()
    for (t, a) in zip(teacher, merged(teacher: teacher, audit: audit)) where a.teacher == "audit" {
        switch (isMark(t.kind), isMark(a.kind)) {
        case (true, true):
            s.hits += 1
            if t.kind != a.kind { s.wrongKind += 1 }
        case (true, false): s.falseMarks += 1
        case (false, true): s.missed += 1
        default: break
        }
    }
    return s
}

/// What a model may learn from: labels of the training and validation runs, never of the test runs.
func learnable(_ labels: [MarkLabel]) -> [MarkLabel] { labels.filter { runSplit(run(of: $0.frame)) != .test } }
