#!/usr/bin/env python3
"""Recompute readiness after autonomous semantic grammar construction."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_semantic_prospective_v1 import verify as verify_prefreeze
from freeze_semantic_result_v1 import verify as verify_result_freeze


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    prefreeze = verify_prefreeze()
    result_freeze = verify_result_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_0.json", "FOUNDRY_READINESS_ITERATION_2_0"
    )
    forge, forge_sha = load(
        "phase25_semantic_grammar_forge.json",
        "FOUNDRY_SEMANTIC_GRAMMAR_FORGE_RESULT_V1",
    )
    evaluation, evaluation_sha = load(
        "phase26_independent_semantic_eval.json",
        "FOUNDRY_INDEPENDENT_SEMANTIC_EVAL_V1",
    )
    native, native_sha = load(
        "phase27_semantic_native_dedup.json",
        "FOUNDRY_SEMANTIC_NATIVE_DEDUP_V1",
    )
    resource, resource_sha = load(
        "phase28_semantic_resource_audit.json",
        "FOUNDRY_SEMANTIC_RESOURCE_AUDIT_V1",
    )
    if (
        forge["status"] != "SEMANTIC_GRAMMAR_FORGE_READY"
        or evaluation["status"] != "SEMANTIC_PROSPECTIVE_VALID_NEGATIVE"
        or native["status"] != "SEMANTIC_NATIVE_DEDUP_COMPLETE"
        or resource["status"] != "SEMANTIC_RESOURCE_COMPONENT_READY"
    ):
        raise RuntimeError("semantic construction evidence is not expected")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_1",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "semantic_prefreeze_records_sha256": prefreeze["records_sha256"],
        "semantic_result_records_sha256": result_freeze["records_sha256"],
        "semantic_forge_sha256": forge_sha,
        "semantic_evaluation_sha256": evaluation_sha,
        "semantic_native_sha256": native_sha,
        "semantic_resource_sha256": resource_sha,
        "progress": {
            "machine_constructed_tool_grammar": True,
            "llm_calls": forge["autonomy_boundary"]["llm_calls"],
            "supplied_tool_forms": forge["autonomy_boundary"][
                "supplied_tool_forms"
            ],
            "semantic_candidate_patterns": forge["candidate_patterns"],
            "semantic_tools_forged": forge["tools_forged"],
            "semantic_description_length_gain": forge[
                "description_length_gain"
            ],
            "validation_families": evaluation["families"],
            "matched_tools": evaluation["matched_tools"],
            "matched_families": evaluation["matched_families"],
            "successful_replays": evaluation["successful_replays"],
            "fixed_matches": evaluation["fixed"]["matches"],
            "candidate_total_cost": evaluation["candidate"]["total_cost"],
            "fixed_total_cost": evaluation["fixed"]["total_cost"],
            "runtime_candidates_rejected": native["summary"]["rejected"],
            "runtime_candidates_admitted": native["summary"]["admitted"],
            "semantic_resource_matrix_integrated": resource["P3"][
                "semantic_forge_matrix_integrated"
            ],
            "P2_complete": False,
            "P3_complete": resource["P3"]["complete"],
            "P5_complete": native["P5"]["complete"],
        },
        "interpretation": (
            "Ghost crossed the autonomous grammar-construction boundary: it "
            "selected operation targets, inferred four typed boundary inputs, "
            "and emitted three independently parseable executable DAG tools "
            "without an LLM or supplied tool forms. The prospective result was "
            "zero transfer, while the strong fixed portfolio matched four "
            "times across two families. All generated tools copied a sparse "
            "layout from one calibration family, and all were exact stock-ATen "
            "compositions rather than runtime inventions."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "construct a constraint-polymorphic grammar whose rank, dtype, "
                "and layout variables are inferred from operator-wide "
                "calibration evidence, then reserve and freeze a new validation "
                "corpus before evaluating it"
            ),
            "forbidden_shortcuts": [
                "do not reuse the now-observed validation-v3 corpus",
                "do not erase concrete type constraints by hand",
                "do not label grammar construction alone as real-world reuse",
                "do not admit exact stock decompositions as runtime inventions",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_1.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_1_NOT_READY"
        f" semantic_tools={forge['tools_forged']}"
        " supplied_forms=0"
        f" transfers={evaluation['successful_replays']}"
        f" fixed_matches={evaluation['fixed']['matches']}"
        f" admitted={native['summary']['admitted']}"
    )


if __name__ == "__main__":
    run()
