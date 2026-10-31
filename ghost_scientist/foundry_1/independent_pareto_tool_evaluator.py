#!/usr/bin/env python3
"""Strict parser for Pareto tools using the independent typed interpreter."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
from typing import Any

from independent_diversity_tool_evaluator import (
    ContractError,
    canonical,
    exact,
    execute_tool,
    hostile_tests as _unused_hostile_tests,
    max_error,
    node_type,
    parse_term,
    parse_type,
    semantic_matches,
    CapturingInterpreter,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY = RESULTS / "forged_pareto_tools.json"


def parse_library(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("Pareto library is not JSON") from exc
    root = exact(
        value,
        {
            "version",
            "construction",
            "pool_sha256",
            "fixed_portfolio_sha256",
            "selected_metrics",
            "tools",
        },
        "Pareto library",
    )
    if root["version"] != "FOUNDRY_PARETO_TOOL_LIBRARY_V1":
        raise ContractError("Pareto library version invalid")
    construction = exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "supplied_tool_forms",
            "candidate_subsets",
            "frontier_portfolios",
            "benefit_dimensions",
            "cost_dimensions",
            "utopia_weights",
            "validation_v6_accessed",
        },
        "Pareto construction",
    )
    if (
        construction["algorithm"]
        != "exhaustive_nonempty_subset_pareto_utopia"
        or construction["llm_calls"] != 0
        or construction["supplied_tool_forms"] != 0
        or construction["candidate_subsets"] != 1023
        or construction["frontier_portfolios"] <= 0
        or construction["validation_v6_accessed"] is not False
        or construction["benefit_dimensions"]
        != [
            "unique_nodes",
            "families",
            "repositories",
            "semantic_domains",
        ]
        or construction["cost_dimensions"]
        != [
            "shared_construction_cost",
            "definition_cost",
            "graph_node_visits",
            "edge_checks",
        ]
        or set(construction["utopia_weights"])
        != {
            "unique_nodes",
            "families",
            "repositories",
            "semantic_domains",
            "inverse_total_cost",
        }
        or any(value != 1 for value in construction["utopia_weights"].values())
    ):
        raise ContractError("Pareto construction boundary invalid")
    metrics = exact(
        root["selected_metrics"],
        {
            "tool_ids",
            "tools",
            "unique_nodes",
            "families",
            "repositories",
            "semantic_domains",
            "definition_cost",
            "graph_node_visits",
            "edge_checks",
            "shared_construction_cost",
            "total_cost",
            "utopia_score",
        },
        "selected metrics",
    )
    if (
        not isinstance(metrics["tool_ids"], list)
        or metrics["tools"] != len(metrics["tool_ids"])
        or metrics["tools"] <= 0
        or metrics["total_cost"]
        != metrics["shared_construction_cost"]
        + metrics["definition_cost"]
        + metrics["graph_node_visits"]
        + metrics["edge_checks"]
        or not 0.0 <= metrics["utopia_score"] <= 1.0
    ):
        raise ContractError("selected metrics invalid")
    if not isinstance(root["tools"], list) or len(root["tools"]) != metrics["tools"]:
        raise ContractError("selected tool count invalid")
    seen = set()
    for tool_index, tool in enumerate(root["tools"]):
        row = exact(
            tool,
            {"tool_id", "version", "inputs", "nodes", "outputs", "training"},
            f"Pareto tool {tool_index}",
        )
        if row["version"] != "FOUNDRY_PARETO_TOOL_V1":
            raise ContractError(f"Pareto tool {tool_index} version invalid")
        if not isinstance(row["inputs"], list):
            raise ContractError(f"Pareto tool {tool_index} inputs invalid")
        for index, input_row in enumerate(row["inputs"]):
            item = exact(
                input_row, {"type"}, f"Pareto tool {tool_index} input {index}"
            )
            parse_type(
                item["type"], f"Pareto tool {tool_index} input {index} type"
            )
        if not isinstance(row["nodes"], list) or not 2 <= len(row["nodes"]) <= 4:
            raise ContractError(f"Pareto tool {tool_index} nodes invalid")
        for index, node in enumerate(row["nodes"]):
            item = exact(
                node,
                {"target", "args", "kwargs", "output_type"},
                f"Pareto tool {tool_index} node {index}",
            )
            if (
                not isinstance(item["target"], str)
                or not item["target"].startswith("aten.")
                or len(item["target"]) > 128
            ):
                raise ContractError(f"Pareto tool {tool_index} target invalid")
            parse_term(
                item["args"],
                len(row["inputs"]),
                index,
                f"Pareto tool {tool_index} args {index}",
            )
            parse_term(
                item["kwargs"],
                len(row["inputs"]),
                index,
                f"Pareto tool {tool_index} kwargs {index}",
            )
            parse_type(
                item["output_type"],
                f"Pareto tool {tool_index} output {index}",
            )
        if row["outputs"] != [{"node": len(row["nodes"]) - 1}]:
            raise ContractError(f"Pareto tool {tool_index} outputs invalid")
        training = exact(
            row["training"],
            {
                "occurrence_count",
                "family_count",
                "repository_count",
                "semantic_domain_count",
                "suite_count",
                "structural_units",
                "raw_cost",
                "tool_cost",
                "description_length_gain",
                "fixed_target_sequence_duplicate",
                "fixed_name",
                "families",
                "repositories",
                "semantic_domains",
                "suites",
                "occurrences",
            },
            f"Pareto tool {tool_index} training",
        )
        if (
            training["family_count"] < 2
            or training["repository_count"] < 2
            or training["occurrence_count"] != len(training["occurrences"])
            or training["family_count"] != len(training["families"])
            or training["repository_count"] != len(training["repositories"])
            or training["semantic_domain_count"]
            != len(training["semantic_domains"])
            or training["suite_count"] != len(training["suites"])
            or training["raw_cost"] - training["tool_cost"]
            != training["description_length_gain"]
            or training["description_length_gain"] <= 0
        ):
            raise ContractError(f"Pareto tool {tool_index} training invalid")
        body = {
            "version": row["version"],
            "inputs": row["inputs"],
            "nodes": row["nodes"],
            "outputs": row["outputs"],
        }
        identity = hashlib.sha256(canonical(body).encode()).hexdigest()
        if row["tool_id"] != identity or identity in seen:
            raise ContractError(f"Pareto tool {tool_index} identity invalid")
        seen.add(identity)
    if sorted(seen) != metrics["tool_ids"]:
        raise ContractError("selected tool identities do not match metrics")
    return root


def hostile_tests(raw: bytes) -> list[str]:
    source = json.loads(raw)
    mutations = []
    extra = copy.deepcopy(source)
    extra["tools"][0]["extra"] = True
    mutations.append(("extra_field", extra))
    bad_id = copy.deepcopy(source)
    bad_id["tools"][0]["tool_id"] = "0" * 64
    mutations.append(("bad_identity", bad_id))
    forward = copy.deepcopy(source)
    forward["tools"][0]["nodes"][0]["args"] = {"node": 0}
    mutations.append(("forward_node_reference", forward))
    untyped = copy.deepcopy(source)
    untyped["tools"][0]["inputs"][0]["type"]["rank"] = "two"
    mutations.append(("untyped_input", untyped))
    target = copy.deepcopy(source)
    target["tools"][0]["nodes"][0]["target"] = "python.eval"
    mutations.append(("non_aten_target", target))
    accessed = copy.deepcopy(source)
    accessed["construction"]["validation_v6_accessed"] = True
    mutations.append(("validation_access", accessed))
    selected = copy.deepcopy(source)
    selected["selected_metrics"]["tool_ids"][0] = "f" * 64
    mutations.append(("selected_identity_mismatch", selected))
    rejected = []
    for name, mutation in mutations:
        try:
            parse_library(canonical(mutation).encode())
        except ContractError:
            rejected.append(name)
        else:
            raise RuntimeError(f"hostile Pareto mutation accepted: {name}")
    return rejected
