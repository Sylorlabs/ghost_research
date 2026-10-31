#!/usr/bin/env python3
"""Execute the frozen local LLM-free grammar-emergence experiment."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys

from independent_local_grammar_emergence_v1 import (
    IndependentGrammarReject,
    independent_run,
    verify_ledger as independent_verify,
)
from local_grammar_emergence_core_v1 import (
    GrammarLedgerReject,
    canonical,
    digest,
    run_experiment,
    verify_ledger,
)
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/LOCAL_GRAMMAR_EMERGENCE_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/local_grammar_emergence_v1_freeze.json"
WORKER_RESULT = HERE / "results/phase160_local_grammar_emergence_worker.json"
RESULT = HERE / "results/phase160_local_grammar_emergence.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    primary = run_experiment()
    independent = independent_run()
    verify_ledger(primary, protocol, freeze)
    independent_verify(primary, protocol)
    comparable_lists = (
        "production_ids",
        "non_chain_production_ids",
        "multi_output_production_ids",
        "tool_ids",
        "chain_tool_ids",
        "candidate_only_tool_ids",
        "candidate_only_node_ids",
    )
    if any(primary[key] != independent[key] for key in comparable_lists):
        raise RuntimeError("independent grammar sets disagree")
    if digest(primary["graph_records"]) != independent["graph_record_digest"]:
        raise RuntimeError("independent graph census disagrees")
    for key, value in independent["summary"].items():
        if primary["summary"].get(key) != value:
            raise RuntimeError(f"independent summary disagrees: {key}")
    hostile = []

    def case(name: str, mutate) -> None:
        altered = copy.deepcopy(primary)
        mutate(altered)
        primary_rejected = independent_rejected = False
        try:
            verify_ledger(altered, protocol, freeze)
        except (
            GrammarLedgerReject,
            KeyError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
        ):
            primary_rejected = True
        try:
            independent_verify(altered, protocol)
        except (
            IndependentGrammarReject,
            KeyError,
            TypeError,
            ValueError,
            json.JSONDecodeError,
        ):
            independent_rejected = True
        hostile.append(
            {
                "case": name,
                "primary_rejected": primary_rejected,
                "independent_rejected": independent_rejected,
            }
        )

    case(
        "split_assignment_mutation",
        lambda value: value["graph_records"][0].update(
            assignment=(
                "training"
                if value["graph_records"][0]["assignment"] == "heldout"
                else "heldout"
            )
        ),
    )
    case(
        "graph_digest_mutation",
        lambda value: value["graph_records"][0].update(graph_sha256="0" * 64),
    )
    case(
        "disconnected_subset",
        lambda value: value["production_records"][0]["topology"].update(
            internal_edges=[]
        ),
    )
    case(
        "duplicate_node_index",
        lambda value: value["production_records"][0]["topology"][
            "internal_edges"
        ].append(
            value["production_records"][0]["topology"]["internal_edges"][0]
        ),
    )
    case(
        "non_topological_node_order",
        lambda value: value["production_records"][0]["topology"].update(
            internal_edges=[[1, 0]]
        ),
    )
    case(
        "missing_internal_edge",
        lambda value: value["production_records"][0]["topology"][
            "internal_edges"
        ].pop(),
    )
    case(
        "extra_internal_edge",
        lambda value: value["production_records"][0]["topology"][
            "internal_edges"
        ].append([0, value["production_records"][0]["topology"]["node_count"] - 1]),
    )
    case(
        "external_input_count_mutation",
        lambda value: value["production_records"][0]["topology"][
            "external_input_uses"
        ].__setitem__(
            0,
            value["production_records"][0]["topology"][
                "external_input_uses"
            ][0]
            + 1,
        ),
    )
    case(
        "missing_output_index",
        lambda value: value["production_records"][0]["topology"][
            "output_indices"
        ].pop(),
    )
    case(
        "duplicate_output_index",
        lambda value: value["production_records"][0]["topology"][
            "output_indices"
        ].append(
            value["production_records"][0]["topology"]["output_indices"][0]
        ),
    )
    case(
        "non_boundary_output",
        lambda value: value["production_records"][0]["topology"].update(
            output_indices=[0]
        ),
    )
    case(
        "unknown_topology_field",
        lambda value: value["production_records"][0]["topology"].update(
            unknown=True
        ),
    )
    case(
        "tool_topology_digest_mismatch",
        lambda value: value["tool_records"][0].update(topology_sha256="0" * 64),
    )
    case(
        "tool_body_digest_mismatch",
        lambda value: value["tool_records"][0].update(body_sha256="0" * 64),
    )
    case(
        "heldout_learning_flag_enabled",
        lambda value: value["claims"].update(heldout_learning_performed=True),
    )

    def fabricate_match(value: dict) -> None:
        value["candidate_only_matches"].append(
            {
                "graph_id": protocol["split"]["heldout_graph_ids"][0],
                "body_sha256": "0" * 64,
                "topology_sha256": "0" * 64,
                "node_names": ["fabricated"],
                "fixed_chain": False,
            }
        )
        value["summary"]["candidate_only_heldout_matches"] += 1

    case("fabricated_heldout_match", fabricate_match)
    case(
        "causal_removal_ledger_mutation",
        lambda value: value["per_tool_causal_losses"].update(
            {"0" * 64: 1}
        ),
    )
    case(
        "claim_inflation_to_prospective",
        lambda value: value["claims"].update(
            P6_advanced=True, prospective_trial_authorized=True
        ),
    )
    summary = primary["summary"]
    positive = (
        summary["selected_non_chain_productions"] >= 1
        and summary["candidate_only_heldout_tools"] >= 1
        and summary["candidate_only_heldout_nodes"] >= 1
    )
    payload = {
        "version": "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_WORKER_V1",
        "ledger": primary,
        "ledger_sha256": digest(primary),
        "independent": {
            "graph_record_digest": independent["graph_record_digest"],
            "production_ids_sha256": digest(independent["production_ids"]),
            "tool_ids_sha256": digest(independent["tool_ids"]),
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
            "LOCAL_GRAMMAR_EMERGENCE_POSITIVE"
            if positive
            else "LOCAL_GRAMMAR_EMERGENCE_VALID_NEGATIVE"
        ),
        "native_dedup_required_now": positive,
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE160_WORKER"
        f" classification={payload['classification']}"
        f" productions={summary['selected_productions']}"
        f" non_chain={summary['selected_non_chain_productions']}"
        f" tools={summary['selected_tools']}"
        f" non_chain_tools={summary['selected_non_chain_tools']}"
        f" heldout_nodes={summary['candidate_unique_heldout_nodes']}"
        f"/{summary['chain_unique_heldout_nodes']}"
        f"/{summary['fixed_unique_heldout_nodes']}"
        f" candidate_only={summary['candidate_only_heldout_nodes']}"
    )


def main() -> None:
    if len(sys.argv) == 2 and sys.argv[1] == "--worker":
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    if not (
        freeze["status"] == "FROZEN_BEFORE_ENUMERATOR_OR_OUTCOME_IMPLEMENTATION"
        and freeze["protocol_sha256"] == sha(PROTOCOL)
    ):
        raise RuntimeError("local grammar-emergence freeze mismatch")
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
        failure_path = (
            HERE
            / "results/phase160_local_grammar_emergence_failed_worker_receipt.json"
        )
        failure_path.write_text(
            json.dumps(receipt, sort_keys=True, separators=(",", ":")) + "\n"
        )
        raise RuntimeError(
            "local grammar worker failed: " + receipt["stderr_text"]
        )
    observed = json.loads(WORKER_RESULT.read_text())
    summary = observed["summary"]
    checks = {
        "protocol_frozen_before_implementation": True,
        "authenticated_hash_split_exact": (
            summary["training_graphs"] == 16
            and summary["heldout_graphs"] == 7
        ),
        "two_independent_complete_enumerators_agree": (
            summary["independent_implementations"] == 2
        ),
        "true_connected_dag_search_exceeds_old_chain_search": (
            summary["training_connected_subsets"]
            + summary["heldout_connected_subsets"]
            > 581
        ),
        "machine_selected_non_chain_and_multi_output_productions": (
            summary["selected_non_chain_productions"] >= 1
            and summary["selected_multi_output_productions"] >= 1
        ),
        "machine_constructed_non_chain_tools": (
            summary["selected_non_chain_tools"] >= 1
        ),
        "eighteen_hostile_cases_rejected_twice": (
            summary["hostile_cases"]
            == summary["hostile_rejected_twice"]
            == 18
        ),
        "heldout_learning_forbidden_and_absent": (
            observed["ledger"]["claims"]["heldout_learning_performed"] is False
        ),
        "causal_candidate_only_removal_relation_exact": (
            summary[
                "causal_candidate_only_matches_after_non_chain_removal"
            ]
            == 0
        ),
        "native_dedup_trigger_obeyed": (
            observed["native_dedup_required_now"]
            is (
                observed["classification"]
                == "LOCAL_GRAMMAR_EMERGENCE_POSITIVE"
            )
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
        raise RuntimeError("local grammar-emergence execution failed")
    result = {
        "version": "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_RESULT_V1",
        "status": observed["classification"],
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "checks": checks,
        "operationally_valid": True,
        "observed": observed,
        "receipt": receipt,
        "decision": {
            "bounded_topology_grammar_selection_demonstrated": True,
            "non_chain_tool_construction_demonstrated": True,
            "candidate_only_heldout_transfer_demonstrated": (
                observed["classification"]
                == "LOCAL_GRAMMAR_EMERGENCE_POSITIVE"
            ),
            "native_dedup_executed": False,
            "native_dedup_not_triggered_by_valid_negative": (
                observed["classification"]
                == "LOCAL_GRAMMAR_EMERGENCE_VALID_NEGATIVE"
            ),
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "next_route": (
                "falsify whether exact-body identity is the bottleneck by "
                "freezing typed anti-unification across learned non-chain "
                "topologies; retain the same hash split and controls"
            ),
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE160"
        f" status={result['status']}"
        f" productions={summary['selected_productions']}"
        f" non_chain={summary['selected_non_chain_productions']}"
        f" tools={summary['selected_tools']}"
        f" heldout_coverage={summary['candidate_unique_heldout_nodes']}"
        f"/{summary['chain_unique_heldout_nodes']}"
        f"/{summary['fixed_unique_heldout_nodes']}"
        f" candidate_only={summary['candidate_only_heldout_nodes']}"
        " P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
