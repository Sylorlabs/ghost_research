#!/usr/bin/env python3
"""Execute the frozen five-fold local operator-prediction experiment."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_operator_prediction_v1 import (
    IndependentOperatorPredictionReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_operator_prediction_core_v1 import (
    OperatorPredictionReject,
    canonical,
    digest,
    run_operator_prediction,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_OPERATOR_PREDICTION_PROTOCOL_V1.json"
FREEZE = HERE / "results/local_operator_prediction_v1_freeze.json"
WORKER = HERE / "results/phase163_local_operator_prediction_worker.json"
RESULT = HERE / "results/phase163_local_operator_prediction.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_operator_prediction()
    independent = independent_run()
    verify_ledger(primary, protocol)
    independent_verify(primary, protocol)
    if canonical(primary) != canonical(independent):
        raise RuntimeError("independent operator-prediction ledgers disagree")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_ledger, OperatorPredictionReject),
            (independent_verify, IndependentOperatorPredictionReject),
        ):
            try:
                verifier(altered, protocol)
            except (error, KeyError, TypeError, ValueError, json.JSONDecodeError):
                rejected.append(True)
            else:
                rejected.append(False)
        hostile.append(
            {
                "case": name,
                "primary_rejected": rejected[0],
                "independent_rejected": rejected[1],
            }
        )

    case(
        "fold_assignment_mutation",
        lambda value: value["graph_assignments"][0].update(fold=4),
    )
    case("graph_omitted", lambda value: value["graph_assignments"].pop())
    case(
        "graph_duplicated_across_heldout_folds",
        lambda value: value["graph_assignments"].append(
            {**value["graph_assignments"][0], "fold": 4}
        ),
    )
    case(
        "training_threshold_weakened",
        lambda value: value["prediction_records"][0].update(training_occurrences=2),
    )
    case(
        "training_family_count_fabricated",
        lambda value: value["prediction_records"][0].update(training_families=99),
    )
    case(
        "target_prediction_tie_changed",
        lambda value: value["prediction_records"][0]["candidate_sequence"].reverse(),
    )
    case(
        "heldout_target_leakage_enabled",
        lambda value: value["claims"].update(
            heldout_target_or_recipe_access_before_prediction=True
        ),
    )

    def fabricate_exact(value: dict) -> None:
        row = next(row for row in value["heldout_evaluations"] if not row["candidate_exact"])
        row["candidate_exact"] = True
        value["summary"]["candidate_exact_sequences"] += 1

    case("candidate_exact_row_fabricated", fabricate_exact)
    case(
        "boundary_exact_count_reduced",
        lambda value: value["summary"].update(boundary_exact_sequences=-1),
    )
    case(
        "global_exact_count_reduced",
        lambda value: value["summary"].update(global_exact_sequences=-1),
    )
    case(
        "paired_candidate_win_fabricated",
        lambda value: value["summary"].update(paired_candidate_wins=19),
    )
    case(
        "paired_boundary_loss_removed",
        lambda value: value["summary"].update(paired_boundary_wins=-1),
    )
    case(
        "family_count_inflated",
        lambda value: value["summary"].update(candidate_exact_families=23),
    )
    case(
        "fold_count_inflated",
        lambda value: value["summary"].update(candidate_exact_folds=6),
    )
    case(
        "unseen_sequence_prediction_fabricated",
        lambda value: value["summary"].update(unseen_sequences_predicted=1),
    )
    case(
        "claim_inflation",
        lambda value: value["claims"].update(
            recipe_or_type_prediction_performed=True,
            concrete_exact_tool_reuse=True,
            new_operation_semantics=True,
            P6_advanced=True,
            prospective_trial_authorized=True,
        ),
    )
    summary = primary["summary"]
    positive = (
        summary["eligible_heldout_motifs"] >= 10
        and summary["candidate_exact_families"] >= 3
        and summary["candidate_exact_folds"] >= 3
        and summary["paired_candidate_wins"] > summary["paired_boundary_wins"]
        and summary["candidate_exact_sequences"] > summary["boundary_exact_sequences"]
        and summary["candidate_exact_sequences"] > summary["global_exact_sequences"]
    )
    payload = {
        "version": "FOUNDRY_LOCAL_OPERATOR_PREDICTION_WORKER_V1",
        "ledger": primary,
        "ledger_sha256": digest(primary),
        "independent_ledger_sha256": digest(independent),
        "hostile_rejections": hostile,
        "summary": {
            **summary,
            "independent_implementations": 2,
            "hostile_cases": len(hostile),
            "hostile_rejected_twice": sum(
                row["primary_rejected"] and row["independent_rejected"]
                for row in hostile
            ),
        },
        "classification": (
            "LOCAL_OPERATOR_PREDICTION_POSITIVE"
            if positive
            else "LOCAL_OPERATOR_PREDICTION_VALID_NEGATIVE"
        ),
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE163_WORKER"
        f" classification={payload['classification']}"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" exact={summary['candidate_exact_sequences']}"
        f" controls={summary['boundary_exact_sequences']}/{summary['global_exact_sequences']}"
        f" paired={summary['paired_candidate_wins']}/{summary['paired_boundary_wins']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"]
        == "FROZEN_BEFORE_FOLD_PREDICTION_IMPLEMENTATION_OR_OUTCOME"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("operator-prediction freeze mismatch")
    limits = protocol["resource_limits"]
    receipt = run_metered_tree(
        [sys.executable, str(pathlib.Path(__file__).resolve()), "--worker"],
        cwd=HERE,
        wall_limit_seconds=limits["wall_seconds"],
        cpu_limit_seconds=limits["cpu_seconds"],
        rss_limit_kib=limits["rss_kib"],
        environment={"PYTHONWARNINGS": "ignore"},
    )
    if receipt["returncode"] != 0:
        failure = HERE / "results/phase163_local_operator_prediction_failed_worker_receipt.json"
        failure.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
        raise RuntimeError("operator-prediction worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_prediction_outcomes": True,
        "five_fold_assignment_exact": summary["fold_graph_counts"] == [6, 4, 4, 1, 8],
        "every_graph_heldout_once": (
            summary["graphs"] == summary["graph_assignments"] == 23
        ),
        "two_independent_implementations_agree": (
            observed["ledger_sha256"] == observed["independent_ledger_sha256"]
            and summary["independent_implementations"] == 2
        ),
        "sixteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"] == summary["hostile_rejected_twice"] == 16
        ),
        "no_heldout_target_leakage": (
            summary["heldout_target_leakage_events"] == 0
            and observed["ledger"]["claims"][
                "heldout_target_or_recipe_access_before_prediction"
            ]
            is False
        ),
        "frequency_learner_emits_no_unseen_sequence": (
            summary["unseen_sequences_predicted"] == 0
        ),
        "operator_only_claim_boundary_preserved": (
            observed["ledger"]["claims"]["complete_operator_sequence_predicted"]
            is True
            and observed["ledger"]["claims"]["recipe_or_type_prediction_performed"]
            is False
            and observed["ledger"]["claims"]["concrete_exact_tool_reuse"] is False
            and observed["ledger"]["claims"]["P6_advanced"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("operator-prediction execution failed")
    result = {
        "version": "FOUNDRY_LOCAL_OPERATOR_PREDICTION_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "training_only_complete_operator_prediction_demonstrated": (
                observed["classification"] == "LOCAL_OPERATOR_PREDICTION_POSITIVE"
            ),
            "recipe_and_type_prediction_demonstrated": False,
            "concrete_exact_tool_construction_demonstrated": False,
            "new_operation_semantics": False,
            "runtime_primitive_invented": False,
            "native_dedup_executed": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "freeze training-only full body prediction on the same folds, "
                "requiring operator sequence, canonical argument recipe, and "
                "output types to be predicted before heldout access; only exact "
                "body predictions may proceed to executable construction"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE163"
        f" status={result['status']}"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" exact={summary['candidate_exact_sequences']}"
        f" families={summary['candidate_exact_families']}"
        f" folds={summary['candidate_exact_folds']}"
        f" controls={summary['boundary_exact_sequences']}/{summary['global_exact_sequences']}"
        " exact_tool=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
