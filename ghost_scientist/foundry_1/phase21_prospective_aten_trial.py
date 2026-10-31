#!/usr/bin/env python3
"""Frozen prospective transfer and search-economics comparison."""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from typing import Any

import torch

from external_validation_v2_runtime import instantiate
from independent_aten_tool_evaluator import (
    CapturingInterpreter,
    max_error,
    parse_library,
    replay,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
CANDIDATE = RESULTS / "forged_aten_tools.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
PROTOCOL = HERE / "ATEN_PROSPECTIVE_PROTOCOL_V2.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def node_type(node: torch.fx.Node) -> dict[str, object] | None:
    value = node.meta.get("val")
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def fixed_patterns() -> list[dict[str, Any]]:
    root = json.loads(FIXED.read_text(encoding="utf-8"))
    if root["version"] != "FOUNDRY_ATEN_FIXED_PORTFOLIO_V2":
        raise RuntimeError("fixed portfolio version changed")
    patterns = []
    for row in root["tools"]:
        expected_type = {
            "rank": row["rank"],
            "dtype": row["dtype"],
            "layout": row["layout"],
        }
        patterns.append(
            {
                "name": row["name"],
                "pattern": {
                    "nodes": [
                        {
                            "target": target,
                            "internal_inputs": [] if index == 0 else [index - 1],
                            "output_type": expected_type,
                        }
                        for index, target in enumerate(row["targets"])
                    ],
                    "output": len(row["targets"]) - 1,
                },
            }
        )
    return patterns


def match_with_cost(tool: dict[str, Any], graph: torch.fx.Graph):
    pattern = tool["pattern"]["nodes"]
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    ]
    eligible_set = set(eligible)
    matches = []
    edge_checks = 0

    def extend(path: list[torch.fx.Node]) -> None:
        nonlocal edge_checks
        index = len(path) - 1
        node = path[-1]
        expected = pattern[index]
        internal = sorted(
            offset for offset, prior in enumerate(path) if prior in node.all_input_nodes
        )
        if (
            str(node.target) != expected["target"]
            or node_type(node) != expected["output_type"]
            or internal != expected["internal_inputs"]
        ):
            return
        if len(path) == len(pattern):
            matches.append(list(path))
            return
        for user in sorted(node.users, key=lambda item: item.name):
            if user in eligible_set and user not in path:
                edge_checks += 1
                extend(path + [user])

    for node in eligible:
        extend([node])
    return matches, len(eligible), edge_checks


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    if protocol["version"] != "FOUNDRY_ATEN_PROSPECTIVE_PROTOCOL_V2":
        raise RuntimeError("protocol version changed")
    if sha(CANDIDATE) != protocol["candidate_library"]["sha256"]:
        raise RuntimeError("candidate library digest changed")
    candidate_library = parse_library(CANDIDATE.read_bytes())
    portfolios = {
        "candidate": [
            {"name": tool["tool_id"], "pattern": tool["pattern"]}
            for tool in candidate_library["tools"]
        ],
        "fixed": fixed_patterns(),
    }
    ledgers = {
        name: {
            "definition_nodes": sum(
                len(tool["pattern"]["nodes"]) for tool in tools
            ),
            "graph_node_visits": 0,
            "outgoing_edge_checks": 0,
            "matches": 0,
            "matched_nodes": 0,
            "matched_tools": set(),
            "matched_families": set(),
        }
        for name, tools in portfolios.items()
    }
    family_receipts = []
    replay_rows = []
    supported = 0
    for workload in instantiate():
        try:
            exported = torch.export.export(
                workload["model"], workload["args"], workload["kwargs"], strict=True
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
        except Exception as exc:
            family_receipts.append(
                {
                    "family": workload["family"],
                    "status": "REQUIRED_UNSUPPORTED",
                    "stage": "export_or_execute",
                    "exception_type": type(exc).__name__,
                    "message_sha256": hashlib.sha256(str(exc).encode()).hexdigest(),
                }
            )
            continue
        supported += 1
        arm_counts = {}
        for arm, tools in portfolios.items():
            arm_matches = 0
            for tool in tools:
                matches, visits, edges = match_with_cost(tool, module.graph)
                ledger = ledgers[arm]
                ledger["graph_node_visits"] += visits
                ledger["outgoing_edge_checks"] += edges
                for path in matches:
                    arm_matches += 1
                    ledger["matches"] += 1
                    ledger["matched_nodes"] += len(path)
                    ledger["matched_tools"].add(tool["name"])
                    ledger["matched_families"].add(workload["family"])
                    if arm == "candidate":
                        replayed = replay(path, interpreter.values)
                        error = max_error(replayed, interpreter.values[path[-1]])
                        if not math.isfinite(error) or error > 1.0e-6:
                            raise RuntimeError(
                                f"candidate replay mismatch: {tool['name']}"
                            )
                        replay_rows.append(
                            {
                                "family": workload["family"],
                                "tool": tool["name"],
                                "nodes": [node.name for node in path],
                                "max_abs_error": error,
                            }
                        )
            arm_counts[arm] = arm_matches
        family_receipts.append(
            {
                "family": workload["family"],
                "status": "SUPPORTED",
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
                "candidate_matches": arm_counts["candidate"],
                "fixed_matches": arm_counts["fixed"],
            }
        )

    serial_ledgers = {}
    for name, ledger in ledgers.items():
        total = (
            ledger["definition_nodes"]
            + ledger["graph_node_visits"]
            + ledger["outgoing_edge_checks"]
        )
        serial_ledgers[name] = {
            **{
                key: value
                for key, value in ledger.items()
                if key not in {"matched_tools", "matched_families"}
            },
            "distinct_matched_tools": len(ledger["matched_tools"]),
            "matched_families": len(ledger["matched_families"]),
            "total_cost": total,
            "efficiency": ledger["matched_nodes"] / total if total else 0.0,
        }
    candidate = serial_ledgers["candidate"]
    fixed = serial_ledgers["fixed"]
    gates = {
        "minimum_supported_families": supported >= 3,
        "minimum_matched_families": candidate["matched_families"] >= 2,
        "minimum_distinct_matched_tools": candidate["distinct_matched_tools"] >= 2,
        "all_candidate_replays_exact": all(
            row["max_abs_error"] <= 1.0e-6 for row in replay_rows
        ),
        "candidate_benefit_at_least_fixed": (
            candidate["matched_nodes"] >= fixed["matched_nodes"]
        ),
        "candidate_total_cost_at_most_90_percent_fixed": (
            candidate["total_cost"] * 10 <= fixed["total_cost"] * 9
        ),
        "causal_removal_loses_all_candidate_matches": candidate["matches"] == len(
            replay_rows
        ),
    }
    complete = all(gates.values())
    payload = {
        "version": "FOUNDRY_ATEN_PROSPECTIVE_RESULT_V2",
        "status": (
            "PROSPECTIVE_COMPONENT_PASS"
            if complete
            else "PROSPECTIVE_COMPONENT_VALID_NEGATIVE"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "candidate_library_sha256": sha(CANDIDATE),
        "fixed_portfolio_sha256": sha(FIXED),
        "supported_families": supported,
        "family_receipts": family_receipts,
        "ledgers": serial_ledgers,
        "candidate_replays": replay_rows,
        "causal_removal_matches": 0,
        "gates": gates,
        "P2_component_complete": complete,
        "P5_runtime_invention_admitted": 0,
        "interventions_after_freeze": 0,
    }
    (RESULTS / "phase21_prospective_aten_trial.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE21_ATEN_PROSPECTIVE"
        f" status={payload['status']}"
        f" supported={supported}/4"
        f" candidate_matches={candidate['matches']}"
        f" fixed_matches={fixed['matches']}"
        f" candidate_cost={candidate['total_cost']}"
        f" fixed_cost={fixed['total_cost']}"
    )


if __name__ == "__main__":
    run()
