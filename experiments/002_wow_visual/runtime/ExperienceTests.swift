// Synthetic outcome/memory tests. No game, capture, input or model call.
import Foundation

@main struct ExperienceTests {
    static func main() throws {
        var n = 0
        func check(_ ok: Bool, _ message: String) { n += 1; precondition(ok, message) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("memory.json")
        let context = ["target": "sample", "place": "cell A"]
        func frame(_ t: Double, _ progress: [String: Int] = ["Q": 0]) -> ExperienceFrame {
            ExperienceFrame(context: context, progress: progress, capturedAt: t, stream: "s", geometry: "g")
        }
        func example(_ id: String, blocked: Bool? = nil, after: ExperienceFrame? = nil, action: String = "GO_N") -> ExperienceCase {
            ExperienceCase(id: id, run: "synthetic-run", action: action, before: frame(0), after: after,
                           reported: "fixture result, not a live observation", blocked: blocked, elapsed: 1)
        }
        let book = try ExperienceStore(scope: "simulation-v1", url: file)
        check(book.cases.isEmpty, "empty memory starts empty")
        check(!FileManager.default.fileExists(atPath: file.path), "reading missing store has no write")
        check(try book.record(example("1", blocked: true, after: frame(2))), "store executed failure")
        check(book.cases[0].progressDelta == 0, "unchanged counter is zero, not success")
        check(!(try book.record(example("1"))), "duplicate ID is not another trial")
        check(book.cases.count == 1, "duplicate not counted")
        check(FileManager.default.fileExists(atPath: file.path), "source evidence persisted")
        check(book.persistenceError == nil, "save confirmed")
        try book.record(example("2", after: frame(3, ["Q": 1])))
        check(book.cases.last!.progressDelta == 1, "measure observed counter increase")
        try book.record(example("3"))
        check(book.cases.last!.progressDelta == nil, "no after frame is unknown")
        try book.record(example("4", after: frame(4, [:])))
        check(book.cases.last!.progressDelta == nil, "missing quest is NOT complete")
        try book.record(example("5", after: frame(5, ["Q": 0, "Other": 9])))
        check(book.cases.last!.progressDelta == 0, "unrelated quest progress is not reward")
        check(book.matches(["place": "cell B"]).isEmpty, "do not transfer across unmatched places")
        let recalled = book.recall(context)
        let ids = (recalled["cases"] as! [[String: Any]]).map { $0["id"] as! String }
        check(ids.count <= 3, "bounded detail in context")
        check(ids.contains("1") && ids.contains("2"), "both negative and positive evidence retained")
        check((recalled["counts"] as! [[String: Any]])[0]["attempts"] as? Int == 5, "counts retain unconfirmed attempts")
        check(book.availableReviewTools(context).count == 5, "matching episode exposes bounded Jev review tools")
        check(book.reviewLatest("movement", context: context)?.caseID == "5", "review tied to exact matching case")
        check(book.availableReviewTools(context)["REVIEW_MOVEMENT"] == nil, "completed review tool is not repeatedly offered")
        check(book.reviewLatest("made_up") == nil, "only bounded research categories")
        _ = book.reviewLatest("movement")
        check(book.reviews.count == 1, "same research question deduplicated")
        check(book.reviews[0].json["status"] as? String == "hypothesis", "model label not promoted truth")
        let again = try ExperienceStore(scope: "simulation-v1", url: file)
        check(again.cases.count == 5 && again.reviews.count == 1, "experiences survive restart")
        check(again.matches(context).count == 5, "reloaded memory reaches retrieval")
        do { _ = try ExperienceStore(scope: "live-v1", url: file); check(false, "mode isolation") }
        catch { check(true, "simulation never silently loaded as live") }
        do { try book.record(example("bad", after: frame(-1))); check(false, "future leakage") }
        catch { check(true, "after must follow before") }
        let backwards = ExperienceCase(id: "back", run: "r", action: "go", before: frame(1, ["Q": 2]),
            after: frame(2, ["Q": 1]), reported: "ambiguous", blocked: nil, elapsed: 1)
        check(backwards.progressDelta == nil, "counter regression remains uncertain")
        let badFile = dir.appendingPathComponent("missing-parent/memory.json")
        let volatile = try ExperienceStore(scope: "test", url: badFile)
        try volatile.record(example("v"))
        check(volatile.persistenceError != nil && volatile.cases.count == 1, "I/O failure visible; memory not silently lost")
        let capped = try ExperienceStore(scope: "bounded")
        for i in 0..<257 { try capped.record(example(String(i))) }
        check(capped.cases.count == 256 && capped.cases.first?.id == "1", "bounded retention")
        check(capped.hint(context)["matching_cases"] as? Int == 256, "counts describe retained cache")
        check((book.hint(context)["blocked_cases"] as? Int) == 1, "hint exposes blocked evidence without a call")
        check((book.hint(context)["counter_unknown_cases"] as? Int) == 2, "hint retains uncertain outcomes")
        check(book.summary["cases"] as? Int == 5 && book.summary["reviews"] as? Int == 1, "small manifest summary")
        check(book.reviews.count == 1 && book.cases[4].reported.contains("fixture"), "review leaves outcome evidence unchanged")
        print("experience checks passed: \(n)")
    }
}
