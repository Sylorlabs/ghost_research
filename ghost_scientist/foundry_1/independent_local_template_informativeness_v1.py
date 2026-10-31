#!/usr/bin/env python3
"""Independent replay of the frozen local-template informativity ablation."""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import math
import pathlib
from typing import Any

from independent_local_grammar_emergence_v1 import digest, load


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/LOCAL_TEMPLATE_INFORMATIVENESS_PROTOCOL_V1.json"
)
PHASE161 = HERE / "results/phase161_local_typed_template_transfer.json"


class IndependentInformativenessReject(ValueError):
    """The informativeness claim is not the independently replayed result."""


def _canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _frozen_protocol() -> dict[str, Any]:
    value = json.loads(PROTOCOL.read_text())
    try:
        if (
            value["version"]
            != "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_PROTOCOL_V1"
            or value["classification"]["local_exploratory_only"] is not True
            or value["classification"]["phase161_outcome_known"] is not True
            or value["classification"]["post_outcome_diagnostic_not_pristine"]
            is not True
            or value["candidate"]["heldout_learning_forbidden"] is not True
            or value["decision_rule"][
                "never_advance_P2_or_P6_or_authorize_prospective_trial"
            ]
            is not True
            or value["claim_boundary"]["P2_not_advanced"] is not True
            or value["claim_boundary"]["P6_not_advanced"] is not True
            or value["claim_boundary"]["prospective_trial_authorized"]
            is not False
            or value["claim_boundary"]["prospective_trial_executed"] is not False
            or value["claim_boundary"]["validation_v7_payload_decrypted"]
            is not False
            or len(value["hostile_requirements"]["must_cover"]) != 12
        ):
            raise IndependentInformativenessReject("protocol boundary")
    except (KeyError, TypeError) as error:
        raise IndependentInformativenessReject("protocol schema") from error
    for provider in value["provider_records"]:
        try:
            path = HERE / provider["path"]
            expected = provider["sha256"]
        except (KeyError, TypeError) as error:
            raise IndependentInformativenessReject(
                "provider record schema"
            ) from error
        if _sha(path) != expected:
            raise IndependentInformativenessReject(
                f"provider hash: {provider.get('path')}"
            )
    return value


def _candidate() -> tuple[dict[str, Any], dict[str, Any]]:
    source = json.loads(PHASE161.read_text())
    try:
        if (
            source["status"] != "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
            or source["observed"]["ledger"]["version"]
            != "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_LEDGER_V1"
        ):
            raise IndependentInformativenessReject("Phase161 source status")
        templates = source["observed"]["ledger"]["templates"]
    except (KeyError, TypeError) as error:
        raise IndependentInformativenessReject(
            "Phase161 source schema"
        ) from error
    if not isinstance(templates, list) or len(templates) != 1:
        raise IndependentInformativenessReject(
            "Phase161 candidate multiplicity"
        )
    candidate = templates[0]
    try:
        definition = candidate["definition"]
        topology = definition["topology"]
        if (
            definition["version"]
            != "FOUNDRY_LOCAL_TYPED_DAG_TEMPLATE_V1"
            or candidate["template_sha256"] != digest(definition)
            or definition["topology_sha256"] != digest(topology)
            or definition["outputs"]
            != [{"node": item} for item in topology["output_indices"]]
            or len(definition["operator_slots"]) != topology["node_count"]
            or len(definition["recipe_slots"]) != topology["node_count"]
            or topology["node_count"] != 2
        ):
            raise IndependentInformativenessReject(
                "Phase161 candidate integrity"
            )
    except (KeyError, TypeError) as error:
        raise IndependentInformativenessReject(
            "Phase161 candidate schema"
        ) from error
    return source, candidate


def _slot_constraints_accept(
    definition: dict[str, Any], motif: dict[str, Any]
) -> bool:
    nodes = motif["body"]["nodes"]
    if len(nodes) != definition["topology"]["node_count"]:
        return False
    for index, slot in enumerate(definition["operator_slots"]):
        if set(slot) == {"exact"} and nodes[index]["target"] != slot["exact"]:
            return False
        if set(slot) not in ({"exact"}, {"hole"}):
            raise IndependentInformativenessReject("operator slot schema")
    for index, slot in enumerate(definition["recipe_slots"]):
        observed = {
            "args": nodes[index]["args"],
            "kwargs": nodes[index]["kwargs"],
        }
        if set(slot) == {"exact"} and observed != slot["exact"]:
            return False
        if set(slot) not in ({"exact"}, {"hole"}):
            raise IndependentInformativenessReject("recipe slot schema")
    return True


def _typed_accepts(
    definition: dict[str, Any], motif: dict[str, Any]
) -> bool:
    if (
        motif["topology_sha256"] != definition["topology_sha256"]
        or not _slot_constraints_accept(definition, motif)
    ):
        return False
    nodes = motif["body"]["nodes"]
    for equality in definition["node_output_type_equalities"]:
        if (
            type(equality) is not list
            or len(equality) != 2
            or not all(type(item) is int for item in equality)
            or not 0 <= equality[0] < equality[1] < len(nodes)
        ):
            raise IndependentInformativenessReject(
                "type equality schema"
            )
        if (
            nodes[equality[0]]["output_type"]
            != nodes[equality[1]]["output_type"]
        ):
            return False
    return True


def _match(record: dict[str, Any], motif: dict[str, Any]) -> dict[str, Any]:
    return {
        "graph_id": record["graph_id"],
        "family": record["family"],
        "topology_sha256": motif["topology_sha256"],
        "body_sha256": motif["body_sha256"],
        "node_names": motif["node_names"],
        "ordered_targets": [
            node["target"] for node in motif["body"]["nodes"]
        ],
    }


def _key(row: dict[str, Any]) -> tuple[str, str, tuple[str, ...]]:
    return (
        row["graph_id"],
        row["body_sha256"],
        tuple(row["node_names"]),
    )


@functools.lru_cache(maxsize=1)
def _computed() -> dict[str, Any]:
    _frozen_protocol()
    source, candidate = _candidate()
    definition = candidate["definition"]
    records = load()
    training = [row for row in records if row["assignment"] == "training"]
    heldout = [row for row in records if row["assignment"] == "heldout"]
    if len(training) != 16 or len(heldout) != 7:
        raise IndependentInformativenessReject("hash split")

    topology_groups: dict[str, dict[str, Any]] = {}
    candidate_training_targets: set[tuple[str, ...]] = set()
    candidate_training_occurrences = []
    for record in training:
        for motif in record["motifs"]:
            identifier = motif["topology_sha256"]
            group = topology_groups.setdefault(
                identifier,
                {
                    "count": 0,
                    "families": set(),
                    "topology": motif["topology"],
                },
            )
            if group["topology"] != motif["topology"]:
                raise IndependentInformativenessReject(
                    "topology digest collision"
                )
            group["count"] += 1
            group["families"].add(record["family"])
            if identifier == definition["topology_sha256"]:
                candidate_training_occurrences.append(motif)
                candidate_training_targets.add(
                    tuple(
                        node["target"]
                        for node in motif["body"]["nodes"]
                    )
                )

    if (
        len(candidate_training_occurrences)
        != candidate["training_occurrences"]
        or sorted(
            {
                record["family"]
                for record in training
                for motif in record["motifs"]
                if motif["topology_sha256"]
                == definition["topology_sha256"]
            }
        )
        != candidate["training_families"]
        or any(
            not _typed_accepts(definition, motif)
            for motif in candidate_training_occurrences
        )
    ):
        raise IndependentInformativenessReject(
            "candidate training provenance"
        )

    eligible_baselines = [
        (identifier, group)
        for identifier, group in topology_groups.items()
        if len(group["families"]) >= 2
    ]
    if not eligible_baselines:
        raise IndependentInformativenessReject(
            "frequency baseline absent"
        )
    baseline_id, baseline = sorted(
        eligible_baselines,
        key=lambda item: (-item[1]["count"], item[0]),
    )[0]

    candidate_matches = []
    topology_matches = []
    boundary_matches = []
    baseline_matches = []
    boundary_node_count = definition["topology"]["node_count"]
    boundary_outputs = definition["topology"]["output_indices"]
    for record in heldout:
        for motif in record["motifs"]:
            if (
                motif["topology_sha256"]
                == definition["topology_sha256"]
                and _slot_constraints_accept(definition, motif)
            ):
                topology_matches.append(_match(record, motif))
                if _typed_accepts(definition, motif):
                    candidate_matches.append(_match(record, motif))
            if (
                motif["topology"]["node_count"] == boundary_node_count
                and motif["topology"]["output_indices"] == boundary_outputs
                and _slot_constraints_accept(definition, motif)
            ):
                boundary_matches.append(_match(record, motif))
            if motif["topology_sha256"] == baseline_id:
                baseline_matches.append(_match(record, motif))

    candidate_keys = {_key(row) for row in candidate_matches}
    typed_rejections = [
        row for row in topology_matches if _key(row) not in candidate_keys
    ]
    unseen = [
        row
        for row in candidate_matches
        if tuple(row["ordered_targets"])
        not in candidate_training_targets
    ]
    if len(candidate_matches) > len(topology_matches):
        raise IndependentInformativenessReject("ablation monotonicity")
    information_bits = (
        0.0
        if len(candidate_matches) == len(topology_matches)
        else -math.log2(len(candidate_matches) / len(topology_matches))
    )
    try:
        controls = source["observed"]["ledger"]["summary"]
        exact_nodes = controls["exact_control_nodes"]
        chain_nodes = controls["chain_control_nodes"]
        fixed_nodes = controls["fixed_control_nodes"]
    except (KeyError, TypeError) as error:
        raise IndependentInformativenessReject(
            "Phase161 control counts"
        ) from error
    summary = {
        "training_graphs": len(training),
        "heldout_graphs": len(heldout),
        "selected_templates": 1,
        "candidate_heldout_matches": len(candidate_matches),
        "topology_only_heldout_matches": len(topology_matches),
        "typed_rejections": len(typed_rejections),
        "boundary_only_heldout_matches": len(boundary_matches),
        "frequency_baseline_training_occurrences": baseline["count"],
        "frequency_baseline_training_families": len(
            baseline["families"]
        ),
        "frequency_baseline_heldout_matches": len(baseline_matches),
        "unseen_operator_pairs": len(unseen),
        "candidate_information_bits": information_bits,
        "exact_control_nodes": exact_nodes,
        "chain_control_nodes": chain_nodes,
        "fixed_control_nodes": fixed_nodes,
    }
    return {
        "version": "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_LEDGER_V1",
        "source_phase161_sha256": _sha(PHASE161),
        "candidate_template_sha256": candidate["template_sha256"],
        "candidate_topology_sha256": definition["topology_sha256"],
        "frequency_baseline_topology_sha256": baseline_id,
        "candidate_matches": candidate_matches,
        "topology_only_matches": topology_matches,
        "typed_rejections": typed_rejections,
        "boundary_only_matches": boundary_matches,
        "frequency_baseline_matches": baseline_matches,
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


def independent_run() -> dict[str, Any]:
    """Return a detached copy of the independently enumerated ledger."""

    return copy.deepcopy(_computed())


def verify_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    """Strictly compare a proposed ledger with frozen-protocol replay."""

    if not isinstance(protocol, dict):
        raise IndependentInformativenessReject("protocol type")
    frozen = _frozen_protocol()
    if _canonical(protocol) != _canonical(frozen):
        raise IndependentInformativenessReject("protocol mismatch")
    if not isinstance(ledger, dict):
        raise IndependentInformativenessReject("ledger type")
    expected = _computed()
    if _canonical(ledger) != _canonical(expected):
        differing = sorted(
            key
            for key in set(ledger) | set(expected)
            if ledger.get(key) != expected.get(key)
        )
        raise IndependentInformativenessReject(
            "independent ledger mismatch: " + ",".join(differing)
        )


if __name__ == "__main__":
    observed = independent_run()
    verify_ledger(observed, json.loads(PROTOCOL.read_text()))
    summary = observed["summary"]
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_TEMPLATE_INFORMATIVENESS"
        f" candidate={summary['candidate_heldout_matches']}"
        f" topology={summary['topology_only_heldout_matches']}"
        f" typed_rejections={summary['typed_rejections']}"
        f" bits={summary['candidate_information_bits']}"
        " prospective=false"
    )
