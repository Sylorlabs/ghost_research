#!/usr/bin/env python3
"""Recompute readiness after autonomous typed tensor-tool construction."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    path = RESULTS / name
    raw = path.read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    prior, prior_sha = load(
        "readiness_iteration_1_5.json", "FOUNDRY_READINESS_ITERATION_1_5"
    )
    forge, forge_sha = load(
        "phase10_tensor_forge.json", "FOUNDRY_TENSOR_FORGE_RESULT_V1"
    )
    evaluation, evaluation_sha = load(
        "phase11_independent_tensor_eval.json",
        "FOUNDRY_INDEPENDENT_TENSOR_TOOL_EVAL_V1",
    )
    native, native_sha = load(
        "phase12_tensor_native_resource.json",
        "FOUNDRY_TENSOR_NATIVE_RESOURCE_AUDIT_V1",
    )
    gates = {
        "forge_constructed_multiple_tools": forge["tools_forged"] >= 2,
        "forge_has_repeated_measured_support": (
            forge["support_total"] >= 2 * forge["tools_forged"]
        ),
        "independent_parser_interpreter_passed": (
            evaluation["status"] == "INDEPENDENT_TENSOR_TOOL_EVAL_PASS"
        ),
        "all_tools_transferred": (
            len(evaluation["match_counts"]) == forge["tools_forged"]
            and all(value > 0 for value in evaluation["match_counts"].values())
        ),
        "all_hostile_mutations_rejected": len(evaluation["hostile_rejections"]) == 4,
        "all_current_candidates_native_classified": native["P5"][
            "current_candidates_classified"
        ],
        "new_arms_resource_metered": native["P3"][
            "new_tensor_forge_arms_integrated"
        ],
        "external_controls_ready": False,
        "external_workload_and_trace_ready": False,
        "strong_fixed_beaten_on_frozen_heldout": False,
    }
    if not all(list(gates.values())[:7]):
        raise RuntimeError("iteration 1.6 component evidence is internally incomplete")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_1_6",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "forge_sha256": forge_sha,
        "evaluation_sha256": evaluation_sha,
        "native_resource_sha256": native_sha,
        "gates": gates,
        "progress": {
            "typed_tools_forged": forge["tools_forged"],
            "measured_training_support": forge["support_total"],
            "reserved_numerical_transfers": evaluation["successful_transfers"],
            "P3_new_tensor_arms": True,
            "P3_complete": False,
            "P4_future_tensor_tool_component": True,
            "P5_future_candidate_audit": True,
            "P5_current_candidates_classified": True,
            "P5_admitted": native["P5"]["admitted"],
            "P5_complete": False,
        },
        "interpretation": (
            "The machine constructed four reusable typed tensor rewrite records "
            "from calibration-only measured pairs, and separately implemented "
            "code parsed, instantiated, type-checked, executed, and native-audited "
            "them. This crosses the tensor tool-construction component boundary, "
            "but it does not cross the external total-cost prospective boundary."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "limits": [
            "the primitive tensor operation vocabulary and training transformations were supplied",
            "reserved transfer establishes mechanism and numerical validity, not reserved performance",
            "three nonidentical compiler results and one sparse unsupported result remain quarantined",
            "no forged tool is admitted to a prospective candidate library yet",
        ],
    }
    (RESULTS / "readiness_iteration_1_6.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_1_6_NOT_READY"
        f" tools={forge['tools_forged']}"
        f" transfers={evaluation['successful_transfers']}"
        f" classified={len(native['rows'])}"
        f" admitted={native['P5']['admitted']}"
    )


if __name__ == "__main__":
    run()
