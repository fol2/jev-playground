// Offline M5 checks on synthetic frames: the candidate proposer, the teacher's crop, the run split and the
// score. SIMULATION ONLY: nothing here shows how well the teacher labels, or how a reader does on real frames.
import Foundation

@main
struct MarksTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }

    static func main() {
        print("M5 checks: synthetic frames, the candidate proposer, the run split and the score.")
        print("SIMULATION-ONLY proof: no frame, teacher or model.")
        candidates()
        split()
        scores()
        audits()
        print("perception checks passed: \(checks)")
    }

    static func frame(_ paint: (inout [UInt8], Int) -> Void) -> RGBA {
        let w = 400, h = 300
        var p = [UInt8](repeating: 30, count: w * h * 4)
        paint(&p, w)
        return RGBA(width: w, height: h, pixels: p)
    }

    static func rect(_ p: inout [UInt8], _ w: Int, _ x: Int, _ y: Int, _ rw: Int, _ rh: Int, _ c: (UInt8, UInt8, UInt8)) {
        for yy in y..<(y + rh) { for xx in x..<(x + rw) { let i = (yy * w + xx) * 4; (p[i], p[i + 1], p[i + 2]) = c } }
    }

    static func candidates() {
        check(markWarm(198, 173, 44) && markWarm(190, 121, 34) && !markYellow(190, 121, 34),
              "live, 26 Sept: a near \"!\" is yellow at its top and orange at its foot; the proposer takes both, markYellow only the top")
        check(!markWarm(60, 190, 40) && !markWarm(150, 150, 150) && !markWarm(170, 150, 110),
              "a green name, grey stone and tan are not warm")
        // The near "!" of live run 13: a 17 px yellow bar, 10 px of orange under it, its dot 8 px lower.
        let bang = frame { p, w in
            rect(&p, w, 200, 100, 10, 17, (198, 173, 44)); rect(&p, w, 200, 117, 10, 10, (190, 121, 34))
            rect(&p, w, 201, 135, 7, 5, (196, 150, 43))
        }
        let found = markCandidates(bang, box: (0, 0, 400, 300))
        check(found.count == 1 && found[0].y0 == 100 && found[0].y1 == 139 && found[0].x0 == 200,
              "the bar, its orange foot and its dot are one candidate")
        let flecks = frame { p, w in for i in 0..<12 { rect(&p, w, 100 + 5 * (i % 4), 100 + 5 * (i / 4), 1, 1, (200, 170, 40)) } }
        check(markCandidates(flecks, box: (0, 0, 400, 300)).isEmpty, "sparse flecks, as on tan grass, are no candidate")
        let strip = frame { p, w in rect(&p, w, 100, 100, 100, 8, (200, 170, 40)) }
        check(markCandidates(strip, box: (0, 0, 400, 300)).isEmpty, "a flat strip, such as a neutral nameplate's bar, is no candidate")
        let outside = frame { p, w in rect(&p, w, 10, 10, 10, 20, (198, 173, 44)) }
        check(markCandidates(outside, box: (50, 50, 400, 300)).isEmpty, "nothing outside the box is proposed")
        let r = teacherCrop((100, 0, 0, 200, 209, 100, 139), width: 400, height: 300)
        check(r.x == 84 && r.w == 240 && r.y == 60 && r.h == 239, "the crop is at least 240 px wide, with room above and a name's room below, clamped to the frame")
        let edge = teacherCrop((100, 0, 0, 2, 11, 2, 21), width: 400, height: 300)
        check(edge.x == 0 && edge.y == 0 && edge.w > 0 && edge.h > 0 && edge.x + edge.w <= 400 && edge.y + edge.h <= 300,
              "a mark at the frame's corner keeps its crop inside the frame")
    }

    static func split() {
        check(heldOut(run: "m4_quests_20260926T075801Z_0bff55") == heldOut(run: "m4_quests_20260926T075801Z_0bff55"),
              "the split is by run name and never moves")
        let held = (0..<500).filter { heldOut(run: "run_\($0)") }.count
        check(held > 60 && held < 140, "about one run in five is held out (\(held) of 500)")
    }

    static func audits() {
        let a = MarkLabel(frame: "r/f1.jpg", box: [1, 2, 3, 4], kind: "question", teacher: MarkLabels.teacher, crop: "a")
        let b = MarkLabel(frame: "r/f1.jpg", box: [9, 9, 3, 4], kind: "question", teacher: MarkLabels.teacher, crop: "b")
        let c = MarkLabel(frame: "r/f2.jpg", box: [1, 2, 3, 4], kind: "none", teacher: MarkLabels.teacher, crop: "c")
        let checked = audited([a, b], corrections: [1: "none"])
        check(checked.map(\.kind) == ["question", "none"] && checked.allSatisfy { $0.teacher == "audit" },
              "an audit keeps every label shown: the auditor's kind where corrected, the teacher's where confirmed")
        let later = audited([checked[1]], corrections: [0: "exclamation"])
        check(merged(teacher: [a, b, c], audit: checked + later).map(\.kind) == ["question", "exclamation", "none"],
              "an audited label replaces the teacher's for the same candidate, the latest pass winning; an unaudited one stays")
    }

    static func scores() {
        let labels = [[100, 100, 10, 20], [300, 200, 10, 20]]
        let s = score(found: [(105, 110), (105, 111), (50, 50)], labels: labels)
        check(s == MarkScore(hits: 1, falseMarks: 2, missed: 1), "a label is hit at most once; a second reading on it and one elsewhere are false; the other label is missed")
        check(score(found: [(98, 96)], labels: labels).hits == 1 && score(found: [(96, 90)], labels: labels).hits == 0,
              "a reading within a quarter of the box outside it is a hit; beyond that it is not")
        check(MarkScore().precision == nil && MarkScore().recall == nil && (s + s).hits == 2 && s.recall == 0.5,
              "no reading and no label give no rate, not a perfect one; scores add up")
    }
}
