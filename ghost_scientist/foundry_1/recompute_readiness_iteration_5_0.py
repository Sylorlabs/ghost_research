#!/usr/bin/env python3
"""Recompute readiness after the A7 direct-compatibility rejection."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_pareto_remediation_v12 import verify as verify_remediation


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR = RESULTS / "readiness_iteration_4_9.json"
OUTPUT = RESULTS / "readiness_iteration_5_0.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    freeze = verify_remediation()
    if not (
        freeze["A7_direct_adapter_supported"] is False
        and freeze["A7_production_integrated"] is False
        and freeze["production_integrated_arms"] == 6
        and freeze["P3_complete"] is False
        and freeze["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("readiness 5.0 evidence invalid")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_0",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": sha(PRIOR),
        "remediation_freeze_sha256": sha(
            RESULTS / "pareto_remediation_v12_freeze.json"
        ),
        "progress": {
            "P2_complete": True,
            "A1_compatibility_audited_not_integrated": True,
            "A3_A9_production_integrated_calibration_arms": True,
            "A4_production_integrated_calibration_arm": True,
            "A5_production_integrated_calibration_structural_control": True,
            "A7_compatibility_audited": True,
            "A7_direct_adapter_supported": False,
            "A7_framework_graphs_audited": 23,
            "A7_framework_operator_targets": 41,
            "A7_framework_call_function_invocations": 337,
            "A7_direct_operator_target_matches": 0,
            "A7_direct_call_matches": 0,
            "A7_new_tensor_domain_component_classes_required": 8,
            "A7_source_conformance_preserved": True,
            "A7_metamorphic_rule_set_failure_preserved": True,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
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
            "required_arms_production_integrated": 6,
            "required_arms": 10,
            "active_stop_conditions": 1,
            "prospective_trial_authorized": False,
        },
        "remaining_blockers": [
            "P1 still lacks the fourth complete source-faithful control",
            "A1 remains incompatible with the complete framework IR and is not integrated",
            "A7 requires a separately frozen new tensor SynthLanguage research program rather than a direct adapter",
            "A6 and A8 remain required fail-closed arms with incomplete declared controls",
            "all ten required arm paths do not yet have explicit common-contract metered outcomes",
            "zero candidate runtime inventions survive native deduplication and the final measured-search distinction remains unregistered"
        ],
        "remediation": {
            "next_action": (
                "close explicit common-contract REQUIRED_UNSUPPORTED outcomes "
                "for A1, A6, A7, and A8 so P3 accounts for every required arm; "
                "pursue a tensor Enumo domain only under a separate frozen "
                "research protocol"
            ),
            "required": True,
            "forbidden_shortcuts": [
                "do not rename tensor operators to Boolean symbols",
                "do not call a newly authored tensor SynthLanguage a direct Enumo wrapper",
                "do not hide the failed Enumo rule-set metamorphic test",
                "do not count A7 as integrated after a compatibility rejection",
                "do not mount or execute validation-v6 before authorization"
            ]
        },
        "interpretation": (
            "A7 has a complete, metered compatibility outcome: the existing "
            "source-faithful Enumo Boolean control directly covers zero of "
            "337 framework calls. A faithful tensor route would be a new "
            "domain-language research construction with eight missing "
            "semantic component classes, not routine adapter work. A7 remains "
            "non-integrated and truth stays six of ten. P1 and P3 remain open."
        ),
    }
    OUTPUT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_READINESS_ITERATION_5_0"
        " verdict=FOUNDRY_V6_NOT_READY"
        " prerequisites=4/6 integrated=6/10"
        " A7=DIRECT_REJECTED prospective=false"
    )


if __name__ == "__main__":
    main()
