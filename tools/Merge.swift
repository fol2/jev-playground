// Exact-head GitHub integration. Read-only unless --execute is explicitly supplied.
import Foundation

let repoName = "fol2/jev-playground"
let apiPrefix = "repos/" + repoName
let workflowPath = ".github/workflows/ai-sdlc.yml"
let workflowID = 363313034  // native identity observed when this repository workflow was registered

struct Hold: Error, CustomStringConvertible {
    let description: String
    init(_ d: String) { description = d }
}

// GitHub evidence is read as the Python tool read it, `x["key"]`: an absent field holds, never a default.
extension JSON {
    func need(_ key: String) throws -> JSON {
        guard let value = self[key] else { throw Hold("GitHub evidence lacks '\(key)'") }
        return value
    }
    func needString(_ key: String) throws -> String {
        guard let value = try need(key).string else { throw Hold("GitHub evidence has no text '\(key)'") }
        return value
    }
    func needList(_ key: String) throws -> [JSON] {
        guard let value = try need(key).items else { throw Hold("GitHub evidence has no list '\(key)'") }
        return value
    }
}

/// A review body as `review.get("body") or ""`: absent or null is empty; anything but text holds.
func reviewBody(_ review: JSON) throws -> String {
    switch review["body"] {
    case nil, .null?: return ""
    case let .string(body)?: return body
    default: throw Hold("review body is not text")
    }
}

/// Runs order by number, then attempt (1 when GitHub omits it); a run without a number holds.
func attempt(_ run: JSON) throws -> (Double, Double) {
    guard let number = run["run_number"]?.number, let tries = (run["run_attempt"] ?? .int(1)).number else {
        throw Hold("workflow run has no number or attempt")
    }
    return (number, tries)
}

/// GitHub through `gh api`: a GET, or a POST/PUT with a JSON body. The tests replace it.
struct GitHub {
    var call: (_ method: String, _ path: String, _ body: JSON?) throws -> JSON

    static let live = GitHub { method, path, body in
        var args = ["gh", "api", "--hostname", "github.com", path]
        if let _ = body { args += ["--method", method, "--input", "-"] }
        let ran = try sh(args, timeout: 60, input: body.map { Data($0.text().utf8) })
        guard ran.code == 0 else {
            throw Hold(method == "PUT" ? "merge request failed; read GitHub state before retrying"
                                       : "GitHub request failed; no merge attempted for failed preflight")
        }
        return try JSON.parse(ran.out)
    }

    func get(_ path: String) throws -> JSON { try call("GET", path, nil) }

    func pages(_ path: String, _ key: String? = nil) throws -> [JSON] {
        var items: [JSON] = []
        for page in 1...50 {
            let response = try get(path + (path.contains("?") ? "&" : "?") + "per_page=100&page=\(page)")
            guard let batch = (key.map { response[$0] } ?? response)?.items else { throw Hold("malformed pagination response") }
            items += batch
            if batch.count < 100 { return items }
        }
        throw Hold("pagination limit reached; refusing incomplete evidence")
    }

    func threads(_ number: Int) throws -> [JSON] {
        let query = """
            query($owner:String!,$name:String!,$number:Int!,$after:String){
              repository(owner:$owner,name:$name){pullRequest(number:$number){
                reviewThreads(first:100,after:$after){nodes{isResolved}
                  pageInfo{hasNextPage endCursor}}}}}
            """
        var cursor = JSON.null, result: [JSON] = []
        for _ in 0..<50 {
            let data = try call("POST", "graphql", .object([("query", .string(query)), ("variables", .object([
                ("owner", .string("fol2")), ("name", .string("jev-playground")), ("number", .int(number)), ("after", cursor)]))]))
            if truthy(data["errors"]) { throw Hold("review-thread query failed") }
            guard let batch = data["data"]?["repository"]?["pullRequest"]?["reviewThreads"], let nodes = batch["nodes"]?.items else {
                throw Hold("review-thread query failed")
            }
            result += nodes
            guard case let .bool(more)? = batch["pageInfo"]?["hasNextPage"] else { throw Hold("review-thread query failed") }
            if !more { return result }
            let next = batch["pageInfo"]?["endCursor"] ?? .null
            if !truthy(next) || next == cursor { throw Hold("review-thread pagination did not advance") }
            cursor = next
        }
        throw Hold("review-thread pagination limit reached")
    }
}

let githubTime: DateFormatter = {
    let format = DateFormatter()
    format.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
    format.timeZone = TimeZone(identifier: "UTC")
    format.locale = Locale(identifier: "en_US_POSIX")
    format.isLenient = false
    return format
}()

/// Lines split at "\n" only, as Python's re.M sees them: a CRLF line keeps its "\r" and does not match.
func verdictLines(_ body: String) -> [String] { body.components(separatedBy: "\n") }

/// IDs are allocated before a draft is submitted. Vetoes win ambiguous same-second ties.
func reviewOrder(_ review: JSON) throws -> (Date, Int, Int) {
    guard let text = review["submitted_at"]?.string, let submitted = githubTime.date(from: text),
          githubTime.string(from: submitted) == text else {
        throw Hold("review submission time is unavailable or malformed")
    }
    let body = try reviewBody(review)
    let blocking = ["CHANGES_REQUESTED", "DISMISSED"].contains(try review.needString("state"))
        || verdictLines(body).contains { $0 == "AI-SDLC review: REQUEST_CHANGES" || $0 == "AI-SDLC review: INCONCLUSIVE" }
    guard case let .int(id)? = review["id"] else { throw Hold("review has no id") }
    return (submitted, blocking ? 1 : 0, id)
}

/// Pure merge decision; network reads and mutation are deliberately separate.
func evaluate(_ s: JSON, number: Int, head: String, into: String = "main") throws -> JSON {
    func require(_ condition: Bool, _ reason: String) throws { if !condition { throw Hold(reason) } }
    try require(head.wholeMatch(of: #/[0-9a-f]{40}/#) != nil, "full expected head SHA required")
    guard let p = s["pr"] else { throw Hold("PR is not open and ready") }
    try require(p["number"] == .int(number) && p["state"] == .string("open") && !truthy(p.need("draft")) && !truthy(p.need("merged")),
                "PR is not open and ready")
    try require(p["head"]?["sha"] == .string(head), "PR head moved")
    try require(p["head"]?["repo"]?["full_name"] == .string(repoName) && p["base"]?["repo"]?["full_name"] == .string(repoName), "foreign repository")
    try require(p["base"]?["ref"] == .string(into) && p.need("head").need("ref") != .string(into), "unexpected integration branches")
    try require(try p.need("base").need("sha") == s.need("integration") && s["compare"]?["status"] == .string("ahead"), "integration branch is not included")
    // Merging into a topic branch still must not promote work that predates current main.
    try require(["ahead", "identical"].contains(s["main_compare"]?["status"]?.string ?? ""), "current main is not included")
    try require(p["mergeable"] == .bool(true) && p["mergeable_state"] == .string("clean"), "mergeability is not clean")
    let runs = s["runs"]?.items ?? []
    try require(!runs.isEmpty, "no exact-head PR workflow run")
    let run = try runs.map { ($0, try attempt($0)) }.max { $0.1 < $1.1 }!.0  // every run keyed, as max(key=) did
    try require(run["workflow_id"] == .int(workflowID) && run["path"] == .string(workflowPath) && run["head_sha"] == .string(head)
                && run["event"] == .string("pull_request"), "workflow identity mismatch")
    try require(run["head_repository"]?["full_name"] == .string(repoName)
                && (run["pull_requests"]?.items ?? []).contains { $0["number"] == .int(number) }, "run is not bound to this PR")
    try require(run["status"] == .string("completed") && run["conclusion"] == .string("success"), "latest workflow is not successful")
    let focus = (s["jobs"]?.items ?? []).filter { $0["name"] == .string("Focus Gate") }
    try require(focus.count == 1 && focus[0]["conclusion"] == .string("success") && focus[0]["status"] == .string("completed")
                && focus[0]["run_id"] == run.need("id"), "authentic Focus Gate did not pass")
    try require(try s.needList("checks").allSatisfy { $0["status"] == .string("completed")
                && ["success", "neutral", "skipped"].contains($0["conclusion"]?.string ?? "") }, "another check is pending or failed")
    try require(try s.needList("statuses").allSatisfy { $0["state"] == .string("success") }, "commit status is pending or failed")
    var decisions: [(actor: String, review: JSON, verdict: String)] = []
    var native: [String: String] = [:]
    let submitted = try s.needList("reviews").filter { try $0.needString("state") != "PENDING" }.map { ($0, try reviewOrder($0)) }
    for (review, _) in submitted.sorted(by: { $0.1 < $1.1 }) {
        let actor = try review.need("user").needString("login")
        let state = try review.needString("state")
        if ["CHANGES_REQUESTED", "APPROVED"].contains(state) { native[actor] = state }
        if try review.need("commit_id") != .string(head)
            || !["OWNER", "MEMBER", "COLLABORATOR"].contains(review.need("author_association").string ?? "") {
            continue
        }
        let verdicts = verdictLines(try reviewBody(review)).compactMap { line -> String? in
            ["PASS", "REQUEST_CHANGES", "INCONCLUSIVE"].first { line == "AI-SDLC review: " + $0 }
        }
        try require(verdicts.count <= 1, "ambiguous review verdict")
        if let verdict = verdicts.first {
            decisions.removeAll { $0.actor == actor }
            decisions.append((actor, review, verdict))
        }
    }
    try require(!native.values.contains("CHANGES_REQUESTED"), "native changes-requested review remains")
    try require(!decisions.isEmpty, "no trusted exact-head review verdict")
    for (_, review, verdict) in decisions {
        let body = review["body"]?.string ?? ""
        try require(verdict == "PASS" && ["COMMENTED", "APPROVED"].contains(review["state"]?.string ?? ""), "review is not PASS")
        try require(verdictLines(body).contains { ["Independence: fresh-context", "Independence: author-review", "Independence: deterministic"].contains($0) },
                    "review independence is undisclosed")
        try require(body.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).contains { $0 == "Head: \(head)" },
                    "review text head mismatch")
        try require(review["state"] != .string("APPROVED") || review.need("user").need("login") != p.need("user").need("login"),
                    "author must not self-approve")
    }
    try require(try s.needList("threads").allSatisfy { $0["isResolved"] == .bool(true) }, "unresolved review thread")
    return .object([("decision", .string("ELIGIBLE")), ("pr", .int(number)), ("head", .string(head)), ("base", s["integration"] ?? .null),
                    ("integration_ref", .string(into)), ("workflow_run", run["id"] ?? .null), ("live_effect_authority", .string("none"))])
}

func collect(_ github: GitHub, number: Int, head: String, into: String = "main") throws -> JSON {
    let p = try github.get("\(apiPrefix)/pulls/\(number)")
    guard let integration = try github.get("\(apiPrefix)/branches/\(into)")["commit"]?["sha"] else { throw Hold("integration branch unreadable") }
    let runs = try github.pages("\(apiPrefix)/actions/runs?event=pull_request&head_sha=\(head)", "workflow_runs")
        .filter { $0["workflow_id"] == .int(workflowID) }
    let latest = try runs.map { ($0, try attempt($0)) }.max { $0.1 < $1.1 }?.0
    let compare = try github.get("\(apiPrefix)/compare/\(integration.string ?? "")...\(head)")
    return .object([
        ("pr", p), ("integration", integration), ("runs", .array(runs)), ("compare", compare),
        ("main_compare", into == "main" ? compare : try github.get("\(apiPrefix)/compare/main...\(head)")),
        ("jobs", .array(try latest.map { try github.pages("\(apiPrefix)/actions/runs/\(try $0.need("id").text())/jobs?filter=latest", "jobs") } ?? [])),
        ("checks", .array(try github.pages("\(apiPrefix)/commits/\(head)/check-runs?filter=latest", "check_runs"))),
        ("statuses", .array(try github.pages("\(apiPrefix)/commits/\(head)/status", "statuses"))),
        ("reviews", .array(try github.pages("\(apiPrefix)/pulls/\(number)/reviews"))), ("threads", .array(try github.threads(number)))])
}

/// `tools/sdlc merge PR FULL_HEAD_SHA [--execute] [--into BRANCH]`; returns the exit status.
func mergeMain(_ arguments: [String], github: GitHub = .live, collect: (GitHub, Int, String, String) throws -> JSON = collect,
               say: (String) -> Void = { print($0) }) -> Int32 {
    var positional: [String] = [], execute = false, into = "main"
    var rest = arguments[...]
    while let arg = rest.popFirst() {
        switch arg {
        case "--execute": execute = true
        case "--into":
            guard let branch = rest.popFirst() else { return usage() }
            into = branch
        default: positional.append(arg)
        }
    }
    guard positional.count == 2, let number = Int(positional[0]) else { return usage() }
    let head = positional[1]
    do {
        if number <= 0 || head.wholeMatch(of: #/[0-9a-f]{40}/#) == nil { throw Hold("positive PR number and full expected head SHA required") }
        // Interpolated into an API path, so no traversal, no empty or absolute segments.
        if into.contains("..") || into.count > 100 || into.wholeMatch(of: #/[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*/#) == nil {
            throw Hold("malformed integration branch")
        }
        let snapshot = try collect(github, number, head, into)
        var decision = try evaluate(snapshot, number: number, head: head, into: into)
        if execute {
            // Re-read immediately; GitHub's SHA guard closes the head race, not the base race.
            let p = try github.get("\(apiPrefix)/pulls/\(number)")
            let base = try github.get("\(apiPrefix)/branches/\(into)")["commit"]?["sha"]
            if p["head"]?["sha"] != .string(head) || p["base"]?["sha"] != decision["base"] || base != decision["base"] {
                throw Hold("integration state moved; revalidate")
            }
            let merged = try github.call("PUT", "\(apiPrefix)/pulls/\(number)/merge",
                                         .object([("sha", .string(head)), ("merge_method", .string("squash"))]))
            let readback = try github.get("\(apiPrefix)/pulls/\(number)")
            guard merged["merged"] == .bool(true), readback["merged"] == .bool(true), let sha = merged["sha"],
                  readback["merge_commit_sha"] == sha else {
                throw Hold("merge outcome inconclusive; inspect readback, do not blindly retry")
            }
            decision = decision.setting("decision", .string("MERGED")).setting("merge_sha", sha)
        }
        say(decision.text(indent: 2))
        return 0
    } catch let hold as Hold {
        FileHandle.standardError.write(Data("HOLD: \(hold)\n".utf8))
        return 1
    } catch {
        // No raw API output or credential-bearing diagnostics in evidence.
        FileHandle.standardError.write(Data("HOLD: merge preflight/action could not be proved; inspect exact GitHub state\n".utf8))
        return 1
    }

    func usage() -> Int32 {
        FileHandle.standardError.write(Data("usage: tools/sdlc merge PR FULL_HEAD_SHA [--execute] [--into BRANCH]\n".utf8))
        return 2
    }
}
