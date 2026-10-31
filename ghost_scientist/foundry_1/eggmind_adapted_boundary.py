#!/usr/bin/env python3
"""Strict paper-derived EqSatL boundary. This is not the EggMind system."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any


NAME = re.compile(r"^[A-Za-z][A-Za-z0-9_]{0,63}$")


class EqSatLReject(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def exact_keys(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise EqSatLReject(f"{context} keys")
    return value


def name(value: object, context: str) -> str:
    if not isinstance(value, str) or NAME.fullmatch(value) is None:
        raise EqSatLReject(f"{context} name")
    return value


def positive_int(value: object, context: str) -> int:
    if type(value) is not int or value <= 0:
        raise EqSatLReject(f"{context} positive integer")
    return value


def theta(value: object, context: str) -> float:
    if type(value) not in {int, float} or not 0.0 < float(value) <= 1.0:
        raise EqSatLReject(f"{context} theta")
    return float(value)


def parse_flow(value: object, rulesets: set[str]) -> dict[str, Any]:
    row = exact_keys(value, {"sequence"}, "flow")
    sequence = row["sequence"]
    if not isinstance(sequence, list) or not sequence:
        raise EqSatLReject("sequence")
    parsed = [parse_node(item, rulesets) for item in sequence]
    return {"sequence": parsed}


def parse_node(value: object, rulesets: set[str]) -> dict[str, Any]:
    if not isinstance(value, dict) or len(value) != 1:
        raise EqSatLReject("node shape")
    kind = next(iter(value))
    body = value[kind]
    if kind == "phase":
        row = exact_keys(
            body, {"name", "ruleset", "iter_limit"}, "phase"
        )
        phase_ruleset = name(row["ruleset"], "phase ruleset")
        if phase_ruleset not in rulesets:
            raise EqSatLReject("unknown ruleset")
        return {
            "phase": {
                "name": name(row["name"], "phase"),
                "ruleset": phase_ruleset,
                "iter_limit": positive_int(row["iter_limit"], "phase"),
            }
        }
    if kind == "repeat":
        row = exact_keys(body, {"flow", "rounds"}, "repeat")
        parsed_flow = parse_flow(row["flow"], rulesets)
        last = parsed_flow["sequence"][-1]
        if not (
            "heuristic_simplify" in last
            or "hint_guided_simplify" in last
        ):
            raise EqSatLReject("repeat must end in simplify")
        return {
            "repeat": {
                "flow": parsed_flow,
                "rounds": positive_int(row["rounds"], "repeat"),
            }
        }
    if kind == "heuristic_simplify":
        row = exact_keys(body, {"theta"}, "heuristic simplify")
        return {"heuristic_simplify": {"theta": theta(row["theta"], kind)}}
    if kind == "hint_guided_simplify":
        row = exact_keys(body, {"theta", "hints"}, "hint simplify")
        hints = row["hints"]
        if not isinstance(hints, list):
            raise EqSatLReject("hints")
        parsed_hints = []
        for hint in hints:
            pair = exact_keys(
                hint, {"preferred_pattern", "pruned_pattern"}, "hint"
            )
            preferred = name(pair["preferred_pattern"], "preferred pattern")
            pruned = name(pair["pruned_pattern"], "pruned pattern")
            if preferred == pruned:
                raise EqSatLReject("reflexive hint")
            parsed_hints.append(
                {
                    "preferred_pattern": preferred,
                    "pruned_pattern": pruned,
                }
            )
        return {
            "hint_guided_simplify": {
                "theta": theta(row["theta"], kind),
                "hints": parsed_hints,
            }
        }
    raise EqSatLReject("unknown node")


def parse_strategy(value: object) -> dict[str, Any]:
    row = exact_keys(value, {"name", "rulesets", "flow"}, "strategy")
    raw_rulesets = row["rulesets"]
    if not isinstance(raw_rulesets, list) or not raw_rulesets:
        raise EqSatLReject("rulesets")
    parsed_rulesets = []
    seen: set[str] = set()
    for raw_ruleset in raw_rulesets:
        item = exact_keys(raw_ruleset, {"name", "tags"}, "ruleset")
        ruleset_name = name(item["name"], "ruleset")
        tags = item["tags"]
        if (
            ruleset_name in seen
            or not isinstance(tags, list)
            or not tags
            or len(set(tags)) != len(tags)
        ):
            raise EqSatLReject("ruleset uniqueness")
        parsed_tags = [name(tag, "tag") for tag in tags]
        seen.add(ruleset_name)
        parsed_rulesets.append(
            {"name": ruleset_name, "tags": parsed_tags}
        )
    parsed = {
        "name": name(row["name"], "strategy"),
        "rulesets": parsed_rulesets,
        "flow": parse_flow(row["flow"], seen),
    }
    return parsed


def lower(strategy: dict[str, Any]) -> list[dict[str, Any]]:
    actions: list[dict[str, Any]] = []

    def visit_flow(flow: dict[str, Any]) -> None:
        for node in flow["sequence"]:
            if "repeat" in node:
                repeat = node["repeat"]
                for _ in range(repeat["rounds"]):
                    visit_flow(repeat["flow"])
            else:
                actions.append(node)

    visit_flow(strategy["flow"])
    return actions


def strategy_digest(strategy: dict[str, Any]) -> str:
    return hashlib.sha256(canonical(strategy).encode()).hexdigest()


def rank_motifs(motifs: list[dict[str, Any]]) -> list[list[str]]:
    rows = []
    for motif in motifs:
        tags = motif["tags"]
        gain = motif["relative_gain"]
        frequency = motif["successful_case_frequency"]
        if (
            not isinstance(tags, list)
            or not tags
            or any(not isinstance(tag, str) for tag in tags)
            or type(gain) not in {int, float}
            or not 0.0 <= float(gain) < 1.0
            or type(frequency) is not int
            or frequency <= 0
        ):
            raise EqSatLReject("motif")
        rows.append((float(gain) * frequency, list(tags)))
    rows.sort(key=lambda item: (-item[0], item[1]))
    return [tags for _, tags in rows]


def risk_score(model: dict[str, Any]) -> dict[str, float]:
    phases = model["phase_assignment"]
    coeff = model["coefficients"]
    terms = {
        "forward": 0.0,
        "backflow": 0.0,
        "phase_1_inflow": 0.0,
        "same_phase": 0.0,
    }
    for edge in model["edges"]:
        source = phases[edge["source"]]
        target = phases[edge["target"]]
        weight = float(edge["weight"])
        if source + 1 == target:
            terms["forward"] += coeff["alpha"] * weight
        if source > target:
            terms["backflow"] -= coeff["beta"] * weight
        if target == 1 and source != 1:
            terms["phase_1_inflow"] -= coeff["gamma"] * weight
        if source == target:
            terms["same_phase"] -= coeff["delta"] * weight
    terms["total"] = sum(terms.values())
    return terms
