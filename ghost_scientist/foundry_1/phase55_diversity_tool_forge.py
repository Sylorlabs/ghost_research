#!/usr/bin/env python3
"""Forge executable typed tools from frozen historical diversity motifs."""

from __future__ import annotations

import collections
import hashlib
import importlib
import json
import pathlib
import sys
from typing import Any

import torch
from torch.fx import Node


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
CALIBRATION = RESULTS / "phase53_diversity_calibration_audit.json"
CALIBRATION_FREEZE = RESULTS / "diversity_calibration_v1_freeze.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
LIBRARY = RESULTS / "forged_diversity_tools.json"
RESULT = RESULTS / "phase55_diversity_tool_forge.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v5"
opened_paths: list[str] = []


def audit(event: str, args: tuple[object, ...]) -> None:
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        opened_paths.append(str(args[0]))


sys.addaudithook(audit)


class UnsupportedTerm(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tensor_type(value: object) -> dict[str, object] | None:
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def encode_literal(value: object) -> dict[str, object]:
    if value is None or type(value) in {bool, int, float, str}:
        return {"literal": value}
    if isinstance(value, torch.dtype):
        return {"torch_dtype": str(value)}
    if isinstance(value, torch.device):
        return {"torch_device": str(value)}
    raise UnsupportedTerm(f"unsupported literal {type(value).__name__}")


def encode_term(
    value: object,
    internal: dict[Node, int],
    external: dict[Node, int],
    inputs: list[dict[str, object]],
) -> dict[str, object]:
    if isinstance(value, Node):
        if value in internal:
            return {"node": internal[value]}
        kind = tensor_type(value.meta.get("val"))
        if kind is None:
            raise UnsupportedTerm("external node is not a typed tensor")
        if value not in external:
            external[value] = len(inputs)
            inputs.append({"type": kind})
        return {"input": external[value]}
    if isinstance(value, list):
        return {
            "list": [
                encode_term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, tuple):
        return {
            "tuple": [
                encode_term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, dict):
        return {
            "dict": [
                [
                    encode_literal(key),
                    encode_term(item, internal, external, inputs),
                ]
                for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
            ]
        }
    return encode_literal(value)


def construct_body(path: list[Node]) -> dict[str, object]:
    internal = {node: index for index, node in enumerate(path)}
    external: dict[Node, int] = {}
    inputs: list[dict[str, object]] = []
    nodes = []
    for node in path:
        output_type = tensor_type(node.meta.get("val"))
        if output_type is None or not str(node.target).startswith("aten."):
            raise UnsupportedTerm("candidate node is not a typed ATen tensor")
        nodes.append(
            {
                "target": str(node.target),
                "args": encode_term(node.args, internal, external, inputs),
                "kwargs": encode_term(node.kwargs, internal, external, inputs),
                "output_type": output_type,
            }
        )
    return {
        "version": "FOUNDRY_DIVERSITY_TOOL_V1",
        "inputs": inputs,
        "nodes": nodes,
        "outputs": [{"node": len(nodes) - 1}],
    }


def pattern_for(path: list[Node]) -> dict[str, object]:
    index = {node: offset for offset, node in enumerate(path)}
    return {
        "nodes": [
            {
                "target": str(node.target),
                "internal_inputs": sorted(
                    index[item]
                    for item in node.all_input_nodes
                    if item in index
                ),
                "output_type": tensor_type(node.meta.get("val")),
            }
            for node in path
        ],
        "output": len(path) - 1,
    }


def paths(graph: torch.fx.Graph, length: int) -> list[list[Node]]:
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
    }
    found: list[list[Node]] = []

    def extend(path: list[Node]) -> None:
        if len(path) == length:
            found.append(list(path))
            return
        for user in sorted(path[-1].users, key=lambda item: item.name):
            if user in eligible and user not in path:
                extend(path + [user])

    for node in sorted(eligible, key=lambda item: item.name):
        extend([node])
    return found


def workloads() -> tuple[
    list[tuple[str, dict[str, Any]]], list[dict[str, str]]
]:
    rows: list[tuple[str, dict[str, Any]]] = []
    unsupported: list[dict[str, str]] = []
    suite_modules = (
        ("original_external", "phase15_external_application_trace"),
        ("validation_v1", "external_validation_runtime"),
        ("validation_v3", "external_validation_v3_runtime"),
        ("validation_v4", "external_validation_v4_runtime"),
    )
    for suite, module_name in suite_modules:
        module = importlib.import_module(module_name)
        rows.extend((suite, item) for item in module.instantiate())
    v2 = importlib.import_module("external_validation_v2_2_runtime")
    for family, construct in v2.constructors():
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
    calibration_raw = CALIBRATION.read_bytes()
    calibration = json.loads(calibration_raw)
    calibration_freeze = json.loads(CALIBRATION_FREEZE.read_text())
    fixed_raw = FIXED.read_bytes()
    if (
        calibration["classification"]
        != "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        or calibration_freeze["classification"]
        != "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        or calibration["fixed_portfolio_sha256"]
        != hashlib.sha256(fixed_raw).hexdigest()
    ):
        raise RuntimeError("historical calibration boundary changed")
    motifs = {
        item["pattern_sha256"]: item for item in calibration["novel"]
    }
    if len(motifs) != 6:
        raise RuntimeError("expected six frozen novel calibration motifs")

    groups: dict[str, dict[str, Any]] = {}
    exported_families = []
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
            graph = exported.module().graph
        except Exception as exc:
            unsupported.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        exported_families.append({"suite": suite, "family": family})
        lengths = sorted(
            {len(item["pattern"]["nodes"]) for item in motifs.values()}
        )
        for length in lengths:
            for path in paths(graph, length):
                pattern = pattern_for(path)
                pattern_sha = digest(pattern)
                if pattern_sha not in motifs:
                    continue
                try:
                    body = construct_body(path)
                except UnsupportedTerm:
                    continue
                body_sha = digest(body)
                group = groups.setdefault(
                    body_sha,
                    {
                        "body": body,
                        "pattern_sha256": pattern_sha,
                        "occurrences": [],
                    },
                )
                group["occurrences"].append(
                    {
                        "suite": suite,
                        "family": family,
                        "nodes": [node.name for node in path],
                    }
                )

    candidates = []
    rejections: collections.Counter[str] = collections.Counter()
    for tool_id, group in sorted(groups.items()):
        occurrences = group["occurrences"]
        families = sorted({item["family"] for item in occurrences})
        suites = sorted({item["suite"] for item in occurrences})
        body = group["body"]
        structural_units = len(body["nodes"]) + len(body["inputs"])
        raw_cost = structural_units * len(occurrences)
        tool_cost = structural_units + len(occurrences)
        gain = raw_cost - tool_cost
        if len(families) < 3:
            rejections["fewer_than_three_families"] += 1
            continue
        if len(suites) < 2:
            rejections["fewer_than_two_suites"] += 1
            continue
        if gain <= 0:
            rejections["nonpositive_description_length_gain"] += 1
            continue
        candidates.append(
            {
                "tool_id": tool_id,
                **body,
                "training": {
                    "source_pattern_sha256": group["pattern_sha256"],
                    "occurrence_count": len(occurrences),
                    "family_count": len(families),
                    "suite_count": len(suites),
                    "structural_units": structural_units,
                    "raw_cost": raw_cost,
                    "tool_cost": tool_cost,
                    "description_length_gain": gain,
                    "families": families,
                    "suites": suites,
                    "occurrences": occurrences,
                },
            }
        )
    candidates.sort(
        key=lambda item: (
            -item["training"]["description_length_gain"],
            item["tool_id"],
        )
    )
    represented = {item["training"]["source_pattern_sha256"] for item in candidates}
    if not candidates:
        raise RuntimeError("diversity forge produced no executable candidates")
    forbidden_opens = sorted(
        {path for path in opened_paths if FORBIDDEN_FRAGMENT in path}
    )
    if forbidden_opens:
        raise RuntimeError("prospective validation path was accessed")
    library = {
        "version": "FOUNDRY_DIVERSITY_TOOL_LIBRARY_V1",
        "construction": {
            "algorithm": "frozen_diversity_motif_exact_boundary_mdl",
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "source_motifs": len(motifs),
            "minimum_families": 3,
            "minimum_suites": 2,
            "validation_source_or_runtime_accessed": False,
        },
        "calibration_result_sha256": hashlib.sha256(
            calibration_raw
        ).hexdigest(),
        "calibration_freeze_records_sha256": calibration_freeze[
            "records_sha256"
        ],
        "fixed_portfolio_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "tools": candidates,
    }
    LIBRARY.write_text(canonical(library) + "\n")
    result = {
        "version": "FOUNDRY_DIVERSITY_TOOL_FORGE_RESULT_V1",
        "status": "DIVERSITY_TOOL_FORGE_READY",
        "classification": "CALIBRATION_ONLY_CANDIDATE_CONSTRUCTION",
        "source_motifs": len(motifs),
        "represented_source_motifs": len(represented),
        "executable_body_groups": len(groups),
        "tools_forged": len(candidates),
        "calibration_families_exported": len(exported_families),
        "unsupported_families": unsupported,
        "description_length_gain": sum(
            item["training"]["description_length_gain"]
            for item in candidates
        ),
        "rejections": dict(sorted(rejections.items())),
        "library_sha256": file_sha(LIBRARY),
        "access_audit": {
            "file_open_events": len(opened_paths),
            "forbidden_path_fragment": FORBIDDEN_FRAGMENT,
            "forbidden_open_count": 0,
        },
        "autonomy_boundary": {
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "targets_chosen_by_machine": True,
            "argument_grammar_constructed_by_machine": True,
            "validation_source_or_runtime_accessed": False,
        },
    }
    RESULT.write_text(canonical(result) + "\n")
    print(
        "FOUNDRY_PHASE55_DIVERSITY_TOOL_FORGE_PASS"
        f" source_motifs={len(motifs)}"
        f" represented={len(represented)}"
        f" groups={len(groups)}"
        f" tools={len(candidates)}"
    )


if __name__ == "__main__":
    run()
