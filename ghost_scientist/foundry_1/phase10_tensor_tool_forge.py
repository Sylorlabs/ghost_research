#!/usr/bin/env python3
"""Phase 10: mine executable typed tensor tools from calibration-only pairs.

The forge is deliberately LLM-free.  It receives measured source/plan pairs,
abstracts artifact-specific names and constants into typed bindings, groups
identical transformations, and emits only transformations with repeated
positive support.  Applying the emitted tools does not require the legacy
rewrite enumerator.
"""

from __future__ import annotations

import collections
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

from ghost_operator_core_v5 import canonical_json, load_artifact, sha256_json  # noqa: E402
from ghost_operator_synthesis_v5 import enumerate_plans  # noqa: E402


TOOL_VERSION = "FOUNDRY_TYPED_TENSOR_TOOL_V1"
LIBRARY_VERSION = "FOUNDRY_TYPED_TENSOR_LIBRARY_V1"
MIN_SUPPORT = 2
MIN_RELATIVE_IMPROVEMENT = 0.001
TRAINING_PHASES = (
    ("development_corpus", "development_outcomes_v5.jsonl"),
    ("validation_corpus", "validation_outcomes_v5.jsonl"),
)


def exact_keys(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError(f"{context} fields differ")
    return value


def constant_descriptor(value: object) -> dict[str, object]:
    if isinstance(value, list):
        return {
            "kind": "list",
            "length": len(value),
            "element_kinds": sorted({type(item).__name__ for item in value}),
        }
    return {"kind": type(value).__name__}


def binding_maps(artifact) -> tuple[dict[str, int], dict[str, int], dict[str, int]]:
    return (
        {item.name: index for index, item in enumerate(artifact.inputs)},
        {item.name: index for index, item in enumerate(artifact.parameters)},
        {name: index for index, name in enumerate(sorted(artifact.constants))},
    )


def encode_attr(
    key: str,
    value: object,
    artifact,
    *,
    allow_value_bindings: bool,
    allow_symbolic_numbers: bool = False,
) -> object:
    input_slots, parameter_slots, constant_slots = binding_maps(artifact)
    if allow_value_bindings and key == "name":
        if value in input_slots:
            return {"binding": "input", "slot": input_slots[value]}
        if value in parameter_slots:
            return {"binding": "parameter", "slot": parameter_slots[value]}
        if isinstance(value, str) and value.startswith("d") and value[1:].isdigit():
            return {"binding": "derived", "slot": int(value[1:])}
        raise ValueError(f"unbound value name: {value!r}")
    if key.endswith("_constant"):
        if value not in constant_slots:
            raise ValueError(f"unbound constant: {value!r}")
        return {
            "binding": "constant",
            "slot": constant_slots[value],
            "descriptor": constant_descriptor(artifact.constants[value]),
        }
    if allow_symbolic_numbers and type(value) in (int, float):
        expressions = []
        constant_names = sorted(artifact.constants)
        for slot, name in enumerate(constant_names):
            constant = artifact.constants[name]
            if type(constant) in (int, float) and constant == value:
                expressions.append(
                    (1, slot, -1, {"op": "constant", "slot": slot})
                )
            if isinstance(constant, list) and all(
                type(item) in (int, float) for item in constant
            ):
                for index, item in enumerate(constant):
                    if item == value:
                        expressions.append(
                            (
                                2,
                                slot,
                                index,
                                {"op": "constant_item", "slot": slot, "index": index},
                            )
                        )
                if sum(constant) == value:
                    expressions.append(
                        (3, slot, -1, {"op": "constant_sum", "slot": slot})
                    )
                for index, item in enumerate(constant):
                    if sum(constant) - item == value:
                        expressions.append(
                            (
                                4,
                                slot,
                                index,
                                {
                                    "op": "constant_sum_minus_item",
                                    "slot": slot,
                                    "index": index,
                                },
                            )
                        )
        if expressions:
            return {"expression": min(expressions, key=lambda item: item[:3])[3]}
    return {"literal": value}


def encode_source(artifact) -> dict[str, object]:
    nodes = artifact.reference_program["nodes"]
    node_slots = {node["id"]: index for index, node in enumerate(nodes)}
    return {
        "nodes": [
            {
                "op": node["op"],
                "args": [node_slots[arg] for arg in node["args"]],
                "attrs": {
                    key: encode_attr(
                        key,
                        value,
                        artifact,
                        allow_value_bindings=True,
                    )
                    for key, value in sorted(node["attrs"].items())
                },
            }
            for node in nodes
        ],
        "outputs": [node_slots[item] for item in artifact.reference_program["outputs"]],
        "input_types": [
            {
                "rank": len(item.type.shape),
                "dtype": item.type.dtype,
                "storage": item.type.storage,
            }
            for item in artifact.inputs
        ],
        "parameter_types": [
            {
                "rank": len(item.type.shape),
                "dtype": item.type.dtype,
                "storage": item.type.storage,
            }
            for item in artifact.parameters
        ],
    }


def encode_parameter_arg(
    value: str, artifact, derived_slots: dict[str, int]
) -> dict[str, object]:
    parameter_slots = binding_maps(artifact)[1]
    if value in parameter_slots:
        return {"binding": "parameter", "slot": parameter_slots[value]}
    if value in derived_slots:
        return {"binding": "derived", "slot": derived_slots[value]}
    raise ValueError(f"unbound parameter-program argument: {value}")


def encode_expansion(plan: dict[str, Any], artifact) -> dict[str, object]:
    parameter_nodes = plan["parameter_program"]["nodes"]
    derived_slots = {node["id"]: index for index, node in enumerate(parameter_nodes)}
    runtime_nodes = plan["program"]["nodes"]
    runtime_slots = {node["id"]: index for index, node in enumerate(runtime_nodes)}
    return {
        "parameter_nodes": [
            {
                "op": node["op"],
                "args": [
                    encode_parameter_arg(arg, artifact, derived_slots)
                    for arg in node["args"]
                ],
                "attrs": {
                    key: encode_attr(
                        key,
                        value,
                        artifact,
                        allow_value_bindings=False,
                        allow_symbolic_numbers=True,
                    )
                    for key, value in sorted(node["attrs"].items())
                },
            }
            for node in parameter_nodes
        ],
        "runtime_nodes": [
            {
                "op": node["op"],
                "args": [runtime_slots[arg] for arg in node["args"]],
                "attrs": {
                    key: encode_attr(
                        key,
                        value,
                        artifact,
                        allow_value_bindings=True,
                    )
                    for key, value in sorted(node["attrs"].items())
                },
            }
            for node in runtime_nodes
        ],
        "outputs": [runtime_slots[item] for item in plan["program"]["outputs"]],
    }


def load_rows(path: pathlib.Path) -> dict[str, dict[int, dict[str, Any]]]:
    rows: dict[str, dict[int, dict[str, Any]]] = collections.defaultdict(dict)
    for line in path.read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        rows[row["opaque_id"]][int(row["plan_index"])] = row
    return rows


def sha_file(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run() -> None:
    from freeze_foundry_1 import verify

    verify()
    groups: dict[str, dict[str, Any]] = {}
    source_receipts = []
    eligible_pairs = 0
    for corpus_name, outcomes_name in TRAINING_PHASES:
        corpus = V5 / "results" / corpus_name / "artifacts"
        outcomes_path = V5 / "results" / outcomes_name
        rows = load_rows(outcomes_path)
        source_receipts.append(
            {
                "corpus": corpus_name,
                "outcomes": outcomes_name,
                "outcomes_sha256": sha_file(outcomes_path),
            }
        )
        for artifact_path in sorted(corpus.glob("*.json")):
            artifact, raw = load_artifact(artifact_path)
            if artifact.opaque_id not in rows:
                continue
            plans = enumerate_plans(artifact)
            artifact_rows = rows[artifact.opaque_id]
            if set(artifact_rows) != set(range(len(plans))):
                raise RuntimeError(f"incomplete measured plan set for {artifact.opaque_id}")
            reference_score = float(artifact_rows[0]["score"])
            for index, plan in enumerate(plans[1:], 1):
                row = artifact_rows[index]
                score = float(row["score"])
                improvement = reference_score / score - 1.0
                if (
                    row["measurement_status"] != "MEASURED"
                    or not row["numerically_valid"]
                    or improvement < MIN_RELATIVE_IMPROVEMENT
                ):
                    continue
                eligible_pairs += 1
                source = encode_source(artifact)
                expansion = encode_expansion(dict(plan), artifact)
                key = sha256_json({"match": source, "expansion": expansion})
                record = groups.setdefault(
                    key,
                    {
                        "match": source,
                        "expansion": expansion,
                        "support": [],
                    },
                )
                record["support"].append(
                    {
                        "opaque_id": artifact.opaque_id,
                        "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                        "plan_index": index,
                        "plan_sha256": sha256_json(plan),
                        "reference_score": reference_score,
                        "candidate_score": score,
                        "relative_improvement": improvement,
                    }
                )

    tools = []
    for key, group in sorted(groups.items()):
        support = group["support"]
        if len(support) < MIN_SUPPORT:
            continue
        geometric_improvement = (
            math.exp(
                sum(math.log1p(item["relative_improvement"]) for item in support)
                / len(support)
            )
            - 1.0
        )
        body = {
            "version": TOOL_VERSION,
            "match": group["match"],
            "expansion": group["expansion"],
        }
        tool_id = hashlib.sha256(canonical_json(body).encode()).hexdigest()
        tools.append(
            {
                **body,
                "tool_id": tool_id,
                "training": {
                    "support_count": len(support),
                    "geometric_relative_improvement": geometric_improvement,
                    "receipts": support,
                },
            }
        )

    if not tools:
        raise RuntimeError("forge produced no repeatedly supported typed tools")
    library = {
        "version": LIBRARY_VERSION,
        "construction": {
            "algorithm": "deterministic_name_abstracted_source_target_clustering",
            "llm_calls": 0,
            "minimum_support": MIN_SUPPORT,
            "minimum_relative_improvement": MIN_RELATIVE_IMPROVEMENT,
            "answer_blind_to_reserved_artifacts": True,
            "legacy_enumerator_used_only_to_reconstruct_measured_training_pairs": True,
        },
        "sources": source_receipts,
        "tools": tools,
    }
    library_sha = sha256_json(library)
    output = RESULTS / "forged_tensor_tools.json"
    output.write_text(canonical_json(library) + "\n", encoding="utf-8")
    result = {
        "version": "FOUNDRY_TENSOR_FORGE_RESULT_V1",
        "status": "TENSOR_FORGE_COMPONENT_READY",
        "library_sha256": library_sha,
        "library_file_sha256": sha_file(output),
        "eligible_training_pairs": eligible_pairs,
        "candidate_clusters": len(groups),
        "tools_forged": len(tools),
        "support_total": sum(item["training"]["support_count"] for item in tools),
        "limits": [
            "training transformations were reconstructed from the legacy evaluator candidate space",
            "the forge constructs reusable tool records but does not invent primitive tensor operations",
            "reserved validation, native deduplication, and resource accounting are separate phases",
        ],
    }
    (RESULTS / "phase10_tensor_forge.json").write_text(
        canonical_json(result) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE10_TENSOR_FORGE_PASS"
        f" eligible_pairs={eligible_pairs}"
        f" clusters={len(groups)}"
        f" tools={len(tools)}"
        f" support={result['support_total']}"
    )


if __name__ == "__main__":
    run()
