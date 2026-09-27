// The run report: the metrics every change to the decision path is judged by, and the failure
// records the offline learning loop reads. Built from a run's events.jsonl. Pure Foundation.
import Foundation

struct RunEvent {
    var t: Double
    var name: String
    var fields: [String: Any]
}

/// One failure, with everything the analyst needs to classify it without the whole log.
struct FailureRecord {
    var t: Double
    var task: String
    var kind: FailureKind
    var code: String
    var detail: String
    var frame: String?       // the saved frame's path, when the event named one
    var hypothesis: String?  // left empty here; the offline loop fills it in review

    var json: [String: Any] {
        ["t": t, "task": task, "kind": kind.rawValue, "code": code, "detail": detail,
         "frame": frame as Any? ?? NSNull(), "hypothesis": hypothesis as Any? ?? NSNull()]
    }
}

struct RunReport {
    var runID: String
    var seconds: Double = 0
    var decisionsByController: [String: Int] = [:]
    var judgeCalls = 0
    var judgeLatencies: [Double] = []
    var promptTokens = 0
    var completionTokens = 0
    var usageMissing = 0
    var frames = 0
    var unreadFrames = 0
    var deaths = 0
    var questsCompleted = 0
    var questsAccepted = 0
    var kills = 0
    var failuresByKind: [String: Int] = [:]
    var failures: [FailureRecord] = []
    var outcome: String?

    func percentile(_ p: Double) -> Double? {
        guard !judgeLatencies.isEmpty else { return nil }
        let sorted = judgeLatencies.sorted()
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count) * p).rounded(.up)) - 1))
        return sorted[index]
    }

    var json: [String: Any] {
        ["run_id": runID, "seconds": seconds, "decisions_by_controller": decisionsByController,
         "judge_calls": judgeCalls, "judge_latency_p50": percentile(0.5) as Any? ?? NSNull(),
         "judge_latency_p95": percentile(0.95) as Any? ?? NSNull(),
         "prompt_tokens": promptTokens, "completion_tokens": completionTokens, "usage_missing": usageMissing,
         "frames": frames, "unread_frames": unreadFrames,
         "unread_frame_rate": frames > 0 ? Double(unreadFrames) / Double(frames) : NSNull(),
         "deaths": deaths, "quests_completed": questsCompleted, "quests_accepted": questsAccepted, "kills": kills,
         "quests_per_hour": seconds > 0 ? Double(questsCompleted) * 3600 / seconds : NSNull(),
         "failures_by_kind": failuresByKind, "failures": failures.map(\.json), "outcome": outcome as Any? ?? NSNull()]
    }
}

enum RunReportBuilder {
    /// One event per line, as `Log.emit` writes them: {"t": seconds, "event": name, ...fields}. A line that does
    /// not parse is skipped and counted, never guessed.
    static func parseEvents(_ jsonl: String) -> (events: [RunEvent], skipped: Int) {
        var events: [RunEvent] = [], skipped = 0
        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = object["event"] as? String else { skipped += 1; continue }
            let t = (object["t"] as? Double) ?? (object["t"] as? Int).map(Double.init) ?? 0
            var fields = object
            fields.removeValue(forKey: "event"); fields.removeValue(forKey: "t")
            events.append(RunEvent(t: t, name: name, fields: fields))
        }
        return (events, skipped)
    }

    /// The existing event names of the probes are read where they carry the fact; a future engine emits the
    /// generic `task_failed`, `judge_call`, `frame` and `death` events directly.
    static func build(runID: String, events: [RunEvent]) -> RunReport {
        var r = RunReport(runID: runID)
        if let first = events.first, let last = events.last { r.seconds = max(0, last.t - first.t) }
        for e in events {
            switch e.name {
            case "quest_step", "decision", "reflex", "recover", "leave_danger", "equip":
                let controller = (e.fields["controller"] as? String) ?? (e.name == "decision" ? "JEV" : "RULE")
                r.decisionsByController[controller, default: 0] += 1
            case "graph_call", "judge_call":
                r.judgeCalls += 1
                if let l = e.fields["latency_s"] as? Double { r.judgeLatencies.append(l) }
                if let usage = e.fields["usage"] as? [String: Any] {
                    r.promptTokens += (usage["prompt_tokens"] as? Int) ?? 0
                    r.completionTokens += (usage["completion_tokens"] as? Int) ?? 0
                } else if let response = e.fields["response"] as? [String: Any], let usage = response["usage"] as? [String: Any] {
                    r.promptTokens += (usage["prompt_tokens"] as? Int) ?? 0
                    r.completionTokens += (usage["completion_tokens"] as? Int) ?? 0
                } else { r.usageMissing += 1 }
            case "frame", "look":
                r.frames += 1
                if e.fields["unread"] as? Bool == true || e.fields["position"] is NSNull { r.unreadFrames += 1 }
            case "frame_wait", "position_turn":
                r.unreadFrames += 1
            case "death", "revive":
                r.deaths += e.name == "death" ? 1 : 0
            case "task_failed", "proposal_rejected", "jev_error":
                let code = (e.fields["code"] as? String) ?? (e.fields["reason"] as? String) ?? (e.fields["error"] as? String) ?? e.name
                let kind = (e.fields["kind"] as? String).flatMap(FailureKind.init(rawValue:)) ?? failureKind(forCode: code)
                let record = FailureRecord(t: e.t, task: (e.fields["task"] as? String) ?? (e.fields["skill"] as? String) ?? "?",
                                           kind: kind, code: code, detail: (e.fields["detail"] as? String) ?? "",
                                           frame: e.fields["frame"] as? String, hypothesis: nil)
                r.failures.append(record)
                r.failuresByKind[kind.rawValue, default: 0] += 1
            case "quests_done", "skill_result", "hunt_done", "fight_done":
                if let outcome = e.fields["outcome"] as? String ?? e.fields["code"] as? String {
                    r.outcome = outcome
                    if e.name == "fight_done", outcome.hasPrefix("KILLED") { r.kills += 1 }
                }
                if let steps = e.fields["steps"] as? [[String: Any]] {
                    for s in steps {
                        let outcome = (s["outcome"] as? String) ?? ""
                        if outcome.hasPrefix("COMPLETED") { r.questsCompleted += 1 }
                        if outcome.hasPrefix("ACCEPTED") { r.questsAccepted += 1 }
                        if outcome.hasPrefix("FIGHT_") || outcome.hasPrefix("WALK_") || outcome.hasPrefix("HUNT_")
                            || outcome == "DIALOGUE_NOT_OPEN" || outcome.hasPrefix("NO_") {
                            let kind = failureKind(forCode: outcome)
                            r.failures.append(FailureRecord(t: e.t, task: (s["quest"] as? String) ?? "?", kind: kind,
                                                            code: outcome, detail: "", frame: nil, hypothesis: nil))
                            r.failuresByKind[kind.rawValue, default: 0] += 1
                        }
                    }
                }
            default:
                break
            }
        }
        return r
    }
}
