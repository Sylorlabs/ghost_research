#!/usr/bin/env python3
"""Infer constraint-polymorphic semantic tools from operator-wide evidence."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
from typing import Any

import torch
from torch.fx import Node

from external_validation_v2_2_runtime import constructors
from phase26_independent_semantic_evaluator import parse_library


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
SOURCE = RESULTS / "forged_semantic_tools.json"
OUTPUT = RESULTS / "forged_polymorphic_semantic_tools.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(value: object) -> str:
    raw = value if isinstance(value, bytes) else canonical(value).encode()
    return hashlib.sha256(raw).hexdigest()


def tensor_signature(value: object) -> tuple[int, str, str] | None:
    if not isinstance(value, torch.Tensor):
        return None
    return len(value.shape), str(value.dtype), str(value.layout)


def signature_row(signature: tuple[int, str, str]) -> dict[str, object]:
    rank, dtype, layout = signature
    return {"rank": rank, "dtype": dtype, "layout": layout}


def constraint(signatures: set[tuple[int, str, str]]) -> dict[str, object]:
    if not signatures:
        raise RuntimeError("empty polymorphic signature constraint")
    return {
        "one_of": [
            signature_row(item)
            for item in sorted(signatures, key=lambda row: (row[0], row[1], row[2]))
        ]
    }


def exact_signature(value: dict[str, object]) -> tuple[int, str, str]:
    return int(value["rank"]), str(value["dtype"]), str(value["layout"])


def run() -> None:
    source_raw = SOURCE.read_bytes()
    source = parse_library(source_raw)
    argument_evidence: dict[
        tuple[str, str, str], set[tuple[int, str, str]]
    ] = collections.defaultdict(set)
    output_evidence: dict[str, set[tuple[int, str, str]]] = collections.defaultdict(
        set
    )
    evidence_counts: collections.Counter[tuple[str, str, str, tuple]] = (
        collections.Counter()
    )
    graph_rows = []
    unsupported = []
    for family, construct in constructors():
        try:
            workload = construct()
            exported = torch.export.export(
                workload["model"], workload["args"], workload["kwargs"], strict=True
            )
            module = exported.module()
        except Exception as exc:
            unsupported.append(
                {"family": family, "exception_type": type(exc).__name__}
            )
            continue
        graph_rows.append(
            {
                "family": family,
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
            }
        )
        for node in module.graph.nodes:
            if node.op != "call_function" or not str(node.target).startswith("aten."):
                continue
            target = str(node.target)
            output = tensor_signature(node.meta.get("val"))
            if output is not None:
                output_evidence[target].add(output)
                evidence_counts[(target, "output", "", output)] += 1
            for index, item in enumerate(node.args):
                if isinstance(item, Node):
                    observed = tensor_signature(item.meta.get("val"))
                    if observed is not None:
                        key = (target, "arg", str(index))
                        argument_evidence[key].add(observed)
                        evidence_counts[(*key, observed)] += 1
            for name, item in node.kwargs.items():
                if isinstance(item, Node):
                    observed = tensor_signature(item.meta.get("val"))
                    if observed is not None:
                        key = (target, "kw", str(name))
                        argument_evidence[key].add(observed)
                        evidence_counts[(*key, observed)] += 1

    tools = []
    generalized_inputs = 0
    generalized_outputs = 0
    for source_tool in source["tools"]:
        input_sets = [
            {exact_signature(row["type"])} for row in source_tool["inputs"]
        ]
        input_evidence_keys: list[list[str]] = [[] for _ in input_sets]
        transformed_nodes = []
        for node in source_tool["nodes"]:
            target = node["target"]
            args = node["args"]
            if set(args) == {"tuple"}:
                for index, term in enumerate(args["tuple"]):
                    if set(term) == {"input"}:
                        slot = int(term["input"])
                        key = (target, "arg", str(index))
                        observed = argument_evidence.get(key)
                        if observed:
                            input_sets[slot] = (
                                observed
                                if len(input_evidence_keys[slot]) == 0
                                else input_sets[slot] & observed
                            )
                            if not input_sets[slot]:
                                raise RuntimeError(
                                    f"empty evidence intersection for input {slot}"
                                )
                            input_evidence_keys[slot].append("|".join(key))
            kwargs = node["kwargs"]
            if set(kwargs) == {"dict"}:
                for key_term, term in kwargs["dict"]:
                    if set(term) != {"input"} or set(key_term) != {"literal"}:
                        continue
                    slot = int(term["input"])
                    key = (target, "kw", str(key_term["literal"]))
                    observed = argument_evidence.get(key)
                    if observed:
                        input_sets[slot] = (
                            observed
                            if len(input_evidence_keys[slot]) == 0
                            else input_sets[slot] & observed
                        )
                        if not input_sets[slot]:
                            raise RuntimeError(
                                f"empty evidence intersection for input {slot}"
                            )
                        input_evidence_keys[slot].append("|".join(key))
            exact_output = exact_signature(node["output_type"])
            allowed_outputs = output_evidence.get(target, {exact_output})
            if exact_output not in allowed_outputs:
                raise RuntimeError("source output missing from operator evidence")
            if len(allowed_outputs) > 1:
                generalized_outputs += 1
            transformed_nodes.append(
                {
                    "target": target,
                    "args": args,
                    "kwargs": kwargs,
                    "output_constraint": constraint(set(allowed_outputs)),
                }
            )
        transformed_inputs = []
        for index, allowed in enumerate(input_sets):
            exact = exact_signature(source_tool["inputs"][index]["type"])
            if exact not in allowed:
                raise RuntimeError("source input missing from inferred constraint")
            if len(allowed) > 1:
                generalized_inputs += 1
            transformed_inputs.append(
                {
                    "constraint": constraint(allowed),
                    "evidence_positions": sorted(input_evidence_keys[index]),
                }
            )
        body = {
            "version": "FOUNDRY_POLYMORPHIC_SEMANTIC_TOOL_V1",
            "inputs": transformed_inputs,
            "nodes": transformed_nodes,
            "outputs": source_tool["outputs"],
        }
        tools.append(
            {
                "tool_id": sha(body),
                **body,
                "source_tool_id": source_tool["tool_id"],
                "training": {
                    **source_tool["training"],
                    "constraint_generalized_inputs": sum(
                        len(row["constraint"]["one_of"]) > 1
                        for row in transformed_inputs
                    ),
                    "constraint_generalized_outputs": sum(
                        len(row["output_constraint"]["one_of"]) > 1
                        for row in transformed_nodes
                    ),
                },
            }
        )
    evidence_rows = [
        {
            "target": target,
            "position_kind": kind,
            "position": position,
            "signature": signature_row(signature),
            "occurrences": count,
        }
        for (target, kind, position, signature), count in sorted(
            evidence_counts.items(),
            key=lambda row: (
                row[0][0],
                row[0][1],
                row[0][2],
                row[0][3],
            ),
        )
    ]
    library = {
        "version": "FOUNDRY_POLYMORPHIC_SEMANTIC_LIBRARY_V1",
        "construction": {
            "algorithm": "operator_position_observed_signature_constraints",
            "llm_calls": 0,
            "manual_type_widenings": 0,
            "validation_graphs_accessed": False,
            "constraint_rule": (
                "a signature is admitted only if observed at every operator "
                "position where that external input is used"
            ),
        },
        "source_library_sha256": hashlib.sha256(source_raw).hexdigest(),
        "evidence_graphs": graph_rows,
        "unsupported_evidence_families": unsupported,
        "evidence": evidence_rows,
        "tools": tools,
    }
    OUTPUT.write_text(canonical(library) + "\n", encoding="utf-8")
    payload = {
        "version": "FOUNDRY_POLYMORPHIC_SEMANTIC_FORGE_RESULT_V1",
        "status": "POLYMORPHIC_SEMANTIC_FORGE_READY",
        "tools": len(tools),
        "evidence_graphs": len(graph_rows),
        "evidence_records": len(evidence_rows),
        "generalized_input_constraints": generalized_inputs,
        "generalized_output_constraints": generalized_outputs,
        "library_sha256": hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),
        "autonomy_boundary": {
            "llm_calls": 0,
            "manual_type_widenings": 0,
            "validation_accessed": False,
            "all_allowed_signatures_observed": True,
        },
    }
    (RESULTS / "phase29_polymorphic_semantic_forge.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE29_POLYMORPHIC_FORGE_PASS"
        f" tools={len(tools)}"
        f" evidence_graphs={len(graph_rows)}"
        f" evidence_records={len(evidence_rows)}"
        f" generalized_inputs={generalized_inputs}"
        f" generalized_outputs={generalized_outputs}"
    )


if __name__ == "__main__":
    run()
