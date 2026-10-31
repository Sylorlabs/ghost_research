#!/usr/bin/env python3
"""Meter and independently falsify the frozen SymPy CSE control."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

import independent_sympy_cse_control as independent
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/sympy_cse_control_v1_freeze.json"
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_V1.json"
)
AMENDMENT_FREEZE = (
    HERE / "results/sympy_cse_control_execution_amendment_v1_freeze.json"
)
SOURCE_RESULT = HERE / "results/phase137_sympy_cse_source_control.json"
RESULT = (
    HERE / "results/phase138_sympy_cse_independent_resource_conformance.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def hostile_rows(source: dict) -> list[tuple[str, dict]]:
    rows = []
    value = copy.deepcopy(source)
    value["identity"]["version"] = "1.13.0"
    rows.append(("wrong_distribution_version", value))
    value = copy.deepcopy(source)
    value["source_records"][0]["git_blob_sha1"] = "0" * 40
    rows.append(("algorithm_source_hash_mismatch", value))
    value = copy.deepcopy(source)
    value["source_records"][2]["sha256"] = "0" * 64
    rows.append(("official_test_source_hash_mismatch", value))
    value = copy.deepcopy(source)
    value["distribution_integrity"]["record_sha256"] = "0" * 64
    value["distribution_integrity"]["all_hashed_files_exact"] = False
    rows.append(("distribution_record_hash_mismatch", value))
    value = copy.deepcopy(source)
    value["baseline_fixture"]["replacements"].pop()
    rows.append(("deleted_replacement", value))
    value = copy.deepcopy(source)
    value["baseline_fixture"]["reduced"][0] = "0"
    rows.append(("changed_reduced_expression", value))
    value = copy.deepcopy(source)
    value["surprise"] = True
    rows.append(("unknown_output_key", value))
    value = copy.deepcopy(source)
    value["validation_v6_accessed"] = True
    rows.append(("claimed_validation_access", value))
    value = copy.deepcopy(source)
    value["A6_satisfied"] = True
    rows.append(("claimed_A6_substitution", value))
    value = copy.deepcopy(source)
    value["production_integrated_arms"] = 7
    rows.append(("claimed_production_arm_promotion", value))
    return rows


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    amendment = json.loads(AMENDMENT.read_text())
    amendment_freeze = json.loads(AMENDMENT_FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["frozen_before_control_execution"] is True
        and freeze["validation_v6_accessed"] is False
        and amendment_freeze["amendment_sha256"] == sha(AMENDMENT)
        and amendment_freeze["initial_infrastructure_failure_preserved"]
        is True
        and amendment_freeze["pristine_preregistration"] is False
    ):
        raise RuntimeError("SymPy CSE freeze authentication failed")
    python = pathlib.Path(sys.executable).resolve()
    limits = protocol["resource_limits"]
    receipt = run_metered_tree(
        [str(python), str(HERE / "sympy_cse_source_control.py")],
        cwd=HERE,
        wall_limit_seconds=limits["wall_seconds"],
        cpu_limit_seconds=limits["cpu_seconds"],
        rss_limit_kib=limits["rss_kib"],
        environment={
            "HOME": str(pathlib.Path.home()),
            "PYTHONPATH": str(
                pathlib.Path.home() / ".local/lib/python3.12/site-packages"
            ),
        },
    )
    source = json.loads(SOURCE_RESULT.read_text())
    independent_result = independent.validate_result(
        source,
        tolerance=protocol["independent_semantic_fixture"][
            "absolute_tolerance"
        ],
    )
    hostile = []
    for name, mutation in hostile_rows(source):
        rejected = False
        try:
            independent.validate_result(
                mutation,
                tolerance=protocol["independent_semantic_fixture"][
                    "absolute_tolerance"
                ],
            )
        except independent.IndependentReject:
            rejected = True
        hostile.append({"name": name, "rejected": rejected})
    checks = {
        "preexecution_freeze_authentic": True,
        "source_control_process_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
            and "FOUNDRY_PHASE137_SYMPY_CSE_SOURCE"
            in receipt["stdout_text"]
        ),
        "source_control_gates_all_pass": all(source["gates"].values()),
        "official_suite_threshold_pass": source["official_suite"]["accepted"],
        "official_expected_outcomes_exact": (
            source["official_suite"]["passed"] == 53
            and source["official_suite"]["source_declared_xfails"] == 8
            and source["official_suite"]["pytest_classified_xfails"] == 8
            and source["official_suite"]["accepted_expected_outcomes"] == 61
            and source["official_suite"]["failures"] == 0
            and source["official_suite"]["errors"] == 0
            and source["official_suite"]["xpassed"] == 0
        ),
        "initial_infrastructure_failure_preserved": source[
            "initial_infrastructure_failure"
        ]["preserved"]
        is True,
        "independent_baseline_numeric_pass": independent_result["baseline"][
            "passed"
        ],
        "independent_renamed_reordered_numeric_pass":
        independent_result["renamed_reordered"]["passed"],
        "metamorphic_replacement_count_preserved":
        independent_result["replacement_count_preserved"],
        "ten_hostile_results_rejected": (
            len(hostile) == len(protocol["hostile_checks"]) == 10
            and all(row["rejected"] for row in hostile)
        ),
        "control_is_independent_of_prior_three": len(
            protocol["selection_boundary"]["distinct_from_existing_controls"]
        )
        == 5,
        "A6_and_A8_not_substituted": (
            source["A6_satisfied"] is False
            and source["A8_satisfied"] is False
            and protocol["selection_boundary"]["may_replace_isamore_as_A6"]
            is False
        ),
        "production_arm_count_not_increased": (
            source["production_integrated_arms"] == 6
            and protocol["selection_boundary"][
                "may_increase_production_integrated_arm_count"
            ]
            is False
        ),
        "validation_v6_unread": source["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        failed = [name for name, passed in checks.items() if not passed]
        raise RuntimeError(
            "SymPy CSE independent/resource conformance failed: "
            + ", ".join(failed)
        )
    payload = {
        "version":
        "FOUNDRY_SYMPY_CSE_INDEPENDENT_RESOURCE_CONFORMANCE_V1",
        "status": "SYMPY_CSE_FOURTH_SOURCE_FAITHFUL_CONTROL_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "amendment_sha256": sha(AMENDMENT),
        "amendment_freeze_sha256": sha(AMENDMENT_FREEZE),
        "source_result_sha256": sha(SOURCE_RESULT),
        "checks": checks,
        "official_suite": source["official_suite"],
        "distribution_integrity": source["distribution_integrity"],
        "independent_result": independent_result,
        "hostile_rejections": hostile,
        "receipt": receipt,
        "P1": {
            "source_faithful_controls_reproduced": 4,
            "controls_required": 4,
            "complete": True,
        },
        "P3": {
            "metered_source_control_arms": 4,
            "controls_required": 4,
            "complete": True,
        },
        "A6_satisfied": False,
        "A8_satisfied": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "SymPy CSE closes only the generic four-independent-control P1 "
            "count. It does not replace ISAMORE as A6, does not satisfy A8, "
            "does not add a production arm, and does not authorize the trial."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE138_SYMPY_CSE_CONFORMANCE"
        f" status={payload['status']}"
        f" official={source['official_suite']['passed']}/"
        f"{source['official_suite']['tests']}"
        f" hostile={len(hostile)} controls=4/4 P1=true"
        " integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
