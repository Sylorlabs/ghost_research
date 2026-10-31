#!/usr/bin/env python3
"""Recompute readiness after freezing the evaluator-owned arm contract."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v4 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_1.json"
OUTPUT = RESULTS / "readiness_iteration_4_2.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    freeze = verify_remediation()
    conformance = json.loads(
        (
            RESULTS / "phase83_arm_adapter_contract_conformance.json"
        ).read_text()
    )
    resources = json.loads(
        (
            RESULTS / "phase84_arm_adapter_contract_resource_audit.json"
        ).read_text()
    )
    if not (
        conformance["status"] == "ARM_ADAPTER_CONTRACT_CONFORMANCE_PASS"
        and resources["status"] == "ARM_ADAPTER_CONTRACT_RESOURCE_PASS"
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 4.2 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_4_2",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v4_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "arm_adapter_contract_ready": True,
            "strict_contract_verifiers": 2,
            "required_arms_named": conformance["integration"][
                "required_arms_named"
            ],
            "hostile_mutations_rejected_twice": len(
                conformance["hostile_rejections"]
            ),
            "contract_process_tree_metered": resources["P3"][
                "adapter_contract_conformance_metered"
            ],
            "production_integrated_arms": conformance["integration"][
                "production_integrated_arms"
            ],
            "P3_complete": False,
            "heldout_source_runtime_graph_or_outcome_accessed": False,
        },
        "prerequisites": {
            "P1_external_control_conformance": False,
            "P2_independent_corpus_and_invocation_trace": True,
            "P3_complete_resource_meter": False,
            "P4_independent_typed_tool_verifier": True,
            "P5_native_compiler_deduplication": True,
            "P6_unchanged_prospective_freeze": True,
        },
        "authorization": {
            "prerequisites_passed": 4,
            "prerequisites_required": 6,
            "required_arms_production_integrated": 2,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1 and A3-A9 still lack complete implementations behind the frozen adapter contract",
            "all ten required adapter paths are not yet process-tree metered under matched ceilings",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered",
        ],
        "remediation": {
            "next_action": (
                "implement and independently test A3 and A9 first against an "
                "evaluator-owned typed graph artifact, preserving empty state "
                "per artifact; then adapt A1, A4, A5, and A7 and keep A6/A8 "
                "fail-closed until full controls exist"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not count a schema as an implemented adapter",
                "do not emit PASS from an unsupported or partial control",
                "do not omit failed and unsupported CPU costs",
                "do not let A3 or A9 retain cross-artifact state",
                "do not open validation-v6 before a new authorization pass",
            ],
        },
        "interpretation": (
            "The evaluator now owns a strict common arm boundary and two "
            "independent parsers agree on it. The contract binds the 4-by-3 "
            "schedule, complete CPU ledger, correctness, provenance, state "
            "reset, and process-tree receipt fields and rejects nine hostile "
            "mutations twice. This removes interface ambiguity but implements "
            "no missing arm by itself; P3 and integration remain unchanged."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_4_2"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6"
        " integrated=2/10"
        " contract=PASS"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
