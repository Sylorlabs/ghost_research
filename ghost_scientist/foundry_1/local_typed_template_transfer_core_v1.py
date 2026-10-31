#!/usr/bin/env python3
"""Primary typed anti-unification over machine-selected non-chain forms."""

from __future__ import annotations

import hashlib
import json
import pathlib
from typing import Any

from local_grammar_emergence_core_v1 import (
    canonical,
    digest,
    eligible_nodes,
    enumerate_motifs,
    load_graphs,
    tensor_type,
)


HERE = pathlib.Path(__file__).resolve().parent


def equalities(bodies: list[dict[str, Any]]) -> list[list[int]]:
    count = len(bodies[0]["nodes"])
    return [
        [left, right]
        for left in range(count)
        for right in range(left + 1, count)
        if all(
            body["nodes"][left]["output_type"]
            == body["nodes"][right]["output_type"]
            for body in bodies
        )
    ]


def derive_template(
    topology_sha256: str,
    topology: dict[str, Any],
    occurrences: list[tuple[dict[str, Any], dict[str, Any]]],
) -> dict[str, Any] | None:
    bodies = [motif["body"] for _, motif in occurrences]
    families = sorted({row["family"] for row, _ in occurrences})
    if len(families) < 2:
        return None
    operator_slots = []
    recipe_slots = []
    holes = 0
    for index in range(topology["node_count"]):
        targets = {body["nodes"][index]["target"] for body in bodies}
        if len(targets) == 1:
            operator_slots.append({"exact": next(iter(targets))})
        else:
            operator_slots.append({"hole": f"op_{index}"})
            holes += 1
        recipes = [
            {
                "args": body["nodes"][index]["args"],
                "kwargs": body["nodes"][index]["kwargs"],
            }
            for body in bodies
        ]
        if all(recipe == recipes[0] for recipe in recipes[1:]):
            recipe_slots.append({"exact": recipes[0]})
        else:
            recipe_slots.append({"hole": f"recipe_{index}"})
            holes += 1
    if holes == 0:
        return None
    definition = {
        "version": "FOUNDRY_LOCAL_TYPED_DAG_TEMPLATE_V1",
        "topology_sha256": topology_sha256,
        "topology": topology,
        "operator_slots": operator_slots,
        "recipe_slots": recipe_slots,
        "node_output_type_equalities": equalities(bodies),
        "outputs": [{"node": value} for value in topology["output_indices"]],
    }
    return {
        "template_sha256": digest(definition),
        "definition": definition,
        "training_occurrences": len(occurrences),
        "training_families": families,
        "operator_holes": sum("hole" in slot for slot in operator_slots),
        "recipe_holes": sum("hole" in slot for slot in recipe_slots),
    }


def template_matches(template: dict[str, Any], motif: dict[str, Any]) -> bool:
    definition = template["definition"]
    if motif["topology_sha256"] != definition["topology_sha256"]:
        return False
    body = motif["body"]
    for index, slot in enumerate(definition["operator_slots"]):
        if "exact" in slot and body["nodes"][index]["target"] != slot["exact"]:
            return False
    for index, slot in enumerate(definition["recipe_slots"]):
        recipe = {
            "args": body["nodes"][index]["args"],
            "kwargs": body["nodes"][index]["kwargs"],
        }
        if "exact" in slot and recipe != slot["exact"]:
            return False
    for left, right in definition["node_output_type_equalities"]:
        if (
            body["nodes"][left]["output_type"]
            != body["nodes"][right]["output_type"]
        ):
            return False
    return True


def instantiate(template: dict[str, Any], body: dict[str, Any]) -> dict[str, Any]:
    definition = template["definition"]
    nodes = []
    for index, original in enumerate(body["nodes"]):
        operator = definition["operator_slots"][index]
        recipe = definition["recipe_slots"][index]
        target = operator.get("exact", original["target"])
        bound_recipe = recipe.get(
            "exact", {"args": original["args"], "kwargs": original["kwargs"]}
        )
        nodes.append(
            {
                "target": target,
                "args": bound_recipe["args"],
                "kwargs": bound_recipe["kwargs"],
                "output_type": original["output_type"],
            }
        )
    return {
        "version": body["version"],
        "inputs": body["inputs"],
        "nodes": nodes,
        "outputs": definition["outputs"],
    }


def fixed_coverage(records: list[dict[str, Any]]) -> set[str]:
    fixed = json.loads((HERE / "ATEN_FIXED_PORTFOLIO_V2.json").read_text())
    coverage: set[str] = set()
    for row in records:
        if row["assignment"] != "heldout":
            continue
        nodes = eligible_nodes(row["graph"])
        allowed = set(nodes)
        for tool in fixed["tools"]:
            expected = {
                "rank": tool["rank"],
                "dtype": tool["dtype"],
                "layout": tool["layout"],
            }

            def extend(path) -> None:
                index = len(path) - 1
                if (
                    str(path[-1].target) != tool["targets"][index]
                    or tensor_type(path[-1].meta.get("val")) != expected
                ):
                    return
                if len(path) == len(tool["targets"]):
                    coverage.update(
                        f"{row['graph_id']}:{node.name}" for node in path
                    )
                    return
                for user in sorted(path[-1].users, key=lambda item: item.name):
                    if user in allowed and user not in path:
                        extend(path + [user])

            for node in nodes:
                extend([node])
    return coverage


def run_template_transfer() -> dict[str, Any]:
    phase160 = json.loads(
        (HERE / "results/phase160_local_grammar_emergence.json").read_text()
    )["observed"]["ledger"]
    non_chain = set(phase160["non_chain_production_ids"])
    topology_records = {
        row["topology_sha256"]: row["topology"]
        for row in phase160["production_records"]
    }
    raw_records = load_graphs()
    records = [enumerate_motifs(row) for row in raw_records]
    occurrences = {identifier: [] for identifier in non_chain}
    for row in records:
        if row["assignment"] != "training":
            continue
        for motif in row["motifs"]:
            if motif["topology_sha256"] in occurrences:
                occurrences[motif["topology_sha256"]].append((row, motif))
    templates = []
    for identifier in sorted(non_chain):
        template = derive_template(
            identifier, topology_records[identifier], occurrences[identifier]
        )
        if template is not None:
            templates.append(template)
    matches = []
    for row in records:
        if row["assignment"] != "heldout":
            continue
        for motif in row["motifs"]:
            for template in templates:
                if not template_matches(template, motif):
                    continue
                reconstructed = instantiate(template, motif["body"])
                matches.append(
                    {
                        "template_sha256": template["template_sha256"],
                        "graph_id": row["graph_id"],
                        "family": row["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "reconstructed_body_sha256": digest(reconstructed),
                        "byte_identical_reconstruction": (
                            canonical(reconstructed) == canonical(motif["body"])
                        ),
                    }
                )
    exact_match_keys = {
        (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        for row in phase160["heldout_matches"]
    }
    candidate_only_matches = [
        row
        for row in matches
        if (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        not in exact_match_keys
    ]
    exact_coverage = {
        f"{row['graph_id']}:{name}"
        for row in phase160["heldout_matches"]
        for name in row["node_names"]
    }
    chain_coverage = {
        f"{row['graph_id']}:{name}"
        for row in phase160["heldout_matches"]
        if row["body_sha256"] in set(phase160["chain_tool_ids"])
        for name in row["node_names"]
    }
    fixed = fixed_coverage(raw_records)
    candidate_only_coverage = {
        f"{row['graph_id']}:{name}"
        for row in candidate_only_matches
        for name in row["node_names"]
    }
    unreachable = candidate_only_coverage - exact_coverage - chain_coverage - fixed
    summary = {
        "training_graphs": 16,
        "heldout_graphs": 7,
        "input_non_chain_productions": len(non_chain),
        "selected_templates": len(templates),
        "operator_holes": sum(row["operator_holes"] for row in templates),
        "recipe_holes": sum(row["recipe_holes"] for row in templates),
        "heldout_template_matches": len(matches),
        "byte_identical_reconstructions": sum(
            row["byte_identical_reconstruction"] for row in matches
        ),
        "candidate_only_template_matches": len(candidate_only_matches),
        "candidate_only_template_nodes": len(unreachable),
        "candidate_only_families": len(
            {row["family"] for row in candidate_only_matches}
        ),
        "exact_control_nodes": len(exact_coverage),
        "chain_control_nodes": len(chain_coverage),
        "fixed_control_nodes": len(fixed),
        "causal_matches_after_remove_all_templates": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_LEDGER_V1",
        "templates": templates,
        "template_ids": sorted(row["template_sha256"] for row in templates),
        "matches": matches,
        "candidate_only_matches": candidate_only_matches,
        "candidate_only_node_ids": sorted(unreachable),
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


class TemplateLedgerReject(ValueError):
    pass


_EXPECTED_LEDGER: dict[str, Any] | None = None


def verify_template_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    if (
        protocol.get("version")
        != "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_PROTOCOL_V1"
        or protocol.get("status") != "PREFROZEN_POST_PHASE160_DIAGNOSTIC"
        or protocol.get("training_scope", {}).get(
            "heldout_learning_forbidden"
        )
        is not True
    ):
        raise TemplateLedgerReject("protocol identity")
    if set(ledger) != {
        "version",
        "templates",
        "template_ids",
        "matches",
        "candidate_only_matches",
        "candidate_only_node_ids",
        "summary",
        "claims",
    } or ledger["version"] != "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_LEDGER_V1":
        raise TemplateLedgerReject("ledger schema")
    template_map = {}
    for row in ledger["templates"]:
        if set(row) != {
            "template_sha256",
            "definition",
            "training_occurrences",
            "training_families",
            "operator_holes",
            "recipe_holes",
        }:
            raise TemplateLedgerReject("template schema")
        definition = row["definition"]
        if (
            row["template_sha256"] != digest(definition)
            or row["template_sha256"] in template_map
            or set(definition)
            != {
                "version",
                "topology_sha256",
                "topology",
                "operator_slots",
                "recipe_slots",
                "node_output_type_equalities",
                "outputs",
            }
            or definition["version"] != "FOUNDRY_LOCAL_TYPED_DAG_TEMPLATE_V1"
            or len(definition["operator_slots"])
            != definition["topology"]["node_count"]
            or len(definition["recipe_slots"])
            != definition["topology"]["node_count"]
            or row["operator_holes"]
            != sum("hole" in slot for slot in definition["operator_slots"])
            or row["recipe_holes"]
            != sum("hole" in slot for slot in definition["recipe_slots"])
            or row["operator_holes"] + row["recipe_holes"] < 1
            or len(set(row["training_families"])) < 2
        ):
            raise TemplateLedgerReject("template relation")
        for index, slot in enumerate(definition["operator_slots"]):
            if set(slot) not in ({"exact"}, {"hole"}) or (
                "hole" in slot and slot["hole"] != f"op_{index}"
            ):
                raise TemplateLedgerReject("operator slot")
        for index, slot in enumerate(definition["recipe_slots"]):
            if set(slot) not in ({"exact"}, {"hole"}) or (
                "hole" in slot and slot["hole"] != f"recipe_{index}"
            ):
                raise TemplateLedgerReject("recipe slot")
        count = definition["topology"]["node_count"]
        equalities = definition["node_output_type_equalities"]
        if equalities != [
            list(pair) for pair in sorted({tuple(pair) for pair in equalities})
        ] or any(
            type(pair) is not list
            or len(pair) != 2
            or not 0 <= pair[0] < pair[1] < count
            for pair in equalities
        ):
            raise TemplateLedgerReject("type equalities")
        if definition["outputs"] != [
            {"node": value}
            for value in definition["topology"]["output_indices"]
        ]:
            raise TemplateLedgerReject("output boundary")
        template_map[row["template_sha256"]] = row
    if ledger["template_ids"] != sorted(template_map):
        raise TemplateLedgerReject("template identifiers")
    for match in ledger["matches"]:
        if (
            set(match)
            != {
                "template_sha256",
                "graph_id",
                "family",
                "topology_sha256",
                "body_sha256",
                "node_names",
                "reconstructed_body_sha256",
                "byte_identical_reconstruction",
            }
            or match["template_sha256"] not in template_map
            or match["topology_sha256"]
            != template_map[match["template_sha256"]]["definition"][
                "topology_sha256"
            ]
            or match["reconstructed_body_sha256"] != match["body_sha256"]
            or match["byte_identical_reconstruction"] is not True
            or len(match["node_names"])
            != template_map[match["template_sha256"]]["definition"][
                "topology"
            ]["node_count"]
            or len(match["node_names"]) != len(set(match["node_names"]))
        ):
            raise TemplateLedgerReject("match relation")
    exact = json.loads(
        (HERE / "results/phase160_local_grammar_emergence.json").read_text()
    )["observed"]["ledger"]["heldout_matches"]
    exact_keys = {
        (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        for row in exact
    }
    expected_candidate = [
        row
        for row in ledger["matches"]
        if (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        not in exact_keys
    ]
    if ledger["candidate_only_matches"] != expected_candidate:
        raise TemplateLedgerReject("candidate-only match relation")
    candidate_nodes = {
        f"{row['graph_id']}:{name}"
        for row in ledger["candidate_only_matches"]
        for name in row["node_names"]
    }
    if not set(ledger["candidate_only_node_ids"]) <= candidate_nodes:
        raise TemplateLedgerReject("candidate-only nodes")
    summary = ledger["summary"]
    if (
        summary["training_graphs"] != 16
        or summary["heldout_graphs"] != 7
        or summary["input_non_chain_productions"] != 3
        or summary["selected_templates"] != len(ledger["template_ids"])
        or summary["operator_holes"]
        != sum(row["operator_holes"] for row in ledger["templates"])
        or summary["recipe_holes"]
        != sum(row["recipe_holes"] for row in ledger["templates"])
        or summary["heldout_template_matches"] != len(ledger["matches"])
        or summary["byte_identical_reconstructions"] != len(ledger["matches"])
        or summary["candidate_only_template_matches"]
        != len(ledger["candidate_only_matches"])
        or summary["candidate_only_template_nodes"]
        != len(ledger["candidate_only_node_ids"])
        or summary["exact_control_nodes"] != 11
        or summary["chain_control_nodes"] != 11
        or summary["fixed_control_nodes"] != 17
        or summary["causal_matches_after_remove_all_templates"] != 0
    ):
        raise TemplateLedgerReject("summary relation")
    if ledger["claims"] != {
        "local_exploratory_only": True,
        "post_outcome_diagnostic_not_pristine": True,
        "heldout_learning_performed": False,
        "concrete_exact_tool_reuse": False,
        "runtime_primitive_invented": False,
        "validation_v6_or_v7_accessed": False,
        "P6_advanced": False,
        "prospective_trial_authorized": False,
        "prospective_trial_executed": False,
    }:
        raise TemplateLedgerReject("claim boundary")
    global _EXPECTED_LEDGER
    if _EXPECTED_LEDGER is None:
        _EXPECTED_LEDGER = run_template_transfer()
    if canonical(ledger) != canonical(_EXPECTED_LEDGER):
        raise TemplateLedgerReject("recomputed ledger mismatch")
