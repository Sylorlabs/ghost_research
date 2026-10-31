#!/usr/bin/env python3
"""Recompute readiness after Enumo tensor feasibility and reuse phases."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_20.json"
    feasibility_freeze_path = (
        RESULTS / "enumo_tensor_feasibility_result_v1_freeze.json"
    )
    reuse_freeze_path = (
        RESULTS / "enumo_tensor_rule_reuse_result_v1_freeze.json"
    )
    prior = json.loads(prior_path.read_text())
    feasibility = json.loads(feasibility_freeze_path.read_text())
    reuse = json.loads(reuse_freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and feasibility["status"] == "ENUMO_TENSOR_DOMAIN_FEASIBILITY_PASS"
        and feasibility["learned_rule_count"] == 18
        and feasibility["A7_production_integrated"] is False
        and reuse["status"]
        == "ENUMO_TENSOR_RULE_REUSE_DOES_NOT_BEAT_FIXED"
        and reuse["learned_strict_wins"] == 0
        and reuse["fixed_strict_wins"] == 736
        and reuse["production_integrated_arms"] == 6
    ):
        raise RuntimeError("iteration 5.21 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_21",
        "prior_sha256": sha(prior_path),
        "enumo_tensor_feasibility_freeze_sha256": sha(
            feasibility_freeze_path
        ),
        "enumo_tensor_rule_reuse_freeze_sha256": sha(reuse_freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "enumo_tensor_domain_feasibility_established": True,
            "enumo_tensor_evaluator_authored_domain": True,
            "enumo_tensor_learned_rules": 18,
            "enumo_tensor_independent_lane_checks": 1176,
            "enumo_tensor_reuse_held_out_expressions": 3339,
            "enumo_tensor_reuse_learned_strict_wins": 0,
            "enumo_tensor_reuse_fixed_strict_wins": 736,
            "enumo_tensor_reuse_atom_cost_ties": 2603,
            "enumo_tensor_reuse_beats_fixed": False,
            "A7_production_integrated": False,
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A separately named evaluator-authored tensor SynthLanguage proves "
            "that byte-exact upstream Enumo core machinery can synthesize 18 "
            "independently sound elementwise rules. In the frozen follow-on "
            "reuse audit, those rules obtain zero strict atom-cost wins over a "
            "13-rule fixed portfolio across all 3,339 held-out size-five "
            "expressions; the fixed portfolio wins 736 and 2,603 tie. This "
            "establishes mechanism feasibility but not useful learned reuse, "
            "automatic grammar construction, A7 integration, or real-artifact "
            "advantage."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "do not scale the manually authored Enumo tensor grammar; "
                "prefreeze a grammar-construction falsification phase in which "
                "the machine must derive typed operator forms from calibration "
                "traces and earn a candidate-only held-out advantage over the "
                "same fixed portfolio, while the independent A6 source route "
                "remains the shortest P1 closure when exact transport returns"
            ),
            "forbidden_shortcuts": [
                "do not rename tensor-domain feasibility as frozen Boolean A7",
                "do not count rediscovered fixed identities as useful tool reuse",
                "do not count generated expressions as real artifacts",
                "do not increase P1, P3 integration, or the production arm count",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_21.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_21"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10"
        " tensor_rules=18 learned_wins=0 fixed_wins=736"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
