#!/usr/bin/env python3
"""Mount and execute the frozen A6 typed anti-unification tool."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import time
from collections import Counter
from typing import Any

import torch
from torch.fx import GraphModule, Node

from a6_typed_anti_unification import canonical, extract_roots, matches
from independent_a6_runtime_tool import (
    audit_transformed_graph,
    selected_root_ids,
)
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A6_TYPED_ANTI_UNIFICATION_RUNTIME_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a6_typed_anti_unification_runtime_v1_freeze.json"
REACHABILITY = (
    HERE / "results/phase149_a6_typed_anti_unification_reachability.json"
)

_A6_TOOL_EXECUTIONS = 0


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def a6_linear_relu_tool(
    input_tensor: torch.Tensor,
    weight: torch.Tensor,
    bias: torch.Tensor,
) -> torch.Tensor:
    """Generated from the frozen relu(linear(?0, ?1, ?2)) pattern."""
    global _A6_TOOL_EXECUTIONS
    _A6_TOOL_EXECUTIONS += 1
    linear = torch.ops.aten.linear.default(input_tensor, weight, bias)
    return torch.ops.aten.relu.default(linear)


def reset_tool_counter() -> None:
    global _A6_TOOL_EXECUTIONS
    _A6_TOOL_EXECUTIONS = 0


def tool_counter() -> int:
    return _A6_TOOL_EXECUTIONS


def describe(value: Any) -> dict[str, Any]:
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


def authenticate(protocol: dict[str, Any]) -> dict[str, Any]:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"A6 provider mismatch: {row['path']}")
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["selected_candidate"] == protocol["selected_candidate"]
        and freeze["surface"] == protocol["surface"]
        and freeze["acceptance"] == protocol["acceptance"]
        and freeze[
            "frozen_before_mount_or_contract_runner_implementation_or_execution"
        ]
        is True
    ):
        raise RuntimeError("A6 runtime freeze mismatch")
    reachability = json.loads(REACHABILITY.read_text())
    if reachability["status"] != "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_POSITIVE":
        raise RuntimeError("A6 reachability is not positive")
    selected = reachability["observed"]["selected_candidate"]
    expected = protocol["selected_candidate"]
    if not (
        selected["pattern_sha256"] == expected["pattern_sha256"]
        and selected["operator_nodes"] == expected["operator_nodes"]
        and selected["distinct_metavariables"]
        == expected["distinct_metavariables"]
        and len(selected["matches"]) == expected["matches"]
        and len(selected["matching_artifacts"]) == expected["matching_artifacts"]
    ):
        raise RuntimeError("A6 selected candidate mismatch")
    return selected


def rewrite_matches(
    module: GraphModule,
    root_names: list[str],
) -> tuple[GraphModule, dict[str, Any]]:
    transformed = copy.deepcopy(module)
    by_name = {node.name: node for node in transformed.graph.nodes}
    rewritten = []
    for root_name in root_names:
        root = by_name.get(root_name)
        if (
            root is None
            or root.op != "call_function"
            or str(root.target) != "aten.relu.default"
            or len(root.args) != 1
            or root.kwargs
        ):
            raise RuntimeError(f"A6 selected root changed: {root_name}")
        linear = root.args[0]
        if (
            not isinstance(linear, Node)
            or linear.op != "call_function"
            or str(linear.target) != "aten.linear.default"
            or len(linear.args) != 3
            or linear.kwargs
        ):
            raise RuntimeError(f"A6 selected linear changed: {root_name}")
        with transformed.graph.inserting_before(root):
            replacement = transformed.graph.call_function(
                a6_linear_relu_tool,
                args=linear.args,
            )
            replacement.meta = dict(root.meta)
        root.replace_all_uses_with(replacement)
        transformed.graph.erase_node(root)
        if not linear.users:
            transformed.graph.erase_node(linear)
        rewritten.append(
            {
                "selected_root": root_name,
                "tool_node": replacement.name,
                "source_linear": linear.name,
            }
        )
    transformed.graph.lint()
    transformed.recompile()
    independent = audit_transformed_graph(
        transformed, a6_linear_relu_tool, len(root_names)
    )
    return transformed, {
        "rewrites": rewritten,
        "independent_audit": independent,
    }


def run() -> dict[str, Any]:
    protocol = json.loads(PROTOCOL.read_text())
    selected = authenticate(protocol)
    pattern = selected["pattern"]
    library_sha256 = selected["pattern_sha256"]
    reachability = json.loads(REACHABILITY.read_text())
    historic_receipt = reachability["receipt"]
    candidate_generation_cpu_ns = (
        historic_receipt["rusage_user_cpu_ns"]
        + historic_receipt["rusage_system_cpu_ns"]
    )
    instantiated, unsupported = workloads()
    rows = []
    totals: Counter[str] = Counter()
    all_match_ids = []
    maximum_error = 0.0
    operator_targets = set()

    for index, (suite, workload) in enumerate(instantiated):
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        semantic_domain = workload.get("semantic_domain", family)
        artifact_id = f"{suite}:{family}"

        compiler_start = time.process_time_ns()
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        module = exported.module()
        compiler_cpu_ns = time.process_time_ns() - compiler_start
        graph = module.graph
        counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_targets.update(counts)

        verification_start = time.process_time_ns()
        primary_roots = extract_roots(module, artifact_id, 4)
        primary_ids = sorted(
            row["root_id"]
            for row in primary_roots
            if matches(pattern, row["term"])
        )
        independent_ids = selected_root_ids(
            module, artifact_id, pattern, 4
        )
        if primary_ids != independent_ids:
            raise RuntimeError(f"A6 runtime matchers disagree: {artifact_id}")
        if any(item not in selected["matches"] for item in primary_ids):
            raise RuntimeError(f"A6 runtime found an unfrozen match: {artifact_id}")
        expected_for_artifact = sorted(
            item
            for item in selected["matches"]
            if item.startswith(artifact_id + ":")
        )
        if primary_ids != expected_for_artifact:
            raise RuntimeError(f"A6 frozen match set changed: {artifact_id}")
        root_names = [item.rsplit(":", 1)[1] for item in primary_ids]
        transformed, transform_receipt = rewrite_matches(module, root_names)
        verification_cpu_ns = time.process_time_ns() - verification_start
        all_match_ids.extend(primary_ids)

        invocation_receipts = []
        artifact_error = 0.0
        aliases = True
        executed_workload_cpu_ns = 0
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A6-MOUNT:{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            execution_start = time.process_time_ns()
            torch.manual_seed(seed)
            with torch.no_grad():
                expected_output = module(
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            torch.manual_seed(seed)
            reset_tool_counter()
            with torch.no_grad():
                actual_output = transformed(
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            calls = tool_counter()
            executed_workload_cpu_ns += (
                time.process_time_ns() - execution_start
            )
            if calls != len(root_names):
                raise RuntimeError(
                    f"A6 tool execution count mismatch: {artifact_id}"
                )
            compare_start = time.process_time_ns()
            comparison = primary_compare(expected_output, actual_output)
            independent_assert(expected_output, actual_output)
            verification_cpu_ns += time.process_time_ns() - compare_start
            correct = (
                comparison["max_abs_error"]
                <= protocol["runtime_correctness"]["maximum_absolute_error"]
                and comparison["alias_storage_checks_passed"]
            )
            artifact_error = max(
                artifact_error, comparison["max_abs_error"]
            )
            aliases = aliases and comparison["alias_storage_checks_passed"]
            invocation_receipts.append(
                {
                    "ordinal": ordinal,
                    "seed": seed,
                    "expected_sha256": comparison["expected_sha256"],
                    "actual_sha256": comparison["actual_sha256"],
                    "max_abs_error": comparison["max_abs_error"],
                    "correct": correct,
                    "tool_executions": calls,
                }
            )

        selector_cpu_ns = max(
            1,
            verification_cpu_ns
            // max(1, len(primary_roots) + len(root_names)),
        )
        ledger = {
            "candidate_generation_cpu_ns": (
                candidate_generation_cpu_ns if index == 0 else 0
            ),
            "verification_cpu_ns": verification_cpu_ns,
            "compiler_cpu_ns": compiler_cpu_ns,
            "selector_cpu_ns": selector_cpu_ns,
            "executed_workload_cpu_ns": executed_workload_cpu_ns,
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
        tool_receipts = (
            [
                {
                    "tool_sha256": library_sha256,
                    "action": "constructed_and_reused",
                    "direct_use_count": len(root_names) * 3,
                }
            ]
            if root_names
            else []
        )
        rows.append(
            {
                "arm_id": "A6",
                "artifact_id": artifact_id,
                "family": family,
                "repository": repository,
                "semantic_domain": semantic_domain,
                "source_record_sha256": source_sha256,
                "graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "transformed_graph_sha256": hashlib.sha256(
                    str(transformed.graph).encode()
                ).hexdigest(),
                "shape_seed_sha256": shape_seed_sha256,
                "operator_counts": dict(sorted(counts.items())),
                "root_count": len(primary_roots),
                "selected_match_ids": primary_ids,
                "tool_sites": len(root_names),
                "transform_receipt": transform_receipt,
                "tool_receipts": tool_receipts,
                "invocation_receipts": invocation_receipts,
                "max_abs_error": artifact_error,
                "alias_storage_checks_passed": aliases,
                "state_before_sha256": library_sha256,
                "state_after_sha256": library_sha256,
                "library_retained_across_artifacts": True,
                "cost_ledger": ledger,
            }
        )
        maximum_error = max(maximum_error, artifact_error)
        totals["roots"] += len(primary_roots)
        totals["sites"] += len(root_names)
        totals["executions"] += len(invocation_receipts)
        totals["direct_uses"] += len(root_names) * len(invocation_receipts)

    if sorted(all_match_ids) != sorted(selected["matches"]):
        raise RuntimeError("A6 complete frozen match set not reproduced")
    return {
        "version": "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_RUNTIME_MOUNT_V1",
        "status": "A6_TYPED_ANTI_UNIFICATION_RUNTIME_MOUNT_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "library_sha256": library_sha256,
        "candidate_generation_receipt_sha256": hashlib.sha256(
            canonical(historic_receipt).encode()
        ).hexdigest(),
        "candidate_generation_cpu_ns": candidate_generation_cpu_ns,
        "rows": rows,
        "unsupported_or_failed": unsupported,
        "summary": {
            "graphs": len(rows),
            "unique_operator_targets": len(operator_targets),
            "call_function_invocations": sum(
                sum(row["operator_counts"].values()) for row in rows
            ),
            "roots": totals["roots"],
            "eligible_graphs": sum(row["tool_sites"] > 0 for row in rows),
            "eligible_tool_sites": totals["sites"],
            "historically_unsupported_or_failed": len(unsupported),
            "whole_graph_executions": totals["executions"],
            "transformed_whole_graph_executions": totals["executions"],
            "tool_direct_uses": totals["direct_uses"],
            "maximum_absolute_error": maximum_error,
        },
        "scientific_boundary": {
            "adapted_not_source_faithful_Babble_or_ISAMORE": True,
            "typed_anti_unification_constructed_one_reusable_tool": True,
            "real_selected_matches_replaced": True,
            "transformed_whole_graphs_executed": True,
            "not_hardware_selection": True,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "integration": {
            "A6_runtime_mount_component_ready": True,
            "A6_contract_batch_ready": False,
            "A6_production_integrated": False,
            "production_integrated_arms": 8,
            "required_arms": 10,
        },
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
