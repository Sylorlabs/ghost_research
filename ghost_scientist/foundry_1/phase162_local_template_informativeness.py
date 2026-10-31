#!/usr/bin/env python3
"""Execute the frozen Phase162 typed-template informativeness ablation."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_template_informativeness_v1 import (
    IndependentInformativenessReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_template_informativeness_core_v1 import (
    InformativenessReject,
    canonical,
    digest,
    run_informativeness,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_TEMPLATE_INFORMATIVENESS_PROTOCOL_V1.json"
FREEZE = HERE / "results/local_template_informativeness_v1_freeze.json"
WORKER = HERE / "results/phase162_local_template_informativeness_worker.json"
RESULT = HERE / "results/phase162_local_template_informativeness.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_informativeness()
    independent = independent_run()
    verify_ledger(primary, protocol)
    independent_verify(primary, protocol)
    if canonical(primary) != canonical(independent):
        raise RuntimeError("independent informativeness ledgers disagree")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_ledger, InformativenessReject),
            (independent_verify, IndependentInformativenessReject),
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
        "source_result_mutation",
        lambda value: value.update(source_phase161_sha256="0" * 64),
    )
    case(
        "training_split_mutation",
        lambda value: value["summary"].update(training_graphs=15),
    )
    case(
        "heldout_learning_enabled",
        lambda value: value["claims"].update(heldout_learning_performed=True),
    )
    case(
        "candidate_match_fabricated",
        lambda value: value["candidate_matches"].append(
            copy.deepcopy(value["boundary_only_matches"][0])
        ),
    )
    case(
        "topology_only_count_reduced",
        lambda value: value["summary"].update(topology_only_heldout_matches=1),
    )
    case(
        "typed_rejection_fabricated",
        lambda value: value["typed_rejections"].append(
            copy.deepcopy(value["boundary_only_matches"][0])
        ),
    )
    case(
        "boundary_only_count_reduced",
        lambda value: value["summary"].update(boundary_only_heldout_matches=16),
    )
    case(
        "frequency_baseline_mutation",
        lambda value: value.update(frequency_baseline_topology_sha256="0" * 64),
    )
    case(
        "unseen_operator_pair_fabricated",
        lambda value: value["unseen_operator_pair_matches"].append(
            copy.deepcopy(value["candidate_matches"][0])
        ),
    )
    case(
        "information_bits_inflated",
        lambda value: value["summary"].update(candidate_information_bits=1.0),
    )
    case(
        "control_count_mutation",
        lambda value: value["summary"].update(fixed_control_nodes=18),
    )
    case(
        "claim_inflation",
        lambda value: value["claims"].update(
            typed_template_informative=True,
            concrete_exact_tool_reuse=True,
            P6_advanced=True,
            prospective_trial_authorized=True,
        ),
    )
    summary = primary["summary"]
    informative = (
        summary["candidate_heldout_matches"] >= 1
        and summary["typed_rejections"] >= 1
        and summary["candidate_information_bits"] > 0
    )
    payload = {
        "version": "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_WORKER_V1",
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
            "LOCAL_TYPED_TEMPLATE_INFORMATIVE_POSITIVE"
            if informative
            else "LOCAL_TYPED_TEMPLATE_STRUCTURAL_ONLY_VALID_NEGATIVE"
        ),
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE162_WORKER"
        f" classification={payload['classification']}"
        f" candidate={summary['candidate_heldout_matches']}"
        f" topology={summary['topology_only_heldout_matches']}"
        f" typed_rejections={summary['typed_rejections']}"
        f" bits={summary['candidate_information_bits']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"] == "FROZEN_BEFORE_ABLATION_IMPLEMENTATION_OR_OUTCOME"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("template-informativeness freeze mismatch")
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
        failure = HERE / "results/phase162_local_template_informativeness_failed_worker_receipt.json"
        failure.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
        raise RuntimeError("informativeness worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_ablation_outcome": True,
        "same_authenticated_split_reused": (
            summary["training_graphs"] == 16 and summary["heldout_graphs"] == 7
        ),
        "two_independent_implementations_agree": (
            observed["ledger_sha256"] == observed["independent_ledger_sha256"]
            and summary["independent_implementations"] == 2
        ),
        "twelve_hostile_cases_rejected_twice": (
            summary["hostile_cases"] == summary["hostile_rejected_twice"] == 12
        ),
        "candidate_transfer_reproduced": summary["candidate_heldout_matches"] == 2,
        "typed_ablation_exact": (
            summary["topology_only_heldout_matches"]
            - summary["candidate_heldout_matches"]
            == summary["typed_rejections"]
        ),
        "information_measure_exact": (
            (summary["typed_rejections"] == 0)
            is (summary["candidate_information_bits"] == 0.0)
        ),
        "local_claim_boundary_preserved": (
            observed["ledger"]["claims"]["concrete_exact_tool_reuse"] is False
            and observed["ledger"]["claims"]["new_operation_semantics"] is False
            and observed["ledger"]["claims"]["P6_advanced"] is False
            and observed["validation_v6_or_v7_accessed"] is False
            and observed["prospective_trial_authorized"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("template-informativeness execution failed")
    result = {
        "version": "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "structural_topology_transfer_reproduced": True,
            "typed_constraint_added_heldout_information": (
                observed["classification"]
                == "LOCAL_TYPED_TEMPLATE_INFORMATIVE_POSITIVE"
            ),
            "unseen_operator_pairs_bound": summary["unseen_operator_pairs"],
            "unseen_operator_pairs_are_new_semantics": False,
            "concrete_exact_tool_reuse_demonstrated": False,
            "runtime_primitive_invented": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "require learned constraints that exclude a topology-only "
                "null on a fresh local split before spending work on runtime "
                "specialization; operator and recipe holes must predict or "
                "construct behavior rather than merely bind it"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE162"
        f" status={result['status']}"
        f" candidate={summary['candidate_heldout_matches']}"
        f" topology={summary['topology_only_heldout_matches']}"
        f" typed_rejections={summary['typed_rejections']}"
        f" boundary={summary['boundary_only_heldout_matches']}"
        f" frequency={summary['frequency_baseline_heldout_matches']}"
        f" unseen_pairs={summary['unseen_operator_pairs']}"
        " concrete_reuse=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
