// Offline M5 checks on synthetic frames: the candidate proposer, the teacher's crop, the learned reader's crops, the
// run split and the score. SIMULATION ONLY: nothing here shows how well the teacher labels, or how a reader does
// on real frames.
import Foundation

@main
struct MarksTests {
    static var checks = 0
    static func check(_ condition: @autoclosure () -> Bool, _ name: String) {
        guard condition() else { fatalError("FAIL: \(name)") }
        checks += 1
    }

    static func main() {
        print("M5 checks: synthetic frames, the candidate proposer, the crops, the run split and the score.")
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
        let text = frame { p, w in
            for i in 0..<4 { rect(&p, w, 60 + 13 * i, 200, 8, 12, (230, 190, 40)) }  // four letters on one baseline, 5 px apart
            rect(&p, w, 300, 40, 10, 24, (198, 173, 44))  // a mark standing alone
        }
        let kept = markCandidates(text, box: (0, 0, 400, 300))
        check(kept.count == 1 && kept[0].x0 == 300, "letters on one baseline are a line of text, not marks; a mark standing alone is kept")
        let row = frame { p, w in for i in 0..<3 { rect(&p, w, 100 + 60 * i, 150, 10, 24, (198, 173, 44)) } }  // three marks at one depth
        check(markCandidates(row, box: (0, 0, 400, 300)).count == 3, "three marks on one baseline, over characters apart, are all kept: text is letters no further apart than their height")
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
        let splits = (0..<500).map { runSplit("run_\($0)") }
        check(splits.filter { $0 == .validation }.count > 60 && splits.filter { $0 == .validation }.count < 140
              && zip(0..<500, splits).allSatisfy { ($1 == .test) == heldOut(run: "run_\($0)") } && run(of: "m4_x/f001.jpg") == "m4_x",
              "about one run in five more validates training; the test runs are exactly the held-out ones; a frame's run is its folder")
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
        check(truth(teacher: [a, b, c], audit: checked).map(\.box) == [[1, 2, 3, 4], [9, 9, 3, 4]], "only an audited label is a truth: the unchecked teacher label is left out")
        let d = MarkLabel(frame: "r/f2.jpg", box: [5, 5, 3, 4], kind: "exclamation", teacher: MarkLabels.teacher, crop: "d")
        let e = MarkLabel(frame: "r/f3.jpg", box: [5, 5, 3, 4], kind: "none", teacher: MarkLabels.teacher, crop: "e")
        let verdicts = audited([a, b, c, d, e], corrections: [0: "exclamation", 1: "none", 2: "question", 4: "none"])
        check(teacherScore(teacher: [a, b, c, d, e], audit: verdicts) == MarkScore(hits: 2, falseMarks: 1, missed: 1, wrongKind: 1),
              "the teacher per candidate: a mark of the other kind is a hit of the wrong kind, a mark called none is missed, none called a mark is false")
    }

    static func scores() {
        let labels = [[100, 100, 10, 20], [300, 200, 10, 20]]
        let s = score(found: [(105, 110), (105, 111), (50, 50)], labels: labels)
        check(s == MarkScore(hits: 1, falseMarks: 2, missed: 1), "a label is hit at most once; a second reading on it and one elsewhere are false; the other label is missed")
        check(score(found: [(98, 96)], labels: labels).hits == 1 && score(found: [(96, 90)], labels: labels).hits == 0,
              "a reading within a quarter of the box outside it is a hit; beyond that it is not")
        check(score(found: [(111.5, 110)], labels: labels).hits == 1 && score(found: [(112, 110)], labels: labels).hits == 0,
              "the box ends at its last pixel (x + w - 1): the quarter of room is the same on both sides")
        check(MarkScore().precision == nil && MarkScore().recall == nil && (s + s).hits == 2 && s.recall == 0.5,
              "no reading and no label give no rate, not a perfect one; scores add up")
        let kinds = score(found: [(105, 110), (305, 210)], labels: labels, foundKinds: ["exclamation", "question"], labelKinds: ["question", "question"])
        check(kinds == MarkScore(hits: 2, falseMarks: 0, missed: 0, wrongKind: 1) && (kinds + kinds).wrongKind == 2,
              "a hit of the other kind is counted, by the label it hit; wrong kinds add up")
        let near = glyphCrops([200, 100, 10, 40], width: 400, height: 300), far = glyphCrops([100, 50, 3, 5], width: 400, height: 300)
        check(near.context == (125, 80, 160, 160) && near.shape == (173, 88, 64, 64) && far.context == (89, 48, 24, 24) && far.shape == (91, 42, 20, 20),
              "the context crop is four glyph heights from half a height above; the shape crop 1.6 glyphs, centred; each has a floor")
        let corner = glyphCrops([395, 290, 4, 9], width: 400, height: 300)
        check(corner.context.x + corner.context.w <= 400 && corner.context.y + corner.context.h <= 300 && corner.shape.x + corner.shape.w <= 400
              && corner.context.w == corner.context.h && glyphCrops([0, 0, 50, 120], width: 400, height: 300).context.w == 300,
              "a crop stays square and inside the image, shrunk to it if the glyph is too tall")
    }
}
