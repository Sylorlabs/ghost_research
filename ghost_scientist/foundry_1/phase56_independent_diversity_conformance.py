#!/usr/bin/env python3
"""Independently parse, match, and replay diversity tools on calibration."""

from __future__ import annotations

import hashlib
import json
import pathlib

import torch

from independent_diversity_tool_evaluator import (
    CapturingInterpreter,
    LIBRARY,
    canonical,
    execute_tool,
    historical_workloads,
    hostile_tests,
    max_error,
    parse_library,
    semantic_matches,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase56_independent_diversity_conformance.json"


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    hostile = hostile_tests(raw)
    workloads, unsupported = historical_workloads()
    rows = []
    tool_receipts = {
        tool["tool_id"]: {
            "families": set(),
            "suites": set(),
            "matches": 0,
            "max_abs_error": 0.0,
        }
        for tool in library["tools"]
    }
    visits = 0
    edges = 0
    graph_count = 0
    for suite, workload in workloads:
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
        except Exception as exc:
            unsupported.append(
                {
                    "suite": suite,
                    "family": workload["family"],
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        graph_count += 1
        for tool in library["tools"]:
            matches, tool_visits, tool_edges = semantic_matches(
                tool, module.graph
            )
            visits += tool_visits
            edges += tool_edges
            for path, bindings in matches:
                inputs = [
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                ]
                replayed = execute_tool(tool, inputs)
                error = max_error(replayed, interpreter.values[path[-1]])
                if error > 1.0e-6:
                    raise RuntimeError(
                        f"diversity replay mismatch {tool['tool_id']} "
                        f"{workload['family']} error={error}"
                    )
                receipt = tool_receipts[tool["tool_id"]]
                receipt["families"].add(workload["family"])
                receipt["suites"].add(suite)
                receipt["matches"] += 1
                receipt["max_abs_error"] = max(
                    receipt["max_abs_error"], error
                )
                rows.append(
                    {
                        "suite": suite,
                        "family": workload["family"],
                        "tool_id": tool["tool_id"],
                        "nodes": [node.name for node in path],
                        "input_count": len(inputs),
                        "max_abs_error": error,
                    }
                )
    normalized = []
    declared = {item["tool_id"]: item for item in library["tools"]}
    for tool_id, receipt in sorted(tool_receipts.items()):
        tool = declared[tool_id]
        families = sorted(receipt["families"])
        suites = sorted(receipt["suites"])
        normalized.append(
            {
                "tool_id": tool_id,
                "families": families,
                "suites": suites,
                "matches": receipt["matches"],
                "max_abs_error": receipt["max_abs_error"],
                "declared_families_exact": families
                == tool["training"]["families"],
                "declared_suites_exact": suites == tool["training"]["suites"],
                "declared_occurrences_exact": receipt["matches"]
                == tool["training"]["occurrence_count"],
            }
        )
    gates = {
        "strict_parser_accepts_library": True,
        "five_hostile_mutations_rejected": len(hostile) == 5,
        "nineteen_historical_graphs_exported": graph_count == 19,
        "every_tool_replayed": all(item["matches"] > 0 for item in normalized),
        "every_replay_exact": all(
            item["max_abs_error"] <= 1.0e-6 for item in normalized
        ),
        "training_receipts_reproduced_exactly": all(
            item["declared_families_exact"]
            and item["declared_suites_exact"]
            and item["declared_occurrences_exact"]
            for item in normalized
        ),
    }
    status = (
        "DIVERSITY_TOOL_INDEPENDENT_CONFORMANCE_PASS"
        if all(gates.values())
        else "DIVERSITY_TOOL_INDEPENDENT_CONFORMANCE_FAIL"
    )
    payload = {
        "version": "FOUNDRY_INDEPENDENT_DIVERSITY_CONFORMANCE_V1",
        "status": status,
        "classification": "CALIBRATION_ONLY_INDEPENDENT_CONFORMANCE",
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "tools": len(library["tools"]),
        "graphs": graph_count,
        "successful_replays": len(rows),
        "graph_node_visits": visits,
        "edge_checks": edges,
        "hostile_rejections": hostile,
        "unsupported_families": unsupported,
        "tool_receipts": normalized,
        "gates": gates,
        "rows": rows,
        "validation_source_or_runtime_accessed": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE56_INDEPENDENT_DIVERSITY_CONFORMANCE"
        f" status={status}"
        f" tools={len(library['tools'])}"
        f" graphs={graph_count}"
        f" replays={len(rows)}"
    )


if __name__ == "__main__":
    run()
