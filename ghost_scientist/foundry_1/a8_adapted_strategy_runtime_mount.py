#!/usr/bin/env python3
"""Execute the frozen adapted A8 strategy as whole-graph replacements."""

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

from a8_adapted_strategy_search import canonical, enumerate_matches, evaluate
from independent_a8_adapted_strategy_search import (
    discover,
    score as independent_score,
)
from independent_a8_strategy_runtime import audit as independent_audit
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A8_ADAPTED_STRATEGY_RUNTIME_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a8_adapted_strategy_runtime_v1_freeze.json"
REACHABILITY = (
    HERE / "results/phase152_a8_adapted_strategy_reachability.json"
)
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"

_A8_EXECUTIONS = 0
TARGETS = {
    "aten.conv2d.default": torch.ops.aten.conv2d.default,
    "aten.relu.default": torch.ops.aten.relu.default,
    "aten.view.default": torch.ops.aten.view.default,
    "aten.linear.default": torch.ops.aten.linear.default,
    "aten.mm.default": torch.ops.aten.mm.default,
    "aten.addmm.default": torch.ops.aten.addmm.default,
}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def reset_counter() -> None:
    global _A8_EXECUTIONS
    _A8_EXECUTIONS = 0


def execution_count() -> int:
    return _A8_EXECUTIONS


def _resolve(
    spec: tuple[Any, ...],
    external: tuple[Any, ...],
    local: list[Any],
) -> Any:
    kind = spec[0]
    if kind == "input":
        return external[spec[1]]
    if kind == "node":
        return local[spec[1]]
    if kind == "literal":
        return spec[1]
    if kind == "tuple":
        return tuple(_resolve(item, external, local) for item in spec[1])
    if kind == "list":
        return [_resolve(item, external, local) for item in spec[1]]
    if kind == "dict":
        return {
            key: _resolve(value, external, local)
            for key, value in spec[1]
        }
    raise RuntimeError("unknown A8 recipe value")


def a8_strategy_tool_executor(
    recipe: tuple[Any, ...], *external: Any
) -> Any:
    global _A8_EXECUTIONS
    _A8_EXECUTIONS += 1
    local = []
    for target, args_spec, kwargs_spec in recipe:
        args = _resolve(args_spec, external, local)
        kwargs = _resolve(kwargs_spec, external, local)
        local.append(TARGETS[target](*args, **kwargs))
    return local[-1]


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


def authenticate(
    protocol: dict[str, Any],
) -> tuple[dict[str, Any], dict[str, Any]]:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"A8 provider mismatch: {row['path']}")
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["selected_strategy"] == protocol["selected_strategy"]
        and freeze["surface"] == protocol["surface"]
        and freeze["runtime_policy"] == protocol["runtime_policy"]
        and freeze["acceptance"] == protocol["acceptance"]
        and freeze["pristine_preregistration"] is False
    ):
        raise RuntimeError("A8 runtime freeze mismatch")
    reachability = json.loads(REACHABILITY.read_text())
    observed = reachability["observed"]
    selected = observed["selected"]
    expected = protocol["selected_strategy"]
    if not (
        reachability["status"] == "A8_ADAPTED_STRATEGY_REACHABILITY_POSITIVE"
        and observed["selected_eqsatl_sha256"] == expected["eqsatl_sha256"]
        and observed["repository"]["complete_score_table_sha256"]
        == expected["complete_score_table_sha256"]
        and selected["order"] == expected["order"]
        and selected["unique_covered_nodes"] == expected["covered_nodes"]
        and selected["eligible_artifacts"] == expected["eligible_artifacts"]
        and selected["direct_uses"] == expected["strategy_applications"]
        and selected["conflict_skips"] == expected["conflict_skips"]
    ):
        raise RuntimeError("A8 selected strategy mismatch")
    return selected, reachability


def encode_recipe(
    path: list[Node],
) -> tuple[tuple[Any, ...], list[Any]]:
    local_index = {node: index for index, node in enumerate(path)}
    external_index: dict[Node, int] = {}
    external: list[Any] = []

    def encode(value: Any) -> tuple[Any, ...]:
        if isinstance(value, Node):
            if value in local_index:
                return ("node", local_index[value])
            if value not in external_index:
                external_index[value] = len(external)
                external.append(value)
            return ("input", external_index[value])
        if isinstance(value, tuple):
            return ("tuple", tuple(encode(item) for item in value))
        if isinstance(value, list):
            return ("list", tuple(encode(item) for item in value))
        if isinstance(value, dict):
            return (
                "dict",
                tuple(
                    (str(key), encode(value[key]))
                    for key in sorted(value, key=str)
                ),
            )
        return ("literal", value)

    recipe = tuple(
        (
            str(node.target),
            encode(tuple(node.args)),
            encode(dict(node.kwargs)),
        )
        for node in path
    )
    return recipe, external


def rewrite(
    module: GraphModule,
    decisions: list[dict[str, Any]],
    portfolio: dict[str, Any],
) -> tuple[GraphModule, dict[str, Any]]:
    transformed = copy.deepcopy(module)
    receipts = []
    for decision in decisions:
        by_name = {node.name: node for node in transformed.graph.nodes}
        path = [by_name[name] for name in decision["nodes"]]
        recipe, external = encode_recipe(path)
        with transformed.graph.inserting_before(path[-1]):
            replacement = transformed.graph.call_function(
                a8_strategy_tool_executor,
                args=(recipe, *external),
            )
            replacement.meta = dict(path[-1].meta)
        path[-1].replace_all_uses_with(replacement)
        for node in reversed(path):
            if not node.users:
                transformed.graph.erase_node(node)
        receipts.append(
            {
                "tool": decision["tool"],
                "nodes": decision["nodes"],
                "recipe_targets": [row[0] for row in recipe],
                "external_inputs": len(external),
                "executor_node": replacement.name,
            }
        )
    transformed.graph.lint()
    transformed.recompile()
    audit = independent_audit(
        transformed, a8_strategy_tool_executor, decisions, portfolio
    )
    return transformed, {"recipes": receipts, "independent_audit": audit}


def run() -> dict[str, Any]:
    protocol = json.loads(PROTOCOL.read_text())
    selected, reachability = authenticate(protocol)
    portfolio = json.loads(FIXED.read_text())
    order = tuple(selected["order"])
    strategy_sha256 = reachability["observed"]["selected_eqsatl_sha256"]
    historic_receipt = reachability["receipt"]
    candidate_generation_cpu_ns = (
        historic_receipt["rusage_user_cpu_ns"]
        + historic_receipt["rusage_system_cpu_ns"]
    )
    frozen_by_artifact: dict[str, list[dict[str, Any]]] = {}
    for row in selected["selected"]:
        frozen_by_artifact.setdefault(row["artifact_id"], []).append(row)
    instantiated, unsupported = workloads()
    rows = []
    totals: Counter[str] = Counter()
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
        module = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        ).module()
        compiler_cpu_ns = time.process_time_ns() - compiler_start
        graph = module.graph
        counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_targets.update(counts)

        selector_start = time.process_time_ns()
        primary_matches = enumerate_matches(graph, portfolio)
        independent_matches = discover(graph, portfolio)
        if primary_matches != independent_matches:
            raise RuntimeError(f"A8 runtime matchers disagree: {artifact_id}")
        primary_decision = evaluate(
            order, [(artifact_id, primary_matches)]
        )["selected"]
        independent_decision = independent_score(
            order, [(artifact_id, independent_matches)]
        )["selected"]
        frozen = frozen_by_artifact.get(artifact_id, [])
        if primary_decision != independent_decision or primary_decision != frozen:
            raise RuntimeError(f"A8 frozen strategy changed: {artifact_id}")
        transformed, transform_receipt = rewrite(
            module, frozen, portfolio
        )
        selector_cpu_ns = time.process_time_ns() - selector_start

        invocation_receipts = []
        artifact_error = 0.0
        aliases = True
        executed_workload_cpu_ns = 0
        verification_cpu_ns = 0
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A8-MOUNT:{artifact_id}:{ordinal}".encode()
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
            reset_counter()
            with torch.no_grad():
                actual_output = transformed(
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            calls = execution_count()
            executed_workload_cpu_ns += (
                time.process_time_ns() - execution_start
            )
            if calls != len(frozen):
                raise RuntimeError(f"A8 execution count mismatch: {artifact_id}")
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
                    "strategy_tool_executions": calls,
                }
            )
        ledger = {
            "candidate_generation_cpu_ns": (
                candidate_generation_cpu_ns if index == 0 else 0
            ),
            "verification_cpu_ns": max(1, verification_cpu_ns),
            "compiler_cpu_ns": compiler_cpu_ns,
            "selector_cpu_ns": max(1, selector_cpu_ns),
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
        rows.append(
            {
                "arm_id": "A8",
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
                "selected_decisions": frozen,
                "strategy_applications": len(frozen),
                "covered_nodes": sum(len(item["nodes"]) for item in frozen),
                "transform_receipt": transform_receipt,
                "tool_receipts": (
                    [
                        {
                            "tool_sha256": strategy_sha256,
                            "action": "reused",
                            "direct_use_count": len(frozen) * 3,
                        }
                    ]
                    if frozen
                    else []
                ),
                "invocation_receipts": invocation_receipts,
                "max_abs_error": artifact_error,
                "alias_storage_checks_passed": aliases,
                "state_before_sha256": strategy_sha256,
                "state_after_sha256": strategy_sha256,
                "library_retained_across_artifacts": True,
                "cost_ledger": ledger,
            }
        )
        maximum_error = max(maximum_error, artifact_error)
        totals["applications"] += len(frozen)
        totals["covered_nodes"] += sum(
            len(item["nodes"]) for item in frozen
        )
        totals["executions"] += len(invocation_receipts)
        totals["direct_uses"] += len(frozen) * len(invocation_receipts)

    return {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_RUNTIME_MOUNT_V1",
        "status": "A8_ADAPTED_STRATEGY_RUNTIME_MOUNT_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "library_sha256": strategy_sha256,
        "candidate_generation_cpu_ns": candidate_generation_cpu_ns,
        "rows": rows,
        "unsupported_or_failed": unsupported,
        "summary": {
            "graphs": len(rows),
            "unique_operator_targets": len(operator_targets),
            "call_function_invocations": sum(
                sum(row["operator_counts"].values()) for row in rows
            ),
            "eligible_graphs": sum(
                row["strategy_applications"] > 0 for row in rows
            ),
            "eligible_strategy_applications": totals["applications"],
            "covered_graph_nodes": totals["covered_nodes"],
            "historically_unsupported_or_failed": len(unsupported),
            "whole_graph_executions": totals["executions"],
            "strategy_tool_direct_uses": totals["direct_uses"],
            "maximum_absolute_error": maximum_error,
        },
        "scientific_boundary": {
            "new_adapted_control_not_EggMind": True,
            "post_exploratory_not_pristine": True,
            "unchanged_strong_fixed_tool_grammar": True,
            "strategy_order_beats_supplied_order_on_applications_only": True,
            "fixed_tool_portfolio_beaten": False,
            "real_selected_paths_replaced": True,
            "strategy_transformed_whole_graphs_executed": True,
            "new_tool_constructed": False,
            "heldout_generalization_measured": False,
        },
        "integration": {
            "A8_runtime_mount_component_ready": True,
            "A8_contract_batch_ready": False,
            "A8_production_integrated": False,
            "production_integrated_arms": 9,
            "required_arms": 10,
        },
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
