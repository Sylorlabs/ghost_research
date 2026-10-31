#!/usr/bin/env python3
"""Primary training-only complete canonical body predictor."""

from __future__ import annotations

import hashlib
import json
import pathlib
from collections import Counter, defaultdict
from typing import Any

from local_grammar_emergence_core_v1 import canonical, enumerate_motifs, load_graphs
from local_operator_prediction_core_v1 import fold_for


HERE = pathlib.Path(__file__).resolve().parent


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def most_frequent(counter: Counter[bytes], bodies: dict[bytes, dict[str, Any]]) -> dict[str, Any]:
    key = min(counter, key=lambda value: (-counter[value], value))
    return bodies[key]


def targets(body: dict[str, Any]) -> list[str]:
    return [node["target"] for node in body["nodes"]]


def run_exact_body_prediction() -> dict[str, Any]:
    records = [enumerate_motifs(row) for row in load_graphs()]
    assignments = [
        {"graph_id": row["graph_id"], "family": row["family"], "fold": fold_for(row["graph_id"])}
        for row in records
    ]
    fold_by_graph = {row["graph_id"]: row["fold"] for row in assignments}
    predictions = []
    evaluations = []
    for fold in range(5):
        topo_bodies: dict[str, Counter[bytes]] = defaultdict(Counter)
        topo_occurrences: Counter[str] = Counter()
        topo_families: dict[str, set[str]] = defaultdict(set)
        topo_shapes: dict[str, dict[str, Any]] = {}
        boundary_bodies: dict[tuple[int, tuple[int, ...]], Counter[bytes]] = defaultdict(Counter)
        size_bodies: dict[int, Counter[bytes]] = defaultdict(Counter)
        bodies: dict[bytes, dict[str, Any]] = {}
        for row in records:
            if fold_by_graph[row["graph_id"]] == fold:
                continue
            for motif in row["motifs"]:
                identifier = motif["topology_sha256"]
                body_key = canonical(motif["body"])
                bodies[body_key] = motif["body"]
                topo_bodies[identifier][body_key] += 1
                topo_occurrences[identifier] += 1
                topo_families[identifier].add(row["family"])
                topo_shapes[identifier] = motif["topology"]
                boundary = (
                    motif["topology"]["node_count"],
                    tuple(motif["topology"]["output_indices"]),
                )
                boundary_bodies[boundary][body_key] += 1
                size_bodies[motif["topology"]["node_count"]][body_key] += 1
        eligible = {
            identifier
            for identifier in topo_bodies
            if topo_occurrences[identifier] >= 3
            and len(topo_families[identifier]) >= 2
        }
        fold_predictions = {}
        for identifier in sorted(eligible):
            shape = topo_shapes[identifier]
            boundary = (shape["node_count"], tuple(shape["output_indices"]))
            candidate = most_frequent(topo_bodies[identifier], bodies)
            boundary_body = most_frequent(boundary_bodies[boundary], bodies)
            global_body = most_frequent(size_bodies[shape["node_count"]], bodies)
            row = {
                "fold": fold,
                "topology_sha256": identifier,
                "training_occurrences": topo_occurrences[identifier],
                "training_families": len(topo_families[identifier]),
                "candidate_body": candidate,
                "candidate_body_sha256": digest(candidate),
                "boundary_body": boundary_body,
                "boundary_body_sha256": digest(boundary_body),
                "global_size_body": global_body,
                "global_size_body_sha256": digest(global_body),
            }
            predictions.append(row)
            fold_predictions[identifier] = row
        for graph in records:
            if fold_by_graph[graph["graph_id"]] != fold:
                continue
            for motif in graph["motifs"]:
                prediction = fold_predictions.get(motif["topology_sha256"])
                if prediction is None:
                    continue
                actual_bytes = canonical(motif["body"])
                candidate_exact = actual_bytes == canonical(prediction["candidate_body"])
                boundary_exact = actual_bytes == canonical(prediction["boundary_body"])
                global_exact = actual_bytes == canonical(prediction["global_size_body"])
                operator_exact = targets(motif["body"]) == targets(prediction["candidate_body"])
                evaluations.append(
                    {
                        "fold": fold,
                        "graph_id": graph["graph_id"],
                        "family": graph["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "candidate_body_sha256": prediction["candidate_body_sha256"],
                        "boundary_body_sha256": prediction["boundary_body_sha256"],
                        "global_size_body_sha256": prediction["global_size_body_sha256"],
                        "candidate_exact": candidate_exact,
                        "boundary_exact": boundary_exact,
                        "global_size_exact": global_exact,
                        "operator_sequence_exact": operator_exact,
                    }
                )
    exact = [row for row in evaluations if row["candidate_exact"]]
    summary = {
        "graphs": len(records),
        "folds": 5,
        "fold_graph_counts": [sum(row["fold"] == fold for row in assignments) for fold in range(5)],
        "graph_assignments": len(assignments),
        "prediction_records": len(predictions),
        "eligible_heldout_motifs": len(evaluations),
        "operator_sequence_exact": sum(row["operator_sequence_exact"] for row in evaluations),
        "candidate_exact_bodies": len(exact),
        "boundary_exact_bodies": sum(row["boundary_exact"] for row in evaluations),
        "global_exact_bodies": sum(row["global_size_exact"] for row in evaluations),
        "candidate_exact_families": len({row["family"] for row in exact}),
        "candidate_exact_folds": len({row["fold"] for row in exact}),
        "heldout_body_leakage_events": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_LEDGER_V1",
        "graph_assignments": assignments,
        "prediction_records": predictions,
        "heldout_evaluations": evaluations,
        "exact_match_rows": exact,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "previously_observed_graph_corpus_not_pristine": True,
            "same_prefrozen_split_reused": True,
            "cross_fold_learning_performed": False,
            "heldout_body_access_before_prediction": False,
            "complete_body_prediction_performed": True,
            "concrete_exact_tool_candidates_constructed": len(exact) > 0,
            "tool_execution_demonstrated": False,
            "new_operation_semantics": False,
            "native_dedup_executed": False,
            "runtime_primitive_invented": False,
            "validation_v6_or_v7_accessed": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


class ExactBodyPredictionReject(ValueError):
    pass


_EXPECTED: dict[str, Any] | None = None


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
    if (
        protocol.get("version") != "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_PROTOCOL_V1"
        or protocol.get("status")
        != "PREFROZEN_BEFORE_EXACT_BODY_PREDICTION_IMPLEMENTATION"
    ):
        raise ExactBodyPredictionReject("protocol identity")
    global _EXPECTED
    if _EXPECTED is None:
        _EXPECTED = run_exact_body_prediction()
    if set(ledger) != set(_EXPECTED):
        raise ExactBodyPredictionReject("ledger schema")
    changed = [
        key for key in sorted(_EXPECTED)
        if canonical(ledger[key]) != canonical(_EXPECTED[key])
    ]
    if changed:
        raise ExactBodyPredictionReject("recomputed ledger mismatch: " + ",".join(changed))


if __name__ == "__main__":
    result = run_exact_body_prediction()
    summary = result["summary"]
    print(
        "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" operator={summary['operator_sequence_exact']}"
        f" bodies={summary['candidate_exact_bodies']}"
        f" controls={summary['boundary_exact_bodies']}/{summary['global_exact_bodies']}"
    )
