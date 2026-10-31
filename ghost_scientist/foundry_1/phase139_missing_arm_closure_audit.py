#!/usr/bin/env python3
"""Rank the four missing production arms without opening validation-v6."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase139_missing_arm_closure_audit.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v6"

INPUTS = {
    "a1": "phase93_a1_ir_compatibility_audit.json",
    "a1_no_go": "phase131_a1_reference_fallback_no_go_audit.json",
    "a6": "phase136_isamore_exact_artifact_ingress_conformance.json",
    "a7": "phase105_a7_enumo_compatibility_audit.json",
    "a7_feasibility": "phase132_enumo_tensor_domain_feasibility.json",
    "a7_reuse": "phase133_enumo_tensor_rule_reuse_competitiveness.json",
    "a8": "phase135_eggmind_full_reproduction_sufficiency_audit.json",
    "readiness": "readiness_iteration_5_24.json",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(name: str) -> dict:
    path = RESULTS / INPUTS[name]
    if FORBIDDEN_FRAGMENT in str(path):
        raise RuntimeError("validation-v6 path forbidden")
    return json.loads(path.read_text())


def main() -> None:
    a1 = load("a1")
    a1_no_go = load("a1_no_go")
    a6 = load("a6")
    a7 = load("a7")
    a7_feasibility = load("a7_feasibility")
    a7_reuse = load("a7_reuse")
    a8 = load("a8")
    readiness = load("readiness")

    operator_counts: dict[str, int] = {}
    for graph in a1["graphs"]:
        for operator, count in graph["operator_counts"].items():
            operator_counts[operator] = operator_counts.get(operator, 0) + count
    tensor_island_targets = {
        "aten.add.Tensor",
        "aten.mul.Tensor",
        "aten.relu.default",
    }
    tensor_island_calls = sum(
        operator_counts.get(target, 0) for target in tensor_island_targets
    )
    tensor_island_graphs = sum(
        any(graph["operator_counts"].get(target, 0) for target in tensor_island_targets)
        for graph in a1["graphs"]
    )

    checks = {
        "readiness_is_6_of_6_but_6_of_10": (
            sum(readiness["prerequisites"].values()) == 6
            and readiness["authorization"]["prerequisites_passed"] == 6
            and readiness["authorization"][
                "required_arms_production_integrated"
            ]
            == 6
            and readiness["authorization"]["required_arms"] == 10
        ),
        "a1_shortcut_formally_rejected": (
            a1["summary"]["exact_constructor_pattern_candidates"] == 0
            and a1["mapping_counts"]["UNSUPPORTED"] == 21
            and a1["invocation_counts"]["UNSUPPORTED"] == 80
            and a1_no_go["status"]
            == "A1_OPAQUE_REFERENCE_FALLBACK_FORMALLY_REJECTED"
        ),
        "a6_real_ingress_empty": (
            a6["real_inbox"]["exact_artifacts_acquired"] == 0
            and a6["production_integrated_arms"] == 6
        ),
        "a7_direct_boolean_wrapper_rejected": (
            a7["status"] == "A7_DIRECT_ADAPTER_REJECTED"
            and a7["framework_surface"]["direct_call_matches"] == 0
        ),
        "a7_tensor_mechanism_exists_but_did_not_beat_fixed": (
            a7_feasibility["status"]
            == "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
            and len(a7_feasibility["observed"]["learned_rules"]) == 18
            and a7_reuse["observed"]["learned_strict_wins"] == 0
            and a7_reuse["observed"]["fixed_strict_wins"] == 736
        ),
        "a7_real_surface_has_declared_three_op_islands": (
            tensor_island_calls == 53 and tensor_island_graphs == 17
        ),
        "a8_reproduction_is_outcome_underdetermined": (
            a8["status"]
            == "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
            and a8["surface_counts"]["missing_outcome_determining"] == 16
        ),
        "validation_v6_unread": True,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "missing-arm ranking inputs changed: "
            + canonical({"failed": [key for key, value in checks.items() if not value]})
        )

    ranking = [
        {
            "rank": 1,
            "arm_id": "A7",
            "route": "prefrozen real-graph transfer falsification",
            "local_completion_class": "LOCALLY_TESTABLE_NOT_YET_INTEGRATABLE",
            "evidence": {
                "compatible_real_calls": tensor_island_calls,
                "compatible_real_graphs": tensor_island_graphs,
                "learned_rules": 18,
                "synthetic_learned_strict_wins": 0,
            },
            "next_gate": (
                "independently extract typed add/mul/relu islands, count direct "
                "learned-rule matches, and differentially check every matched "
                "rewrite on concrete calibration values"
            ),
        },
        {
            "rank": 2,
            "arm_id": "A1",
            "route": "complete evaluator-owned ATen to Operator-v5 typed lowering",
            "local_completion_class": "LOCALLY_IMPLEMENTABLE_LARGE_SEMANTIC_BRIDGE",
            "evidence": {
                "unsupported_targets": 21,
                "unsupported_calls": 80,
                "conditional_calls": 114,
                "exact_frozen_constructor_patterns": 0,
            },
            "next_gate": (
                "preserve complete value/type/layout/alias semantics and obtain "
                "a genuine frozen-constructor alternative without opaque fallback"
            ),
        },
        {
            "rank": 3,
            "arm_id": "A6",
            "route": "exact ISAMORE locked/native closure",
            "local_completion_class": "EXTERNALLY_BLOCKED_ARTIFACT_TRANSPORT",
            "evidence": {
                "real_complete_batches_staged": 0,
                "synthetic_ingress_passed": True,
            },
            "next_gate": "ingest and authenticate a complete exact real artifact batch",
        },
        {
            "rank": 4,
            "arm_id": "A8",
            "route": "distinctly named pre-registered adapted strategy synthesizer",
            "local_completion_class": "PAPER_UNDERDETERMINED_OR_UPSTREAM_UNAVAILABLE",
            "evidence": {
                "published_surfaces_preserved": 10,
                "outcome_determining_surfaces_missing": 16,
            },
            "next_gate": (
                "obtain upstream implementation or specify all missing policy "
                "surfaces before implementation and keep the adapted label"
            ),
        },
    ]
    payload = {
        "version": "FOUNDRY_MISSING_ARM_CLOSURE_AUDIT_V1",
        "status": "A7_REAL_GRAPH_TRANSFER_SELECTED_AS_NEXT_FALSIFICATION",
        "input_records": [
            {"path": f"results/{name}", "sha256": sha(RESULTS / name)}
            for name in INPUTS.values()
        ],
        "checks": checks,
        "ranking": ranking,
        "selection": {
            "arm_id": "A7",
            "reason": (
                "A7 is the only missing arm with an already executed upstream "
                "mechanism, independently verified learned rules, and a nonzero "
                "declared operator intersection with real calibration graphs. "
                "That does not establish useful transfer or production validity."
            ),
            "promotion_by_this_audit": False,
            "production_integrated_arms_after_audit": 6,
        },
        "claim_boundary": {
            "ranking_not_arm_conformance": True,
            "ranking_not_production_integration": True,
            "synthetic_reuse_failure_preserved": True,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE139_MISSING_ARM_CLOSURE"
        " selected=A7 compatible_calls=53 compatible_graphs=17"
        " integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
