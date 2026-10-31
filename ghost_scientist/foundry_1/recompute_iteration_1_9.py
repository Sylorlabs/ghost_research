#!/usr/bin/env python3
"""Recompute readiness after the calibration-only ATen macro pilot."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_external_validation_v1 import verify as verify_validation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    validation_freeze = verify_validation()
    prior, prior_sha = load(
        "readiness_iteration_1_8.json", "FOUNDRY_READINESS_ITERATION_1_8"
    )
    forge, forge_sha = load(
        "phase17_aten_tool_forge.json", "FOUNDRY_ATEN_FORGE_RESULT_V1"
    )
    evaluation, evaluation_sha = load(
        "phase18_independent_aten_eval.json",
        "FOUNDRY_INDEPENDENT_ATEN_EVAL_V1",
    )
    audit, audit_sha = load(
        "phase19_aten_resource_native.json",
        "FOUNDRY_ATEN_RESOURCE_NATIVE_AUDIT_V1",
    )
    if (
        forge["status"] != "ATEN_FORGE_COMPONENT_READY"
        or evaluation["status"] != "INDEPENDENT_ATEN_EVAL_TRANSFER_PASS"
        or evaluation["prospective_boundary"]["classification"]
        != "CALIBRATION_ONLY_ADVERSARIAL_PILOT"
        or audit["status"] != "ATEN_RESOURCE_COMPONENT_READY"
        or audit["summary"]["admitted"] != 0
    ):
        raise RuntimeError("ATen calibration evidence is not the expected result")

    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_9",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "validation_freeze_records_sha256": validation_freeze["records_sha256"],
        "aten_forge_sha256": forge_sha,
        "aten_evaluation_sha256": evaluation_sha,
        "aten_resource_native_sha256": audit_sha,
        "progress": {
            "aten_candidate_patterns": forge["candidate_patterns"],
            "aten_tools_forged": forge["tools_forged"],
            "aten_description_length_gain": forge[
                "selected_description_length_gain"
            ],
            "independent_validation_families": evaluation["families"],
            "matched_tools": evaluation["matched_tools"],
            "successful_macro_replays": evaluation["successful_macro_replays"],
            "hostile_mutations_rejected": len(evaluation["hostile_rejections"]),
            "resource_arms_metered": audit["summary"]["resource_metered"],
            "tools_quarantined": audit["summary"]["quarantined"],
            "tools_admitted": audit["summary"]["admitted"],
            "P2_complete": False,
            "P3_complete": audit["P3"]["complete"],
            "P5_complete": audit["P5"]["complete"],
        },
        "interpretation": (
            "The LLM-free forge found six cross-family ATen subgraph macros and "
            "an independent evaluator replayed one exactly on a separately "
            "sourced family. This is calibration evidence only: source files "
            "were frozen before forging, but concrete runtime shapes and the "
            "execution harness were not. The macros recognize existing ATen "
            "nodes and have no distinct runtime implementation, so they are "
            "quarantined rather than admitted."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "freeze a new upstream source set together with its complete "
                "runtime harness, input shapes, seeds, strong fixed macro "
                "portfolio, exact search-cost ledger, resource limits, and "
                "no-intervention rule before forging or validation"
            ),
            "forbidden_shortcuts": [
                "do not label the phase-18 replay prospective",
                "do not equate structural description-length gain with speedup",
                "do not admit search-only macros as native runtime inventions",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_1_9.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_1_9_NOT_READY"
        f" aten_tools={forge['tools_forged']}"
        f" macro_replays={evaluation['successful_macro_replays']}"
        f" admitted={audit['summary']['admitted']}"
        " classification=CALIBRATION_ONLY"
    )


if __name__ == "__main__":
    run()
