#!/usr/bin/env python3
"""Recompute readiness after authenticated ISAMORE source acquisition."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_isamore_acquisition_v2 import verify as verify_isamore


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_5_1.json"
OUTPUT = RESULTS / "readiness_iteration_5_2.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_isamore()
    build = json.loads(
        (RESULTS / "phase112_isamore_offline_build_closure.json").read_text()
    )
    if not (
        freeze["route_buildable"] is False
        and freeze["control_executed"] is False
        and freeze["P1_complete"] is False
        and build["checks"]["offline_locked_metadata_resolved"] is True
        and build["checks"]["route_buildable"] is False
        and build["validation_v6_accessed"] is False
    ):
        raise RuntimeError("readiness 5.2 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_2",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "isamore_acquisition_freeze_sha256": sha(
            RESULTS / "isamore_acquisition_v2_freeze.json"
        ),
        "progress": {
            "P1_complete": False,
            "P2_complete": True,
            "P3_complete": True,
            "P4_complete": True,
            "P5_complete": True,
            "P6_complete": True,
            "isamore_top_level_source_materialized": True,
            "isamore_recursive_gitlinks_observed": 4,
            "isamore_authenticated_source_records": 29,
            "isamore_published_workload_present": True,
            "isamore_parent_lock_recovered": True,
            "isamore_offline_locked_metadata_resolved": True,
            "isamore_offline_locked_build_attempted": True,
            "isamore_control_executed": False,
            "source_faithful_controls_reproduced": 3,
            "controls_required": 4,
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
            "P1 still lacks the fourth executed source-faithful control",
            "the exact offline build stops at the first unavailable locked registry package, colored",
            "the pinned nightly-2024-12-25 toolchain is absent",
            "the Coin-OR CBC native library required by Egg LP extraction is absent",
            "A1, A6, A7, and A8 remain nonconformant and nonintegrated despite resource-complete REQUIRED_UNSUPPORTED outcomes",
            "the required production arm matrix remains 6/10",
            "no candidate runtime invention survives native compiler deduplication"
        ],
        "remediation": {
            "next_action": (
                "recover the exact locked Rust registry closure, pinned "
                "nightly, and Coin-OR CBC; rerun the unchanged offline build "
                "audit, then pre-freeze an ISAMORE point-product conformance "
                "criterion before any algorithm outcome is observed"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not count source acquisition as control execution",
                "do not replace ISAMORE SMT validation or LP selection with mocks",
                "do not count Babble or Enumo subsystem reruns as an independent fourth control",
                "do not count REQUIRED_UNSUPPORTED as conformance",
                "do not open validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "The uncertainty moved from repository identity to executable "
            "closure. Exact ISAMORE source, four gitlinks, a historical lock, "
            "hardware models, and a published RVSDG/profile pair are now "
            "authenticated locally. The metered offline build resolves the "
            "workspace and then stops before compilation on a missing locked "
            "package; pinned-nightly and CBC gaps remain. Therefore P1 stays "
            "three of four, prerequisites stay five of six, and v6 remains "
            "sealed."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_5_2"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=5/6 controls=3/4 integrated=6/10"
        " source=RECOVERED build=INFRASTRUCTURE_STOP prospective=false"
    )


if __name__ == "__main__":
    main()
