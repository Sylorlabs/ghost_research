#!/usr/bin/env python3
"""Recompute readiness after the EggMind artifact and boundary audit."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_3_7.json"
OUTPUT = RESULTS / "readiness_iteration_3_8.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    source = json.loads(
        (RESULTS / "phase70_eggmind_source_route_audit.json").read_text()
    )
    boundary = json.loads(
        (
            RESULTS / "phase71_eggmind_adapted_boundary_conformance.json"
        ).read_text()
    )
    if not (
        source["P1"]["complete"] is False
        and boundary["P1"]["complete"] is False
        and boundary["status"]
        == "EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_PASS"
    ):
        raise RuntimeError("EggMind readiness evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_3_8",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "source_route_sha256": sha(
            RESULTS / "phase70_eggmind_source_route_audit.json"
        ),
        "adapted_boundary_sha256": sha(
            RESULTS / "phase71_eggmind_adapted_boundary_conformance.json"
        ),
        "progress": {
            "artifact_search_routes": source["search_routes"],
            "official_repository_matches": source[
                "official_repository_matches"
            ],
            "adapted_schedule_actions_recomputed": boundary[
                "schedule_counts"
            ]["actions"],
            "hostile_mutations_rejected_by_two_parsers": len(
                boundary["hostile_rejections"]
            ),
            "paper_risk_equation_recomputed": True,
            "full_A8_conformance": False,
            "production_A8_integration": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": False,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "remaining_blockers": [
            "the authors' EggMind implementation is not discoverable and the paper-derived boundary is not the full A8 control",
            "A3 and A9 still lack independently checked state-reset and budget-equivalent kernels",
            "the required control matrix is not production-integrated or completely metered",
            "no independently sourced invocation trace justifies N*",
            "zero candidate tools survive native compiler deduplication as runtime inventions"
        ],
        "remediation": {
            "next_action": (
                "implement and independently meter calibration-only A3 "
                "no-library and A9 per-instance kernels while validation-v6 "
                "remains sealed"
            ),
            "required": True,
        },
        "interpretation": (
            "The paper-derived EqSatL artifact boundary is reproducible and "
            "hostile-tested, but no official EggMind source was discoverable. "
            "The result is an ADAPTED partial conformance receipt, not A8."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_3_8"
        " verdict=FOUNDRY_V6_NOT_READY"
        " A8_full=false"
    )


if __name__ == "__main__":
    run()
