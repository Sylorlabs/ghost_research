#!/usr/bin/env python3
"""Recompute readiness after evidence-constrained polymorphic transfer."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_polymorphic_prospective_v1 import verify as verify_prefreeze
from freeze_polymorphic_result_v1 import verify as verify_result_freeze


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
        "readiness_iteration_2_1.json", "FOUNDRY_READINESS_ITERATION_2_1"
    )
    forge, forge_sha = load(
        "phase29_polymorphic_semantic_forge.json",
        "FOUNDRY_POLYMORPHIC_SEMANTIC_FORGE_RESULT_V1",
    )
    evaluation, evaluation_sha = load(
        "phase30_independent_polymorphic_eval.json",
        "FOUNDRY_INDEPENDENT_POLYMORPHIC_EVAL_V1",
    )
    native, native_sha = load(
        "phase31_polymorphic_native_dedup.json",
        "FOUNDRY_POLYMORPHIC_NATIVE_DEDUP_V1",
    )
    resource, resource_sha = load(
        "phase32_polymorphic_resource_audit.json",
        "FOUNDRY_POLYMORPHIC_RESOURCE_AUDIT_V1",
    )
    if (
        forge["status"] != "POLYMORPHIC_SEMANTIC_FORGE_READY"
        or evaluation["status"] != "POLYMORPHIC_PROSPECTIVE_VALID_NEGATIVE"
        or native["status"] != "POLYMORPHIC_NATIVE_DEDUP_COMPLETE"
        or resource["status"] != "POLYMORPHIC_RESOURCE_COMPONENT_READY"
    ):
        raise RuntimeError("polymorphic prospective evidence is not expected")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_2",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "polymorphic_prefreeze_records_sha256": prefreeze["records_sha256"],
        "polymorphic_result_records_sha256": result_freeze["records_sha256"],
        "polymorphic_forge_sha256": forge_sha,
        "polymorphic_evaluation_sha256": evaluation_sha,
        "polymorphic_native_sha256": native_sha,
        "polymorphic_resource_sha256": resource_sha,
        "progress": {
            "evidence_constrained_polymorphism": True,
            "llm_calls": forge["autonomy_boundary"]["llm_calls"],
            "manual_type_widenings": forge["autonomy_boundary"][
                "manual_type_widenings"
            ],
            "validation_accessed_by_forge": forge["autonomy_boundary"][
                "validation_accessed"
            ],
            "generalized_input_constraints": forge[
                "generalized_input_constraints"
            ],
            "generalized_output_constraints": forge[
                "generalized_output_constraints"
            ],
            "polymorphic_tools_forged": forge["tools"],
            "validation_families": evaluation["families"],
            "matched_tools": evaluation["matched_tools"],
            "matched_families": evaluation["matched_families"],
            "successful_replays": evaluation["successful_replays"],
            "candidate_benefit": evaluation["candidate"]["benefit"],
            "fixed_benefit": evaluation["fixed"]["benefit"],
            "candidate_total_cost": evaluation["candidate"]["total_cost"],
            "fixed_total_cost": evaluation["fixed"]["total_cost"],
            "native_compiler_duplicates": native["summary"][
                "normalized_inductor_duplicates"
            ],
            "runtime_candidates_admitted": native["summary"]["admitted"],
            "polymorphic_resource_matrix_integrated": resource["P3"][
                "polymorphic_matrix_integrated"
            ],
            "P2_complete": False,
            "P3_complete": resource["P3"]["complete"],
            "P5_complete": native["P5"]["complete"],
        },
        "interpretation": (
            "Operator-position evidence generalized five input constraints "
            "without an LLM, validation access, or manual widening. This "
            "repaired the concrete-layout failure: all three tools replayed "
            "exactly on a fresh dense PyHealth graph-convolution family. It "
            "did not establish heterogeneous reuse. Candidate benefit was "
            "seven versus fourteen for the fixed portfolio, and all candidate "
            "matches occurred in one of four families. Native compilation "
            "showed every candidate was exactly equivalent to its stock ATen "
            "decomposition, so zero runtime inventions were admitted."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "stop tuning graph-convolution variants and reproduce the "
                "pinned external controls with paper-derived conformance "
                "fixtures under process-tree accounting; only after that "
                "prerequisite closes should a diversity-seeking forge reserve "
                "another prospective corpus"
            ),
            "forbidden_shortcuts": [
                "do not reuse the now-observed validation-v4 corpus",
                "do not count three tools in one semantic family as broad reuse",
                "do not claim cheaper search when candidate benefit is lower",
                "do not admit exact stock decompositions as runtime inventions",
                "do not replace external controls with locally invented emulators",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_2.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_2_NOT_READY"
        f" polymorphic_tools={forge['tools']}"
        f" transfers={evaluation['successful_replays']}"
        f" families={evaluation['matched_families']}/{evaluation['families']}"
        f" benefit={evaluation['candidate']['benefit']}/"
        f"{evaluation['fixed']['benefit']}"
        f" native_duplicates={native['summary']['normalized_inductor_duplicates']}"
        f" admitted={native['summary']['admitted']}"
    )


if __name__ == "__main__":
    run()
