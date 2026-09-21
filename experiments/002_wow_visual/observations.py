"""Offline screen-evidence boundary. No capture, model call or input executor.

This validates provenance/shape, not the truth of a detector's interpretation.
Times must share the caller's monotonic clock; ROI coordinates are capture pixels.
"""
from copy import deepcopy
import math

SCHEMA = "screen-evidence/v1"
METHODS = {"pixels", "ocr", "motion"}


class InvalidObservation(ValueError):
    """The packet must not be passed to a policy."""


def _number(value: object) -> bool:
    try:
        return type(value) in (int, float) and math.isfinite(value)
    except OverflowError:
        return False


def policy_state(packet: dict, *, now: float, max_age: float,
                 stream_id: str, geometry_id: str) -> dict:
    """Return a detached, bounded Jev-ready state or fail closed.

    Identity and freshness are local checks, never probabilistic model decisions.
    Unknown is represented explicitly; missing pixels are not a negative fact.
    max_age is supplied by each experiment, not a universal combat deadline.
    """
    def require(condition, reason):
        if not condition:
            raise InvalidObservation(reason)

    require(isinstance(packet, dict), "packet must be an object")
    require(set(packet) == {"schema", "stream_id", "geometry_id", "frame_id",
                            "captured_at", "size", "facts"}, "unexpected packet fields")
    require(packet["schema"] == SCHEMA, "unsupported schema")
    require(all(isinstance(x, str) and 0 < len(x) <= 128 for x in
                [stream_id, geometry_id, packet["stream_id"], packet["geometry_id"]]), "invalid identity")
    require(packet["stream_id"] == stream_id and packet["geometry_id"] == geometry_id,
            "stream or geometry changed")
    require(type(packet["frame_id"]) is int and 0 <= packet["frame_id"] < 2**63, "invalid frame ID")
    captured = packet["captured_at"]
    require(_number(now) and _number(captured) and _number(max_age) and max_age > 0,
            "invalid clock or deadline")
    require(captured >= 0 and captured <= now < captured+max_age, "stale or future evidence")
    size = packet["size"]
    require(isinstance(size, list) and len(size) == 2 and
            all(type(x) is int and 0 < x <= 32768 for x in size), "invalid capture size")
    facts = packet["facts"]
    require(isinstance(facts, dict) and len(facts) <= 64, "invalid or unbounded facts")
    for name, fact in facts.items():
        require(isinstance(name, str) and 0 < len(name) <= 128, "invalid fact name")
        require(isinstance(fact, dict) and set(fact) == {"status", "value", "method", "roi"},
                "unexpected fact fields")
        require(fact["method"] in METHODS if isinstance(fact["method"], str) else False,
                "unsupported observation method")
        if fact["status"] == "unknown":
            require(fact["value"] is None and fact["roi"] is None, "unknown cannot carry a fact")
            continue
        require(fact["status"] == "observed", "invalid observation status")
        value = fact["value"]
        require(type(value) is bool or _number(value) or
                (isinstance(value, str) and 0 < len(value) <= 512), "invalid or unbounded value")
        roi = fact["roi"]
        require(isinstance(roi, list) and len(roi) == 4 and all(_number(x) for x in roi),
                "observed fact needs a source ROI")
        x, y, w, h = roi
        require(x >= 0 and y >= 0 and w > 0 and h > 0 and
                x+w <= size[0] and y+h <= size[1], "ROI outside capture")
    return deepcopy(packet)
