#!/usr/bin/env python3
"""Freeze the accepted A5 calibration abstraction without rerunning Stitch."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PHASE99 = HERE / "results/phase99_a5_stitch_typed_graph_audit.json"
PHASE100 = (
    HERE / "results/phase100_a5_stitch_typed_graph_resource_audit.json"
)
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_STITCH_TYPED_GRAPH_PROTOCOL_V1.json"
)
OUTPUT = HERE / "results/a5_stitch_calibration_library_v1.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    typed = json.loads(PHASE99.read_text())
    resource = json.loads(PHASE100.read_text())
    abstractions = typed["observed"]["abstraction_rows"]
    if not (
        typed["status"] == "A5_STITCH_TYPED_GRAPH_COMPONENT_PASS"
        and resource["status"]
        == "A5_STITCH_TYPED_GRAPH_RESOURCE_COMPONENT_PASS"
        and typed["observed"]["abstractions"] == len(abstractions) == 1
        and typed["observed"]["original_cost"] == 452962
        and typed["observed"]["final_cost"] == 386504
        and typed["observed"]["cost_change"] == 66458
        and typed["input"]["programs"] == 23
        and typed["input"]["call_function_invocations"] == 337
        and typed["integration"]["A5_production_integrated"] is False
        and typed["validation_v6_accessed"] is False
    ):
        raise RuntimeError("A5 calibration inputs do not match frozen gate")
    definitions = [
        {
            "name": row["name"],
            "arity": row["arity"],
            "body": row["body"],
            "num_uses": row["num_uses"],
            "utility": row["utility"],
        }
        for row in abstractions
    ]
    payload = {
        "version": "FOUNDRY_A5_STITCH_CALIBRATION_LIBRARY_V1",
        "status": "FROZEN_CALIBRATION_ONLY_STRUCTURAL_LIBRARY",
        "arm_id": "A5",
        "source_algorithm": "upstream Stitch with disclosed build shims",
        "typed_encoding": "evaluator-owned complete framework graph encoding",
        "binary_sha256": typed["binary_sha256"],
        "encoding_protocol_sha256": sha(PROTOCOL),
        "phase99_sha256": sha(PHASE99),
        "phase100_sha256": sha(PHASE100),
        "input_call_sha256": typed["input"]["call_sha256"],
        "rewritten_sha256": typed["observed"]["rewritten_sha256"],
        "programs": typed["input"]["programs"],
        "unique_programs": typed["input"]["unique_programs"],
        "call_function_invocations": typed["input"][
            "call_function_invocations"
        ],
        "original_cost": typed["observed"]["original_cost"],
        "final_cost": typed["observed"]["final_cost"],
        "cost_change": typed["observed"]["cost_change"],
        "definitions": definitions,
        "classification": (
            "GENERIC_STRUCTURAL_CALL_SEQUENCE_ABSTRACTION_NOT_A_NEW_"
            "TENSOR_PRIMITIVE"
        ),
        "claim_boundary": {
            "numerical_semantics_supplied_by_stitch": False,
            "multi_operator_runtime_tool_invented": False,
            "production_integrated": False,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_A5_STITCH_CALIBRATION_FREEZE"
        f" library_sha256={sha(OUTPUT)} abstractions=1 uses=329"
        " integrated=5/10 prospective=false"
    )


if __name__ == "__main__":
    main()
