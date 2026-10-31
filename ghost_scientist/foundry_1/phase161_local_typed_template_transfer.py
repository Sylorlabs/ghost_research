#!/usr/bin/env python3
"""Execute the frozen local typed-template transfer experiment."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_typed_template_transfer_v1 import (
    IndependentTemplateReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_typed_template_transfer_core_v1 import (
    TemplateLedgerReject,
    canonical,
    digest,
    run_template_transfer,
    verify_template_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/LOCAL_TYPED_TEMPLATE_TRANSFER_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/local_typed_template_transfer_v1_freeze.json"
WORKER_RESULT = HERE / "results/phase161_local_typed_template_transfer_worker.json"
RESULT = HERE / "results/phase161_local_typed_template_transfer.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_template_transfer()
    independent = independent_run()
    verify_template_ledger(primary, protocol)
    independent_verify(primary, protocol)
    for key in (
        "template_ids",
        "matches",
        "candidate_only_matches",
        "candidate_only_node_ids",
        "summary",
    ):
        if canonical(primary[key]) != canonical(independent[key]):
            raise RuntimeError(f"independent template result disagrees: {key}")

    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_template_ledger, TemplateLedgerReject),
            (independent_verify, IndependentTemplateReject),
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
        "training_split_mutation",
        lambda value: value["summary"].update(training_graphs=15),
    )
    case(
        "heldout_learning_enabled",
        lambda value: value["claims"].update(heldout_learning_performed=True),
    )
    case(
        "unknown_template_field",
        lambda value: value["templates"][0].update(unknown=True),
    )
    case(
        "topology_digest_mismatch",
        lambda value: value["templates"][0]["definition"].update(
            topology_sha256="0" * 64
        ),
    )
    # The observed template has no exact operator slot. A wildcard in place of
    # the first learned slot is therefore the strict verifier fixture for an
    # impermissibly weakened operator constraint.
    case(
        "preserved_operator_weakened",
        lambda value: value["templates"][0]["definition"][
            "operator_slots"
        ].__setitem__(0, {"wildcard": "op_0"}),
    )
    case(
        "operator_hole_removed",
        lambda value: value["templates"][0]["definition"][
            "operator_slots"
        ].__setitem__(0, {"exact": "aten.relu.default"}),
    )
    case(
        "recipe_hole_removed",
        lambda value: value["templates"][0]["definition"][
            "recipe_slots"
        ].__setitem__(0, {"exact": {"args": [], "kwargs": {}}}),
    )
    case(
        "type_equality_removed",
        lambda value: value["templates"][0]["definition"].update(
            node_output_type_equalities=[]
        ),
    )
    case(
        "type_equality_fabricated",
        lambda value: value["templates"][0]["definition"][
            "node_output_type_equalities"
        ].append([0, 0]),
    )
    case(
        "output_boundary_mutation",
        lambda value: value["templates"][0]["definition"].update(
            outputs=[{"node": 1}]
        ),
    )

    def fabricated_match(value: dict) -> None:
        row = copy.deepcopy(value["matches"][0])
        row["graph_id"] = "fabricated"
        value["matches"].append(row)
        value["summary"]["heldout_template_matches"] += 1
        value["summary"]["byte_identical_reconstructions"] += 1

    case("fabricated_template_match", fabricated_match)
    case(
        "non_byte_identical_reconstruction",
        lambda value: value["matches"][0].update(
            reconstructed_body_sha256="0" * 64,
            byte_identical_reconstruction=False,
        ),
    )
    case(
        "exact_control_match_removed",
        lambda value: value["summary"].update(exact_control_nodes=10),
    )
    case(
        "candidate_only_node_fabricated",
        lambda value: value["candidate_only_node_ids"].append(
            "fabricated:node"
        ),
    )
    case(
        "causal_removal_ledger_mutation",
        lambda value: value["summary"].update(
            causal_matches_after_remove_all_templates=1
        ),
    )
    case(
        "claim_inflation_to_concrete_reuse_or_prospective",
        lambda value: value["claims"].update(
            concrete_exact_tool_reuse=True,
            P6_advanced=True,
            prospective_trial_authorized=True,
        ),
    )

    summary = primary["summary"]
    positive = (
        summary["candidate_only_template_matches"] >= 1
        and summary["candidate_only_template_nodes"] >= 1
        and summary["byte_identical_reconstructions"]
        == summary["heldout_template_matches"]
    )
    payload = {
        "version": "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_WORKER_V1",
        "ledger": primary,
        "ledger_sha256": digest(primary),
        "independent": {
            "template_ids_sha256": digest(independent["template_ids"]),
            "matches_sha256": digest(independent["matches"]),
            "candidate_only_node_ids_sha256": digest(
                independent["candidate_only_node_ids"]
            ),
            "summary": independent["summary"],
        },
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
            "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
            if positive
            else "LOCAL_TYPED_TEMPLATE_TRANSFER_VALID_NEGATIVE"
        ),
        "native_dedup_required_now": False,
        "native_dedup_not_applicable_parameterized_dispatch": True,
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE161_WORKER"
        f" classification={payload['classification']}"
        f" templates={summary['selected_templates']}"
        f" matches={summary['heldout_template_matches']}"
        f" candidate_only={summary['candidate_only_template_matches']}"
        f" nodes={summary['candidate_only_template_nodes']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"] == "FROZEN_BEFORE_TEMPLATE_OR_MATCH_IMPLEMENTATION"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("typed-template freeze mismatch")
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
        failure = HERE / "results/phase161_local_typed_template_transfer_failed_worker_receipt.json"
        failure.write_text(
            json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n"
        )
        raise RuntimeError("typed-template worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER_RESULT.read_text())
    summary = observed["summary"]
    checks = {
        "post_phase160_protocol_frozen_before_template_implementation": True,
        "same_authenticated_split_reused": (
            summary["training_graphs"] == 16
            and summary["heldout_graphs"] == 7
        ),
        "two_independent_implementations_agree": (
            summary["independent_implementations"] == 2
        ),
        "sixteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"]
            == summary["hostile_rejected_twice"]
            == 16
        ),
        "heldout_learning_forbidden_and_absent": (
            observed["ledger"]["claims"]["heldout_learning_performed"] is False
        ),
        "all_matches_reconstruct_byte_identically": (
            summary["byte_identical_reconstructions"]
            == summary["heldout_template_matches"]
        ),
        "causal_removal_zeroes_matches": (
            summary["causal_matches_after_remove_all_templates"] == 0
        ),
        "parameterized_dispatch_not_mislabeled_native_invention": (
            observed["native_dedup_required_now"] is False
            and observed["native_dedup_not_applicable_parameterized_dispatch"]
            is True
            and observed["ledger"]["claims"]["concrete_exact_tool_reuse"] is False
            and observed["ledger"]["claims"]["runtime_primitive_invented"] is False
        ),
        "local_claim_boundary_preserved": (
            observed["validation_v6_or_v7_accessed"] is False
            and observed["prospective_trial_authorized"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("typed-template execution failed")
    result = {
        "version": "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "bounded_typed_topology_transfer_demonstrated": (
                observed["classification"]
                == "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
            ),
            "concrete_exact_tool_reuse_demonstrated": False,
            "runtime_primitive_invented": False,
            "native_dedup_executed": False,
            "native_dedup_not_applicable_parameterized_dispatch": True,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "freeze a specialization and amortization experiment that "
                "charges template dispatch, binding, and compilation against "
                "the exact, chain, and fixed controls; require a reusable "
                "concrete executable artifact before any tool-reuse claim"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE161"
        f" status={result['status']}"
        f" templates={summary['selected_templates']}"
        f" holes={summary['operator_holes']}+{summary['recipe_holes']}"
        f" matches={summary['heldout_template_matches']}"
        f" candidate_only={summary['candidate_only_template_matches']}"
        f" nodes={summary['candidate_only_template_nodes']}"
        " concrete_reuse=false P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
