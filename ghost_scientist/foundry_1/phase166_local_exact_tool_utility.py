#!/usr/bin/env python3
"""Execute the frozen fully charged local utility comparison."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_exact_tool_utility_v1 import (
    IndependentExactToolUtilityReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_exact_tool_utility_core_v1 import (
    ExactToolUtilityReject,
    canonical,
    digest,
    run_utility,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_TOOL_UTILITY_PROTOCOL_V1.json"
FREEZE = HERE / "results/local_exact_tool_utility_v1_freeze.json"
WORKER = HERE / "results/phase166_local_exact_tool_utility_worker.json"
RESULT = HERE / "results/phase166_local_exact_tool_utility.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    primary = run_utility()
    independent = independent_run()
    verify_ledger(primary, protocol)
    independent_verify(primary, protocol)
    if canonical(primary) != canonical(independent):
        raise RuntimeError("independent utility ledgers disagree")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        rejected = []
        for verifier, error in (
            (verify_ledger, ExactToolUtilityReject),
            (independent_verify, IndependentExactToolUtilityReject),
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

    case("candidate_match_mutation", lambda value: value["summary"].update(candidate_matches=16))
    case("candidate_tool_count_mutation", lambda value: value["summary"].update(candidate_tools=2))
    case(
        "training_scan_undercharge",
        lambda value: value["candidate_cost_components"].update(training_motif_scans=0),
    )
    case(
        "heldout_scan_undercharge",
        lambda value: value["candidate_cost_components"].update(heldout_motif_scans=0),
    )
    case(
        "model_definition_undercharge",
        lambda value: value["candidate_cost_components"].update(model_definition=0),
    )
    case(
        "exact_comparison_undercharge",
        lambda value: value["candidate_cost_components"].update(exact_comparisons=0),
    )
    case(
        "dispatch_undercharge",
        lambda value: value["candidate_cost_components"].update(dispatch=0),
    )
    case(
        "compile_unit_undercharge",
        lambda value: value["candidate_cost_components"].update(native_compile_units=0),
    )
    case(
        "fixed_definition_overcharge",
        lambda value: value["fixed_cost_components"].update(definition=999),
    )
    case(
        "fixed_visit_overcharge",
        lambda value: value["fixed_cost_components"].update(match_visits=9999),
    )
    case(
        "fixed_edge_overcharge",
        lambda value: value["fixed_cost_components"].update(edge_checks=9999),
    )
    case(
        "candidate_coverage_fabrication",
        lambda value: value["candidate_node_ids"].append("fabricated:node"),
    )
    case("fixed_coverage_removal", lambda value: value["fixed_node_ids"].pop())
    case(
        "candidate_only_node_fabrication",
        lambda value: value["candidate_only_node_ids"].append("fabricated:node"),
    )
    case(
        "causal_loss_mutation",
        lambda value: value["summary"].update(causal_candidate_only_nodes_after_remove_all=1),
    )
    case(
        "claim_inflation",
        lambda value: value["claims"].update(
            prospective_real_world_discovery=True,
            whole_graph_replacement_demonstrated=True,
            runtime_primitive_invented=True,
            P6_advanced=True,
            prospective_trial_authorized=True,
        ),
    )
    summary = primary["summary"]
    positive = summary["candidate_cheaper"] or summary["candidate_only_nodes"] > 0
    payload = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_WORKER_V1",
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
            "LOCAL_EXACT_TOOL_UTILITY_POSITIVE"
            if positive
            else "LOCAL_EXACT_TOOL_UTILITY_VALID_NEGATIVE"
        ),
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER.write_text(json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE166_WORKER"
        f" classification={payload['classification']}"
        f" cost={summary['candidate_total_cost']}/{summary['fixed_total_cost']}"
        f" nodes={summary['candidate_unique_nodes']}/{summary['fixed_unique_nodes']}"
        f" candidate_only={summary['candidate_only_nodes']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"] == "FROZEN_BEFORE_TOTAL_COST_OR_REACHABILITY_IMPLEMENTATION"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
        and all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
    ):
        raise RuntimeError("utility freeze mismatch")
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
        failure = HERE / "results/phase166_local_exact_tool_utility_failed_worker_receipt.json"
        failure.write_text(json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n")
        raise RuntimeError("utility worker failed: " + receipt["stderr_text"])
    observed = json.loads(WORKER.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_cost_or_reachability_outcome": True,
        "two_independent_implementations_agree": (
            observed["ledger_sha256"] == observed["independent_ledger_sha256"]
            and summary["independent_implementations"] == 2
        ),
        "sixteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"] == summary["hostile_rejected_twice"] == 16
        ),
        "complete_candidate_cost_charged": (
            all(value > 0 for value in observed["ledger"]["candidate_cost_components"].values())
            and summary["candidate_total_cost"]
            == sum(observed["ledger"]["candidate_cost_components"].values())
        ),
        "fixed_cost_exact": (
            summary["fixed_total_cost"]
            == sum(observed["ledger"]["fixed_cost_components"].values())
        ),
        "coverage_set_arithmetic_exact": (
            summary["candidate_only_nodes"]
            == len(observed["ledger"]["candidate_only_node_ids"])
            and summary["fixed_only_nodes"]
            == len(observed["ledger"]["fixed_only_node_ids"])
        ),
        "causal_removal_exact": (
            summary["causal_candidate_nodes_after_remove_all"] == 0
            and summary["causal_candidate_only_nodes_after_remove_all"] == 0
        ),
        "resource_dimensions_kept_separate": (
            len(observed["ledger"]["resource_receipts"]) == 3
            and len(observed["ledger"]["native_compile_cpu"]) == 3
            and observed["ledger"]["claims"]["abstract_cost_not_wall_clock_speedup"] is True
        ),
        "local_only_claim_boundary_preserved": (
            observed["ledger"]["claims"]["prospective_real_world_discovery"] is False
            and observed["ledger"]["claims"]["whole_graph_replacement_demonstrated"] is False
            and observed["ledger"]["claims"]["P6_advanced"] is False
            and observed["prospective_trial_authorized"] is False
        ),
        "metered_worker_passed": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
            and receipt["process_group_reaped"] is True
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("utility result failed")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "candidate_lower_abstract_cost": summary["candidate_cheaper"],
            "candidate_higher_benefit_per_cost": summary["candidate_more_efficient"],
            "locally_newly_reachable_nodes_demonstrated": summary["candidate_only_nodes"] > 0,
            "locally_newly_reachable_families": summary["candidate_only_families"],
            "prospective_real_world_discovery_demonstrated": False,
            "whole_graph_replacement_demonstrated": False,
            "runtime_primitive_invented": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "the local forge now constructs executable exact tools with bounded "
                "candidate-only reach, but at substantially higher total cost; use "
                "this frozen forge only after the external sponsor/provenance and V08 "
                "gates permit a genuinely fresh repository-disjoint trial"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_PHASE166"
        f" status={result['status']}"
        f" cost={summary['candidate_total_cost']}/{summary['fixed_total_cost']}"
        f" efficiency={summary['candidate_benefit_per_cost']:.9f}/{summary['fixed_benefit_per_cost']:.9f}"
        f" nodes={summary['candidate_unique_nodes']}/{summary['fixed_unique_nodes']}"
        f" candidate_only={summary['candidate_only_nodes']}"
        f" families={summary['candidate_only_families']}"
        " prospective=false P6=false"
    )


if __name__ == "__main__":
    main()
