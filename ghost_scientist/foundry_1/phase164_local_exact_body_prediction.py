#!/usr/bin/env python3
"""Execute the frozen complete canonical body prediction experiment."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_exact_body_prediction_v1 import (
    IndependentExactBodyPredictionReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_exact_body_prediction_core_v1 import (
    ExactBodyPredictionReject,
    canonical,
    digest,
    run_exact_body_prediction,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_BODY_PREDICTION_PROTOCOL_V1.json"
FREEZE = HERE / "results/local_exact_body_prediction_v1_freeze.json"
WORKER = HERE / "results/phase164_local_exact_body_prediction_worker.json"
RESULT = HERE / "results/phase164_local_exact_body_prediction.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_exact_body_prediction()
    independent = independent_run()
    verify_ledger(primary, protocol)
    independent_verify(primary, protocol)
    if canonical(primary) != canonical(independent):
        raise RuntimeError("independent exact-body ledgers disagree")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_ledger, ExactBodyPredictionReject),
            (independent_verify, IndependentExactBodyPredictionReject),
        ):
            try:
                verifier(altered, protocol)
            except (error, KeyError, TypeError, ValueError, json.JSONDecodeError):
                rejected.append(True)
            else:
                rejected.append(False)
        hostile.append(
            {"case": name, "primary_rejected": rejected[0], "independent_rejected": rejected[1]}
        )

    case("fold_mutation", lambda value: value["graph_assignments"][0].update(fold=4))
    case("graph_omission", lambda value: value["graph_assignments"].pop())
    case(
        "eligibility_weakening",
        lambda value: value["prediction_records"][0].update(training_occurrences=2),
    )
    case(
        "training_family_fabrication",
        lambda value: value["prediction_records"][0].update(training_families=99),
    )
    case(
        "predicted_operator_mutation",
        lambda value: value["prediction_records"][0]["candidate_body"]["nodes"][0].update(
            target="aten.fabricated.default"
        ),
    )
    case(
        "predicted_recipe_mutation",
        lambda value: value["prediction_records"][0]["candidate_body"]["nodes"][0].update(
            kwargs={"dict": [["fabricated", {"literal": True}]]}
        ),
    )
    case(
        "predicted_input_type_mutation",
        lambda value: value["prediction_records"][0]["candidate_body"]["inputs"][0][
            "type"
        ].update(rank=99),
    )
    case(
        "predicted_output_type_mutation",
        lambda value: value["prediction_records"][0]["candidate_body"]["nodes"][0][
            "output_type"
        ].update(dtype="torch.float64"),
    )
    case(
        "predicted_output_boundary_mutation",
        lambda value: value["prediction_records"][0]["candidate_body"].update(outputs=[]),
    )
    case(
        "heldout_body_leakage_enabled",
        lambda value: value["claims"].update(heldout_body_access_before_prediction=True),
    )

    def fabricate_exact(value: dict) -> None:
        row = next(row for row in value["heldout_evaluations"] if not row["candidate_exact"])
        row["candidate_exact"] = True
        value["exact_match_rows"].append(copy.deepcopy(row))
        value["summary"]["candidate_exact_bodies"] += 1

    case("exact_match_fabricated", fabricate_exact)
    case(
        "control_count_mutation",
        lambda value: value["summary"].update(boundary_exact_bodies=5),
    )
    case(
        "family_or_fold_inflation",
        lambda value: value["summary"].update(candidate_exact_families=23, candidate_exact_folds=5),
    )
    case(
        "claim_inflation",
        lambda value: value["claims"].update(
            tool_execution_demonstrated=True,
            new_operation_semantics=True,
            native_dedup_executed=True,
            P6_advanced=True,
            prospective_trial_authorized=True,
        ),
    )
    summary = primary["summary"]
    positive = (
        summary["candidate_exact_bodies"] >= 1
        and summary["candidate_exact_families"] >= 2
        and summary["candidate_exact_folds"] >= 2
        and summary["candidate_exact_bodies"] > summary["boundary_exact_bodies"]
        and summary["candidate_exact_bodies"] > summary["global_exact_bodies"]
    )
    payload = {
        "version": "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_WORKER_V1",
        "ledger": primary,
        "ledger_sha256": digest(primary),
        "independent_ledger_sha256": digest(independent),
        "hostile_rejections": hostile,
        "summary": {
            **summary,
            "independent_implementations": 2,
            "hostile_cases": len(hostile),
            "hostile_rejected_twice": sum(
                row["primary_rejected"] and row["independent_rejected"] for row in hostile
            ),
        },
        "classification": (
            "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
            if positive
            else "LOCAL_EXACT_BODY_PREDICTION_VALID_NEGATIVE"
        ),
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE164_WORKER"
        f" classification={payload['classification']}"
        f" eligible={summary['eligible_heldout_motifs']}"
        f" bodies={summary['candidate_exact_bodies']}"
        f" controls={summary['boundary_exact_bodies']}/{summary['global_exact_bodies']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"]
        == "FROZEN_BEFORE_EXACT_BODY_PREDICTION_IMPLEMENTATION_OR_OUTCOME"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("exact-body freeze mismatch")
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
        failure = HERE / "results/phase164_local_exact_body_prediction_failed_worker_receipt.json"
        failure.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
        raise RuntimeError("exact-body worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_exact_body_outcomes": True,
        "five_fold_assignment_exact": summary["fold_graph_counts"] == [6, 4, 4, 1, 8],
        "two_independent_implementations_agree": (
            observed["ledger_sha256"] == observed["independent_ledger_sha256"]
            and summary["independent_implementations"] == 2
        ),
        "fourteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"] == summary["hostile_rejected_twice"] == 14
        ),
        "no_heldout_body_leakage": (
            summary["heldout_body_leakage_events"] == 0
            and observed["ledger"]["claims"]["heldout_body_access_before_prediction"] is False
        ),
        "every_exact_row_byte_identical": (
            len(observed["ledger"]["exact_match_rows"]) == summary["candidate_exact_bodies"]
            and all(
                row["body_sha256"] == row["candidate_body_sha256"]
                for row in observed["ledger"]["exact_match_rows"]
            )
        ),
        "execution_and_native_claims_deferred": (
            observed["ledger"]["claims"]["tool_execution_demonstrated"] is False
            and observed["ledger"]["claims"]["native_dedup_executed"] is False
            and observed["ledger"]["claims"]["runtime_primitive_invented"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("exact-body execution failed")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "training_only_complete_body_prediction_demonstrated": (
                observed["classification"] == "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
            ),
            "concrete_exact_tool_candidates_constructed": (
                observed["classification"] == "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
            ),
            "tool_execution_demonstrated": False,
            "new_operation_semantics": False,
            "native_dedup_executed": False,
            "runtime_primitive_invented": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "freeze execution of each unique predicted body against its heldout "
                "source subgraph, then causally remove the predicted library and "
                "compile every surviving candidate against stock ATen for native dedup"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE164"
        f" status={result['status']}"
        f" bodies={summary['candidate_exact_bodies']}"
        f" families={summary['candidate_exact_families']}"
        f" folds={summary['candidate_exact_folds']}"
        f" controls={summary['boundary_exact_bodies']}/{summary['global_exact_bodies']}"
        " execution=false native=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
