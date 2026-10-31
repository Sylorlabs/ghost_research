#!/usr/bin/env python3
"""Mine the full historical external corpus for multi-family motif ceilings."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
from typing import Any

import torch

import external_validation_runtime
import external_validation_v2_2_runtime
import external_validation_v3_runtime
import external_validation_v4_runtime
import phase15_external_application_trace


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase53_diversity_calibration_audit.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
MIN_FAMILIES = 3
MIN_SUITES = 2
MIN_LENGTH = 2
MAX_LENGTH = 3


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(value: object) -> str:
    raw = value if isinstance(value, bytes) else canonical(value).encode()
    return hashlib.sha256(raw).hexdigest()


def tensor_type(value: object) -> dict[str, object] | None:
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def enumerate_paths(graph: torch.fx.Graph) -> list[list[torch.fx.Node]]:
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
    ]
    eligible_set = set(eligible)
    paths: list[list[torch.fx.Node]] = []

    def extend(path: list[torch.fx.Node]) -> None:
        if len(path) >= MIN_LENGTH:
            paths.append(list(path))
        if len(path) == MAX_LENGTH:
            return
        for user in sorted(path[-1].users, key=lambda item: item.name):
            if user in eligible_set and user not in path:
                extend(path + [user])

    for node in eligible:
        extend([node])
    return paths


def pattern_for(path: list[torch.fx.Node]) -> dict[str, object] | None:
    index = {node: offset for offset, node in enumerate(path)}
    nodes = []
    for offset, node in enumerate(path):
        observed = tensor_type(node.meta.get("val"))
        if observed is None:
            return None
        internal = sorted(
            index[item] for item in node.all_input_nodes if item in index
        )
        if offset and offset - 1 not in internal:
            return None
        nodes.append(
            {
                "target": str(node.target),
                "internal_inputs": internal,
                "output_type": observed,
            }
        )
    return {"nodes": nodes, "output": len(nodes) - 1}


def repository_for(suite: str, family: str) -> str:
    if suite == "validation_v4":
        return {
            "healthcare_dense_graph_convolution": "sunlabuiuc/PyHealth",
            "robust_gaussian_graph_convolution": "DSE-MSU/DeepRobust",
        }.get(family, "pytorch/examples")
    return "pytorch/examples"


def workloads() -> tuple[list[tuple[str, dict[str, Any]]], list[dict[str, str]]]:
    rows: list[tuple[str, dict[str, Any]]] = []
    unsupported: list[dict[str, str]] = []
    suites = (
        ("original_external", phase15_external_application_trace.instantiate),
        ("validation_v1", external_validation_runtime.instantiate),
        ("validation_v3", external_validation_v3_runtime.instantiate),
        ("validation_v4", external_validation_v4_runtime.instantiate),
    )
    for suite, instantiate in suites:
        try:
            rows.extend((suite, item) for item in instantiate())
        except Exception as exc:
            unsupported.append(
                {
                    "suite": suite,
                    "family": "*",
                    "exception_type": type(exc).__name__,
                }
            )
    for family, construct in external_validation_v2_2_runtime.constructors():
        try:
            rows.append(("validation_v2", construct()))
        except Exception as exc:
            unsupported.append(
                {
                    "suite": "validation_v2",
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
    return rows, unsupported


def run() -> None:
    fixed_raw = FIXED.read_bytes()
    fixed = json.loads(fixed_raw)
    fixed_sequences = {
        tuple(tool["targets"]): tool["name"] for tool in fixed["tools"]
    }
    groups: dict[str, dict[str, Any]] = {}
    graph_rows = []
    instantiated, unsupported = workloads()
    for suite, workload in instantiated:
        family = workload["family"]
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
        except Exception as exc:
            unsupported.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        graph_text = str(module.graph)
        graph_rows.append(
            {
                "suite": suite,
                "family": family,
                "repository": repository_for(suite, family),
                "graph_sha256": hashlib.sha256(
                    graph_text.encode()
                ).hexdigest(),
                "call_function_nodes": sum(
                    node.op == "call_function" for node in module.graph.nodes
                ),
            }
        )
        for path in enumerate_paths(module.graph):
            pattern = pattern_for(path)
            if pattern is None:
                continue
            key = sha(pattern)
            record = groups.setdefault(
                key, {"pattern": pattern, "occurrences": []}
            )
            record["occurrences"].append(
                {
                    "suite": suite,
                    "family": family,
                    "repository": repository_for(suite, family),
                    "nodes": [node.name for node in path],
                }
            )

    selected = []
    rejection_counts: collections.Counter[str] = collections.Counter()
    for pattern_sha, record in sorted(groups.items()):
        occurrences = record["occurrences"]
        families = sorted({item["family"] for item in occurrences})
        suites = sorted({item["suite"] for item in occurrences})
        repositories = sorted(
            {item["repository"] for item in occurrences}
        )
        length = len(record["pattern"]["nodes"])
        raw_cost = length * len(occurrences)
        encoded_cost = length + len(occurrences)
        gain = raw_cost - encoded_cost
        sequence = tuple(
            node["target"] for node in record["pattern"]["nodes"]
        )
        if len(families) < MIN_FAMILIES:
            rejection_counts["fewer_than_three_families"] += 1
            continue
        if len(suites) < MIN_SUITES:
            rejection_counts["fewer_than_two_suites"] += 1
            continue
        if gain <= 0:
            rejection_counts["nonpositive_description_length_gain"] += 1
            continue
        selected.append(
            {
                "pattern_sha256": pattern_sha,
                "pattern": record["pattern"],
                "target_sequence": list(sequence),
                "families": families,
                "family_count": len(families),
                "suites": suites,
                "suite_count": len(suites),
                "repositories": repositories,
                "repository_count": len(repositories),
                "occurrences": occurrences,
                "occurrence_count": len(occurrences),
                "description_length_gain": gain,
                "fixed_target_sequence_duplicate": sequence
                in fixed_sequences,
                "fixed_name": fixed_sequences.get(sequence),
            }
        )
    selected.sort(
        key=lambda row: (
            -row["family_count"],
            -row["suite_count"],
            -row["description_length_gain"],
            row["pattern_sha256"],
        )
    )
    novel = [
        row for row in selected if not row["fixed_target_sequence_duplicate"]
    ]
    payload = {
        "version": "FOUNDRY_DIVERSITY_CALIBRATION_AUDIT_V1",
        "status": "DIVERSITY_CALIBRATION_AUDIT_COMPLETE",
        "classification": "HISTORICAL_OUTCOMES_CALIBRATION_ONLY",
        "fixed_portfolio_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "graph_rows": graph_rows,
        "unsupported": unsupported,
        "candidate_patterns_enumerated": len(groups),
        "selection": {
            "minimum_families": MIN_FAMILIES,
            "minimum_suites": MIN_SUITES,
            "minimum_length": MIN_LENGTH,
            "maximum_length": MAX_LENGTH,
            "selected_patterns": len(selected),
            "fixed_target_sequence_duplicates": sum(
                row["fixed_target_sequence_duplicate"] for row in selected
            ),
            "novel_target_sequences": len(novel),
        },
        "selected": selected,
        "novel": novel,
        "rejections": dict(sorted(rejection_counts.items())),
        "autonomy_boundary": {
            "llm_calls": 0,
            "manual_pattern_forms": 0,
            "historical_outcomes_accessed": True,
            "prospective_claim_allowed": False,
        },
        "claim_boundary": (
            "All five suites have already produced outcomes in prior phases. "
            "This audit may diagnose the diversity ceiling and design a later "
            "forge, but neither its patterns nor any corpus used here may be "
            "reported as prospective validation."
        ),
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE53_DIVERSITY_CALIBRATION"
        f" status={payload['status']}"
        f" graphs={len(graph_rows)}"
        f" patterns={len(groups)}"
        f" selected={len(selected)}"
        f" novel={len(novel)}"
        f" unsupported={len(unsupported)}"
    )


if __name__ == "__main__":
    run()
