#!/usr/bin/env python3
"""Independent parser, interpreter, and validator for forged tensor tools.

This module intentionally does not import the phase-10 forge or the legacy
rewrite enumerator.  It reconstructs the tool contract from the serialized
library, applies matching tools, passes every expansion through the evaluator's
whole-program type checker, and executes reference/candidate programs.
"""

from __future__ import annotations

import copy
import hashlib
import json
import math
import pathlib
import sys
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
V5 = ROOT / "ghost_scientist/operator_v5"
RESULTS = HERE / "results"
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import (  # noqa: E402
    PLAN_VERSION,
    TensorProgramModule,
    canonical_json,
    load_artifact,
    load_plan_text,
    materialize_inputs,
    reference_plan,
)


class ToolContractError(ValueError):
    pass


def exact(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ToolContractError(f"{context} fields are not exact")
    return value


def bounded_int(value: object, context: str, *, upper: int = 256) -> int:
    if type(value) is not int or not 0 <= value < upper:
        raise ToolContractError(f"{context} is outside bounds")
    return value


def json_literal(value: object, context: str) -> None:
    if value is None or type(value) in (bool, int, float, str):
        if isinstance(value, float) and not math.isfinite(value):
            raise ToolContractError(f"{context} is non-finite")
        return
    if isinstance(value, list) and len(value) <= 128:
        for index, item in enumerate(value):
            json_literal(item, f"{context}[{index}]")
        return
    raise ToolContractError(f"{context} is not a bounded literal")


def descriptor(value: object, context: str) -> None:
    if not isinstance(value, dict):
        raise ToolContractError(f"{context} descriptor is not an object")
    if value.get("kind") == "list":
        item = exact(value, {"kind", "length", "element_kinds"}, context)
        bounded_int(item["length"], f"{context} length", upper=129)
        if (
            not isinstance(item["element_kinds"], list)
            or not item["element_kinds"]
            or len(item["element_kinds"]) > 8
            or any(
                value not in {"bool", "float", "int", "str"}
                for value in item["element_kinds"]
            )
        ):
            raise ToolContractError(f"{context} element kinds are invalid")
    else:
        item = exact(value, {"kind"}, context)
        if item["kind"] not in {"bool", "float", "int", "str", "NoneType"}:
            raise ToolContractError(f"{context} kind is invalid")


def binding(value: object, context: str, allowed: set[str]) -> None:
    if not isinstance(value, dict) or value.get("binding") not in allowed:
        raise ToolContractError(f"{context} binding kind is invalid")
    kind = value["binding"]
    if kind == "constant":
        item = exact(value, {"binding", "slot", "descriptor"}, context)
        descriptor(item["descriptor"], f"{context} descriptor")
    else:
        item = exact(value, {"binding", "slot"}, context)
    bounded_int(item["slot"], f"{context} slot")


def expression(value: object, context: str) -> None:
    if not isinstance(value, dict):
        raise ToolContractError(f"{context} expression is not an object")
    op = value.get("op")
    if op in {"constant", "constant_sum"}:
        item = exact(value, {"op", "slot"}, context)
    elif op in {"constant_item", "constant_sum_minus_item"}:
        item = exact(value, {"op", "slot", "index"}, context)
        bounded_int(item["index"], f"{context} index", upper=128)
    else:
        raise ToolContractError(f"{context} expression op is invalid")
    bounded_int(item["slot"], f"{context} slot", upper=128)


def attr_spec(
    value: object,
    context: str,
    *,
    allowed_bindings: set[str],
    allow_expression: bool,
) -> None:
    if not isinstance(value, dict):
        raise ToolContractError(f"{context} attr spec is not an object")
    if set(value) == {"literal"}:
        json_literal(value["literal"], f"{context} literal")
    elif set(value) == {"binding"} | (
        {"slot", "descriptor"} if value.get("binding") == "constant" else {"slot"}
    ):
        binding(value, context, allowed_bindings)
    elif set(value) == {"expression"} and allow_expression:
        expression(value["expression"], f"{context} expression")
    else:
        raise ToolContractError(f"{context} attr spec is invalid")


def type_pattern(value: object, context: str) -> None:
    item = exact(value, {"rank", "dtype", "storage"}, context)
    if type(item["rank"]) is not int or not 1 <= item["rank"] <= 6:
        raise ToolContractError(f"{context} rank is invalid")
    if item["dtype"] not in {"float32", "float64"}:
        raise ToolContractError(f"{context} dtype is invalid")
    if item["storage"] not in {"strided", "sparse_csr"}:
        raise ToolContractError(f"{context} storage is invalid")


def graph_node(
    value: object,
    index: int,
    context: str,
    *,
    parameter_node: bool,
) -> None:
    item = exact(value, {"op", "args", "attrs"}, context)
    if not isinstance(item["op"], str) or not item["op"] or len(item["op"]) > 64:
        raise ToolContractError(f"{context} op is invalid")
    if not isinstance(item["args"], list) or len(item["args"]) > 16:
        raise ToolContractError(f"{context} args are invalid")
    if parameter_node:
        for number, arg in enumerate(item["args"]):
            binding(
                arg,
                f"{context} arg {number}",
                {"parameter", "derived"},
            )
            if arg["binding"] == "derived" and arg["slot"] >= index:
                raise ToolContractError(f"{context} has forward derived reference")
    else:
        for number, arg in enumerate(item["args"]):
            if type(arg) is not int or not 0 <= arg < index:
                raise ToolContractError(f"{context} arg {number} is forward")
    if not isinstance(item["attrs"], dict) or len(item["attrs"]) > 16:
        raise ToolContractError(f"{context} attrs are invalid")
    for key, spec in item["attrs"].items():
        if not isinstance(key, str) or not key:
            raise ToolContractError(f"{context} attr key is invalid")
        attr_spec(
            spec,
            f"{context} attr {key}",
            allowed_bindings={"input", "parameter", "derived", "constant"},
            allow_expression=parameter_node,
        )


def match_contract(value: object) -> None:
    item = exact(
        value,
        {"nodes", "outputs", "input_types", "parameter_types"},
        "match",
    )
    if not isinstance(item["nodes"], list) or not 1 <= len(item["nodes"]) <= 256:
        raise ToolContractError("match node count is invalid")
    for index, node in enumerate(item["nodes"]):
        graph_node(node, index, f"match node {index}", parameter_node=False)
    if (
        not isinstance(item["outputs"], list)
        or not item["outputs"]
        or any(type(value) is not int or not 0 <= value < len(item["nodes"]) for value in item["outputs"])
    ):
        raise ToolContractError("match outputs are invalid")
    for kind in ("input_types", "parameter_types"):
        if not isinstance(item[kind], list) or len(item[kind]) > 64:
            raise ToolContractError(f"match {kind} are invalid")
        for index, value in enumerate(item[kind]):
            type_pattern(value, f"match {kind} {index}")


def expansion_contract(value: object) -> None:
    item = exact(value, {"parameter_nodes", "runtime_nodes", "outputs"}, "expansion")
    if not isinstance(item["parameter_nodes"], list) or len(item["parameter_nodes"]) > 256:
        raise ToolContractError("expansion parameter nodes are invalid")
    for index, node in enumerate(item["parameter_nodes"]):
        graph_node(node, index, f"parameter node {index}", parameter_node=True)
    if not isinstance(item["runtime_nodes"], list) or not 1 <= len(item["runtime_nodes"]) <= 256:
        raise ToolContractError("expansion runtime nodes are invalid")
    for index, node in enumerate(item["runtime_nodes"]):
        graph_node(node, index, f"runtime node {index}", parameter_node=False)
    if (
        not isinstance(item["outputs"], list)
        or not item["outputs"]
        or any(type(value) is not int or not 0 <= value < len(item["runtime_nodes"]) for value in item["outputs"])
    ):
        raise ToolContractError("expansion outputs are invalid")


def training_contract(value: object) -> None:
    item = exact(
        value,
        {"support_count", "geometric_relative_improvement", "receipts"},
        "training",
    )
    if type(item["support_count"]) is not int or item["support_count"] < 2:
        raise ToolContractError("training support is invalid")
    if type(item["geometric_relative_improvement"]) not in (int, float) or not (
        0.0 < float(item["geometric_relative_improvement"]) < 1_000_000.0
    ):
        raise ToolContractError("training improvement is invalid")
    if not isinstance(item["receipts"], list) or len(item["receipts"]) != item["support_count"]:
        raise ToolContractError("training receipts do not match support")
    receipt_keys = {
        "opaque_id",
        "artifact_sha256",
        "plan_index",
        "plan_sha256",
        "reference_score",
        "candidate_score",
        "relative_improvement",
    }
    for index, receipt in enumerate(item["receipts"]):
        row = exact(receipt, receipt_keys, f"training receipt {index}")
        if (
            not isinstance(row["opaque_id"], str)
            or type(row["plan_index"]) is not int
            or row["plan_index"] <= 0
            or any(
                not isinstance(row[key], str) or len(row[key]) != 64
                for key in ("artifact_sha256", "plan_sha256")
            )
            or any(
                type(row[key]) not in (int, float) or float(row[key]) <= 0.0
                for key in ("reference_score", "candidate_score", "relative_improvement")
            )
        ):
            raise ToolContractError(f"training receipt {index} is invalid")


def parse_library_bytes(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ToolContractError("library is not JSON") from exc
    root = exact(value, {"version", "construction", "sources", "tools"}, "library")
    if root["version"] != "FOUNDRY_TYPED_TENSOR_LIBRARY_V1":
        raise ToolContractError("library version mismatch")
    exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "minimum_support",
            "minimum_relative_improvement",
            "answer_blind_to_reserved_artifacts",
            "legacy_enumerator_used_only_to_reconstruct_measured_training_pairs",
        },
        "construction",
    )
    if (
        root["construction"]["llm_calls"] != 0
        or root["construction"]["answer_blind_to_reserved_artifacts"] is not True
        or root["construction"]["minimum_support"] < 2
    ):
        raise ToolContractError("construction policy mismatch")
    if not isinstance(root["sources"], list) or not root["sources"]:
        raise ToolContractError("library sources are missing")
    for index, source in enumerate(root["sources"]):
        item = exact(source, {"corpus", "outcomes", "outcomes_sha256"}, f"source {index}")
        if (
            not isinstance(item["corpus"], str)
            or not isinstance(item["outcomes"], str)
            or not isinstance(item["outcomes_sha256"], str)
            or len(item["outcomes_sha256"]) != 64
        ):
            raise ToolContractError(f"source {index} is invalid")
    if not isinstance(root["tools"], list) or not 1 <= len(root["tools"]) <= 64:
        raise ToolContractError("tool count is invalid")
    seen = set()
    for index, tool in enumerate(root["tools"]):
        item = exact(
            tool,
            {"version", "tool_id", "match", "expansion", "training"},
            f"tool {index}",
        )
        if item["version"] != "FOUNDRY_TYPED_TENSOR_TOOL_V1":
            raise ToolContractError(f"tool {index} version mismatch")
        match_contract(item["match"])
        expansion_contract(item["expansion"])
        training_contract(item["training"])
        body = {
            "version": item["version"],
            "match": item["match"],
            "expansion": item["expansion"],
        }
        digest = hashlib.sha256(canonical_json(body).encode()).hexdigest()
        if item["tool_id"] != digest or digest in seen:
            raise ToolContractError(f"tool {index} digest is invalid or duplicated")
        seen.add(digest)
    return root


def value_descriptor(value: object) -> dict[str, object]:
    if isinstance(value, list):
        return {
            "kind": "list",
            "length": len(value),
            "element_kinds": sorted({type(item).__name__ for item in value}),
        }
    return {"kind": type(value).__name__}


def type_matches(pattern: dict[str, Any], value) -> bool:
    return (
        pattern["rank"] == len(value.type.shape)
        and pattern["dtype"] == value.type.dtype
        and pattern["storage"] == value.type.storage
    )


def resolve_match_attr(spec: dict[str, Any], artifact) -> object:
    if "literal" in spec:
        return spec["literal"]
    kind, slot = spec["binding"], spec["slot"]
    if kind == "input":
        return artifact.inputs[slot].name if slot < len(artifact.inputs) else object()
    if kind == "parameter":
        return artifact.parameters[slot].name if slot < len(artifact.parameters) else object()
    if kind == "constant":
        names = sorted(artifact.constants)
        if slot >= len(names):
            return object()
        name = names[slot]
        if value_descriptor(artifact.constants[name]) != spec["descriptor"]:
            return object()
        return name
    return object()


def tool_matches(tool: dict[str, Any], artifact) -> bool:
    pattern = tool["match"]
    if (
        len(pattern["input_types"]) != len(artifact.inputs)
        or len(pattern["parameter_types"]) != len(artifact.parameters)
        or any(
            not type_matches(item, value)
            for item, value in zip(pattern["input_types"], artifact.inputs)
        )
        or any(
            not type_matches(item, value)
            for item, value in zip(pattern["parameter_types"], artifact.parameters)
        )
    ):
        return False
    source = artifact.reference_program
    nodes = source["nodes"]
    source_slots = {node["id"]: index for index, node in enumerate(nodes)}
    if len(nodes) != len(pattern["nodes"]):
        return False
    for index, (actual, expected) in enumerate(zip(nodes, pattern["nodes"])):
        if (
            actual["op"] != expected["op"]
            or [source_slots[arg] for arg in actual["args"]] != expected["args"]
            or set(actual["attrs"]) != set(expected["attrs"])
        ):
            return False
        for key, spec in expected["attrs"].items():
            if actual["attrs"][key] != resolve_match_attr(spec, artifact):
                return False
    return [source_slots[item] for item in source["outputs"]] == pattern["outputs"]


def eval_expression(spec: dict[str, Any], artifact) -> object:
    names = sorted(artifact.constants)
    if spec["slot"] >= len(names):
        raise ToolContractError("expression constant slot is unavailable")
    value = artifact.constants[names[spec["slot"]]]
    op = spec["op"]
    if op == "constant":
        if type(value) not in (int, float):
            raise ToolContractError("constant expression is not numeric")
        return value
    if not isinstance(value, list) or not all(type(item) in (int, float) for item in value):
        raise ToolContractError("list expression source is not numeric")
    if op == "constant_sum":
        return sum(value)
    if spec["index"] >= len(value):
        raise ToolContractError("expression index is unavailable")
    if op == "constant_item":
        return value[spec["index"]]
    if op == "constant_sum_minus_item":
        return sum(value) - value[spec["index"]]
    raise ToolContractError("unreachable expression")


def resolve_expansion_attr(spec: dict[str, Any], artifact) -> object:
    if "literal" in spec:
        return spec["literal"]
    if "expression" in spec:
        return eval_expression(spec["expression"], artifact)
    kind, slot = spec["binding"], spec["slot"]
    if kind == "input":
        values = [item.name for item in artifact.inputs]
    elif kind == "parameter":
        values = [item.name for item in artifact.parameters]
    elif kind == "constant":
        values = sorted(artifact.constants)
        if slot < len(values) and value_descriptor(artifact.constants[values[slot]]) != spec["descriptor"]:
            raise ToolContractError("constant descriptor changed during expansion")
    elif kind == "derived":
        return f"d{slot}"
    else:
        raise ToolContractError("unknown expansion binding")
    if slot >= len(values):
        raise ToolContractError("expansion binding slot is unavailable")
    return values[slot]


def render_plan(tool: dict[str, Any], artifact) -> dict[str, object]:
    expansion = tool["expansion"]
    parameter_nodes = []
    for index, node in enumerate(expansion["parameter_nodes"]):
        args = []
        for arg in node["args"]:
            if arg["binding"] == "parameter":
                if arg["slot"] >= len(artifact.parameters):
                    raise ToolContractError("parameter arg slot is unavailable")
                args.append(artifact.parameters[arg["slot"]].name)
            else:
                args.append(f"d{arg['slot']}")
        parameter_nodes.append(
            {
                "id": f"d{index}",
                "op": node["op"],
                "args": args,
                "attrs": {
                    key: resolve_expansion_attr(spec, artifact)
                    for key, spec in node["attrs"].items()
                },
            }
        )
    runtime_nodes = [
        {
            "id": f"r{index}",
            "op": node["op"],
            "args": [f"r{slot}" for slot in node["args"]],
            "attrs": {
                key: resolve_expansion_attr(spec, artifact)
                for key, spec in node["attrs"].items()
            },
        }
        for index, node in enumerate(expansion["runtime_nodes"])
    ]
    raw = {
        "version": PLAN_VERSION,
        "parameter_program": {"nodes": parameter_nodes},
        "program": {
            "nodes": runtime_nodes,
            "outputs": [f"r{slot}" for slot in expansion["outputs"]],
        },
    }
    return dict(load_plan_text(canonical_json(raw), artifact))


def max_error(reference, candidate) -> float:
    import torch

    refs = reference if isinstance(reference, tuple) else (reference,)
    cands = candidate if isinstance(candidate, tuple) else (candidate,)
    if len(refs) != len(cands):
        return math.inf
    return max(
        float(torch.max(torch.abs(left - right)).item())
        for left, right in zip(refs, cands)
    )


def hostile_tests(raw: bytes) -> list[str]:
    source = json.loads(raw)
    mutations = []
    extra = copy.deepcopy(source)
    extra["tools"][0]["unexpected"] = True
    mutations.append(("extra_tool_field", extra))
    digest = copy.deepcopy(source)
    digest["tools"][0]["tool_id"] = "0" * 64
    mutations.append(("wrong_digest", digest))
    forward = copy.deepcopy(source)
    forward["tools"][0]["expansion"]["runtime_nodes"][0]["args"] = [0]
    mutations.append(("forward_runtime_reference", forward))
    bad_expression = copy.deepcopy(source)
    target = bad_expression["tools"][0]["expansion"]["parameter_nodes"]
    if target:
        target[0]["attrs"]["injected"] = {"expression": {"op": "network", "slot": 0}}
    else:
        bad_expression["tools"][0]["expansion"]["runtime_nodes"][0]["attrs"]["injected"] = {
            "expression": {"op": "network", "slot": 0}
        }
    mutations.append(("unknown_expression", bad_expression))
    rejected = []
    for name, mutation in mutations:
        try:
            parse_library_bytes(canonical_json(mutation).encode())
        except ToolContractError:
            rejected.append(name)
        else:
            raise RuntimeError(f"hostile mutation accepted: {name}")
    return rejected


def run() -> None:
    from freeze_foundry_1 import verify

    verify()
    library_path = RESULTS / "forged_tensor_tools.json"
    raw = library_path.read_bytes()
    library = parse_library_bytes(raw)
    hostile = hostile_tests(raw)
    rows = []
    maximum_error = 0.0
    match_counts = {tool["tool_id"]: 0 for tool in library["tools"]}
    for corpus_name in ("prefreeze_corpus", "confirmation_corpus"):
        artifact_dir = V5 / "results" / corpus_name / "artifacts"
        for artifact_path in sorted(artifact_dir.glob("*.json")):
            artifact, artifact_raw = load_artifact(artifact_path)
            for tool in library["tools"]:
                if not tool_matches(tool, artifact):
                    continue
                plan = render_plan(tool, artifact)
                inputs = materialize_inputs(artifact)
                reference, _ = TensorProgramModule.build(artifact, reference_plan(artifact))
                candidate, _ = TensorProgramModule.build(artifact, plan)
                reference_value = reference(*inputs)
                candidate_value = candidate(*inputs)
                error = max_error(reference_value, candidate_value)
                if not math.isfinite(error) or error > 1.0e-5:
                    raise RuntimeError(
                        f"tool {tool['tool_id']} failed {artifact.opaque_id}: {error}"
                    )
                maximum_error = max(maximum_error, error)
                match_counts[tool["tool_id"]] += 1
                rows.append(
                    {
                        "corpus": corpus_name,
                        "opaque_id": artifact.opaque_id,
                        "artifact_sha256": hashlib.sha256(artifact_raw).hexdigest(),
                        "tool_id": tool["tool_id"],
                        "plan_sha256": hashlib.sha256(
                            canonical_json(plan).encode()
                        ).hexdigest(),
                        "max_abs_error": error,
                        "typed_validation": True,
                        "executed": True,
                    }
                )
    if any(count == 0 for count in match_counts.values()):
        raise RuntimeError(f"one or more forged tools did not transfer: {match_counts}")
    payload = {
        "version": "FOUNDRY_INDEPENDENT_TENSOR_TOOL_EVAL_V1",
        "status": "INDEPENDENT_TENSOR_TOOL_EVAL_PASS",
        "library_file_sha256": hashlib.sha256(raw).hexdigest(),
        "tools": len(library["tools"]),
        "reserved_artifacts_scanned": sum(
            len(list((V5 / "results" / name / "artifacts").glob("*.json")))
            for name in ("prefreeze_corpus", "confirmation_corpus")
        ),
        "successful_transfers": len(rows),
        "match_counts": match_counts,
        "maximum_abs_error": maximum_error,
        "hostile_rejections": hostile,
        "causal_removal": {
            "with_library_nonreference_plans": len(rows),
            "without_library_nonreference_plans": 0,
            "losses": len(rows),
        },
        "rows": rows,
        "limits": [
            "reserved artifacts are historical calibration-only data, not a new prospective trial",
            "numerical equivalence and transfer do not prove performance improvement on reserved artifacts",
            "the core tensor type checker and executor are reused, while tool parsing and interpretation are independent",
        ],
    }
    (RESULTS / "phase11_independent_tensor_eval.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE11_INDEPENDENT_TENSOR_EVAL_PASS"
        f" tools={payload['tools']}"
        f" transfers={payload['successful_transfers']}"
        f" hostile={len(hostile)}"
        f" max_error={maximum_error:.9g}"
    )


if __name__ == "__main__":
    run()
