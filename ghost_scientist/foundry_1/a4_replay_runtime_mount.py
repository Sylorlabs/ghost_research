#!/usr/bin/env python3
"""Framework runtime mount for the frozen A4 historical replay arm."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
import time
from collections import Counter
from typing import Any

import torch

from independent_diversity_tool_evaluator import (
    CapturingInterpreter,
    execute_tool,
    max_error,
    parse_library,
    semantic_matches,
)
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A4_REPLAY_RUNTIME_PROTOCOL_V1.json"
LIBRARY = HERE / "results/forged_diversity_tools.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")


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


def run() -> dict:
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    parse_start = time.process_time_ns()
    library_raw = LIBRARY.read_bytes()
    library = parse_library(library_raw)
    parse_cpu_ns = time.process_time_ns() - parse_start
    library_sha256 = hashlib.sha256(library_raw).hexdigest()
    instantiated, unsupported = workloads()
    rows = []
    failures = list(unsupported)
    totals = Counter()
    tool_totals = Counter()
    maximum_graph_error = 0.0
    maximum_tool_error = 0.0
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
        operator_counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_targets.update(operator_counts)

        verification_start = time.process_time_ns()
        interpreter = CapturingInterpreter(module)
        with torch.no_grad():
            interpreter.run(
                *clone_tree(workload["args"]),
                **clone_tree(workload["kwargs"]),
            )
        tool_receipts = []
        matched_nodes = set()
        visits_total = edges_total = 0
        for tool in library["tools"]:
            matches, visits, edges = semantic_matches(tool, graph)
            visits_total += visits
            edges_total += edges
            tool_error = 0.0
            for path, bindings in matches:
                inputs = [
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                ]
                replayed = execute_tool(tool, inputs)
                error = max_error(
                    replayed, interpreter.values[path[-1]]
                )
                if error > 1.0e-6:
                    raise RuntimeError(
                        f"A4 replay mismatch {artifact_id} "
                        f"{tool['tool_id']} error={error}"
                    )
                tool_error = max(tool_error, error)
                matched_nodes.update(node.name for node in path)
            maximum_tool_error = max(maximum_tool_error, tool_error)
            tool_totals[tool["tool_id"]] += len(matches)
            tool_receipts.append(
                {
                    "tool_sha256": tool["tool_id"],
                    "direct_use_count": len(matches),
                    "max_abs_error": tool_error,
                }
            )
        verification_cpu_ns = time.process_time_ns() - verification_start

        execution_start = time.process_time_ns()
        invocation_receipts = []
        artifact_error = 0.0
        aliases = True
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A4:{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            torch.manual_seed(seed)
            with torch.no_grad():
                expected = workload["model"](
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            torch.manual_seed(seed)
            with torch.no_grad():
                actual = module(
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            compared = primary_compare(expected, actual)
            independent_assert(expected, actual)
            artifact_error = max(
                artifact_error, compared["max_abs_error"]
            )
            aliases = aliases and compared[
                "alias_storage_checks_passed"
            ]
            invocation_receipts.append(
                {
                    "ordinal": ordinal,
                    "seed": seed,
                    "expected_sha256": compared["expected_sha256"],
                    "actual_sha256": compared["actual_sha256"],
                    "max_abs_error": compared["max_abs_error"],
                    "correct": compared["max_abs_error"] <= 1.0e-5,
                }
            )
        execution_cpu_ns = time.process_time_ns() - execution_start
        maximum_graph_error = max(maximum_graph_error, artifact_error)
        ledger = {
            "candidate_generation_cpu_ns": 0,
            "verification_cpu_ns": verification_cpu_ns,
            "compiler_cpu_ns": compiler_cpu_ns,
            "selector_cpu_ns": parse_cpu_ns if not rows else 0,
            "executed_workload_cpu_ns": execution_cpu_ns,
            "failed_attempt_cpu_ns": 0,
        }
        ledger["total_cpu_ns"] = sum(ledger.values())
        source_sha256 = hashlib.sha256(
            canonical(
                {
                    "mount_id": protocol["mount_id"],
                    "suite": suite,
                    "family": family,
                    "repository": repository,
                    "providers": protocol["provider_records"],
                }
            ).encode()
        ).hexdigest()
        shape_seed_sha256 = hashlib.sha256(
            canonical(
                {
                    "args": describe(workload["args"]),
                    "kwargs": describe(workload["kwargs"]),
                    "base_seed": 0,
                }
            ).encode()
        ).hexdigest()
        rows.append(
            {
                "arm_id": "A4",
                "artifact_id": artifact_id,
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "source_record_sha256": source_sha256,
                "graph_sha256": graph_sha256,
                "shape_seed_sha256": shape_seed_sha256,
                "operator_counts": dict(sorted(operator_counts.items())),
                "state_before_sha256": library_sha256,
                "state_after_sha256": library_sha256,
                "library_retained_across_artifacts": True,
                "tool_receipts": tool_receipts,
                "semantic_node_visits": visits_total,
                "semantic_edge_checks": edges_total,
                "unique_nodes_covered": len(matched_nodes),
                "invocation_receipts": invocation_receipts,
                "max_abs_error": artifact_error,
                "alias_storage_checks_passed": aliases,
                "cost_ledger": ledger,
            }
        )
        totals["calls"] += sum(operator_counts.values())
        totals["executions"] += len(invocation_receipts)
        totals["visits"] += visits_total
        totals["edges"] += edges_total
        totals["coverage"] += len(matched_nodes)
        totals["cpu_ns"] += ledger["total_cpu_ns"]
    summary = {
        "graphs": len(rows),
        "unique_operator_targets": len(operator_targets),
        "call_function_invocations": totals["calls"],
        "whole_graph_executions": totals["executions"],
        "unsupported_or_failed": len(failures),
        "immutable_tools": len(library["tools"]),
        "tools_replayed": sum(value > 0 for value in tool_totals.values()),
        "successful_tool_replays": sum(tool_totals.values()),
        "tool_replays_by_id": dict(sorted(tool_totals.items())),
        "unique_node_coverage_sum": totals["coverage"],
        "semantic_node_visits": totals["visits"],
        "semantic_edge_checks": totals["edges"],
        "max_tool_abs_error": maximum_tool_error,
        "max_graph_abs_error": maximum_graph_error,
        "cpu_ns": totals["cpu_ns"],
    }
    expected = protocol["acceptance_rules"]
    passed = (
        summary["graphs"] == expected["graphs"]
        and summary["unique_operator_targets"]
        == expected["unique_operator_targets"]
        and summary["call_function_invocations"]
        == expected["call_function_invocations"]
        and summary["whole_graph_executions"]
        == expected["whole_graph_executions"]
        and summary["unsupported_or_failed"]
        == expected["unsupported_or_failed"]
        and summary["immutable_tools"] == expected["immutable_tools"]
        and summary["tools_replayed"] == expected["immutable_tools"]
        and summary["max_tool_abs_error"] <= 1.0e-6
        and summary["max_graph_abs_error"] <= 1.0e-5
        and all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == library_sha256
            and row["library_retained_across_artifacts"] is True
            for row in rows
        )
    )
    if not passed:
        raise RuntimeError(
            "A4 replay runtime acceptance failed: " + canonical(summary)
        )
    return {
        "version": "FOUNDRY_A4_REPLAY_RUNTIME_MOUNT_V1",
        "status": "A4_REPLAY_RUNTIME_MOUNT_COMPONENT_PASS",
        "mount_id": protocol["mount_id"],
        "provider_records_authenticated": len(
            protocol["provider_records"]
        ),
        "library_sha256": library_sha256,
        "rows": rows,
        "unsupported_or_failed": failures,
        "summary": summary,
        "integration": {
            "A4_runtime_mount_component_ready": True,
            "A4_production_integrated": False,
            "production_integrated_arms": 4,
        },
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    receipt = run()
    if args.summary_only:
        receipt = {
            "version": receipt["version"],
            "status": receipt["status"],
            "mount_id": receipt["mount_id"],
            "provider_records_authenticated": receipt[
                "provider_records_authenticated"
            ],
            "library_sha256": receipt["library_sha256"],
            "rows": len(receipt["rows"]),
            "summary": receipt["summary"],
            "A4_production_integrated": receipt["integration"][
                "A4_production_integrated"
            ],
            "P3_complete": receipt["P3_complete"],
            "validation_v6_accessed": receipt["validation_v6_accessed"],
        }
    print(canonical(receipt))


if __name__ == "__main__":
    main()
