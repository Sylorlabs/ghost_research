#!/usr/bin/env python3
"""Audit frozen A1 IR compatibility against all calibration graphs."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib

from independent_a1_ir_audit import (
    classify_graph as independent_classify,
    runtime_ops as independent_runtime_ops,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A1_IR_COMPATIBILITY_PROTOCOL_V1.json"
RESULT = HERE / "results/phase93_a1_ir_compatibility_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def primary_runtime_ops(source: str) -> set[str]:
    tree = ast.parse(source)
    target = next(
        node
        for node in tree.body
        if isinstance(node, ast.FunctionDef)
        and node.name == "infer_runtime_program"
    )
    result = set()
    for node in ast.walk(target):
        if not isinstance(node, ast.Compare):
            continue
        if not (
            isinstance(node.left, ast.Name)
            and node.left.id == "op"
            and len(node.ops) == len(node.comparators) == 1
        ):
            continue
        comparator = node.comparators[0]
        if isinstance(node.ops[0], ast.Eq) and isinstance(
            comparator, ast.Constant
        ):
            if isinstance(comparator.value, str):
                result.add(comparator.value)
        elif isinstance(node.ops[0], ast.In) and isinstance(
            comparator, (ast.Tuple, ast.List)
        ):
            for item in comparator.elts:
                if isinstance(item, ast.Constant) and isinstance(
                    item.value, str
                ):
                    result.add(item.value)
    return result


def classify(
    operator_counts: dict[str, int],
    mapping: dict[str, list[object]],
) -> dict:
    direct = conditional = unsupported = 0
    histogram: dict[str, int] = {}
    for operator, count in sorted(operator_counts.items()):
        classification, runtime_op = mapping[operator]
        if classification == "DIRECT_EXACT":
            direct += count
            histogram[runtime_op] = histogram.get(runtime_op, 0) + count
        elif classification == "CONDITIONAL_COMPOSITE":
            conditional += count
        elif classification == "UNSUPPORTED":
            unsupported += count
        else:
            raise ValueError("unknown mapping classification")
    return {
        "classification_counts": {
            "DIRECT_EXACT": direct,
            "CONDITIONAL_COMPOSITE": conditional,
            "UNSUPPORTED": unsupported,
        },
        "mapped_direct_runtime_histogram": dict(sorted(histogram.items())),
        "whole_graph_direct": conditional == 0 and unsupported == 0,
        "whole_graph_has_no_unsupported": unsupported == 0,
    }


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider hash mismatch: {row['path']}")
    core_source = (HERE / "../operator_v5/ghost_operator_core_v5.py").read_text()
    primary_ops = primary_runtime_ops(core_source)
    independent_ops = independent_runtime_ops(core_source)
    mount = json.loads(
        (
            HERE / "results/phase89_framework_runtime_mount_conformance.json"
        ).read_text()
    )
    graph_rows = mount["arms"]["A3"]["rows"]
    mapping = protocol["operator_mapping"]
    observed = {
        operator
        for row in graph_rows
        for operator in row["operator_counts"]
    }
    rows = []
    aggregate = {"DIRECT_EXACT": 0, "CONDITIONAL_COMPOSITE": 0, "UNSUPPORTED": 0}
    for graph in graph_rows:
        primary = classify(graph["operator_counts"], mapping)
        independent = independent_classify(graph["operator_counts"], mapping)
        if primary != independent:
            raise RuntimeError(
                f"classifiers disagree: {graph['artifact_id']}"
            )
        for key, value in primary["classification_counts"].items():
            aggregate[key] += value
        exact_patterns = [
            name
            for name, histogram in protocol[
                "constructor_pattern_runtime_histograms"
            ].items()
            if primary["whole_graph_direct"]
            and primary["mapped_direct_runtime_histogram"] == histogram
        ]
        rows.append(
            {
                "artifact_id": graph["artifact_id"],
                "source_record_sha256": graph["source_record_sha256"],
                "graph_sha256": graph["graph_sha256"],
                "operator_counts": graph["operator_counts"],
                **primary,
                "exact_constructor_pattern_candidates": exact_patterns,
            }
        )
    whole_direct = sum(row["whole_graph_direct"] for row in rows)
    no_unsupported = sum(row["whole_graph_has_no_unsupported"] for row in rows)
    pattern_candidates = sum(
        bool(row["exact_constructor_pattern_candidates"]) for row in rows
    )
    checks = {
        "protocol_prefrozen": protocol["frozen_before_audit_execution"],
        "provider_hashes_authentic": True,
        "primary_independent_runtime_ops_agree": primary_ops
        == independent_ops,
        "runtime_vocabulary_nonempty": len(primary_ops) == 22,
        "mapping_exactly_covers_observed_41": set(mapping) == observed
        and len(observed) == 41,
        "all_direct_targets_exist_in_A1_runtime": all(
            classification != "DIRECT_EXACT" or runtime_op in primary_ops
            for classification, runtime_op in mapping.values()
        ),
        "surface_exact_23_41_337": (
            len(rows) == 23
            and len(observed) == 41
            and sum(aggregate.values()) == 337
        ),
        "primary_independent_graph_classifiers_agree": True,
        "A1_not_promoted_by_audit": protocol["claim_boundary"][
            "A1_may_be_promoted_by_compatibility_audit_alone"
        ]
        is False,
        "integration_truth_remains_4": protocol["claim_boundary"][
            "production_integrated_arms_after_audit"
        ]
        == 4,
        "validation_v6_unread": protocol["claim_boundary"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "prospective_unauthorized": protocol["claim_boundary"][
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A1 IR compatibility audit failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ],
                    "runtime_ops": sorted(primary_ops),
                }
            )
        )
    production_ready = (
        whole_direct == 23
        and pattern_candidates > 0
        and aggregate["UNSUPPORTED"] == 0
        and aggregate["CONDITIONAL_COMPOSITE"] == 0
    )
    payload = {
        "version": "FOUNDRY_A1_IR_COMPATIBILITY_AUDIT_V1",
        "status": (
            "A1_DIRECT_ADAPTER_READY"
            if production_ready
            else "A1_DIRECT_ADAPTER_REJECTED_INCOMPLETE_IR_SURFACE"
        ),
        "checks": checks,
        "A1_runtime_ops": sorted(primary_ops),
        "mapping_counts": {
            classification: sum(
                1
                for value in mapping.values()
                if value[0] == classification
            )
            for classification in (
                "DIRECT_EXACT",
                "CONDITIONAL_COMPOSITE",
                "UNSUPPORTED",
            )
        },
        "invocation_counts": aggregate,
        "summary": {
            "graphs": len(rows),
            "unique_operator_targets": len(observed),
            "call_function_invocations": sum(aggregate.values()),
            "whole_graph_direct": whole_direct,
            "whole_graph_without_unsupported": no_unsupported,
            "exact_constructor_pattern_candidates": pattern_candidates,
            "production_adapter_ready": production_ready,
        },
        "graphs": rows,
        "decision": {
            "direct_wrapper_allowed": production_ready,
            "required_bridge": (
                "EVALUATOR_OWNED_ATEN_TO_OPERATOR_V5_TYPED_IR_LOWERING"
            ),
            "bridge_must_preserve": [
                "all output values, types, layouts, and alias relations",
                "v5.1 structural signatures and conditional grammar decisions",
                "reference-plan fallback for unrecognized signatures",
                "complete CPU and process-tree accounting",
            ],
            "bridge_must_falsify": [
                "conditional composite argument and adjacency requirements",
                "unsupported operator rejection",
                "at least one nonreference A1 construction on calibration",
            ],
        },
        "integration": {
            "A1": "COMPATIBILITY_AUDITED_NOT_ADAPTED",
            "production_integrated_arms": 4,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE93_A1_IR_COMPATIBILITY"
        f" status={payload['status']}"
        f" runtime_ops={len(primary_ops)}"
        f" mapped_targets={payload['mapping_counts']['DIRECT_EXACT']}/41"
        f" direct_calls={aggregate['DIRECT_EXACT']}/337"
        f" whole_graphs={whole_direct}/23"
        f" patterns={pattern_candidates}"
        " integrated=4/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
