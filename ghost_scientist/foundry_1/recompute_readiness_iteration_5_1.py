#!/usr/bin/env python3
"""Recompute readiness after complete required-arm resource accounting."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v13 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_5_0.json"
OUTPUT = RESULTS / "readiness_iteration_5_1.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_remediation()
    if not (
        freeze["P3_complete"] is True
        and freeze["current_prerequisites_passed"] == 5
        and freeze["production_integrated_arms"] == 6
        and freeze["newly_production_integrated_arms"] == 0
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 5.1 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_1",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v13_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "P3_complete": True,
            "P4_complete": True,
            "P5_complete": True,
            "P6_complete": True,
            "required_unsupported_arms": ["A1", "A6", "A7", "A8"],
            "required_unsupported_contract_pairs": 92,
            "artifacts_per_unsupported_arm": 23,
            "shared_resource_receipts_charged": 1,
            "cpu_charged_bindings": 4,
            "hostile_batches_rejected_twice": 25,
            "newly_conformant_arms": 0,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
            "heldout_source_runtime_graph_or_outcome_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": True,
            "P3_complete_resource_meter": True,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 5,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 6,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1, A6, A7, and A8 have resource-complete REQUIRED_UNSUPPORTED outcomes but remain nonconformant and nonintegrated",
            "the required production arm matrix remains 6/10 rather than 10/10",
            "no candidate runtime invention survives native compiler deduplication",
            "the final measured-search distinction has not passed the frozen authorization gate"
        ],
        "remediation": {
            "next_action": (
                "continue the independently implemented fourth-control "
                "acquisition route, prioritizing exact recursive ISAMORE "
                "source and its published workload; preserve P1=false if the "
                "defining top-level control remains unavailable"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not count REQUIRED_UNSUPPORTED as conformance",
                "do not count complete resource accounting as production integration",
                "do not rerun Babble or Enumo as a fourth independent control",
                "do not manufacture missing ISAMORE or EggMind source",
                "do not open validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "P3 is now complete in its stated sense: the candidate and every "
            "required control arm have explicit process-tree-metered paths, "
            "including 92 strict REQUIRED_UNSUPPORTED outcomes for the four "
            "nonintegrated arms. This raises prerequisites to five of six but "
            "does not make unsupported controls conformant or integrated. P1, "
            "the 6/10 arm matrix, and the native-dedup stop still deny v6."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_5_1"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=5/6 integrated=6/10"
        " P3=PASS prospective=false"
    )


if __name__ == "__main__":
    main()
