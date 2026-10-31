#!/usr/bin/env python3
"""Independent small parser and equations for the paper-derived fixture."""

from __future__ import annotations

import hashlib
import json
from typing import Any


class IndependentReject(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def parse_strategy(value: object) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {"name", "rulesets", "flow"}:
        raise IndependentReject("strategy")
    rulesets = value["rulesets"]
    if not isinstance(rulesets, list) or not rulesets:
        raise IndependentReject("rulesets")
    names = set()
    for item in rulesets:
        if (
            not isinstance(item, dict)
            or set(item) != {"name", "tags"}
            or not isinstance(item["name"], str)
            or not item["name"]
            or item["name"] in names
            or not isinstance(item["tags"], list)
            or not item["tags"]
            or any(not isinstance(tag, str) or not tag for tag in item["tags"])
            or len(set(item["tags"])) != len(item["tags"])
        ):
            raise IndependentReject("ruleset")
        names.add(item["name"])

    def flow(row: object) -> dict[str, Any]:
        if (
            not isinstance(row, dict)
            or set(row) != {"sequence"}
            or not isinstance(row["sequence"], list)
            or not row["sequence"]
        ):
            raise IndependentReject("flow")
        parsed = [node(item) for item in row["sequence"]]
        return {"sequence": parsed}

    def node(row: object) -> dict[str, Any]:
        if not isinstance(row, dict) or len(row) != 1:
            raise IndependentReject("node")
        kind, body = next(iter(row.items()))
        if kind == "phase":
            if (
                not isinstance(body, dict)
                or set(body) != {"name", "ruleset", "iter_limit"}
                or body["ruleset"] not in names
                or type(body["iter_limit"]) is not int
                or body["iter_limit"] <= 0
            ):
                raise IndependentReject("phase")
            return row
        if kind == "repeat":
            if (
                not isinstance(body, dict)
                or set(body) != {"flow", "rounds"}
                or type(body["rounds"]) is not int
                or body["rounds"] <= 0
            ):
                raise IndependentReject("repeat")
            parsed_flow = flow(body["flow"])
            if not any(
                key in parsed_flow["sequence"][-1]
                for key in ("heuristic_simplify", "hint_guided_simplify")
            ):
                raise IndependentReject("repeat terminator")
            return {"repeat": {"flow": parsed_flow, "rounds": body["rounds"]}}
        if kind == "heuristic_simplify":
            if (
                not isinstance(body, dict)
                or set(body) != {"theta"}
                or type(body["theta"]) not in {int, float}
                or not 0 < body["theta"] <= 1
            ):
                raise IndependentReject("heuristic")
            return row
        if kind == "hint_guided_simplify":
            if (
                not isinstance(body, dict)
                or set(body) != {"theta", "hints"}
                or type(body["theta"]) not in {int, float}
                or not 0 < body["theta"] <= 1
                or not isinstance(body["hints"], list)
            ):
                raise IndependentReject("hint simplify")
            for hint in body["hints"]:
                if (
                    not isinstance(hint, dict)
                    or set(hint)
                    != {"preferred_pattern", "pruned_pattern"}
                    or hint["preferred_pattern"] == hint["pruned_pattern"]
                ):
                    raise IndependentReject("hint")
            return row
        raise IndependentReject("kind")

    parsed = {
        "name": value["name"],
        "rulesets": rulesets,
        "flow": flow(value["flow"]),
    }
    return parsed


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def count_actions(flow: dict[str, Any]) -> tuple[int, int, int]:
    phases = 0
    simplifies = 0

    def visit(row: dict[str, Any], multiplier: int) -> None:
        nonlocal phases, simplifies
        for node in row["sequence"]:
            if "repeat" in node:
                body = node["repeat"]
                visit(body["flow"], multiplier * body["rounds"])
            elif "phase" in node:
                phases += multiplier
            else:
                simplifies += multiplier

    visit(flow, 1)
    return phases + simplifies, phases, simplifies


def rank_motifs(motifs: list[dict[str, Any]]) -> list[list[str]]:
    return [
        row["tags"]
        for row in sorted(
            motifs,
            key=lambda row: (
                -row["relative_gain"] * row["successful_case_frequency"],
                row["tags"],
            ),
        )
    ]


def risk_score(model: dict[str, Any]) -> dict[str, float]:
    assignment = model["phase_assignment"]
    c = model["coefficients"]
    forward = backflow = inflow = same = 0.0
    for edge in model["edges"]:
        left = assignment[edge["source"]]
        right = assignment[edge["target"]]
        weight = edge["weight"]
        forward += c["alpha"] * weight if left + 1 == right else 0
        backflow -= c["beta"] * weight if left > right else 0
        inflow -= c["gamma"] * weight if right == 1 and left != 1 else 0
        same -= c["delta"] * weight if left == right else 0
    return {
        "forward": forward,
        "backflow": backflow,
        "phase_1_inflow": inflow,
        "same_phase": same,
        "total": forward + backflow + inflow + same,
    }
