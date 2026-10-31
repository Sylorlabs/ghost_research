#!/usr/bin/env python3
"""Cross-check the paper-derived ADAPTED EggMind boundary."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

import eggmind_adapted_boundary as primary
import independent_eggmind_boundary as independent


HERE = pathlib.Path(__file__).resolve().parent
FIXTURE = HERE / "external_controls/eggmind/conformance_fixture_v1.json"
SOURCE_ROUTE = HERE / "results/phase70_eggmind_source_route_audit.json"
RESULT = HERE / "results/phase71_eggmind_adapted_boundary_conformance.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def hostile_rows(strategy: dict) -> list[tuple[str, dict]]:
    rows = []
    mutation = copy.deepcopy(strategy)
    mutation["surprise"] = True
    rows.append(("unknown_top_level_key", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["rulesets"].append(copy.deepcopy(mutation["rulesets"][0]))
    rows.append(("duplicate_ruleset", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["flow"]["sequence"][1]["phase"]["ruleset"] = "absent"
    rows.append(("unknown_ruleset_reference", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["flow"]["sequence"][0]["repeat"]["rounds"] = 0
    rows.append(("zero_repeat_rounds", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["flow"]["sequence"][0]["repeat"]["flow"]["sequence"].pop()
    rows.append(("repeat_without_terminal_simplify", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["flow"]["sequence"][0]["repeat"]["flow"]["sequence"][-1][
        "heuristic_simplify"
    ]["theta"] = 1.5
    rows.append(("invalid_theta", mutation))
    mutation = copy.deepcopy(strategy)
    mutation["flow"]["sequence"][1] = {"strategy_label": "not_an_action"}
    rows.append(("strategy_label_substituted_for_action", mutation))
    return rows


def run() -> None:
    fixture_raw = FIXTURE.read_bytes()
    fixture = json.loads(fixture_raw)
    source_route = json.loads(SOURCE_ROUTE.read_text(encoding="utf-8"))
    strategy = fixture["strategy"]
    primary_strategy = primary.parse_strategy(strategy)
    independent_strategy = independent.parse_strategy(strategy)
    primary_actions = primary.lower(primary_strategy)
    independent_counts = independent.count_actions(
        independent_strategy["flow"]
    )
    primary_counts = (
        len(primary_actions),
        sum("phase" in action for action in primary_actions),
        sum(
            "heuristic_simplify" in action
            or "hint_guided_simplify" in action
            for action in primary_actions
        ),
    )
    expected = fixture["expected"]
    expected_counts = (
        expected["lowered_action_count"],
        expected["phase_action_count"],
        expected["simplify_action_count"],
    )
    primary_motifs = primary.rank_motifs(fixture["motifs"])
    independent_motifs = independent.rank_motifs(fixture["motifs"])
    primary_risk = primary.risk_score(fixture["risk_model"])
    independent_risk = independent.risk_score(fixture["risk_model"])
    expected_risk = fixture["risk_model"]["expected_terms"]

    rejected = []
    for name, mutation in hostile_rows(strategy):
        primary_rejected = independent_rejected = False
        try:
            primary.parse_strategy(mutation)
        except primary.EqSatLReject:
            primary_rejected = True
        try:
            independent.parse_strategy(mutation)
        except independent.IndependentReject:
            independent_rejected = True
        rejected.append(
            {
                "name": name,
                "primary_rejected": primary_rejected,
                "independent_rejected": independent_rejected,
            }
        )
    checks = {
        "source_route_requires_adaptation": (
            source_route["status"]
            == "EGGMIND_UPSTREAM_SOURCE_NOT_DISCOVERED"
            and source_route["P1"]["complete"] is False
        ),
        "strict_parsers_canonicalize_identically": (
            primary.strategy_digest(primary_strategy)
            == independent.digest(independent_strategy)
        ),
        "lowered_schedule_counts_exact": (
            primary_counts == independent_counts == expected_counts
        ),
        "all_rulesets_referenced": sorted(
            {
                action["phase"]["ruleset"]
                for action in primary_actions
                if "phase" in action
            }
        )
        == expected["referenced_rulesets"],
        "motif_ranking_recomputed_independently": (
            primary_motifs
            == independent_motifs
            == fixture["expected_motif_order"]
        ),
        "risk_equation_recomputed_independently": (
            primary_risk == independent_risk == expected_risk
        ),
        "seven_hostile_mutations_rejected_twice": (
            len(rejected) == 7
            and all(
                row["primary_rejected"] and row["independent_rejected"]
                for row in rejected
            )
        ),
        "full_upstream_claim_forbidden": fixture["adaptation_boundary"][
            "full_eggmind_conformance_claim_allowed"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError("adapted EggMind boundary conformance failed")
    payload = {
        "version": "FOUNDRY_EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_V1",
        "status": "EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_PASS",
        "classification": "PAPER_DERIVED_ADAPTED_PARTIAL_NOT_UPSTREAM",
        "fixture_sha256": hashlib.sha256(fixture_raw).hexdigest(),
        "strategy_sha256": primary.strategy_digest(primary_strategy),
        "checks": checks,
        "schedule_counts": {
            "actions": primary_counts[0],
            "phases": primary_counts[1],
            "simplifications": primary_counts[2],
        },
        "motif_order": primary_motifs,
        "risk_terms": primary_risk,
        "hostile_rejections": rejected,
        "implemented_surfaces": [
            "strict EqSatL artifact parsing",
            "phase, sequence, repeat, and simplify lowering",
            "paper-compatible motif utility ordering",
            "published dependency-risk objective"
        ],
        "unimplemented_surfaces": [
            "upstream EggMind source",
            "LLM strategist, generator, partitioner, and simplifier",
            "proof-object motif extraction",
            "egglog backend lowering and execution",
            "source-paper end-to-end workload reproduction",
            "production Foundry A8 integration and equal-budget metering"
        ],
        "P1": {
            "adapted_boundary_conformance_passed": True,
            "full_eggmind_style_control_conformance_passed": False,
            "production_integrated": False,
            "complete": False,
        },
        "claim_boundary": (
            "The result validates an independently parsed paper-derived "
            "EqSatL and scoring boundary. It is not EggMind, does not execute "
            "the authors' strategy-synthesis system, and does not satisfy A8."
        ),
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE71_EGGMIND_ADAPTED_BOUNDARY"
        f" status={payload['status']}"
        f" actions={primary_counts[0]}"
        f" hostile={len(rejected)}"
        " a8_complete=false"
    )


if __name__ == "__main__":
    run()
