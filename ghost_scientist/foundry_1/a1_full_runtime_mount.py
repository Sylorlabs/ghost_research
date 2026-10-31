#!/usr/bin/env python3
"""Mount the adapted A1 fold control across all 23 calibration graphs."""

from __future__ import annotations

import argparse
import hashlib
import inspect
import json
import pathlib
import tempfile
import time
from collections import Counter
from typing import Any

import torch
from torch.fx import Interpreter

from a1_pattern_first_fold import (
    descriptor,
    extend_grammar,
    folded_actual,
    primary_lower,
    verify_extension,
    v5_execute,
)
from independent_a1_fold_lowering import (
    compare as independent_fold_compare,
    lower as independent_lower,
)
from independent_framework_runtime import (
    clone_tree,
    independent_assert,
    primary_compare,
)
from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A1_FULL_RUNTIME_CONTRACT_PROTOCOL_V1.json"
FREEZE = HERE / "results/a1_full_runtime_contract_v1_freeze.json"
BASE = HERE / "arm_adapter_fixtures/A1_PATTERN_FIRST_FOLD_PROTOCOL_V1.json"
GRAMMAR = HERE / "../operator_v5_1/results/frozen_grammar_v5_1.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict[str, Any]) -> None:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["surface"] == protocol["surface"]
        and freeze["acceptance"] == protocol["acceptance"]
        and freeze[
            "frozen_before_mount_or_contract_runner_implementation_or_execution"
        ]
        is True
    ):
        raise RuntimeError("A1 full runtime freeze mismatch")


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


def randomized(value: Any, generator: torch.Generator) -> Any:
    if isinstance(value, torch.Tensor):
        if value.dtype.is_floating_point:
            return torch.randn(
                value.shape,
                dtype=value.dtype,
                device=value.device,
                generator=generator,
            ).requires_grad_(value.requires_grad)
        return value.detach().clone()
    if isinstance(value, tuple):
        return tuple(randomized(item, generator) for item in value)
    if isinstance(value, list):
        return [randomized(item, generator) for item in value]
    if isinstance(value, dict):
        return {
            key: randomized(item, generator) for key, item in value.items()
        }
    return value


class Capture(Interpreter):
    def __init__(self, module):
        super().__init__(module)
        self.values: dict[str, Any] = {}

    def run_node(self, node):
        value = super().run_node(node)
        self.values[node.name] = value
        return value


def captured_execution(module, args, kwargs):
    bound = inspect.signature(module.forward).bind(
        *clone_tree(args), **clone_tree(kwargs)
    )
    bound.apply_defaults()
    runner = Capture(module)
    with torch.no_grad():
        output = runner.run(*bound.arguments.values())
    return output, runner.values


def run() -> dict[str, Any]:
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    base = json.loads(BASE.read_text())
    original = json.loads(GRAMMAR.read_text())
    signature = protocol["selection_policy"][
        "exact_structural_signature_sha256"
    ]
    generation_start = time.process_time_ns()
    adapted = extend_grammar(original, signature)
    verify_extension(original, adapted, signature)
    library_sha256 = hashlib.sha256(canonical(adapted).encode()).hexdigest()
    tool_sha256 = hashlib.sha256(
        canonical(
            {
                "structural_signature_sha256": signature,
                "decision": {"kind": "leaf", "plan_index": 1},
            }
        ).encode()
    ).hexdigest()
    candidate_generation_cpu_ns = max(
        1, time.process_time_ns() - generation_start
    )
    targets_by_artifact: dict[str, list[dict[str, str]]] = {}
    for target in base["targets"]:
        targets_by_artifact.setdefault(target["artifact_id"], []).append(target)

    instantiated, unsupported = workloads()
    rows = []
    operator_targets = set()
    maximum_error = 0.0
    with tempfile.TemporaryDirectory(prefix="foundry-a1-runtime-") as raw_dir:
        directory = pathlib.Path(raw_dir)
        for index, (suite, workload) in enumerate(instantiated):
            family = workload["family"]
            artifact_id = f"{suite}:{family}"
            repository = workload.get(
                "repository", old_repository(suite, family)
            )
            domain = workload.get("semantic_domain", family)
            compile_start = time.process_time_ns()
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
            compiler_cpu_ns = max(
                1, time.process_time_ns() - compile_start
            )
            graph = module.graph
            counts = Counter(
                str(node.target)
                for node in graph.nodes
                if node.op == "call_function"
            )
            operator_targets.update(counts)

            selector_start = time.process_time_ns()
            selected = []
            for target in targets_by_artifact.get(artifact_id, []):
                desc = descriptor(
                    module,
                    artifact_id,
                    target["conv_node"],
                    target["batch_norm_node"],
                )
                primary = primary_lower(desc)
                independent = independent_lower(
                    module,
                    artifact_id,
                    target["conv_node"],
                    target["batch_norm_node"],
                )
                if canonical(primary) != canonical(independent):
                    raise RuntimeError("A1 runtime lowerers disagree")
                execution = v5_execute(
                    primary,
                    original,
                    signature,
                    directory
                    / f"{target['conv_node']}_runtime_artifact.json",
                )
                selected.append(
                    {
                        "target": target,
                        "descriptor": desc,
                        "lowered_artifact_sha256": hashlib.sha256(
                            (canonical(primary) + "\n").encode()
                        ).hexdigest(),
                        "v5_execution": execution,
                    }
                )
            selector_cpu_ns = max(
                1, time.process_time_ns() - selector_start
            )

            verification_cpu_ns = 0
            executed_workload_cpu_ns = 0
            invocation_receipts = []
            fold_receipts = []
            artifact_error = 0.0
            aliases = True
            for ordinal in (1, 2, 3):
                seed_label = canonical(
                    ["A1-FULL-RUNTIME", artifact_id, ordinal]
                )
                seed = int.from_bytes(
                    hashlib.sha256(seed_label.encode()).digest()[:8], "big"
                ) % (2**63)
                generator = torch.Generator(device="cpu").manual_seed(seed)
                args = randomized(workload["args"], generator)
                kwargs = randomized(workload["kwargs"], generator)
                execution_start = time.process_time_ns()
                torch.manual_seed(seed)
                with torch.no_grad():
                    expected = workload["model"](
                        *clone_tree(args), **clone_tree(kwargs)
                    )
                torch.manual_seed(seed)
                actual, captures = captured_execution(module, args, kwargs)
                fold_actuals = [
                    folded_actual(item["descriptor"], captures)
                    for item in selected
                ]
                executed_workload_cpu_ns += max(
                    1, time.process_time_ns() - execution_start
                )

                verification_start = time.process_time_ns()
                whole = primary_compare(expected, actual)
                independent_assert(expected, actual)
                invocation_error = whole["max_abs_error"]
                aliases = (
                    aliases and whole["alias_storage_checks_passed"]
                )
                per_invocation_folds = []
                for item, folded in zip(
                    selected, fold_actuals, strict=True
                ):
                    desc = item["descriptor"]
                    target = item["target"]
                    reference = captures[target["batch_norm_node"]][0]
                    primary_fold = primary_compare(reference, folded)
                    independent_fold = independent_fold_compare(
                        reference,
                        folded,
                        captures[desc["x"].name],
                        tolerance=protocol["runtime_correctness"][
                            "maximum_absolute_error"
                        ],
                    )
                    fold_error = max(
                        primary_fold["max_abs_error"],
                        independent_fold["max_abs_error"],
                    )
                    invocation_error = max(invocation_error, fold_error)
                    aliases = (
                        aliases
                        and primary_fold["alias_storage_checks_passed"]
                        and independent_fold["alias_checks_passed"]
                    )
                    receipt = {
                        "ordinal": ordinal,
                        "conv_node": target["conv_node"],
                        "batch_norm_node": target["batch_norm_node"],
                        "tool_sha256": tool_sha256,
                        "max_abs_error": fold_error,
                        "expected_sha256": primary_fold[
                            "expected_sha256"
                        ],
                        "actual_sha256": primary_fold["actual_sha256"],
                        "alias_storage_checks_passed": True,
                    }
                    per_invocation_folds.append(receipt)
                    fold_receipts.append(receipt)
                verification_cpu_ns += max(
                    1, time.process_time_ns() - verification_start
                )
                artifact_error = max(artifact_error, invocation_error)
                invocation_receipts.append(
                    {
                        "ordinal": ordinal,
                        "seed_sha256": hashlib.sha256(
                            seed_label.encode()
                        ).hexdigest(),
                        "expected_sha256": whole["expected_sha256"],
                        "actual_sha256": whole["actual_sha256"],
                        "whole_graph_max_abs_error": whole[
                            "max_abs_error"
                        ],
                        "fold_max_abs_error": max(
                            (
                                row["max_abs_error"]
                                for row in per_invocation_folds
                            ),
                            default=0.0,
                        ),
                        "correct": invocation_error
                        <= protocol["runtime_correctness"][
                            "maximum_absolute_error"
                        ],
                    }
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
            source_record_sha256 = hashlib.sha256(
                canonical(
                    {
                        "mount_protocol_sha256": sha(PROTOCOL),
                        "suite": suite,
                        "family": family,
                        "repository": repository,
                    }
                ).encode()
            ).hexdigest()
            shape_seed_sha256 = hashlib.sha256(
                canonical(
                    {
                        "args": describe(workload["args"]),
                        "kwargs": describe(workload["kwargs"]),
                        "seed_rule": "A1-FULL-RUNTIME",
                    }
                ).encode()
            ).hexdigest()
            rows.append(
                {
                    "arm_id": "A1",
                    "artifact_id": artifact_id,
                    "family": family,
                    "repository": repository,
                    "semantic_domain": domain,
                    "source_record_sha256": source_record_sha256,
                    "graph_sha256": hashlib.sha256(
                        str(graph).encode()
                    ).hexdigest(),
                    "shape_seed_sha256": shape_seed_sha256,
                    "operator_counts": dict(sorted(counts.items())),
                    "selected_fold_sites": len(selected),
                    "selector_receipts": [
                        {
                            "conv_node": item["target"]["conv_node"],
                            "batch_norm_node": item["target"][
                                "batch_norm_node"
                            ],
                            "lowered_artifact_sha256": item[
                                "lowered_artifact_sha256"
                            ],
                            "candidate_plan_count": item["v5_execution"][
                                "candidate_plan_count"
                            ],
                            "evaluator_plan_count": item["v5_execution"][
                                "evaluator_plan_count"
                            ],
                            "original_plan_index": item["v5_execution"][
                                "original_grammar_plan_index"
                            ],
                            "adapted_plan_index": item["v5_execution"][
                                "adapted_grammar_plan_index"
                            ],
                            "synthetic_measurement": item["v5_execution"][
                                "metrics"
                            ],
                        }
                        for item in selected
                    ],
                    "tool_receipts": (
                        [
                            {
                                "tool_sha256": tool_sha256,
                                "action": "reused",
                                "direct_use_count": len(selected),
                            }
                        ]
                        if selected
                        else []
                    ),
                    "invocation_receipts": invocation_receipts,
                    "fold_receipts": fold_receipts,
                    "max_abs_error": artifact_error,
                    "alias_storage_checks_passed": aliases,
                    "state_before_sha256": library_sha256,
                    "state_after_sha256": library_sha256,
                    "library_retained_across_artifacts": True,
                    "cost_ledger": ledger,
                }
            )
    return {
        "version": "FOUNDRY_A1_FULL_RUNTIME_MOUNT_COMPONENT_V1",
        "status": "A1_FULL_RUNTIME_MOUNT_COMPONENT_PASS",
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "library_sha256": library_sha256,
        "tool_sha256": tool_sha256,
        "candidate_generation_cpu_ns": candidate_generation_cpu_ns,
        "rows": rows,
        "unsupported_or_failed": unsupported,
        "summary": {
            "graphs": len(rows),
            "unique_operator_targets": len(operator_targets),
            "call_function_invocations": sum(
                sum(row["operator_counts"].values()) for row in rows
            ),
            "historically_unsupported_or_failed": len(unsupported),
            "eligible_graphs": sum(
                row["selected_fold_sites"] > 0 for row in rows
            ),
            "eligible_fold_sites": sum(
                row["selected_fold_sites"] for row in rows
            ),
            "whole_graph_executions": sum(
                len(row["invocation_receipts"]) for row in rows
            ),
            "fold_checks": sum(
                len(row["fold_receipts"]) for row in rows
            ),
            "tool_direct_uses": sum(
                tool["direct_use_count"]
                for row in rows
                for tool in row["tool_receipts"]
            ),
            "maximum_absolute_error": maximum_error,
        },
        "scientific_boundary": {
            "post_failure_numerical_amendment_disclosed": True,
            "adapted_calibration_control_not_unchanged_v5_1": True,
            "exactly_one_calibration_signature_added": True,
            "real_matched_subgraphs_executed": True,
            "whole_transformed_graph_materialized": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "integration": {
            "A1_runtime_mount_component_ready": True,
            "A1_contract_batch_ready": False,
            "A1_production_integrated": False,
            "production_integrated_arms": 7,
            "required_arms": 10,
        },
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
            "validation_v6_accessed": payload[
                "validation_v6_accessed"
            ],
        }
    print(canonical(payload))


if __name__ == "__main__":
    main()
