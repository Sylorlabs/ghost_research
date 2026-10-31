#!/usr/bin/env python3
"""Recompute readiness after the fourth source-faithful control."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_23.json"
    control_path = RESULTS / "sympy_cse_control_result_v1_freeze.json"
    prior = json.loads(prior_path.read_text())
    control = json.loads(control_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["prerequisites"]["P1_external_control_conformance"] is False
        and prior["authorization"]["prerequisites_passed"] == 5
        and control["status"]
        == "SYMPY_CSE_FOURTH_SOURCE_FAITHFUL_CONTROL_PASS"
        and control["source_faithful_controls_reproduced"] == 4
        and control["P1_complete"] is True
        and control["A6_satisfied"] is False
        and control["A8_satisfied"] is False
        and control["production_integrated_arms"] == 6
    ):
        raise RuntimeError("iteration 5.24 inputs changed")
    prerequisites = {
        **prior["prerequisites"],
        "P1_external_control_conformance": True,
    }
    progress = {
        **prior["progress"],
        "P1_complete": True,
        "source_faithful_controls_reproduced": 4,
        "sympy_cse_official_expected_outcomes": 61,
        "sympy_cse_official_ordinary_passes": 53,
        "sympy_cse_official_source_declared_xfails": 8,
        "sympy_cse_distribution_hashed_files_verified": 1556,
        "sympy_cse_independent_numeric_comparisons": 30,
        "sympy_cse_hostile_rejections": 10,
        "sympy_cse_initial_infrastructure_failure_preserved": True,
        "sympy_cse_pristine_preregistration": False,
        "A6_production_integrated": False,
        "A8_production_integrated": False,
    }
    authorization = {
        **prior["authorization"],
        "prerequisites_passed": 6,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_24",
        "prior_sha256": sha(prior_path),
        "sympy_cse_control_freeze_sha256": sha(control_path),
        "prerequisites": prerequisites,
        "progress": progress,
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "P1 is now closed by a fourth independent source-faithful "
            "control. Exact installed SymPy 1.13.1 CSE algorithm and test "
            "sources match the official release tag, 1,556 hashed distribution "
            "files match RECORD, and the official suite produces 53 ordinary "
            "passes plus eight exact source-declared XFAIL outcomes with zero "
            "unexpected failures, errors, or XPASS. A stdlib-only evaluator "
            "reconstructs 30 baseline and renamed/reordered outputs exactly, "
            "ten hostile ledgers fail, and the process tree is metered. The "
            "initial missing-Hypothesis infrastructure failure and the "
            "post-infrastructure runner clarification remain disclosed, so "
            "this is not called pristine preregistration. All six Foundry-0 "
            "prerequisites now pass, but the trial remains unauthorized: only "
            "six of ten required arms are production-integrated, A6/A8 remain "
            "unsatisfied, and the frozen V08 measurement remains pending."
        ),
        "remaining_blockers": [
            "the production arm matrix remains 6/10: A1, A6, A7, and A8 are not production-integrated",
            "A6 still requires the exact ISAMORE locked/native execution closure",
            "A8 still lacks a faithful upstream implementation or a distinctly pre-registered adapted production control",
            "A1 requires a complete typed lowering rather than an opaque fallback",
            "A7 requires a separately frozen tensor-domain production arm rather than the Boolean control label",
            "the frozen V08 search distinction remains unmeasured until a fully authorized trial",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed; audit the four missing production "
                "arms against the exact V10 contract and implement the shortest "
                "complete, non-duplicative arm without relabeling SymPy as A6 "
                "or using its P1 pass to waive arm integration"
            ),
            "forbidden_shortcuts": [
                "do not relabel SymPy CSE as ISAMORE, A6, EggMind, or A8",
                "do not count P1 closure as production-arm integration",
                "do not hide the initial Hypothesis infrastructure failure or call the amendment pristine preregistration",
                "do not lower the required arm count below ten",
                "do not call the pending V08 measurement passed",
                "do not open validation-v6 before the full arm and validity authorization passes",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_24.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_24"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " controls=4/4 integrated=6/10"
        " V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
