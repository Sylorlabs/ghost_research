#!/usr/bin/env python3
"""Mount the frozen adapted Enumo tensor-rule library on calibration graphs."""

from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import pathlib
import time
from collections import Counter

import torch

from independent_a7_real_graph_islands import extract as independent_extract
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads
from phase140_a7_enumo_real_graph_transfer import (
    Capture,
    concrete_leaves,
    evaluate,
    primary_extract,
    selected_rewrites,
    serialize,
)
from enumo_tensor_rule_verifier import parse_rule


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A7_ENUMO_RUNTIME_MOUNT_PROTOCOL_V1.json"
FREEZE = HERE / "results/a7_enumo_runtime_mount_v1_freeze.json"
FEASIBILITY = HERE / "results/phase132_enumo_tensor_domain_feasibility.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["expected"] == protocol["expected"]
        and freeze["frozen_before_mount_implementation_or_execution"] is True
    ):
        raise RuntimeError("A7 runtime mount freeze mismatch")


def describe(value):
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


def captured_execution(module, args, kwargs):
    signature = inspect.signature(module.forward)
    bound = signature.bind(*clone_tree(args), **clone_tree(kwargs))
    bound.apply_defaults()
    runner = Capture(module)
    with torch.no_grad():
        output = runner.run(*bound.arguments.values())
    return output, runner.values


def run() -> dict:
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    feasibility = json.loads(FEASIBILITY.read_text())
    learned_raw = feasibility["observed"]["learned_rules"]
    learned = [parse_rule(rule) for rule in learned_raw]
    library_sha256 = hashlib.sha256(canonical(learned_raw).encode()).hexdigest()
    historic_receipts = feasibility["receipts"]
    candidate_generation_cpu_ns = sum(
        historic_receipts[stage]["rusage_user_cpu_ns"]
        + historic_receipts[stage]["rusage_system_cpu_ns"]
        for stage in ("build", "run")
    )

    instantiated, unsupported = workloads()
    rows = []
    totals: Counter[str] = Counter()
    maximum_error = 0.0
    operator_targets = set()
    selected_semantics = set()
    for index, (suite, workload) in enumerate(instantiated):
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        domain = workload.get("semantic_domain", family)
        artifact_id = f"{suite}:{family}"

        compile_start = time.process_time_ns()
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        module = exported.module()
        compiler_cpu_ns = time.process_time_ns() - compile_start
        graph = module.graph
        counts = Counter(
            str(node.target)
            for node in graph.nodes
            if node.op == "call_function"
        )
        operator_targets.update(counts)

        verification_start = time.process_time_ns()
        primary, sources = primary_extract(graph)
        independent = independent_extract(graph)
        projection = [
            {key: row[key] for key in ("root_node", "target", "expression")}
            for row in primary
        ]
        if projection != independent:
            raise RuntimeError(f"A7 extractors disagree: {artifact_id}")
        verification_cpu_ns = time.process_time_ns() - verification_start

        selector_start = time.process_time_ns()
        raw_matches = 0
        raw_selected = []
        tool_counts: Counter[int] = Counter()
        for island in primary:
            matches, selected = selected_rewrites(island["term"], learned)
            raw_matches += matches
            for rule_index, candidate in selected:
                raw_selected.append(
                    {
                        "root_node": island["root_node"],
                        "rule_index": rule_index,
                        "candidate": candidate,
                        "candidate_serialization": serialize(candidate),
                    }
                )
                tool_counts[rule_index] += 1
                selected_semantics.add(learned_raw[rule_index])
        unique = {}
        for selected in raw_selected:
            key = (
                selected["root_node"],
                selected["candidate_serialization"],
            )
            record = unique.setdefault(
                key,
                {
                    "root_node": selected["root_node"],
                    "candidate": selected["candidate"],
                    "candidate_serialization": selected[
                        "candidate_serialization"
                    ],
                    "rule_indices": [],
                },
            )
            record["rule_indices"].append(selected["rule_index"])
        unique_selected = list(unique.values())
        selector_cpu_ns = time.process_time_ns() - selector_start

        invocation_receipts = []
        rewrite_receipts = []
        artifact_error = 0.0
        aliases = True
        executed_workload_cpu_ns = 0
        for ordinal in (1, 2, 3):
            seed = int.from_bytes(
                hashlib.sha256(
                    f"A7-MOUNT:{artifact_id}:{ordinal}".encode()
                ).digest()[:8],
                "big",
            ) % (2**31)
            execution_start = time.process_time_ns()
            torch.manual_seed(seed)
            with torch.no_grad():
                expected = workload["model"](
                    *clone_tree(workload["args"]),
                    **clone_tree(workload["kwargs"]),
                )
            torch.manual_seed(seed)
            actual, captures = captured_execution(
                module, workload["args"], workload["kwargs"]
            )
            executed_workload_cpu_ns += (
                time.process_time_ns() - execution_start
            )

            comparison_start = time.process_time_ns()
            whole = primary_compare(expected, actual)
            independent_assert(expected, actual)
            artifact_error = max(artifact_error, whole["max_abs_error"])
            aliases = aliases and whole["alias_storage_checks_passed"]
            invocation_receipts.append(
                {
                    "ordinal": ordinal,
                    "seed": seed,
                    "expected_sha256": whole["expected_sha256"],
                    "actual_sha256": whole["actual_sha256"],
                    "max_abs_error": whole["max_abs_error"],
                    "correct": whole["max_abs_error"] <= 1.0e-5,
                }
            )
            leaves = concrete_leaves(sources, captures)
            for selected in unique_selected:
                root = captures[selected["root_node"]]
                rewritten = evaluate(selected["candidate"], leaves)
                check = primary_compare(root, rewritten)
                independent_assert(root, rewritten)
                artifact_error = max(
                    artifact_error, check["max_abs_error"]
                )
                aliases = aliases and check[
                    "alias_storage_checks_passed"
                ]
                rewrite_receipts.append(
                    {
                        "root_node": selected["root_node"],
                        "candidate": selected["candidate_serialization"],
                        "rule_indices": selected["rule_indices"],
                        "ordinal": ordinal,
                        "max_abs_error": check["max_abs_error"],
                        "expected_sha256": check["expected_sha256"],
                        "actual_sha256": check["actual_sha256"],
                        "alias_storage_checks_passed": check[
                            "alias_storage_checks_passed"
                        ],
                    }
                )
            verification_cpu_ns += (
                time.process_time_ns() - comparison_start
            )
        maximum_error = max(maximum_error, artifact_error)
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
        tool_receipts = [
            {
                "tool_sha256": hashlib.sha256(
                    learned_raw[rule_index].encode()
                ).hexdigest(),
                "action": "reused",
                "direct_use_count": count,
                "rule_index": rule_index,
            }
            for rule_index, count in sorted(tool_counts.items())
        ]
        rows.append(
            {
                "arm_id": "A7",
                "artifact_id": artifact_id,
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "source_record_sha256": source_sha256,
                "graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "shape_seed_sha256": shape_seed_sha256,
                "operator_counts": dict(sorted(counts.items())),
                "eligible_roots": len(primary),
                "island_sha256": hashlib.sha256(
                    canonical(projection).encode()
                ).hexdigest(),
                "learned_root_matches": raw_matches,
                "raw_selected_rule_applications": len(raw_selected),
                "unique_selected_transformations": len(unique_selected),
                "tool_receipts": tool_receipts,
                "invocation_receipts": invocation_receipts,
                "rewrite_receipts": rewrite_receipts,
                "max_abs_error": artifact_error,
                "alias_storage_checks_passed": aliases,
                "state_before_sha256": library_sha256,
                "state_after_sha256": library_sha256,
                "library_retained_across_artifacts": True,
                "cost_ledger": ledger,
            }
        )
        totals["eligible_calls"] += len(primary)
        totals["root_matches"] += raw_matches
        totals["raw_selected"] += len(raw_selected)
        totals["unique_selected"] += len(unique_selected)
        totals["whole_graph_executions"] += len(invocation_receipts)
        totals["rewrite_checks"] += len(rewrite_receipts)
        totals["tool_direct_uses"] += sum(tool_counts.values())

    return {
        "version": "FOUNDRY_A7_ENUMO_RUNTIME_MOUNT_COMPONENT_V1",
        "status": "A7_ENUMO_RUNTIME_MOUNT_COMPONENT_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "library_sha256": library_sha256,
        "candidate_generation_receipt_sha256": hashlib.sha256(
            canonical(historic_receipts).encode()
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
            "eligible_graphs": sum(row["eligible_roots"] > 0 for row in rows),
            "eligible_calls": totals["eligible_calls"],
            "historically_unsupported_or_failed": len(unsupported),
            "learned_rules": len(learned),
            "learned_root_matches": totals["root_matches"],
            "raw_selected_rule_applications": totals["raw_selected"],
            "unique_selected_transformations": totals["unique_selected"],
            "whole_graph_executions": totals["whole_graph_executions"],
            "unique_rewrite_concrete_checks": totals["rewrite_checks"],
            "tool_direct_uses": totals["tool_direct_uses"],
            "maximum_absolute_error": maximum_error,
            "selected_rule_semantics": sorted(selected_semantics),
        },
        "scientific_boundary": {
            "adapted_evaluator_authored_tensor_domain": True,
            "equal_cost_operand_canonicalization_only": True,
            "strict_atom_cost_reductions": 0,
            "rewritten_whole_tensor_graph_executed": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
            "universal_floating_point_theorem": False,
        },
        "integration": {
            "A7_runtime_mount_component_ready": True,
            "A7_contract_batch_ready": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    payload = run()
    if args.summary_only:
        payload = {
            "version": payload["version"],
            "status": payload["status"],
            "protocol_sha256": payload["protocol_sha256"],
            "library_sha256": payload["library_sha256"],
            "summary": payload["summary"],
            "integration": payload["integration"],
            "validation_v6_accessed": payload["validation_v6_accessed"],
        }
    print(canonical(payload))


if __name__ == "__main__":
    main()
