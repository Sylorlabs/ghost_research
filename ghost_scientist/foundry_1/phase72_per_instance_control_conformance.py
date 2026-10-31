#!/usr/bin/env python3
"""Conformance-test calibration-only A3 and A9 control kernels."""

from __future__ import annotations

import hashlib
import json
import pathlib

from per_instance_controls import (
    ControlReject,
    EMPTY_STATE_SHA256,
    canonical,
    run_mode,
    validate_mode,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase72_per_instance_control_conformance.json"
A2_CALIBRATION = HERE / "results/phase63_pareto_motif_calibration.json"


def run() -> None:
    a2 = json.loads(A2_CALIBRATION.read_text(encoding="utf-8"))
    a3 = run_mode("A3_NO_LIBRARY")
    a9 = run_mode("A9_PER_INSTANCE")
    hostile_rejected = False
    try:
        validate_mode("A2_WITH_SECRET_LIBRARY")
    except ControlReject:
        hostile_rejected = True
    a3_summary = a3["summary"]
    a9_summary = a9["summary"]
    checks = {
        "both_controls_cover_same_23_calibration_graphs": (
            a3["graphs"] == a9["graphs"] == a2["graphs"] == 23
        ),
        "same_machine_enumerator_reproduces_A2_path_count": (
            a3_summary["paths_enumerated"]
            == a9_summary["paths_enumerated"]
            == a2["paths_enumerated"]
            == 581
        ),
        "state_reset_exposes_local_rediscovery_overhead": (
            a3_summary["exact_body_groups"]
            == a9_summary["exact_body_groups"]
            == 388
            and a3_summary["exact_body_groups"] - a2["exact_body_groups"]
            == 49
        ),
        "search_units_exactly_equal_between_A3_and_A9": (
            a3_summary["search_construction_units"]
            == a9_summary["search_construction_units"]
            == 969
        ),
        "every_graph_starts_and_ends_empty": all(
            row["state_before_sha256"]
            == row["state_after_disposal_sha256"]
            == EMPTY_STATE_SHA256
            for payload in (a3, a9)
            for row in payload["graph_receipts"]
        ),
        "no_cross_graph_library_retained": all(
            payload["state_policy"]["library_retained_across_graphs"] is False
            and payload["state_policy"]["candidate_state_reset_each_graph"]
            is True
            for payload in (a3, a9)
        ),
        "per_instance_search_is_not_weaker_than_no_library": (
            a9_summary["unique_nodes_covered"]
            >= a3_summary["unique_nodes_covered"]
        ),
        "unknown_control_mode_rejected": hostile_rejected,
        "validation_v6_remained_sealed": (
            a3["validation_v6_accessed"] is False
            and a9["validation_v6_accessed"] is False
        ),
    }
    if not all(checks.values()):
        failed = sorted(name for name, passed in checks.items() if not passed)
        raise RuntimeError(
            "per-instance control conformance failed: "
            + ",".join(failed)
            + f"; A3={a3_summary}; A9={a9_summary}"
        )
    payload = {
        "version": "FOUNDRY_PER_INSTANCE_CONTROL_CONFORMANCE_V1",
        "status": "PER_INSTANCE_CONTROL_KERNELS_CONFORMANCE_PASS",
        "classification": "CALIBRATION_ONLY_NOT_PROSPECTIVE_INTEGRATION",
        "checks": checks,
        "A3": a3,
        "A9": a9,
        "A2_calibration_sha256": hashlib.sha256(
            A2_CALIBRATION.read_bytes()
        ).hexdigest(),
        "production_boundary": {
            "heldout_adapter_integrated": False,
            "process_tree_metered": False,
            "wall_cpu_rss_budget_equivalence_passed": False,
            "prospective_arm_complete": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE72_PER_INSTANCE_CONTROLS"
        f" status={payload['status']}"
        f" search={a3_summary['search_construction_units']}/"
        f"{a9_summary['search_construction_units']}"
        f" coverage={a3_summary['unique_nodes_covered']}/"
        f"{a9_summary['unique_nodes_covered']}"
    )


if __name__ == "__main__":
    run()
