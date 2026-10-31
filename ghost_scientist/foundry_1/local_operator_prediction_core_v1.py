#!/usr/bin/env python3
"""Primary five-fold training-only operator-sequence predictor."""

from __future__ import annotations

import hashlib
import json
import pathlib
from collections import Counter, defaultdict
from typing import Any

from local_grammar_emergence_core_v1 import canonical, enumerate_motifs, load_graphs


HERE = pathlib.Path(__file__).resolve().parent
SALT = "ghost-foundry:operator-prediction-v1:"


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def fold_for(graph_id: str) -> int:
    return int(hashlib.sha256((SALT + graph_id).encode()).hexdigest(), 16) % 5


def sequence(motif: dict[str, Any]) -> tuple[str, ...]:
    return tuple(node["target"] for node in motif["body"]["nodes"])


def most_frequent(counter: Counter[tuple[str, ...]]) -> tuple[str, ...]:
    return min(counter, key=lambda value: (-counter[value], canonical(list(value))))


def run_operator_prediction() -> dict[str, Any]:
    records = [enumerate_motifs(row) for row in load_graphs()]
    assignments = [
        {
            "graph_id": row["graph_id"],
            "family": row["family"],
            "fold": fold_for(row["graph_id"]),
        }
        for row in records
    ]
    fold_by_graph = {row["graph_id"]: row["fold"] for row in assignments}
    fixed = json.loads((HERE / "ATEN_FIXED_PORTFOLIO_V2.json").read_text())
    fixed_sequences = {tuple(tool["targets"]) for tool in fixed["tools"]}
    predictions = []
    evaluations = []
    for fold in range(5):
        topology_counts: dict[str, Counter[tuple[str, ...]]] = defaultdict(Counter)
        topology_families: dict[str, set[str]] = defaultdict(set)
        topology_occurrences: Counter[str] = Counter()
        boundary_counts: dict[
            tuple[int, tuple[int, ...]], Counter[tuple[str, ...]]
        ] = defaultdict(Counter)
        size_counts: dict[int, Counter[tuple[str, ...]]] = defaultdict(Counter)
        topology_shape: dict[str, dict[str, Any]] = {}
        for row in records:
            if fold_by_graph[row["graph_id"]] == fold:
                continue
            for motif in row["motifs"]:
                identifier = motif["topology_sha256"]
                targets = sequence(motif)
                topology_counts[identifier][targets] += 1
                topology_occurrences[identifier] += 1
                topology_families[identifier].add(row["family"])
                topology_shape[identifier] = motif["topology"]
                boundary = (
                    motif["topology"]["node_count"],
                    tuple(motif["topology"]["output_indices"]),
                )
                boundary_counts[boundary][targets] += 1
                size_counts[motif["topology"]["node_count"]][targets] += 1
        eligible = {
            identifier
            for identifier in topology_counts
            if topology_occurrences[identifier] >= 3
            and len(topology_families[identifier]) >= 2
        }
        fold_predictions = {}
        for identifier in sorted(eligible):
            shape = topology_shape[identifier]
            boundary = (shape["node_count"], tuple(shape["output_indices"]))
            row = {
                "fold": fold,
                "topology_sha256": identifier,
                "training_occurrences": topology_occurrences[identifier],
                "training_families": len(topology_families[identifier]),
                "candidate_sequence": list(most_frequent(topology_counts[identifier])),
                "boundary_sequence": list(most_frequent(boundary_counts[boundary])),
                "global_size_sequence": list(
                    most_frequent(size_counts[shape["node_count"]])
                ),
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
                actual = list(sequence(motif))
                candidate_exact = actual == prediction["candidate_sequence"]
                boundary_exact = actual == prediction["boundary_sequence"]
                global_exact = actual == prediction["global_size_sequence"]
                evaluations.append(
                    {
                        "fold": fold,
                        "graph_id": graph["graph_id"],
                        "family": graph["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "actual_sequence": actual,
                        "candidate_sequence": prediction["candidate_sequence"],
                        "boundary_sequence": prediction["boundary_sequence"],
                        "global_size_sequence": prediction["global_size_sequence"],
                        "candidate_exact": candidate_exact,
                        "boundary_exact": boundary_exact,
                        "global_size_exact": global_exact,
                        "candidate_paired_win": candidate_exact and not boundary_exact,
                        "boundary_paired_win": boundary_exact and not candidate_exact,
                        "actual_sequence_in_fixed_portfolio": tuple(actual)
                        in fixed_sequences,
                    }
                )
    candidate_exact_rows = [row for row in evaluations if row["candidate_exact"]]
    summary = {
        "graphs": len(records),
        "folds": 5,
        "fold_graph_counts": [
            sum(row["fold"] == fold for row in assignments) for fold in range(5)
        ],
        "graph_assignments": len(assignments),
        "prediction_records": len(predictions),
        "eligible_heldout_motifs": len(evaluations),
        "candidate_exact_sequences": len(candidate_exact_rows),
        "boundary_exact_sequences": sum(row["boundary_exact"] for row in evaluations),
        "global_exact_sequences": sum(row["global_size_exact"] for row in evaluations),
        "paired_candidate_wins": sum(
            row["candidate_paired_win"] for row in evaluations
        ),
        "paired_boundary_wins": sum(
            row["boundary_paired_win"] for row in evaluations
        ),
        "candidate_exact_families": len(
            {row["family"] for row in candidate_exact_rows}
        ),
        "candidate_exact_folds": len({row["fold"] for row in candidate_exact_rows}),
        "fixed_portfolio_sequence_matches": sum(
            row["actual_sequence_in_fixed_portfolio"] for row in evaluations
        ),
        "unseen_sequences_predicted": 0,
        "heldout_target_leakage_events": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_OPERATOR_PREDICTION_LEDGER_V1",
        "split_salt": SALT,
        "graph_assignments": assignments,
        "prediction_records": predictions,
        "heldout_evaluations": evaluations,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "previously_observed_graph_corpus_not_pristine": True,
            "new_split_and_rule_prefrozen": True,
            "cross_fold_learning_performed": False,
            "heldout_target_or_recipe_access_before_prediction": False,
            "complete_operator_sequence_predicted": True,
            "recipe_or_type_prediction_performed": False,
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


class OperatorPredictionReject(ValueError):
    pass


_EXPECTED: dict[str, Any] | None = None


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
    if (
        protocol.get("version") != "FOUNDRY_LOCAL_OPERATOR_PREDICTION_PROTOCOL_V1"
        or protocol.get("status")
        != "PREFROZEN_BEFORE_FOLD_PREDICTION_IMPLEMENTATION"
        or protocol.get("split", {}).get("salt") != SALT
    ):
        raise OperatorPredictionReject("protocol identity")
    global _EXPECTED
    if _EXPECTED is None:
        _EXPECTED = run_operator_prediction()
    if set(ledger) != set(_EXPECTED):
        raise OperatorPredictionReject("ledger schema")
    changed = [
        key
        for key in sorted(_EXPECTED)
        if canonical(ledger[key]) != canonical(_EXPECTED[key])
    ]
    if changed:
        raise OperatorPredictionReject("recomputed ledger mismatch: " + ",".join(changed))


if __name__ == "__main__":
    result = run_operator_prediction()
    summary = result["summary"]
    print(
        "FOUNDRY_LOCAL_OPERATOR_PREDICTION"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" candidate={summary['candidate_exact_sequences']}"
        f" boundary={summary['boundary_exact_sequences']}"
        f" global={summary['global_exact_sequences']}"
        f" paired={summary['paired_candidate_wins']}/{summary['paired_boundary_wins']}"
    )
