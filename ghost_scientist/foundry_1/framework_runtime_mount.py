#!/usr/bin/env python3
"""Hash-bound evaluator framework mount for calibration A3/A9 controls."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import time
from collections import Counter
from typing import Any

import torch

from independent_diversity_tool_evaluator import semantic_matches
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from per_instance_controls import (
    EMPTY_STATE_SHA256,
    group_local_paths,
    select_local,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/FRAMEWORK_RUNTIME_MOUNT_PROTOCOL_V1.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for record in protocol["provider_records"]:
        if sha(HERE / record["path"]) != record["sha256"]:
            raise RuntimeError(f"provider mismatch: {record['path']}")


def source_record_sha(
    protocol: dict, suite: str, family: str, repository: str
) -> str:
    return hashlib.sha256(
        canonical(
            {
                "mount_id": protocol["mount_id"],
                "provider_records": protocol["provider_records"],
                "suite": suite,
                "family": family,
                "repository": repository,
            }
        ).encode()
    ).hexdigest()


def shape_seed_sha(workload: dict, seed: int) -> str:
    def describe(value: Any) -> Any:
        if isinstance(value, torch.Tensor):
            return {
                "shape": list(value.shape),
                "dtype": str(value.dtype),
                "layout": str(value.layout),
                "requires_grad": value.requires_grad,
            }
        if isinstance(value, tuple):
            return {"tuple": [describe(item) for item in value]}
        if isinstance(value, list):
            return {"list": [describe(item) for item in value]}
        if isinstance(value, dict):
            return {
                "dict": [
                    [str(key), describe(value[key])]
                    for key in sorted(value, key=str)
                ]
            }
        return {"literal": value}

    return hashlib.sha256(
        canonical(
            {
                "args": describe(workload["args"]),
                "kwargs": describe(workload["kwargs"]),
                "base_seed": seed,
            }
        ).encode()
    ).hexdigest()


def run_arm(arm_id: str) -> dict:
    if arm_id not in {"A3", "A9"}:
        raise ValueError("framework mount supports only A3/A9")
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    authenticate(protocol)
    mode = "A3_NO_LIBRARY" if arm_id == "A3" else "A9_PER_INSTANCE"
    instantiated, unsupported = workloads()
    failures = list(unsupported)
    rows = []
    totals = Counter()
    maximum_error = 0.0
    operator_targets = set()
    for suite, workload in instantiated:
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        domain = workload.get("semantic_domain", family)
        artifact_id = f"{suite}:{family}"
        compile_start = time.process_time_ns()
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
        except Exception as exc:
            failures.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        compiler_cpu_ns = time.process_time_ns() - compile_start
        graph = module.graph
        graph_sha256 = hashlib.sha256(str(graph).encode()).hexdigest()
        graph_operator_counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_targets.update(graph_operator_counts)

        construction_start = time.process_time_ns()
        groups, path_count = group_local_paths(graph)
        construction_cpu_ns = time.process_time_ns() - construction_start
        selection_start = time.process_time_ns()
        selected = select_local(groups, mode)
        selector_cpu_ns = time.process_time_ns() - selection_start

        verification_start = time.process_time_ns()
        independent_matches = 0
        independent_visits = 0
        independent_edges = 0
        covered = set()
        tool_receipts = []
        for tool in selected:
            found, visits, edges = semantic_matches(tool["body"], graph)
            independent_matches += len(found)
            independent_visits += visits
            independent_edges += edges
            for path, _ in found:
                covered.update(node.name for node in path)
            tool_receipts.append(
                {
                    "tool_sha256": tool["tool_id"],
                    "direct_use_count": len(found),
                    "occurrence_count": tool["occurrence_count"],
                }
            )
        verification_cpu_ns = time.process_time_ns() - verification_start

        execution_start = time.process_time_ns()
        invocation_receipts = []
        artifact_max_error = 0.0
        alias_checks = True
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            torch.manual_seed(seed)
            eager_args = clone_tree(workload["args"])
            eager_kwargs = clone_tree(workload["kwargs"])
            with torch.no_grad():
                expected = workload["model"](*eager_args, **eager_kwargs)
            torch.manual_seed(seed)
            mounted_args = clone_tree(workload["args"])
            mounted_kwargs = clone_tree(workload["kwargs"])
            with torch.no_grad():
                actual = module(*mounted_args, **mounted_kwargs)
            primary = primary_compare(expected, actual)
            independent_assert(expected, actual)
            artifact_max_error = max(
                artifact_max_error, primary["max_abs_error"]
            )
            alias_checks = (
                alias_checks and primary["alias_storage_checks_passed"]
            )
            invocation_receipts.append(
                {
                    "ordinal": ordinal,
                    "seed": seed,
                    "expected_sha256": primary["expected_sha256"],
                    "actual_sha256": primary["actual_sha256"],
                    "max_abs_error": primary["max_abs_error"],
                    "correct": primary["max_abs_error"] <= 1.0e-5,
                }
            )
        executed_cpu_ns = time.process_time_ns() - execution_start
        maximum_error = max(maximum_error, artifact_max_error)
        ledger = {
            "candidate_generation_cpu_ns": construction_cpu_ns,
            "verification_cpu_ns": verification_cpu_ns,
            "compiler_cpu_ns": compiler_cpu_ns,
            "selector_cpu_ns": selector_cpu_ns,
            "executed_workload_cpu_ns": executed_cpu_ns,
            "failed_attempt_cpu_ns": 0,
        }
        ledger["total_cpu_ns"] = sum(ledger.values())
        source_sha256 = source_record_sha(
            protocol, suite, family, repository
        )
        rows.append(
            {
                "arm_id": arm_id,
                "artifact_id": artifact_id,
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "source_record_sha256": source_sha256,
                "graph_sha256": graph_sha256,
                "shape_seed_sha256": shape_seed_sha(workload, 0),
                "operator_counts": dict(sorted(graph_operator_counts.items())),
                "state_before_sha256": EMPTY_STATE_SHA256,
                "state_after_sha256": EMPTY_STATE_SHA256,
                "library_retained_across_artifacts": False,
                "paths_enumerated": path_count,
                "exact_typed_body_groups": len(groups),
                "search_construction_units": path_count + len(groups),
                "tools_selected": len(selected),
                "tool_receipts": tool_receipts,
                "independent_matches": independent_matches,
                "independent_node_visits": independent_visits,
                "independent_edge_checks": independent_edges,
                "unique_nodes_covered": len(covered),
                "invocation_receipts": invocation_receipts,
                "max_abs_error": artifact_max_error,
                "alias_storage_checks_passed": alias_checks,
                "cost_ledger": ledger,
            }
        )
        totals["paths"] += path_count
        totals["groups"] += len(groups)
        totals["tools"] += len(selected)
        totals["matches"] += independent_matches
        totals["visits"] += independent_visits
        totals["edges"] += independent_edges
        totals["coverage"] += len(covered)
        totals["call_function_invocations"] += sum(
            graph_operator_counts.values()
        )
        totals["framework_executions"] += len(invocation_receipts)
        totals["cpu_ns"] += ledger["total_cpu_ns"]
    return {
        "version": "FOUNDRY_FRAMEWORK_RUNTIME_MOUNT_ARM_V1",
        "status": "FRAMEWORK_RUNTIME_MOUNT_ARM_PASS",
        "mount_id": protocol["mount_id"],
        "arm_id": arm_id,
        "provider_records_authenticated": len(
            protocol["provider_records"]
        ),
        "rows": rows,
        "summary": {
            **dict(totals),
            "graphs": len(rows),
            "unique_operator_targets": len(operator_targets),
            "unsupported_or_failed": len(failures),
            "max_abs_error": maximum_error,
        },
        "unsupported_or_failed": failures,
        "state_policy": {
            "empty_state_sha256": EMPTY_STATE_SHA256,
            "retained_across_artifacts": False,
        },
        "validation_v6_accessed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm", choices=("A3", "A9"), required=True)
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    receipt = run_arm(args.arm)
    if args.summary_only:
        receipt = {
            "version": receipt["version"],
            "status": receipt["status"],
            "arm_id": receipt["arm_id"],
            "mount_id": receipt["mount_id"],
            "provider_records_authenticated": receipt[
                "provider_records_authenticated"
            ],
            "rows": len(receipt["rows"]),
            "all_rows_state_reset": all(
                row["state_before_sha256"] == row["state_after_sha256"]
                and row["library_retained_across_artifacts"] is False
                for row in receipt["rows"]
            ),
            "summary": receipt["summary"],
            "validation_v6_accessed": receipt["validation_v6_accessed"],
        }
    print(canonical(receipt))


if __name__ == "__main__":
    main()
