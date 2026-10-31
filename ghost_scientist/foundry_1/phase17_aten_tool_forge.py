#!/usr/bin/env python3
"""Phase 17: LLM-free frequent typed-subgraph forge over calibration exports."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
from typing import Any

import torch

from freeze_external_application_intake import verify as verify_calibration
from freeze_external_validation_v1 import verify as verify_validation_freeze
from phase15_external_application_trace import instantiate


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY_VERSION = "FOUNDRY_ATEN_TOOL_LIBRARY_V1"
TOOL_VERSION = "FOUNDRY_ATEN_TOOL_V1"
MIN_FAMILIES = 2
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


def pattern_for(path: list[torch.fx.Node]) -> dict[str, object] | None:
    index = {node: offset for offset, node in enumerate(path)}
    output_types = [tensor_type(node.meta.get("val")) for node in path]
    if any(item is None for item in output_types):
        return None
    nodes = []
    for offset, node in enumerate(path):
        internal_inputs = sorted(
            index[item] for item in node.all_input_nodes if item in index
        )
        if offset and offset - 1 not in internal_inputs:
            return None
        nodes.append(
            {
                "target": str(node.target),
                "internal_inputs": internal_inputs,
                "output_type": output_types[offset],
            }
        )
    return {"nodes": nodes, "output": len(nodes) - 1}


def enumerate_paths(graph: torch.fx.Graph) -> list[list[torch.fx.Node]]:
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
    ]
    eligible_set = set(eligible)
    paths = []

    def extend(path: list[torch.fx.Node]) -> None:
        if len(path) >= MIN_LENGTH:
            paths.append(list(path))
        if len(path) == MAX_LENGTH:
            return
        last = path[-1]
        for user in sorted(last.users, key=lambda item: item.name):
            if user in eligible_set and user not in path:
                extend(path + [user])

    for node in eligible:
        extend([node])
    return paths


def run() -> None:
    calibration_freeze = verify_calibration()
    validation_freeze = verify_validation_freeze()
    groups: dict[str, dict[str, Any]] = {}
    graph_receipts = []
    for workload in instantiate():
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        module = exported.module()
        graph_text = str(module.graph)
        graph_receipts.append(
            {
                "family": workload["family"],
                "graph_sha256": hashlib.sha256(graph_text.encode()).hexdigest(),
            }
        )
        for path in enumerate_paths(module.graph):
            pattern = pattern_for(path)
            if pattern is None:
                continue
            key = sha(pattern)
            record = groups.setdefault(
                key,
                {
                    "pattern": pattern,
                    "occurrences": [],
                },
            )
            record["occurrences"].append(
                {
                    "family": workload["family"],
                    "nodes": [node.name for node in path],
                }
            )

    tools = []
    rejected = collections.Counter()
    for key, record in sorted(groups.items()):
        occurrences = record["occurrences"]
        families = sorted({item["family"] for item in occurrences})
        length = len(record["pattern"]["nodes"])
        definition_cost = length
        raw_cost = length * len(occurrences)
        encoded_cost = definition_cost + len(occurrences)
        compression_gain = raw_cost - encoded_cost
        if len(families) < MIN_FAMILIES:
            rejected["insufficient_family_support"] += 1
            continue
        if compression_gain <= 0:
            rejected["nonpositive_description_length_gain"] += 1
            continue
        body = {
            "version": TOOL_VERSION,
            "pattern": record["pattern"],
        }
        tool_id = sha(body)
        tools.append(
            {
                **body,
                "tool_id": tool_id,
                "training": {
                    "family_count": len(families),
                    "families": families,
                    "occurrence_count": len(occurrences),
                    "raw_node_cost": raw_cost,
                    "tool_encoded_cost": encoded_cost,
                    "description_length_gain": compression_gain,
                    "occurrences": occurrences,
                },
            }
        )
    tools.sort(
        key=lambda item: (
            -item["training"]["description_length_gain"],
            -len(item["pattern"]["nodes"]),
            item["tool_id"],
        )
    )
    if not tools:
        raise RuntimeError("ATen forge produced no cross-family positive-gain tools")
    library = {
        "version": LIBRARY_VERSION,
        "construction": {
            "algorithm": "bounded_connected_path_enumeration_and_mdl_selection",
            "llm_calls": 0,
            "minimum_families": MIN_FAMILIES,
            "minimum_length": MIN_LENGTH,
            "maximum_length": MAX_LENGTH,
            "validation_graphs_accessed": False,
            "answer_blind_to_validation_execution": True,
        },
        "calibration_source_freeze_sha256": hashlib.sha256(
            (RESULTS / "external_application_intake_freeze.json").read_bytes()
        ).hexdigest(),
        "validation_source_freeze_sha256": hashlib.sha256(
            (RESULTS / "external_validation_v1_freeze.json").read_bytes()
        ).hexdigest(),
        "calibration_graphs": graph_receipts,
        "tools": tools,
    }
    library_path = RESULTS / "forged_aten_tools.json"
    library_path.write_text(canonical(library) + "\n", encoding="utf-8")
    payload = {
        "version": "FOUNDRY_ATEN_FORGE_RESULT_V1",
        "status": "ATEN_FORGE_COMPONENT_READY",
        "calibration_records_sha256": calibration_freeze["records_sha256"],
        "validation_records_sha256": validation_freeze["records_sha256"],
        "library_file_sha256": hashlib.sha256(library_path.read_bytes()).hexdigest(),
        "candidate_patterns": len(groups),
        "tools_forged": len(tools),
        "families_used": len(graph_receipts),
        "selected_description_length_gain": sum(
            item["training"]["description_length_gain"] for item in tools
        ),
        "rejections": dict(sorted(rejected.items())),
        "limits": [
            "tools are executable subgraph macros, not new primitive tensor semantics",
            "rank dtype and layout are enforced while concrete dimensions are abstracted",
            "description-length gain is a structural search-cost proxy, not runtime speedup",
            "validation transfer and native compiler behavior are separate prospective checks",
        ],
    }
    (RESULTS / "phase17_aten_tool_forge.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE17_ATEN_FORGE_PASS"
        f" candidates={len(groups)}"
        f" tools={len(tools)}"
        f" families={len(graph_receipts)}"
        f" mdl_gain={payload['selected_description_length_gain']}"
    )


if __name__ == "__main__":
    run()
