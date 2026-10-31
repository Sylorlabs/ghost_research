#!/usr/bin/env python3
"""Independent strict parser, matcher, and executable replay for ATen tools."""

from __future__ import annotations

import copy
import hashlib
import json
import math
import pathlib
from typing import Any

import torch
from torch.fx.node import map_arg

from external_validation_runtime import instantiate
from freeze_external_validation_v1 import MANIFEST, verify


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


class ContractError(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def exact(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ContractError(f"{context} fields are not exact")
    return value


def parse_type(value: object, context: str) -> None:
    item = exact(value, {"rank", "dtype", "layout"}, context)
    if type(item["rank"]) is not int or not 0 <= item["rank"] <= 8:
        raise ContractError(f"{context} rank is invalid")
    if item["dtype"] not in {
        "torch.float16",
        "torch.float32",
        "torch.float64",
        "torch.int32",
        "torch.int64",
        "torch.bool",
    }:
        raise ContractError(f"{context} dtype is invalid")
    if item["layout"] not in {"torch.strided", "torch.sparse_coo", "torch.sparse_csr"}:
        raise ContractError(f"{context} layout is invalid")


def parse_pattern(value: object, context: str) -> None:
    item = exact(value, {"nodes", "output"}, context)
    if not isinstance(item["nodes"], list) or not 2 <= len(item["nodes"]) <= 3:
        raise ContractError(f"{context} node count is invalid")
    for index, node in enumerate(item["nodes"]):
        row = exact(node, {"target", "internal_inputs", "output_type"}, f"{context} node {index}")
        if (
            not isinstance(row["target"], str)
            or not row["target"].startswith("aten.")
            or len(row["target"]) > 128
        ):
            raise ContractError(f"{context} node {index} target is invalid")
        if (
            not isinstance(row["internal_inputs"], list)
            or row["internal_inputs"] != sorted(set(row["internal_inputs"]))
            or any(type(slot) is not int or not 0 <= slot < index for slot in row["internal_inputs"])
            or (index > 0 and index - 1 not in row["internal_inputs"])
        ):
            raise ContractError(f"{context} node {index} internal inputs are invalid")
        parse_type(row["output_type"], f"{context} node {index} type")
    if item["output"] != len(item["nodes"]) - 1:
        raise ContractError(f"{context} output is invalid")


def parse_training(value: object, context: str) -> None:
    item = exact(
        value,
        {
            "family_count",
            "families",
            "occurrence_count",
            "raw_node_cost",
            "tool_encoded_cost",
            "description_length_gain",
            "occurrences",
        },
        context,
    )
    if (
        type(item["family_count"]) is not int
        or item["family_count"] < 2
        or not isinstance(item["families"], list)
        or len(set(item["families"])) != item["family_count"]
        or type(item["occurrence_count"]) is not int
        or item["occurrence_count"] != len(item["occurrences"])
        or type(item["description_length_gain"]) is not int
        or item["description_length_gain"] <= 0
        or item["raw_node_cost"] - item["tool_encoded_cost"]
        != item["description_length_gain"]
    ):
        raise ContractError(f"{context} summary is invalid")
    for index, occurrence in enumerate(item["occurrences"]):
        row = exact(occurrence, {"family", "nodes"}, f"{context} occurrence {index}")
        if (
            row["family"] not in item["families"]
            or not isinstance(row["nodes"], list)
            or not row["nodes"]
            or any(not isinstance(name, str) for name in row["nodes"])
        ):
            raise ContractError(f"{context} occurrence {index} is invalid")


def parse_library(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("library is not JSON") from exc
    root = exact(
        value,
        {
            "version",
            "construction",
            "calibration_source_freeze_sha256",
            "validation_source_freeze_sha256",
            "calibration_graphs",
            "tools",
        },
        "library",
    )
    if root["version"] != "FOUNDRY_ATEN_TOOL_LIBRARY_V1":
        raise ContractError("library version mismatch")
    construction = exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "minimum_families",
            "minimum_length",
            "maximum_length",
            "validation_graphs_accessed",
            "answer_blind_to_validation_execution",
        },
        "construction",
    )
    if (
        construction["llm_calls"] != 0
        or construction["minimum_families"] < 2
        or construction["minimum_length"] != 2
        or construction["maximum_length"] != 3
        or construction["validation_graphs_accessed"] is not False
        or construction["answer_blind_to_validation_execution"] is not True
    ):
        raise ContractError("construction boundary is invalid")
    if not isinstance(root["calibration_graphs"], list) or len(root["calibration_graphs"]) != 4:
        raise ContractError("calibration graph receipts are invalid")
    if not isinstance(root["tools"], list) or not root["tools"]:
        raise ContractError("library has no tools")
    seen = set()
    for index, tool in enumerate(root["tools"]):
        row = exact(tool, {"version", "pattern", "tool_id", "training"}, f"tool {index}")
        if row["version"] != "FOUNDRY_ATEN_TOOL_V1":
            raise ContractError(f"tool {index} version mismatch")
        parse_pattern(row["pattern"], f"tool {index} pattern")
        parse_training(row["training"], f"tool {index} training")
        body = {"version": row["version"], "pattern": row["pattern"]}
        digest = hashlib.sha256(canonical(body).encode()).hexdigest()
        if row["tool_id"] != digest or digest in seen:
            raise ContractError(f"tool {index} digest is invalid or duplicated")
        seen.add(digest)
    return root


def node_type(node: torch.fx.Node) -> dict[str, object] | None:
    value = node.meta.get("val")
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def enumerate_matches(tool: dict[str, Any], graph: torch.fx.Graph):
    pattern = tool["pattern"]["nodes"]
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    ]
    eligible_set = set(eligible)
    matches = []

    def extend(path: list[torch.fx.Node]) -> None:
        index = len(path) - 1
        expected = pattern[index]
        node = path[-1]
        internal = sorted(
            offset
            for offset, prior in enumerate(path)
            if prior in node.all_input_nodes
        )
        if str(node.target) != expected["target"] or node_type(node) != expected["output_type"]:
            return
        if internal != expected["internal_inputs"]:
            return
        if len(path) == len(pattern):
            matches.append(list(path))
            return
        for user in sorted(node.users, key=lambda item: item.name):
            if user in eligible_set and user not in path:
                extend(path + [user])

    for node in eligible:
        extend([node])
    return matches


class CapturingInterpreter(torch.fx.Interpreter):
    def __init__(self, module):
        super().__init__(module)
        self.values: dict[torch.fx.Node, object] = {}

    def run_node(self, node):
        value = super().run_node(node)
        self.values[node] = value
        return value


def replay(path: list[torch.fx.Node], captured: dict[torch.fx.Node, object]):
    local: dict[torch.fx.Node, object] = {}

    def resolve(node: torch.fx.Node):
        return local[node] if node in local else captured[node]

    for node in path:
        args = map_arg(node.args, resolve)
        kwargs = map_arg(node.kwargs, resolve)
        local[node] = node.target(*args, **kwargs)
    return local[path[-1]]


def max_error(left: object, right: object) -> float:
    if isinstance(left, torch.Tensor) and isinstance(right, torch.Tensor):
        if left.shape != right.shape:
            return math.inf
        if left.numel() == 0:
            return 0.0
        if left.dtype == torch.bool or not left.dtype.is_floating_point:
            return 0.0 if torch.equal(left, right) else math.inf
        return float(torch.max(torch.abs(left - right)).item())
    return 0.0 if left == right else math.inf


def hostile_tests(raw: bytes) -> list[str]:
    source = json.loads(raw)
    mutations = []
    extra = copy.deepcopy(source)
    extra["tools"][0]["extra"] = True
    mutations.append(("extra_field", extra))
    bad_digest = copy.deepcopy(source)
    bad_digest["tools"][0]["tool_id"] = "0" * 64
    mutations.append(("bad_digest", bad_digest))
    forward = copy.deepcopy(source)
    forward["tools"][0]["pattern"]["nodes"][0]["internal_inputs"] = [0]
    mutations.append(("forward_edge", forward))
    bad_target = copy.deepcopy(source)
    bad_target["tools"][0]["pattern"]["nodes"][0]["target"] = "python.eval"
    mutations.append(("untyped_target", bad_target))
    rejected = []
    for name, mutation in mutations:
        try:
            parse_library(canonical(mutation).encode())
        except ContractError:
            rejected.append(name)
        else:
            raise RuntimeError(f"hostile mutation accepted: {name}")
    return rejected


def run() -> None:
    freeze = verify()
    raw = (RESULTS / "forged_aten_tools.json").read_bytes()
    library = parse_library(raw)
    hostile = hostile_tests(raw)
    rows = []
    family_receipts = []
    maximum_error = 0.0
    matched_tools = set()
    for workload in instantiate():
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        module = exported.module()
        interpreter = CapturingInterpreter(module)
        full_output = interpreter.run(*workload["args"], **workload["kwargs"])
        family_matches = 0
        for tool in library["tools"]:
            for path in enumerate_matches(tool, module.graph):
                replayed = replay(path, interpreter.values)
                error = max_error(replayed, interpreter.values[path[-1]])
                if not math.isfinite(error) or error > 1.0e-6:
                    raise RuntimeError(
                        f"ATen tool replay mismatch {tool['tool_id']} "
                        f"{workload['family']} error={error}"
                    )
                maximum_error = max(maximum_error, error)
                matched_tools.add(tool["tool_id"])
                family_matches += 1
                rows.append(
                    {
                        "family": workload["family"],
                        "tool_id": tool["tool_id"],
                        "nodes": [node.name for node in path],
                        "replay_max_abs_error": error,
                        "typed_match": True,
                        "executed": True,
                    }
                )
        family_receipts.append(
            {
                "family": workload["family"],
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
                "output_signature": str(type(full_output)),
                "tool_matches": family_matches,
            }
        )
    payload = {
        "version": "FOUNDRY_INDEPENDENT_ATEN_EVAL_V1",
        "status": (
            "INDEPENDENT_ATEN_EVAL_TRANSFER_PASS"
            if rows
            else "INDEPENDENT_ATEN_EVAL_VALID_NEGATIVE"
        ),
        "validation_freeze_file_sha256": hashlib.sha256(MANIFEST.read_bytes()).hexdigest(),
        "library_file_sha256": hashlib.sha256(raw).hexdigest(),
        "tools": len(library["tools"]),
        "families": len(family_receipts),
        "matched_tools": len(matched_tools),
        "successful_macro_replays": len(rows),
        "maximum_abs_error": maximum_error,
        "hostile_rejections": hostile,
        "causal_removal": {
            "with_library_macro_matches": len(rows),
            "without_library_macro_matches": 0,
            "losses": len(rows),
        },
        "family_receipts": family_receipts,
        "rows": rows,
        "prospective_boundary": {
            "source_selection_preforge": True,
            "runtime_harness_preforge": False,
            "classification": "CALIBRATION_ONLY_ADVERSARIAL_PILOT",
        },
        "limits": [
            "source selection was pre-forge but runtime shapes were selected post-forge",
            "macro replay proves executable semantics preservation, not compiler speedup",
            "unmatched tools remain unsupported rather than counted as failures",
        ],
    }
    (RESULTS / "phase18_independent_aten_eval.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE18_INDEPENDENT_ATEN_EVAL"
        f" status={payload['status']}"
        f" tools={payload['tools']}"
        f" matched_tools={payload['matched_tools']}"
        f" replays={payload['successful_macro_replays']}"
        f" hostile={len(hostile)}"
        " classification=CALIBRATION_ONLY"
    )


if __name__ == "__main__":
    run()
