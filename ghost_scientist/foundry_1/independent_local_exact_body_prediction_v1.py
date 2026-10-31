#!/usr/bin/env python3
"""Independent five-fold complete canonical-body prediction replay."""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import pathlib
from collections import Counter, defaultdict
from typing import Any

from independent_local_grammar_emergence_v1 import load


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/LOCAL_EXACT_BODY_PREDICTION_PROTOCOL_V1.json"
)
SALT = "ghost-foundry:operator-prediction-v1:"


class IndependentExactBodyPredictionReject(ValueError):
    """The proposed ledger differs from independent fold-local replay."""


def _canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _digest(value: object) -> str:
    return hashlib.sha256(_canonical(value)).hexdigest()


def _sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _fold(graph_id: str) -> int:
    return int.from_bytes(
        hashlib.sha256((SALT + graph_id).encode()).digest(), "big"
    ) % 5


def _choice(
    counts: Counter[bytes],
    bodies: dict[bytes, dict[str, Any]],
) -> dict[str, Any]:
    if not counts:
        raise IndependentExactBodyPredictionReject(
            "empty body frequency table"
        )
    maximum = max(counts.values())
    selected = min(
        value for value, count in counts.items() if count == maximum
    )
    return bodies[selected]


def _targets(body: dict[str, Any]) -> list[str]:
    return [node["target"] for node in body["nodes"]]


def _frozen_protocol() -> dict[str, Any]:
    protocol = json.loads(PROTOCOL.read_text())
    try:
        if (
            protocol["version"]
            != "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_PROTOCOL_V1"
            or protocol["status"]
            != "PREFROZEN_BEFORE_EXACT_BODY_PREDICTION_IMPLEMENTATION"
            or protocol["split"]["salt"] != SALT
            or protocol["split"]["folds"] != 5
            or protocol["split"]["expected_graph_counts"]
            != [6, 4, 4, 1, 8]
            or protocol["split"]["cross_fold_learning_forbidden"]
            is not True
            or protocol["candidate"][
                "heldout_body_access_before_prediction"
            ]
            is not False
            or protocol["decision_rule"][
                "positive_creates_concrete_exact_tool_candidates"
            ]
            is not True
            or protocol["decision_rule"][
                "positive_requires_execution_causal_and_native_dedup_next"
            ]
            is not True
            or protocol["decision_rule"][
                "never_call_exact_recurrence_new_operation_semantics"
            ]
            is not True
            or protocol["decision_rule"][
                "never_advance_P2_or_P6_or_authorize_prospective_trial"
            ]
            is not True
            or protocol["claim_boundary"][
                "bounded_local_cross_validation_only"
            ]
            is not True
            or protocol["claim_boundary"]["execution_not_yet_demonstrated"]
            is not True
            or protocol["claim_boundary"]["native_novelty_not_yet_tested"]
            is not True
            or protocol["claim_boundary"]["P2_not_advanced"] is not True
            or protocol["claim_boundary"]["P6_not_advanced"] is not True
            or protocol["claim_boundary"]["prospective_trial_authorized"]
            is not False
            or protocol["claim_boundary"]["prospective_trial_executed"]
            is not False
            or len(protocol["hostile_requirements"]["must_cover"]) != 14
        ):
            raise IndependentExactBodyPredictionReject(
                "protocol boundary"
            )
    except (KeyError, TypeError) as error:
        raise IndependentExactBodyPredictionReject(
            "protocol schema"
        ) from error
    for provider in protocol["provider_records"]:
        try:
            path = HERE / provider["path"]
            expected = provider["sha256"]
        except (KeyError, TypeError) as error:
            raise IndependentExactBodyPredictionReject(
                "provider schema"
            ) from error
        if _sha(path) != expected:
            raise IndependentExactBodyPredictionReject(
                f"provider hash: {provider.get('path')}"
            )
    return protocol


@functools.lru_cache(maxsize=1)
def _computed() -> dict[str, Any]:
    _frozen_protocol()
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
        assignment["graph_id"]: assignment["fold"]
        for assignment in assignments
    }
    if len(fold_by_graph) != len(records):
        raise IndependentExactBodyPredictionReject(
            "duplicate graph identity"
        )
    fold_counts = [
        sum(assignment["fold"] == fold for assignment in assignments)
        for fold in range(5)
    ]
    if len(records) != 23 or fold_counts != [6, 4, 4, 1, 8]:
        raise IndependentExactBodyPredictionReject("fold census")

    predictions: list[dict[str, Any]] = []
    evaluations: list[dict[str, Any]] = []
    for heldout_fold in range(5):
        topology_bodies: dict[str, Counter[bytes]] = defaultdict(Counter)
        topology_occurrences: Counter[str] = Counter()
        topology_families: dict[str, set[str]] = defaultdict(set)
        topology_shapes: dict[str, dict[str, Any]] = {}
        boundary_bodies: dict[
            tuple[int, tuple[int, ...]], Counter[bytes]
        ] = defaultdict(Counter)
        size_bodies: dict[int, Counter[bytes]] = defaultdict(Counter)
        bodies: dict[bytes, dict[str, Any]] = {}

        # Every predictor and control is frozen from the other four folds.
        for record in records:
            if fold_by_graph[record["graph_id"]] == heldout_fold:
                continue
            for motif in record["motifs"]:
                topology_id = motif["topology_sha256"]
                body_bytes = _canonical(motif["body"])
                if (
                    body_bytes in bodies
                    and bodies[body_bytes] != motif["body"]
                ):
                    raise IndependentExactBodyPredictionReject(
                        "canonical body collision"
                    )
                bodies[body_bytes] = motif["body"]
                topology_bodies[topology_id][body_bytes] += 1
                topology_occurrences[topology_id] += 1
                topology_families[topology_id].add(record["family"])
                if (
                    topology_id in topology_shapes
                    and topology_shapes[topology_id] != motif["topology"]
                ):
                    raise IndependentExactBodyPredictionReject(
                        "topology digest collision"
                    )
                topology_shapes[topology_id] = motif["topology"]
                boundary = (
                    motif["topology"]["node_count"],
                    tuple(motif["topology"]["output_indices"]),
                )
                boundary_bodies[boundary][body_bytes] += 1
                size_bodies[motif["topology"]["node_count"]][
                    body_bytes
                ] += 1

        eligible = sorted(
            topology_id
            for topology_id in topology_bodies
            if topology_occurrences[topology_id] >= 3
            and len(topology_families[topology_id]) >= 2
        )
        fold_predictions: dict[str, dict[str, Any]] = {}
        for topology_id in eligible:
            shape = topology_shapes[topology_id]
            boundary = (
                shape["node_count"],
                tuple(shape["output_indices"]),
            )
            candidate = _choice(
                topology_bodies[topology_id], bodies
            )
            boundary_body = _choice(
                boundary_bodies[boundary], bodies
            )
            global_body = _choice(
                size_bodies[shape["node_count"]], bodies
            )
            prediction = {
                "fold": heldout_fold,
                "topology_sha256": topology_id,
                "training_occurrences": topology_occurrences[topology_id],
                "training_families": len(
                    topology_families[topology_id]
                ),
                "candidate_body": candidate,
                "candidate_body_sha256": _digest(candidate),
                "boundary_body": boundary_body,
                "boundary_body_sha256": _digest(boundary_body),
                "global_size_body": global_body,
                "global_size_body_sha256": _digest(global_body),
            }
            predictions.append(prediction)
            fold_predictions[topology_id] = prediction

        # Heldout bytes are first accessed only after all fold predictions exist.
        for record in records:
            if fold_by_graph[record["graph_id"]] != heldout_fold:
                continue
            for motif in record["motifs"]:
                prediction = fold_predictions.get(
                    motif["topology_sha256"]
                )
                if prediction is None:
                    continue
                actual = _canonical(motif["body"])
                candidate_exact = (
                    actual == _canonical(prediction["candidate_body"])
                )
                boundary_exact = (
                    actual == _canonical(prediction["boundary_body"])
                )
                global_exact = (
                    actual == _canonical(
                        prediction["global_size_body"]
                    )
                )
                evaluations.append(
                    {
                        "fold": heldout_fold,
                        "graph_id": record["graph_id"],
                        "family": record["family"],
                        "topology_sha256": motif["topology_sha256"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                        "candidate_body_sha256": prediction[
                            "candidate_body_sha256"
                        ],
                        "boundary_body_sha256": prediction[
                            "boundary_body_sha256"
                        ],
                        "global_size_body_sha256": prediction[
                            "global_size_body_sha256"
                        ],
                        "candidate_exact": candidate_exact,
                        "boundary_exact": boundary_exact,
                        "global_size_exact": global_exact,
                        "operator_sequence_exact": (
                            _targets(motif["body"])
                            == _targets(prediction["candidate_body"])
                        ),
                    }
                )

    exact = [row for row in evaluations if row["candidate_exact"]]
    summary = {
        "graphs": len(records),
        "folds": 5,
        "fold_graph_counts": fold_counts,
        "graph_assignments": len(assignments),
        "prediction_records": len(predictions),
        "eligible_heldout_motifs": len(evaluations),
        "operator_sequence_exact": sum(
            row["operator_sequence_exact"] for row in evaluations
        ),
        "candidate_exact_bodies": len(exact),
        "boundary_exact_bodies": sum(
            row["boundary_exact"] for row in evaluations
        ),
        "global_exact_bodies": sum(
            row["global_size_exact"] for row in evaluations
        ),
        "candidate_exact_families": len(
            {row["family"] for row in exact}
        ),
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


def independent_run() -> dict[str, Any]:
    """Return a detached copy of the strict independent replay."""

    return copy.deepcopy(_computed())


def verify_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    """Fail closed unless protocol and ledger equal independent replay."""

    if not isinstance(protocol, dict):
        raise IndependentExactBodyPredictionReject("protocol type")
    frozen = _frozen_protocol()
    if _canonical(protocol) != _canonical(frozen):
        raise IndependentExactBodyPredictionReject("protocol mismatch")
    if not isinstance(ledger, dict):
        raise IndependentExactBodyPredictionReject("ledger type")
    expected = _computed()
    if _canonical(ledger) != _canonical(expected):
        changed = sorted(
            key
            for key in set(ledger) | set(expected)
            if ledger.get(key) != expected.get(key)
        )
        raise IndependentExactBodyPredictionReject(
            "independent replay mismatch: " + ",".join(changed)
        )


if __name__ == "__main__":
    result = independent_run()
    verify_ledger(result, json.loads(PROTOCOL.read_text()))
    summary = result["summary"]
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_EXACT_BODY_PREDICTION"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" operator={summary['operator_sequence_exact']}"
        f" bodies={summary['candidate_exact_bodies']}"
        f" controls={summary['boundary_exact_bodies']}/"
        f"{summary['global_exact_bodies']}"
        " leakage=0 prospective=false"
    )
