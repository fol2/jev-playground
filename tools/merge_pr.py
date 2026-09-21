#!/usr/bin/env python3
"""Exact-head GitHub integration. Read-only unless --execute is explicitly supplied."""
from __future__ import annotations
import argparse
from datetime import datetime
import json
import re
import subprocess
import sys

REPO = "fol2/jev-playground"
PREFIX = "repos/" + REPO
PATH = ".github/workflows/ai-sdlc.yml"
WORKFLOW_ID = 363313034  # native identity observed when this repository workflow was registered


class Hold(ValueError):
    pass


def api(path: str, body: dict | None = None) -> object:
    command = ["gh", "api", "--hostname", "github.com", path]
    if body is not None:
        command += ["--method", "POST", "--input", "-"]
    result = subprocess.run(command, input=None if body is None else json.dumps(body),
                            text=True, capture_output=True, timeout=60)
    if result.returncode:
        raise Hold("GitHub request failed; no merge attempted for failed preflight")
    return json.loads(result.stdout)


def pages(path: str, key: str | None = None) -> list:
    items = []
    for page in range(1, 51):
        response = api(path + ("&" if "?" in path else "?") + f"per_page=100&page={page}")
        batch = response if key is None else response[key]
        if not isinstance(batch, list):
            raise Hold("malformed pagination response")
        items.extend(batch)
        if len(batch) < 100:
            return items
    raise Hold("pagination limit reached; refusing incomplete evidence")


def threads(number: int) -> list:
    query = '''query($owner:String!,$name:String!,$number:Int!,$after:String){
      repository(owner:$owner,name:$name){pullRequest(number:$number){
        reviewThreads(first:100,after:$after){nodes{isResolved}
          pageInfo{hasNextPage endCursor}}}}}'''
    cursor = None
    result = []
    for _ in range(50):
        data = api("graphql", {"query": query, "variables": {
            "owner": "fol2", "name": "jev-playground", "number": number, "after": cursor}})
        if data.get("errors"):
            raise Hold("review-thread query failed")
        batch = data["data"]["repository"]["pullRequest"]["reviewThreads"]
        result.extend(batch["nodes"])
        if not batch["pageInfo"]["hasNextPage"]:
            return result
        new = batch["pageInfo"]["endCursor"]
        if not new or new == cursor:
            raise Hold("review-thread pagination did not advance")
        cursor = new
    raise Hold("review-thread pagination limit reached")


def review_order(review: dict) -> tuple:
    # IDs are allocated before a draft is submitted. Vetoes win ambiguous same-second ties.
    try:
        submitted = datetime.strptime(review["submitted_at"], "%Y-%m-%dT%H:%M:%SZ")
    except (KeyError, TypeError, ValueError) as exc:
        raise Hold("review submission time is unavailable or malformed") from exc
    body = review.get("body") or ""
    blocking = review["state"] in {"CHANGES_REQUESTED", "DISMISSED"} or bool(
        re.search(r"^AI-SDLC review: (REQUEST_CHANGES|INCONCLUSIVE)$", body, re.M))
    return submitted, blocking, review["id"]


def evaluate(s: dict, number: int, head: str, into: str = "main") -> dict:
    """Pure merge decision; network reads and mutation are deliberately separate."""
    def require(condition: bool, reason: str) -> None:
        if not condition:
            raise Hold(reason)
    require(bool(re.fullmatch(r"[0-9a-f]{40}", head)), "full expected head SHA required")
    p = s["pr"]
    require(p["number"] == number and p["state"] == "open" and not p["draft"] and not p["merged"], "PR is not open and ready")
    require(p["head"]["sha"] == head, "PR head moved")
    require(p["head"]["repo"]["full_name"] == REPO and p["base"]["repo"]["full_name"] == REPO, "foreign repository")
    require(p["base"]["ref"] == into and p["head"]["ref"] != into, "unexpected integration branches")
    require(p["base"]["sha"] == s["integration"] and s["compare"]["status"] == "ahead",
            "integration branch is not included")
    # Merging into a topic branch still must not promote work that predates current main.
    require(s["main_compare"]["status"] in {"ahead", "identical"}, "current main is not included")
    require(p["mergeable"] is True and p["mergeable_state"] == "clean", "mergeability is not clean")
    runs = s["runs"]
    require(bool(runs), "no exact-head PR workflow run")
    run = max(runs, key=lambda x: (x["run_number"], x.get("run_attempt", 1)))
    require(run["workflow_id"] == WORKFLOW_ID and run["path"] == PATH and run["head_sha"] == head and run["event"] == "pull_request", "workflow identity mismatch")
    require(run["head_repository"]["full_name"] == REPO and any(x["number"] == number for x in run["pull_requests"]), "run is not bound to this PR")
    require(run["status"] == "completed" and run["conclusion"] == "success", "latest workflow is not successful")
    jobs = s["jobs"]
    focus = [x for x in jobs if x["name"] == "Focus Gate"]
    require(len(focus) == 1 and focus[0]["conclusion"] == "success" and
            focus[0]["status"] == "completed" and focus[0]["run_id"] == run["id"], "authentic Focus Gate did not pass")
    require(all(c["status"] == "completed" and c["conclusion"] in {"success", "neutral", "skipped"}
                for c in s["checks"]), "another check is pending or failed")
    require(all(c["state"] == "success" for c in s["statuses"]), "commit status is pending or failed")
    decisions, native = {}, {}
    for review in sorted((r for r in s["reviews"] if r["state"] != "PENDING"), key=review_order):
        actor = review["user"]["login"]
        if review["state"] in {"CHANGES_REQUESTED", "APPROVED"}:
            native[actor] = review["state"]
        if review["commit_id"] != head or review["author_association"] not in {"OWNER", "MEMBER", "COLLABORATOR"}:
            continue
        verdicts = re.findall(r"^AI-SDLC review: (PASS|REQUEST_CHANGES|INCONCLUSIVE)$", review.get("body") or "", re.M)
        require(len(verdicts) <= 1, "ambiguous review verdict")
        if verdicts:
            decisions[actor] = (review, verdicts[0])
    require("CHANGES_REQUESTED" not in native.values(), "native changes-requested review remains")
    require(bool(decisions), "no trusted exact-head review verdict")
    for review, verdict in decisions.values():
        require(verdict == "PASS" and review["state"] in {"COMMENTED", "APPROVED"}, "review is not PASS")
        require(bool(re.search(r"^Independence: (fresh-context|author-review|deterministic)$", review["body"], re.M)), "review independence is undisclosed")
        require(f"Head: {head}" in review["body"].splitlines(), "review text head mismatch")
        require(not (review["state"] == "APPROVED" and review["user"]["login"] == p["user"]["login"]), "author must not self-approve")
    require(all(t["isResolved"] is True for t in s["threads"]), "unresolved review thread")
    return {"decision": "ELIGIBLE", "pr": number, "head": head, "base": s["integration"],
            "integration_ref": into, "workflow_run": run["id"], "live_effect_authority": "none"}


def collect(number: int, head: str, into: str = "main") -> dict:
    p = api(f"{PREFIX}/pulls/{number}")
    integration = api(f"{PREFIX}/branches/{into}")["commit"]["sha"]
    runs = pages(f"{PREFIX}/actions/runs?event=pull_request&head_sha={head}", "workflow_runs")
    runs = [r for r in runs if r["workflow_id"] == WORKFLOW_ID]
    latest = max(runs, key=lambda x: (x["run_number"], x.get("run_attempt", 1))) if runs else None
    compare = api(f"{PREFIX}/compare/{integration}...{head}")
    return {"pr": p, "integration": integration, "runs": runs, "compare": compare,
            "main_compare": compare if into == "main" else api(f"{PREFIX}/compare/main...{head}"),
            "jobs": pages(f"{PREFIX}/actions/runs/{latest['id']}/jobs?filter=latest", "jobs") if latest else [],
            "checks": pages(f"{PREFIX}/commits/{head}/check-runs?filter=latest", "check_runs"),
            "statuses": pages(f"{PREFIX}/commits/{head}/status", "statuses"),
            "reviews": pages(f"{PREFIX}/pulls/{number}/reviews"), "threads": threads(number)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pr", type=int)
    parser.add_argument("head")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--into", default="main",
                        help="integration branch; anything but main must be named explicitly")
    args = parser.parse_args()
    try:
        if args.pr <= 0 or not re.fullmatch(r"[0-9a-f]{40}", args.head):
            raise Hold("positive PR number and full expected head SHA required")
        # Interpolated into an API path, so no traversal, no empty or absolute segments.
        if ".." in args.into or len(args.into) > 100 or not re.fullmatch(
                r"[A-Za-z0-9._-]+(?:/[A-Za-z0-9._-]+)*", args.into):
            raise Hold("malformed integration branch")
        snapshot = collect(args.pr, args.head, args.into)
        decision = evaluate(snapshot, args.pr, args.head, args.into)
        if args.execute:
            # Re-read immediately; GitHub's SHA guard closes the head race, not the base race.
            p = api(f"{PREFIX}/pulls/{args.pr}")
            base = api(f"{PREFIX}/branches/{args.into}")["commit"]["sha"]
            if p["head"]["sha"] != args.head or p["base"]["sha"] != decision["base"] or base != decision["base"]:
                raise Hold("integration state moved; revalidate")
            result = subprocess.run(["gh", "api", "--hostname", "github.com", "--method", "PUT",
                                     f"{PREFIX}/pulls/{args.pr}/merge", "--input", "-"],
                                    input=json.dumps({"sha": args.head, "merge_method": "squash"}),
                                    text=True, capture_output=True, timeout=60)
            if result.returncode:
                raise Hold("merge request failed; read GitHub state before retrying")
            merged = json.loads(result.stdout)
            readback = api(f"{PREFIX}/pulls/{args.pr}")
            if not merged.get("merged") or not readback["merged"] or readback["merge_commit_sha"] != merged["sha"]:
                raise Hold("merge outcome inconclusive; inspect readback, do not blindly retry")
            decision.update(decision="MERGED", merge_sha=merged["sha"])
        print(json.dumps(decision, indent=2))
        return 0
    except Hold as exc:
        print(f"HOLD: {exc}", file=sys.stderr)
        return 1
    except (KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError):
        # No raw API output or credential-bearing diagnostics in evidence.
        print("HOLD: merge preflight/action could not be proved; inspect exact GitHub state", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
