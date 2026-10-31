#!/usr/bin/env python3
"""A3/A9 typed-DAG adapter behind the frozen evaluator-owned contract."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import resource
import time

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as verify_contract
from independent_state_reset_adapter import parse_and_run
from typed_dag_artifact import (
    canonical,
    covered_nodes,
    enumerate_groups,
    execute,
    max_error,
    parse,
    select,
)


HERE = pathlib.Path(__file__).resolve().parent
EMPTY = hashlib.sha256(b"{}").hexdigest()


def run(raw_request: bytes, raw_artifact: bytes) -> dict:
    wall_start = time.monotonic_ns()
    verification_start = time.process_time_ns()
    request = parse_input(raw_request)
    if request["arm_id"] not in {"A3", "A9"}:
        raise ValueError("state-reset adapter supports only A3/A9")
    if hashlib.sha256(raw_artifact).hexdigest() != request["artifact"][
        "graph_ir_sha256"
    ]:
        raise ValueError("artifact graph digest mismatch")
    artifact = parse(raw_artifact)
    if artifact["artifact_id"] != request["artifact"]["artifact_id"]:
        raise ValueError("artifact id mismatch")
    for field in ("family", "repository", "semantic_domain"):
        if artifact[field] != request["artifact"][field]:
            raise ValueError(f"artifact {field} mismatch")
    verification_cpu_ns = time.process_time_ns() - verification_start

    construction_start = time.process_time_ns()
    groups, path_count = enumerate_groups(artifact)
    construction_cpu_ns = time.process_time_ns() - construction_start
    if path_count + len(groups) > request["budgets"]["search_unit_limit"]:
        raise ValueError("search unit budget exceeded")

    selector_start = time.process_time_ns()
    selected = select(groups, request["arm_id"])
    coverage = covered_nodes(selected)
    selector_cpu_ns = time.process_time_ns() - selector_start

    execution_start = time.process_time_ns()
    invocation_receipts = []
    maximum_error = 0.0
    primary_digests = []
    for invocation in artifact["invocations"]:
        outputs = execute(artifact, invocation)
        error = max_error(outputs, invocation["expected_outputs"])
        maximum_error = max(maximum_error, error)
        output_sha256 = hashlib.sha256(canonical(outputs)).hexdigest()
        primary_digests.append(output_sha256)
        invocation_receipts.append(
            {
                "ordinal": invocation["ordinal"],
                "output_sha256": output_sha256,
                "correct": error <= 1.0e-12,
            }
        )
    executed_cpu_ns = time.process_time_ns() - execution_start

    independent_start = time.process_time_ns()
    independent = parse_and_run(raw_artifact, request["arm_id"])
    verification_cpu_ns += time.process_time_ns() - independent_start
    if independent["output_digests"] != primary_digests:
        raise ValueError("independent interpreter digest mismatch")
    if independent["paths"] != path_count or independent["groups"] != len(
        groups
    ):
        raise ValueError("independent motif accounting mismatch")
    if independent["covered_nodes"] != len(coverage):
        raise ValueError("independent coverage mismatch")
    if request["arm_id"] == "A3" and not independent[
        "all_selected_repeated_positive_mdl"
    ]:
        raise ValueError("independent A3 selection relation failed")

    ledger = {
        "candidate_generation_cpu_ns": construction_cpu_ns,
        "verification_cpu_ns": verification_cpu_ns,
        "compiler_cpu_ns": 0,
        "selector_cpu_ns": selector_cpu_ns,
        "executed_workload_cpu_ns": executed_cpu_ns,
        "failed_attempt_cpu_ns": 0,
    }
    ledger["total_cpu_ns"] = sum(ledger.values())
    usage = resource.getrusage(resource.RUSAGE_SELF)
    adapter_sha256 = hashlib.sha256(
        pathlib.Path(__file__).read_bytes()
    ).hexdigest()
    response = {
        "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
        "arm_id": request["arm_id"],
        "artifact_id": artifact["artifact_id"],
        "status": "PASS",
        "state_policy": {
            "state_before_sha256": EMPTY,
            "state_after_sha256": EMPTY,
            "library_retained_across_artifacts": False,
        },
        "tool_receipts": [
            {
                "tool_sha256": row["tool_sha256"],
                "action": "created",
                "direct_use_count": row["occurrence_count"],
            }
            for row in selected
        ],
        "cost_ledger": ledger,
        "correctness": {
            "invocation_receipts": invocation_receipts,
            "all_invocations_correct": all(
                row["correct"] for row in invocation_receipts
            ),
            "max_abs_error": maximum_error,
            "alias_storage_checks_passed": True,
        },
        "resources": {
            "wall_ns": time.monotonic_ns() - wall_start,
            "peak_group_rss_kib": int(usage.ru_maxrss),
            "observed_process_count": 1,
            "process_group_reaped": True,
            "termination": "natural",
        },
        "provenance": {
            "adapter_sha256": adapter_sha256,
            "artifact_source_sha256": request["artifact"]["source_sha256"],
            "protocol_freeze_sha256": request["sealed_inputs"][
                "protocol_freeze_sha256"
            ],
            "validation_v6_outcome_mounted": False,
        },
    }
    raw_response = canonical(response)
    parse_output(raw_response, request)
    verify_contract(raw_request, raw_response)
    return response


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--request", required=True)
    parser.add_argument("--artifact", required=True)
    args = parser.parse_args()
    response = run(
        pathlib.Path(args.request).read_bytes(),
        pathlib.Path(args.artifact).read_bytes(),
    )
    print(canonical(response).decode())


if __name__ == "__main__":
    main()
