#!/usr/bin/env python3
"""Recompute readiness after one exact auxiliary dependency bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_isamore_dependency_bridge_v3 import verify as verify_bridge


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_5_2.json"
OUTPUT = RESULTS / "readiness_iteration_5_3.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_bridge()
    if not (
        freeze["prior_stop"] == "colored"
        and freeze["next_stop"] == "crossbeam"
        and freeze["algorithm_execution_reached"] is False
        and freeze["P1_complete"] is False
    ):
        raise RuntimeError("readiness 5.3 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_3",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "isamore_dependency_bridge_freeze_sha256": sha(
            RESULTS / "isamore_dependency_bridge_v3_freeze.json"
        ),
        "progress": {
            "P1_complete": False,
            "P2_complete": True,
            "P3_complete": True,
            "P4_complete": True,
            "P5_complete": True,
            "P6_complete": True,
            "isamore_source_acquired": True,
            "isamore_offline_build_stop_before_bridge": "colored",
            "isamore_offline_build_stop_after_bridge": "crossbeam",
            "isamore_auxiliary_packages_bridged": 1,
            "isamore_algorithm_compilation_reached": False,
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
            "the offline build now stops at missing crossbeam 0.8.4",
            "the colored bridge is official-tag source but not a crates.io tarball checksum reproduction",
            "the pinned nightly-2024-12-25 toolchain and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
            "no candidate runtime invention survives native compiler deduplication"
        ],
        "remediation": {
            "next_action": (
                "recover and authenticate the locked crossbeam 0.8.4 closure, "
                "then rerun the same metered check; stop rather than bridge a "
                "defining semantic dependency with non-exact source"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not call movement between missing packages algorithm progress",
                "do not count official-tag source as crates.io checksum identity",
                "do not mock SMT validation, LP extraction, or hardware scoring",
                "do not count subsystem reruns as a fourth control",
                "do not open validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "One auxiliary dependency was recovered from its official tag and "
            "the metered build stop moved from colored to crossbeam. That "
            "proves the closure process can advance, but compilation has not "
            "reached ISAMORE and no control outcome exists. P1 remains three "
            "of four, readiness remains five of six, and v6 stays sealed."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_5_3"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=5/6 controls=3/4 integrated=6/10"
        " build_stop=colored_to_crossbeam prospective=false"
    )


if __name__ == "__main__":
    main()
