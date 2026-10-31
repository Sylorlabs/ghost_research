#!/usr/bin/env python3
"""Audit bounded-interpreter coverage over all real calibration operators."""

from __future__ import annotations

import json
import pathlib
from collections import Counter, defaultdict

import torch

from phase63_pareto_motif_calibration import workloads


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/CALIBRATION_OPERATOR_VOCAB_PROTOCOL_V1.json"
)
RESULT = HERE / "results/phase87_calibration_operator_vocabulary_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    instantiated, unsupported = workloads()
    counts: Counter[str] = Counter()
    graphs_by_operator: dict[str, set[str]] = defaultdict(set)
    families_by_operator: dict[str, set[str]] = defaultdict(set)
    repositories_by_operator: dict[str, set[str]] = defaultdict(set)
    domains_by_operator: dict[str, set[str]] = defaultdict(set)
    graph_rows = []
    failures = list(unsupported)
    for suite, workload in instantiated:
        graph_id = f"{suite}:{workload['family']}"
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
        except Exception as exc:
            failures.append(
                {
                    "suite": suite,
                    "family": workload["family"],
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        graph_counts: Counter[str] = Counter()
        for node in exported.module().graph.nodes:
            if node.op != "call_function":
                continue
            operator = str(node.target)
            counts[operator] += 1
            graph_counts[operator] += 1
            graphs_by_operator[operator].add(graph_id)
            families_by_operator[operator].add(workload["family"])
            repositories_by_operator[operator].add(
                workload.get("repository", "pytorch/examples")
            )
            domains_by_operator[operator].add(
                workload.get("semantic_domain", workload["family"])
            )
        graph_rows.append(
            {
                "graph_id": graph_id,
                "family": workload["family"],
                "repository": workload.get(
                    "repository", "pytorch/examples"
                ),
                "semantic_domain": workload.get(
                    "semantic_domain", workload["family"]
                ),
                "operators": dict(sorted(graph_counts.items())),
                "call_function_invocations": sum(graph_counts.values()),
            }
        )
    mapped = set(protocol["current_bounded_mapping"].values())
    rows = [
        {
            "operator": operator,
            "invocations": counts[operator],
            "graphs": len(graphs_by_operator[operator]),
            "families": len(families_by_operator[operator]),
            "repositories": len(repositories_by_operator[operator]),
            "semantic_domains": len(domains_by_operator[operator]),
            "bounded_interpreter_covered": operator in mapped,
        }
        for operator in sorted(counts)
    ]
    covered_unique = sum(row["bounded_interpreter_covered"] for row in rows)
    total_invocations = sum(counts.values())
    covered_invocations = sum(
        row["invocations"] for row in rows if row["bounded_interpreter_covered"]
    )
    unique_fraction = covered_unique / len(rows)
    invocation_fraction = covered_invocations / total_invocations
    thresholds = protocol["route_rule"]
    manual_ready = (
        unique_fraction
        >= thresholds[
            "manual_interpreter_production_ready_only_if_unique_operator_coverage"
        ]
        and invocation_fraction
        >= thresholds[
            "manual_interpreter_production_ready_only_if_invocation_coverage"
        ]
    )
    checks = {
        "calibration_only_classification": protocol["classification"]
        == "CALIBRATION_ROUTE_AUDIT_NOT_PROSPECTIVE",
        "chronology_disclosed": protocol["chronology"][
            "preliminary_operator_census_observed_before_this_freeze"
        ]
        is True,
        "twenty_three_graphs_exported": len(graph_rows) == 23,
        "one_unsupported_or_failed": len(failures) == 1,
        "operator_vocabulary_nonempty": len(rows) > 0,
        "invocations_account_exactly": total_invocations
        == sum(row["call_function_invocations"] for row in graph_rows),
        "bounded_mapping_resolves": mapped.issubset(counts),
        "full_surface_required": (
            thresholds[
                "manual_interpreter_production_ready_only_if_unique_operator_coverage"
            ]
            == thresholds[
                "manual_interpreter_production_ready_only_if_invocation_coverage"
            ]
            == 1.0
        ),
        "manual_route_rejected": manual_ready is False,
        "validation_v6_unread": protocol["chronology"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "integration_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_audit"
        ]
        == 2,
    }
    if not all(checks.values()):
        raise RuntimeError("calibration operator vocabulary audit failed")
    payload = {
        "version": "FOUNDRY_CALIBRATION_OPERATOR_VOCAB_AUDIT_V1",
        "status": "MANUAL_INTERPRETER_ROUTE_REJECTED_INCOMPLETE_SURFACE",
        "classification": protocol["classification"],
        "checks": checks,
        "summary": {
            "graphs": len(graph_rows),
            "unique_operators": len(rows),
            "call_function_invocations": total_invocations,
            "bounded_unique_operators": covered_unique,
            "bounded_invocations": covered_invocations,
            "bounded_unique_fraction": unique_fraction,
            "bounded_invocation_fraction": invocation_fraction,
            "unsupported_or_failed": len(failures),
        },
        "operators": rows,
        "graphs": graph_rows,
        "unsupported_or_failed": failures,
        "decision": {
            "manual_typed_dag_interpreter_production_ready": False,
            "required_route": "EVALUATOR_SIDE_FRAMEWORK_RUNTIME_MOUNT",
            "production_integrated_arms": 2,
        },
        "P3": {
            "operator_surface_audited": True,
            "production_runtime_route_selected": True,
            "framework_runtime_mount_implemented": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE87_OPERATOR_VOCAB"
        f" status={payload['status']}"
        f" graphs={len(graph_rows)}"
        f" ops={covered_unique}/{len(rows)}"
        f" invocations={covered_invocations}/{total_invocations}"
        " route=FRAMEWORK_MOUNT P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
