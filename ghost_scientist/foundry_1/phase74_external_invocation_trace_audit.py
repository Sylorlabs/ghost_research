#!/usr/bin/env python3
"""Audit the predeclared external invocation-horizon aggregation."""

from __future__ import annotations

import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
TRACE_DIR = HERE / "external_traces"
RESULT = HERE / "results/phase74_external_invocation_trace_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def load(name: str) -> dict:
    return json.loads((TRACE_DIR / name).read_text(encoding="utf-8"))


def run() -> None:
    intake = load("INVOCATION_TRACE_INTAKE_V1.json")
    failure = load("INVOCATION_TRACE_SCHEMA_FAILURE_V1.json")
    amendment = load("INVOCATION_TRACE_SCHEMA_AMENDMENT_V1.json")
    aggregate = load("INVOCATION_TRACE_AGGREGATE_V1.json")
    parse = aggregate["parse"]
    counts = aggregate["successful_requests_per_model"]
    checks = {
        "selection_frozen_before_distribution_audit": intake[
            "frozen_before_distribution_audit"
        ],
        "immutable_trace_identity_consistent": (
            intake["selected_source"]["trace_blob"]
            == failure["trace_blob"]
            == aggregate["provenance"]["trace_blob"]
            == "db8d3cfaea62e7086aff40e98ab6446619d9e5ce"
        ),
        "first_schema_failure_preserved": (
            failure["N_star_external_reference_produced"] is False
            and failure["observed_header"] == parse["header"]
        ),
        "amendment_schema_only": (
            amendment["schema_corrections"]["timestamp_field"]["to"]
            == "gmt_create"
            and amendment["schema_corrections"]["completion_field"]["to"]
            == "predict_status"
            and amendment["schema_corrections"]["successful_status"]["to"]
            == "SUCCEED"
            and amendment["unchanged_predeclared_estimator"]["quantile"]
            == 0.25
            and amendment["unchanged_predeclared_estimator"]["filters"] == []
        ),
        "rows_account_exactly": (
            sum(parse["status_counts"].values()) == parse["data_rows"] == 26823
            and parse["bad_width_rows"] == 0
        ),
        "successes_account_exactly": (
            counts["sum"] == parse["status_counts"]["SUCCEED"] == 26392
        ),
        "population_includes_zero_success_models": (
            parse["nonempty_model_identities"] == 86
            and parse["zero_success_model_identities"] == 7
            and counts["minimum"] == 0
        ),
        "predeclared_lower_quartile_bound": (
            counts["q25_nearest_rank"]
            == aggregate["predeclared_result"]["N_star_external_reference"]
            == 3
        ),
        "P2_not_inflated": (
            aggregate["limitations"]["P2_complete"] is False
            and aggregate["limitations"][
                "heldout_foundry_family_mapping_prospectively_justified"
            ]
            is False
        ),
        "validation_v6_remained_sealed": (
            aggregate[
                "validation_v6_source_runtime_graph_or_outcome_accessed"
            ]
            is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("external invocation trace audit failed")
    payload = {
        "version": "FOUNDRY_EXTERNAL_INVOCATION_TRACE_AUDIT_V1",
        "status": "EXTERNAL_INVOCATION_HORIZON_COMPONENT_READY",
        "classification": "PINNED_PRODUCTION_TRACE_AGGREGATE_NOT_TRANSFER_VALIDATED",
        "checks": checks,
        "trace": {
            "rows": parse["data_rows"],
            "models": parse["nonempty_model_identities"],
            "successful_requests": counts["sum"],
            "time_min": parse["timestamp_min"],
            "time_max": parse["timestamp_max"],
        },
        "N_star_external_reference": 3,
        "P2": {
            "independent_production_invocation_trace": True,
            "predeclared_horizon_estimator_executed": True,
            "source_bytes_locally_frozen": False,
            "heldout_stream_transfer_justified": False,
            "complete": False,
        },
        "prospective_trial_authorized": False,
        "validation_v6_accessed": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE74_EXTERNAL_INVOCATION_TRACE"
        f" status={payload['status']}"
        f" rows={payload['trace']['rows']}"
        f" models={payload['trace']['models']}"
        f" N_star={payload['N_star_external_reference']}"
        " P2=false prospective=false"
    )


if __name__ == "__main__":
    run()
