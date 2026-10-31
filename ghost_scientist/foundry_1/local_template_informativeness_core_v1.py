#!/usr/bin/env python3
"""Primary ablation of Phase161 typed-template informativeness."""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from collections import Counter, defaultdict
from typing import Any

from local_grammar_emergence_core_v1 import enumerate_motifs, load_graphs
from local_typed_template_transfer_core_v1 import canonical, template_matches


HERE = pathlib.Path(__file__).resolve().parent
PHASE161 = HERE / "results/phase161_local_typed_template_transfer.json"


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def match_row(record: dict[str, Any], motif: dict[str, Any]) -> dict[str, Any]:
    return {
        "graph_id": record["graph_id"],
        "family": record["family"],
        "topology_sha256": motif["topology_sha256"],
        "body_sha256": motif["body_sha256"],
        "node_names": motif["node_names"],
        "ordered_targets": [node["target"] for node in motif["body"]["nodes"]],
    }


def run_informativeness() -> dict[str, Any]:
    source = json.loads(PHASE161.read_text())
    template = source["observed"]["ledger"]["templates"][0]
    definition = template["definition"]
    records = [enumerate_motifs(row) for row in load_graphs()]

    training_counts: Counter[str] = Counter()
    training_families: dict[str, set[str]] = defaultdict(set)
    training_target_sequences: set[tuple[str, ...]] = set()
    topology_records: dict[str, dict[str, Any]] = {}
    for record in records:
        for motif in record["motifs"]:
            topology_records[motif["topology_sha256"]] = motif["topology"]
            if record["assignment"] != "training":
                continue
            identifier = motif["topology_sha256"]
            training_counts[identifier] += 1
            training_families[identifier].add(record["family"])
            if identifier == definition["topology_sha256"]:
                training_target_sequences.add(
                    tuple(node["target"] for node in motif["body"]["nodes"])
                )
    eligible = [
        identifier
        for identifier in training_counts
        if len(training_families[identifier]) >= 2
    ]
    frequency_topology = min(
        eligible, key=lambda identifier: (-training_counts[identifier], identifier)
    )

    candidate = []
    topology_only = []
    boundary_only = []
    frequency = []
    for record in records:
        if record["assignment"] != "heldout":
            continue
        for motif in record["motifs"]:
            row = match_row(record, motif)
            if template_matches(template, motif):
                candidate.append(row)
            if motif["topology_sha256"] == definition["topology_sha256"]:
                topology_only.append(row)
            if (
                motif["topology"]["node_count"]
                == definition["topology"]["node_count"]
                and motif["topology"]["output_indices"]
                == definition["topology"]["output_indices"]
            ):
                boundary_only.append(row)
            if motif["topology_sha256"] == frequency_topology:
                frequency.append(row)
    candidate_keys = {
        (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        for row in candidate
    }
    typed_rejections = [
        row
        for row in topology_only
        if (row["graph_id"], row["body_sha256"], tuple(row["node_names"]))
        not in candidate_keys
    ]
    unseen = [
        row
        for row in candidate
        if tuple(row["ordered_targets"]) not in training_target_sequences
    ]
    ratio = len(candidate) / len(topology_only) if topology_only else 0.0
    information_bits = -math.log2(ratio) if ratio > 0 else 0.0
    if information_bits == -0.0:
        information_bits = 0.0
    summary = {
        "training_graphs": sum(row["assignment"] == "training" for row in records),
        "heldout_graphs": sum(row["assignment"] == "heldout" for row in records),
        "selected_templates": 1,
        "candidate_heldout_matches": len(candidate),
        "topology_only_heldout_matches": len(topology_only),
        "typed_rejections": len(typed_rejections),
        "boundary_only_heldout_matches": len(boundary_only),
        "frequency_baseline_training_occurrences": training_counts[
            frequency_topology
        ],
        "frequency_baseline_training_families": len(
            training_families[frequency_topology]
        ),
        "frequency_baseline_heldout_matches": len(frequency),
        "unseen_operator_pairs": len(unseen),
        "candidate_information_bits": information_bits,
        "exact_control_nodes": source["observed"]["summary"]["exact_control_nodes"],
        "chain_control_nodes": source["observed"]["summary"]["chain_control_nodes"],
        "fixed_control_nodes": source["observed"]["summary"]["fixed_control_nodes"],
    }
    return {
        "version": "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_LEDGER_V1",
        "source_phase161_sha256": hashlib.sha256(PHASE161.read_bytes()).hexdigest(),
        "candidate_template_sha256": template["template_sha256"],
        "candidate_topology_sha256": definition["topology_sha256"],
        "frequency_baseline_topology_sha256": frequency_topology,
        "candidate_matches": candidate,
        "topology_only_matches": topology_only,
        "typed_rejections": typed_rejections,
        "boundary_only_matches": boundary_only,
        "frequency_baseline_matches": frequency,
        "unseen_operator_pair_matches": unseen,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "post_outcome_diagnostic_not_pristine": True,
            "heldout_learning_performed": False,
            "typed_template_informative": len(typed_rejections) > 0,
            "concrete_exact_tool_reuse": False,
            "new_operation_semantics": False,
            "runtime_primitive_invented": False,
            "validation_v6_or_v7_accessed": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


class InformativenessReject(ValueError):
    pass


_EXPECTED: dict[str, Any] | None = None


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
    if (
        protocol.get("version")
        != "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_PROTOCOL_V1"
        or protocol.get("status") != "PREFROZEN_POST_PHASE161_DIAGNOSTIC"
    ):
        raise InformativenessReject("protocol identity")
    global _EXPECTED
    if _EXPECTED is None:
        _EXPECTED = run_informativeness()
    expected_keys = set(_EXPECTED)
    if set(ledger) != expected_keys:
        raise InformativenessReject("ledger schema")
    changed = [
        key for key in sorted(expected_keys) if canonical(ledger[key]) != canonical(_EXPECTED[key])
    ]
    if changed:
        raise InformativenessReject("recomputed ledger mismatch: " + ",".join(changed))


if __name__ == "__main__":
    result = run_informativeness()
    print(
        "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS"
        f" candidate={result['summary']['candidate_heldout_matches']}"
        f" topology={result['summary']['topology_only_heldout_matches']}"
        f" typed_rejections={result['summary']['typed_rejections']}"
        f" bits={result['summary']['candidate_information_bits']}"
    )
