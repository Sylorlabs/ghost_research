#!/usr/bin/env python3
"""Compare an independently parsed production trace receipt exactly."""

from __future__ import annotations

import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
TRACES = HERE / "external_traces"
RESULT = HERE / "results/phase75_external_trace_independent_replay.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def load(name: str) -> dict:
    return json.loads((TRACES / name).read_text(encoding="utf-8"))


def run() -> None:
    protocol = load("INDEPENDENT_REPLAY_PROTOCOL_V1.json")
    primary = load("INVOCATION_TRACE_AGGREGATE_V1.json")
    replay = load("INDEPENDENT_REPLAY_RECEIPT_V1.json")
    p_parse = primary["parse"]
    p_counts = primary["successful_requests_per_model"]
    checks = {
        "protocol_frozen_before_replay": protocol[
            "frozen_before_independent_replay"
        ],
        "immutable_blob_refetched": (
            protocol["input"]["trace_blob"]
            == primary["provenance"]["trace_blob"]
            == replay["trace_blob"]
        ),
        "source_byte_count_exact": (
            primary["provenance"]["source_bytes"]
            == replay["source_bytes"]
            == 2012418
        ),
        "row_count_exact": p_parse["data_rows"] == replay["data_rows"],
        "malformed_rows_exact": (
            p_parse["bad_width_rows"] == replay["malformed_rows"] == 0
        ),
        "status_histogram_exact": (
            p_parse["status_counts"] == replay["status_counts"]
        ),
        "empty_model_rows_exact": (
            p_parse["empty_model_rows"] == replay["empty_model_rows"]
        ),
        "model_population_exact": (
            p_parse["nonempty_model_identities"]
            == replay["nonempty_model_identities"]
        ),
        "zero_success_population_exact": (
            p_parse["zero_success_model_identities"]
            == replay["zero_success_model_identities"]
        ),
        "all_success_order_statistics_exact": (
            p_counts == replay["successful_requests_per_model"]
        ),
        "N_star_exact": (
            primary["predeclared_result"]["N_star_external_reference"]
            == replay["N_star_external_reference"]
            == 3
        ),
        "validation_v6_remained_sealed": (
            replay["validation_v6_accessed"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("independent external trace replay disagreed")
    payload = {
        "version": "FOUNDRY_EXTERNAL_TRACE_INDEPENDENT_REPLAY_V1",
        "status": "EXTERNAL_TRACE_INDEPENDENT_REPLAY_PASS",
        "checks": checks,
        "exact_relations_passed": sum(checks.values()),
        "exact_relations_total": len(checks),
        "N_star_external_reference": 3,
        "scientific_boundary": {
            "aggregate_independently_reproduced": True,
            "source_bytes_locally_frozen": False,
            "cross_domain_transfer_justified": False,
            "P2_complete": False,
        },
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE75_EXTERNAL_TRACE_REPLAY"
        f" status={payload['status']}"
        f" exact={payload['exact_relations_passed']}/"
        f"{payload['exact_relations_total']}"
        " N_star=3 P2=false prospective=false"
    )


if __name__ == "__main__":
    run()
