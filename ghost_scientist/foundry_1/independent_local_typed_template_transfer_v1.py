#!/usr/bin/env python3
"""Independent evaluator for the bounded local typed-template transfer."""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import pathlib
from typing import Any

from independent_local_grammar_emergence_v1 import (
    digest,
    load,
    nodes_of,
    tensor_kind,
)


HERE = pathlib.Path(__file__).resolve().parent
PHASE160 = HERE / "results/phase160_local_grammar_emergence.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


class IndependentTemplateReject(ValueError):
    """The proposed transfer ledger is not the independently derived result."""


# Descriptive alias for callers that prefer the full experiment name.
IndependentTemplateTransferReject = IndependentTemplateReject


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _phase160_ledger() -> dict[str, Any]:
    value = json.loads(PHASE160.read_text())
    try:
        ledger = value["observed"]["ledger"]
    except (KeyError, TypeError) as error:
        raise IndependentTemplateReject("Phase160 ledger absent") from error
    if ledger.get("version") != "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_LEDGER_V1":
        raise IndependentTemplateReject("Phase160 ledger version")
    return ledger


def _learned_equalities(bodies: list[dict[str, Any]]) -> list[list[int]]:
    if not bodies or not bodies[0].get("nodes"):
        raise IndependentTemplateReject("empty training occurrence set")
    width = len(bodies[0]["nodes"])
    if any(len(body.get("nodes", [])) != width for body in bodies):
        raise IndependentTemplateReject("training body width")
    result: list[list[int]] = []
    for left in range(width):
        for right in range(left + 1, width):
            if all(
                body["nodes"][left]["output_type"]
                == body["nodes"][right]["output_type"]
                for body in bodies
            ):
                result.append([left, right])
    return result


def _derive(
    topology_id: str,
    topology: dict[str, Any],
    occurrences: list[tuple[dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    families = sorted({record["family"] for record, _ in occurrences})
    if len(families) < 2:
        return None
    bodies = [motif["body"] for _, motif in occurrences]
    node_count = topology["node_count"]
    if any(len(body["nodes"]) != node_count for body in bodies):
        raise IndependentTemplateReject("topology/body disagreement")

    operator_slots: list[dict[str, str]] = []
    recipe_slots: list[dict[str, Any]] = []
    for index in range(node_count):
        targets = sorted(
            {body["nodes"][index]["target"] for body in bodies}
        )
        operator_slots.append(
            {"exact": targets[0]}
            if len(targets) == 1
            else {"hole": f"op_{index}"}
        )
        recipes = [
            {
                "args": body["nodes"][index]["args"],
                "kwargs": body["nodes"][index]["kwargs"],
            }
            for body in bodies
        ]
        recipe_slots.append(
            {"exact": recipes[0]}
            if all(value == recipes[0] for value in recipes[1:])
            else {"hole": f"recipe_{index}"}
        )

    operator_holes = sum(set(slot) == {"hole"} for slot in operator_slots)
    recipe_holes = sum(set(slot) == {"hole"} for slot in recipe_slots)
    if operator_holes + recipe_holes == 0:
        return None
    definition = {
        "version": "FOUNDRY_LOCAL_TYPED_DAG_TEMPLATE_V1",
        "topology_sha256": topology_id,
        "topology": topology,
        "operator_slots": operator_slots,
        "recipe_slots": recipe_slots,
        "node_output_type_equalities": _learned_equalities(bodies),
        "outputs": [
            {"node": index} for index in topology["output_indices"]
        ],
    }
    return {
        "template_sha256": digest(definition),
        "definition": definition,
        "training_occurrences": len(occurrences),
        "training_families": families,
        "operator_holes": operator_holes,
        "recipe_holes": recipe_holes,
    }


def _accepts(template: dict[str, Any], motif: dict[str, Any]) -> bool:
    definition = template["definition"]
    if motif["topology_sha256"] != definition["topology_sha256"]:
        return False
    nodes = motif["body"]["nodes"]
    if len(nodes) != definition["topology"]["node_count"]:
        return False
    for index, slot in enumerate(definition["operator_slots"]):
        if set(slot) == {"exact"} and nodes[index]["target"] != slot["exact"]:
            return False
    for index, slot in enumerate(definition["recipe_slots"]):
        observed = {
            "args": nodes[index]["args"],
            "kwargs": nodes[index]["kwargs"],
        }
        if set(slot) == {"exact"} and observed != slot["exact"]:
            return False
    for left, right in definition["node_output_type_equalities"]:
        if nodes[left]["output_type"] != nodes[right]["output_type"]:
            return False
    return True


def _instantiate(
    template: dict[str, Any], observed_body: dict[str, Any]
) -> dict[str, Any]:
    definition = template["definition"]
    instantiated = []
    for index, observed in enumerate(observed_body["nodes"]):
        operator_slot = definition["operator_slots"][index]
        recipe_slot = definition["recipe_slots"][index]
        target = (
            operator_slot["exact"]
            if set(operator_slot) == {"exact"}
            else observed["target"]
        )
        recipe = (
            recipe_slot["exact"]
            if set(recipe_slot) == {"exact"}
            else {
                "args": observed["args"],
                "kwargs": observed["kwargs"],
            }
        )
        instantiated.append(
            {
                "target": target,
                "args": recipe["args"],
                "kwargs": recipe["kwargs"],
                "output_type": observed["output_type"],
            }
        )
    return {
        "version": observed_body["version"],
        "inputs": observed_body["inputs"],
        "nodes": instantiated,
        "outputs": copy.deepcopy(definition["outputs"]),
    }


def _fixed_node_coverage(records: list[dict[str, Any]]) -> set[str]:
    fixed = json.loads(FIXED.read_text())
    coverage: set[str] = set()
    for record in records:
        if record["assignment"] != "heldout":
            continue
        graph_nodes = nodes_of(record["graph"])
        eligible = set(graph_nodes)
        for rule in fixed["tools"]:
            expected_type = {
                "rank": rule["rank"],
                "dtype": rule["dtype"],
                "layout": rule["layout"],
            }
            targets = rule["targets"]

            def visit(path: tuple[Any, ...]) -> None:
                position = len(path) - 1
                current = path[-1]
                if (
                    str(current.target) != targets[position]
                    or tensor_kind(current.meta.get("val")) != expected_type
                ):
                    return
                if len(path) == len(targets):
                    coverage.update(
                        f"{record['graph_id']}:{node.name}"
                        for node in path
                    )
                    return
                for successor in sorted(
                    current.users, key=lambda node: node.name
                ):
                    if successor in eligible and successor not in path:
                        visit((*path, successor))

            for node in graph_nodes:
                visit((node,))
    return coverage


@functools.lru_cache(maxsize=1)
def _computed() -> dict[str, Any]:
    phase160 = _phase160_ledger()
    non_chain_ids = set(phase160["non_chain_production_ids"])
    topology_by_id = {
        row["topology_sha256"]: row["topology"]
        for row in phase160["production_records"]
    }
    if not non_chain_ids <= set(topology_by_id):
        raise IndependentTemplateReject("unknown non-chain production")

    records = load()
    occurrences: dict[
        str, list[tuple[dict[str, Any], dict[str, Any]]]
    ] = {identifier: [] for identifier in non_chain_ids}
    for record in records:
        if record["assignment"] != "training":
            continue
        for motif in record["motifs"]:
            identifier = motif["topology_sha256"]
            if identifier in occurrences:
                occurrences[identifier].append((record, motif))

    templates = []
    for identifier in sorted(non_chain_ids):
        derived = _derive(
            identifier,
            topology_by_id[identifier],
            occurrences[identifier],
        )
        if derived is not None:
            templates.append(derived)

    matches = []
    for record in records:
        if record["assignment"] != "heldout":
            continue
        for motif in record["motifs"]:
            for template in templates:
                if not _accepts(template, motif):
                    continue
                reconstruction = _instantiate(template, motif["body"])
                matches.append(
                    {
                        "template_sha256": template["template_sha256"],
                        "graph_id": record["graph_id"],
                        "family": record["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "reconstructed_body_sha256": digest(
                            reconstruction
                        ),
                        "byte_identical_reconstruction": (
                            canonical(reconstruction)
                            == canonical(motif["body"])
                        ),
                    }
                )

    exact_key_set = {
        (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        for row in phase160["heldout_matches"]
    }
    candidate_only_matches = [
        row
        for row in matches
        if (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        not in exact_key_set
    ]
    exact_nodes = {
        f"{row['graph_id']}:{node_name}"
        for row in phase160["heldout_matches"]
        for node_name in row["node_names"]
    }
    chain_ids = set(phase160["chain_tool_ids"])
    chain_nodes = {
        f"{row['graph_id']}:{node_name}"
        for row in phase160["heldout_matches"]
        if row["body_sha256"] in chain_ids
        for node_name in row["node_names"]
    }
    fixed_nodes = _fixed_node_coverage(records)
    candidate_nodes = {
        f"{row['graph_id']}:{node_name}"
        for row in candidate_only_matches
        for node_name in row["node_names"]
    }
    candidate_only_nodes = sorted(
        candidate_nodes - exact_nodes - chain_nodes - fixed_nodes
    )
    summary = {
        "training_graphs": sum(
            row["assignment"] == "training" for row in records
        ),
        "heldout_graphs": sum(
            row["assignment"] == "heldout" for row in records
        ),
        "input_non_chain_productions": len(non_chain_ids),
        "selected_templates": len(templates),
        "operator_holes": sum(
            row["operator_holes"] for row in templates
        ),
        "recipe_holes": sum(row["recipe_holes"] for row in templates),
        "heldout_template_matches": len(matches),
        "byte_identical_reconstructions": sum(
            row["byte_identical_reconstruction"] for row in matches
        ),
        "candidate_only_template_matches": len(candidate_only_matches),
        "candidate_only_template_nodes": len(candidate_only_nodes),
        "candidate_only_families": len(
            {row["family"] for row in candidate_only_matches}
        ),
        "exact_control_nodes": len(exact_nodes),
        "chain_control_nodes": len(chain_nodes),
        "fixed_control_nodes": len(fixed_nodes),
        "causal_matches_after_remove_all_templates": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_LEDGER_V1",
        "templates": templates,
        "template_ids": sorted(
            row["template_sha256"] for row in templates
        ),
        "matches": matches,
        "candidate_only_matches": candidate_only_matches,
        "candidate_only_node_ids": candidate_only_nodes,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "post_outcome_diagnostic_not_pristine": True,
            "heldout_learning_performed": False,
            "concrete_exact_tool_reuse": False,
            "runtime_primitive_invented": False,
            "validation_v6_or_v7_accessed": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


def independent_run() -> dict[str, Any]:
    """Return a detached copy of the independently reconstructed ledger."""

    return copy.deepcopy(_computed())


def verify_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    """Strictly validate a ledger against protocol and independent replay."""

    if not isinstance(protocol, dict):
        raise IndependentTemplateReject("protocol type")
    try:
        if (
            protocol["version"]
            != "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_PROTOCOL_V1"
            or protocol["training_scope"]["heldout_learning_forbidden"]
            is not True
            or protocol["typed_anti_unification"]["llm_calls"] != 0
            or protocol["decision_rule"][
                "never_call_template_transfer_concrete_tool_reuse_or_runtime_invention"
            ]
            is not True
            or protocol["decision_rule"][
                "never_advance_P6_or_authorize_prospective_trial"
            ]
            is not True
            or protocol["claim_boundary"][
                "bounded_local_template_grammar_transfer_only"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_concrete_exact_tool_reuse_claim"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_new_operation_semantics_discovered"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_runtime_primitive_invention_claim"
            ]
            is not True
        ):
            raise IndependentTemplateReject("protocol boundary")
    except (KeyError, TypeError) as error:
        raise IndependentTemplateReject("protocol schema") from error

    if not isinstance(ledger, dict):
        raise IndependentTemplateReject("ledger type")
    expected = _computed()
    if canonical(ledger) != canonical(expected):
        differing = sorted(
            key
            for key in set(ledger) | set(expected)
            if ledger.get(key) != expected.get(key)
        )
        raise IndependentTemplateReject(
            "independent ledger mismatch: " + ",".join(differing)
        )


verify_template_ledger = verify_ledger


if __name__ == "__main__":
    observed = independent_run()
    protocol = json.loads(
        (
            HERE
            / "arm_adapter_fixtures/"
            "LOCAL_TYPED_TEMPLATE_TRANSFER_PROTOCOL_V1.json"
        ).read_text()
    )
    verify_ledger(observed, protocol)
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_TYPED_TEMPLATE_TRANSFER"
        f" templates={observed['summary']['selected_templates']}"
        f" matches={observed['summary']['heldout_template_matches']}"
        " concrete_reuse=false runtime_invention=false"
    )
