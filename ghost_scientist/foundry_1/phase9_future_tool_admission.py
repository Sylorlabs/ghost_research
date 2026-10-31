#!/usr/bin/env python3
"""Phase 9: fail-closed native-equivalence admission over v5.1 plan evidence."""

from __future__ import annotations

import json
import pathlib

from independent_evaluator import canonical_json, file_sha256_bytes


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def run() -> None:
    audit_path = RESULTS / "phase4_tensor_dedup.json"
    audit = json.loads(audit_path.read_text(encoding="utf-8"))
    if audit["version"] != "FOUNDRY_TENSOR_DEDUP_AUDIT_V1":
        raise RuntimeError("tensor dedup audit schema mismatch")
    compile_by_id = {
        item["opaque_id"]: item for item in audit["compile_receipts"]
    }
    rows = []
    counts = {"REJECT_NATIVE_DUPLICATE": 0, "QUARANTINE_UNRESOLVED": 0, "ADMIT": 0}
    for item in audit["rows"]:
        representative = compile_by_id[item["representative_inductor_receipt"]]
        pre_duplicate = item["pre_lowering_ir_duplicate"]
        compiler_duplicate = representative["byte_normalized_inductor_duplicate"]
        compiler_unsupported = representative["required_unsupported_sparse"]
        search_cost_receipt = None
        search_cost_distinction = False
        if pre_duplicate or compiler_duplicate:
            decision = "REJECT_NATIVE_DUPLICATE"
            reason = (
                "pre_lowering_ir_identical"
                if pre_duplicate
                else "normalized_inductor_code_identical"
            )
        elif compiler_unsupported:
            decision = "QUARANTINE_UNRESOLVED"
            reason = "compiler_required_unsupported"
        else:
            decision = "QUARANTINE_UNRESOLVED"
            reason = "nonidentical_code_is_not_proof_of_native_distinction"
        # A future byte-identical tool may be reconsidered only if a frozen,
        # direct search-cost receipt proves a bounded reachability distinction.
        if (
            decision == "REJECT_NATIVE_DUPLICATE"
            and search_cost_receipt is not None
            and search_cost_distinction
        ):
            decision = "ADMIT"
            reason = "independent_search_cost_distinction"
        counts[decision] += 1
        rows.append(
            {
                "opaque_id": item["opaque_id"],
                "candidate_plan_sha256": item["candidate_plan_sha256"],
                "pre_lowering_duplicate": pre_duplicate,
                "representative_compiler_duplicate": compiler_duplicate,
                "representative_compiler_required_unsupported": compiler_unsupported,
                "derived_parameter_nodes": item["derived_parameter_nodes"],
                "search_cost_receipt": search_cost_receipt,
                "decision": decision,
                "reason": reason,
            }
        )
    payload = {
        "version": "FOUNDRY_FUTURE_TOOL_ADMISSION_V1",
        "status": "FAIL_CLOSED_ADMISSION_COMPONENT_READY",
        "source_audit_sha256": file_sha256_bytes(audit_path.read_bytes()),
        "policy": {
            "reject_exact_or_compiler_duplicate": True,
            "quarantine_nonidentical_without_completeness": True,
            "quarantine_required_unsupported": True,
            "byte_identical_rescue_requires_frozen_search_cost_receipt": True,
            "derived_parameter_count_alone_is_not_novelty": True,
        },
        "rows": rows,
        "summary": {
            **counts,
            "plans": len(rows),
            "accepted_fraction": counts["ADMIT"] / len(rows),
        },
        "P5": {
            "admission_policy_component": True,
            "v5_1_seed_tools_admitted": counts["ADMIT"],
            "future_candidate_audit_executed": False,
            "complete": False,
        },
        "interpretation": (
            "The v5.1 plans remain valid optimization evidence, but none carries "
            "sufficient native-distinction evidence to seed a Foundry v6 tool library."
        ),
    }
    (RESULTS / "phase9_future_tool_admission.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE9_ADMISSION_PASS"
        f" rejected={counts['REJECT_NATIVE_DUPLICATE']}"
        f" quarantined={counts['QUARANTINE_UNRESOLVED']}"
        f" admitted={counts['ADMIT']}"
    )


if __name__ == "__main__":
    run()

