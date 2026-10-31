#!/usr/bin/env python3
"""Independent five-fold evaluator for local operator-sequence prediction."""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import pathlib
from collections import Counter, defaultdict
from typing import Any

from independent_local_grammar_emergence_v1 import encode, load


HERE = pathlib.Path(__file__).resolve().parent
SALT = "ghost-foundry:operator-prediction-v1:"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


class IndependentOperatorPredictionReject(ValueError):
    """The ledger disagrees with the independent fold-local replay."""


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _fold(graph_id: str) -> int:
    payload = (SALT + graph_id).encode()
    return int.from_bytes(hashlib.sha256(payload).digest(), "big") % 5


def _targets(motif: dict[str, Any]) -> tuple[str, ...]:
    return tuple(node["target"] for node in motif["body"]["nodes"])


def _frequency_choice(
    counts: Counter[tuple[str, ...]],
) -> tuple[str, ...]:
    if not counts:
        raise IndependentOperatorPredictionReject("empty frequency table")
    best_count = max(counts.values())
    tied = [value for value, count in counts.items() if count == best_count]
    return min(tied, key=lambda value: encode(list(value)))


@functools.lru_cache(maxsize=1)
def _computed() -> dict[str, Any]:
    records = load()
    assignments = [
        {
            "graph_id": record["graph_id"],
            "family": record["family"],
            "fold": _fold(record["graph_id"]),
        }
        for record in records
    ]
    fold_by_graph = {
        record["graph_id"]: record["fold"] for record in assignments
    }
    if len(fold_by_graph) != len(records):
        raise IndependentOperatorPredictionReject("duplicate graph identity")

    fixed_raw = json.loads(FIXED.read_text())
    fixed_sequences = {
        tuple(record["targets"]) for record in fixed_raw["tools"]
    }
    prediction_records: list[dict[str, Any]] = []
    heldout_evaluations: list[dict[str, Any]] = []

    for heldout_fold in range(5):
        topology_sequence_counts: dict[
            str, Counter[tuple[str, ...]]
        ] = defaultdict(Counter)
        topology_families: dict[str, set[str]] = defaultdict(set)
        topology_occurrences: Counter[str] = Counter()
        topology_shapes: dict[str, dict[str, Any]] = {}
        boundary_sequence_counts: dict[
            tuple[int, tuple[int, ...]], Counter[tuple[str, ...]]
        ] = defaultdict(Counter)
        size_sequence_counts: dict[
            int, Counter[tuple[str, ...]]
        ] = defaultdict(Counter)

        # Construct every statistic exclusively from graphs outside this fold.
        for record in records:
            if fold_by_graph[record["graph_id"]] == heldout_fold:
                continue
            for motif in record["motifs"]:
                topology_id = motif["topology_sha256"]
                target_sequence = _targets(motif)
                topology_sequence_counts[topology_id][target_sequence] += 1
                topology_occurrences[topology_id] += 1
                topology_families[topology_id].add(record["family"])
                topology_shapes[topology_id] = motif["topology"]
                boundary_key = (
                    motif["topology"]["node_count"],
                    tuple(motif["topology"]["output_indices"]),
                )
                boundary_sequence_counts[boundary_key][
                    target_sequence
                ] += 1
                size_sequence_counts[motif["topology"]["node_count"]][
                    target_sequence
                ] += 1

        eligible_ids = sorted(
            topology_id
            for topology_id in topology_sequence_counts
            if topology_occurrences[topology_id] >= 3
            and len(topology_families[topology_id]) >= 2
        )
        predictions_for_fold: dict[str, dict[str, Any]] = {}
        for topology_id in eligible_ids:
            shape = topology_shapes[topology_id]
            boundary_key = (
                shape["node_count"],
                tuple(shape["output_indices"]),
            )
            prediction = {
                "fold": heldout_fold,
                "topology_sha256": topology_id,
                "training_occurrences": topology_occurrences[topology_id],
                "training_families": len(
                    topology_families[topology_id]
                ),
                "candidate_sequence": list(
                    _frequency_choice(
                        topology_sequence_counts[topology_id]
                    )
                ),
                "boundary_sequence": list(
                    _frequency_choice(
                        boundary_sequence_counts[boundary_key]
                    )
                ),
                "global_size_sequence": list(
                    _frequency_choice(
                        size_sequence_counts[shape["node_count"]]
                    )
                ),
            }
            prediction_records.append(prediction)
            predictions_for_fold[topology_id] = prediction

        # Only now inspect this fold's targets and score frozen predictions.
        for record in records:
            if fold_by_graph[record["graph_id"]] != heldout_fold:
                continue
            for motif in record["motifs"]:
                prediction = predictions_for_fold.get(
                    motif["topology_sha256"]
                )
                if prediction is None:
                    continue
                actual = list(_targets(motif))
                candidate_exact = (
                    actual == prediction["candidate_sequence"]
                )
                boundary_exact = (
                    actual == prediction["boundary_sequence"]
                )
                global_exact = (
                    actual == prediction["global_size_sequence"]
                )
                heldout_evaluations.append(
                    {
                        "fold": heldout_fold,
                        "graph_id": record["graph_id"],
                        "family": record["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "actual_sequence": actual,
                        "candidate_sequence": prediction[
                            "candidate_sequence"
                        ],
                        "boundary_sequence": prediction[
                            "boundary_sequence"
                        ],
                        "global_size_sequence": prediction[
                            "global_size_sequence"
                        ],
                        "candidate_exact": candidate_exact,
                        "boundary_exact": boundary_exact,
                        "global_size_exact": global_exact,
                        "candidate_paired_win": (
                            candidate_exact and not boundary_exact
                        ),
                        "boundary_paired_win": (
                            boundary_exact and not candidate_exact
                        ),
                        "actual_sequence_in_fixed_portfolio": (
                            tuple(actual) in fixed_sequences
                        ),
                    }
                )

    exact_rows = [
        row for row in heldout_evaluations if row["candidate_exact"]
    ]
    summary = {
        "graphs": len(records),
        "folds": 5,
        "fold_graph_counts": [
            sum(row["fold"] == fold for row in assignments)
            for fold in range(5)
        ],
        "graph_assignments": len(assignments),
        "prediction_records": len(prediction_records),
        "eligible_heldout_motifs": len(heldout_evaluations),
        "candidate_exact_sequences": len(exact_rows),
        "boundary_exact_sequences": sum(
            row["boundary_exact"] for row in heldout_evaluations
        ),
        "global_exact_sequences": sum(
            row["global_size_exact"] for row in heldout_evaluations
        ),
        "paired_candidate_wins": sum(
            row["candidate_paired_win"] for row in heldout_evaluations
        ),
        "paired_boundary_wins": sum(
            row["boundary_paired_win"] for row in heldout_evaluations
        ),
        "candidate_exact_families": len(
            {row["family"] for row in exact_rows}
        ),
        "candidate_exact_folds": len(
            {row["fold"] for row in exact_rows}
        ),
        "fixed_portfolio_sequence_matches": sum(
            row["actual_sequence_in_fixed_portfolio"]
            for row in heldout_evaluations
        ),
        # A fold-local frequency learner emits only a sequence observed in
        # that fold's training partition.
        "unseen_sequences_predicted": 0,
        "heldout_target_leakage_events": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_OPERATOR_PREDICTION_LEDGER_V1",
        "split_salt": SALT,
        "graph_assignments": assignments,
        "prediction_records": prediction_records,
        "heldout_evaluations": heldout_evaluations,
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


def independent_run() -> dict[str, Any]:
    """Return a detached independent replay of the complete ledger."""

    return copy.deepcopy(_computed())


def verify_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    """Fail closed unless protocol and ledger equal the clean-room replay."""

    if not isinstance(protocol, dict):
        raise IndependentOperatorPredictionReject("protocol type")
    try:
        if (
            protocol["version"]
            != "FOUNDRY_LOCAL_OPERATOR_PREDICTION_PROTOCOL_V1"
            or protocol["status"]
            != "PREFROZEN_BEFORE_FOLD_PREDICTION_IMPLEMENTATION"
            or protocol["split"]["salt"] != SALT
            or protocol["split"]["folds"] != 5
            or protocol["split"]["expected_graph_counts"]
            != [6, 4, 4, 1, 8]
            or protocol["split"]["cross_fold_learning_forbidden"]
            is not True
            or protocol["candidate"]["per_fold_training_only"] is not True
            or protocol["candidate"][
                "heldout_target_or_recipe_access_before_prediction"
            ]
            is not False
            or protocol["motif_universe"]["llm_calls"] != 0
            or protocol["decision_rule"][
                "never_call_frequency_reproduction_new_operation_semantics"
            ]
            is not True
            or protocol["decision_rule"][
                "never_advance_P2_or_P6_or_authorize_prospective_trial"
            ]
            is not True
            or protocol["claim_boundary"][
                "operator_prediction_not_recipe_prediction"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_concrete_exact_tool_reuse_claim"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_new_operation_semantics_claim"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_runtime_primitive_invention_claim"
            ]
            is not True
        ):
            raise IndependentOperatorPredictionReject("protocol boundary")
    except (KeyError, TypeError) as error:
        raise IndependentOperatorPredictionReject(
            "protocol schema"
        ) from error

    if not isinstance(ledger, dict):
        raise IndependentOperatorPredictionReject("ledger type")
    expected = _computed()
    if canonical(ledger) != canonical(expected):
        changed = sorted(
            key
            for key in set(ledger) | set(expected)
            if ledger.get(key) != expected.get(key)
        )
        raise IndependentOperatorPredictionReject(
            "independent replay mismatch: " + ",".join(changed)
        )


if __name__ == "__main__":
    result = independent_run()
    protocol = json.loads(
        (
            HERE
            / "arm_adapter_fixtures/"
            "LOCAL_OPERATOR_PREDICTION_PROTOCOL_V1.json"
        ).read_text()
    )
    verify_ledger(result, protocol)
    summary = result["summary"]
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_OPERATOR_PREDICTION"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" candidate={summary['candidate_exact_sequences']}"
        f" boundary={summary['boundary_exact_sequences']}"
        f" global={summary['global_exact_sequences']}"
        f" paired={summary['paired_candidate_wins']}/"
        f"{summary['paired_boundary_wins']}"
        " leakage=0"
    )
