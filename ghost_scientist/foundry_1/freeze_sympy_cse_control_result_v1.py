#!/usr/bin/env python3
"""Create or verify the immutable SymPy CSE control result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = (
    HERE / "results/phase138_sympy_cse_independent_resource_conformance.json"
)
MANIFEST = HERE / "results/sympy_cse_control_result_v1_freeze.json"
RECORD_PATHS = [
    "arm_adapter_fixtures/SYMPY_CSE_CONTROL_PROTOCOL_V1.json",
    "results/sympy_cse_control_v1_freeze.json",
    "arm_adapter_fixtures/SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_V1.json",
    "results/sympy_cse_control_execution_amendment_v1_freeze.json",
    "sympy_cse_source_control.py",
    "independent_sympy_cse_control.py",
    "phase138_sympy_cse_independent_resource_conformance.py",
    "results/phase137_sympy_cse_source_control.json",
]


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    return [
        {"path": path, "sha256": sha(HERE / path)}
        for path in RECORD_PATHS
    ]


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"]
        == "SYMPY_CSE_FOURTH_SOURCE_FAITHFUL_CONTROL_PASS"
        and all(result["checks"].values())
        and result["official_suite"]["accepted_expected_outcomes"] == 61
        and result["official_suite"]["passed"] == 53
        and result["official_suite"]["pytest_classified_xfails"] == 8
        and result["distribution_integrity"]["hashed_files_verified"] == 1556
        and result["independent_result"]["baseline"]["comparisons"] == 15
        and result["independent_result"]["renamed_reordered"][
            "comparisons"
        ]
        == 15
        and len(result["hostile_rejections"]) == 10
        and result["P1"]["complete"] is True
        and result["A6_satisfied"] is False
        and result["A8_satisfied"] is False
        and result["production_integrated_arms"] == 6
        and result["validation_v6_accessed"] is False
    ):
        raise RuntimeError("phase138 is not the expected P1-only pass")
    return {
        "version": "FOUNDRY_SYMPY_CSE_CONTROL_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": records(),
        "status": result["status"],
        "official_expected_outcomes": 61,
        "official_ordinary_passes": 53,
        "official_source_declared_xfails": 8,
        "distribution_hashed_files_verified": 1556,
        "independent_numeric_comparisons": 30,
        "hostile_rejections": 10,
        "source_faithful_controls_reproduced": 4,
        "P1_complete": True,
        "A6_satisfied": False,
        "A8_satisfied": False,
        "production_integrated_arms": 6,
        "pristine_preregistration": False,
        "initial_infrastructure_failure_preserved": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_SYMPY_CSE_CONTROL_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == records()
        and payload["official_expected_outcomes"] == 61
        and payload["official_ordinary_passes"] == 53
        and payload["official_source_declared_xfails"] == 8
        and payload["distribution_hashed_files_verified"] == 1556
        and payload["independent_numeric_comparisons"] == 30
        and payload["hostile_rejections"] == 10
        and payload["source_faithful_controls_reproduced"] == 4
        and payload["P1_complete"] is True
        and payload["A6_satisfied"] is False
        and payload["A8_satisfied"] is False
        and payload["production_integrated_arms"] == 6
        and payload["pristine_preregistration"] is False
        and payload["initial_infrastructure_failure_preserved"] is True
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("SymPy CSE result freeze changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    if not existed:
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_SYMPY_CSE_CONTROL_RESULT_V1_FREEZE_PASS"
        f" mode={'VERIFY' if existed else 'CREATE'}"
        " controls=4/4 P1=true integrated=6/10"
    )


if __name__ == "__main__":
    main()
