#!/usr/bin/env python3
"""Execute the frozen post-exploratory A8 strategy reachability phase."""

from __future__ import annotations

import copy
import hashlib
import itertools
import json
import pathlib
import sys
from typing import Any

import torch

import eggmind_adapted_boundary as eqsatl
import independent_eggmind_boundary as independent_eqsatl
from a8_adapted_strategy_search import (
    A8StrategyReject,
    canonical,
    enumerate_matches,
    evaluate,
    objective_key,
    validate_record,
)
from independent_a8_adapted_strategy_search import (
    IndependentA8StrategyReject,
    discover,
    rank_key,
    score as independent_score,
    verify as independent_verify_record,
)
from phase63_pareto_motif_calibration import workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A8_ADAPTED_STRATEGY_REACHABILITY_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a8_adapted_strategy_reachability_v1_freeze.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
WORKER_RESULT = (
    HERE / "results/phase152_a8_adapted_strategy_reachability_worker.json"
)
RESULT = HERE / "results/phase152_a8_adapted_strategy_reachability.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def eqsatl_artifact(order: list[str]) -> dict[str, Any]:
    return {
        "name": "AdaptedFixedPriorityStrategy",
        "rulesets": [
            {"name": name, "tags": ["fixed_tool"]} for name in order
        ],
        "flow": {
            "sequence": [
                {
                    "phase": {
                        "name": f"priority_{index + 1}",
                        "ruleset": name,
                        "iter_limit": 1,
                    }
                }
                for index, name in enumerate(order)
            ]
        },
    }


def rejected_record_twice(
    record: dict[str, Any],
    names: list[str],
    graph_matches: list[tuple[str, list[dict[str, Any]]]],
) -> bool:
    primary = independent = False
    try:
        validate_record(record, names, graph_matches)
    except (A8StrategyReject, KeyError, TypeError, ValueError):
        primary = True
    try:
        independent_verify_record(record, names, graph_matches)
    except (
        IndependentA8StrategyReject,
        KeyError,
        TypeError,
        ValueError,
    ):
        independent = True
    return primary and independent


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    portfolio = json.loads(FIXED.read_text())
    names = [row["name"] for row in portfolio["tools"]]
    instantiated, unsupported = workloads()
    graph_matches = []
    graph_rows = []
    call_roots = 0
    for suite, workload in instantiated:
        artifact_id = f"{suite}:{workload['family']}"
        module = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        ).module()
        call_roots += sum(
            node.op == "call_function" for node in module.graph.nodes
        )
        primary = enumerate_matches(module.graph, portfolio)
        independent = discover(module.graph, portfolio)
        if primary != independent:
            raise RuntimeError(f"A8 typed matchers disagree: {artifact_id}")
        graph_matches.append((artifact_id, primary))
        graph_rows.append(
            {
                "artifact_id": artifact_id,
                "raw_matches": len(primary),
                "match_set_sha256": hashlib.sha256(
                    canonical(primary).encode()
                ).hexdigest(),
            }
        )

    baseline = evaluate(tuple(names), graph_matches)
    if baseline != independent_score(tuple(names), graph_matches):
        raise RuntimeError("A8 baseline evaluators disagree")
    table = []
    best = None
    distinct_scores: dict[tuple[int, int, int, int], list[str]] = {}
    for order in itertools.permutations(names):
        primary = evaluate(order, graph_matches)
        independent = independent_score(order, graph_matches)
        if primary != independent or objective_key(primary) != rank_key(
            independent
        ):
            raise RuntimeError("A8 strategy evaluators disagree")
        scalar = {
            key: primary[key]
            for key in (
                "order",
                "unique_covered_nodes",
                "eligible_artifacts",
                "direct_uses",
                "conflict_skips",
            )
        }
        table.append(scalar)
        score_vector = (
            primary["unique_covered_nodes"],
            primary["eligible_artifacts"],
            primary["direct_uses"],
            primary["conflict_skips"],
        )
        distinct_scores.setdefault(score_vector, list(order))
        if best is None or objective_key(primary) < objective_key(best):
            best = primary
    if best is None:
        raise RuntimeError("A8 strategy space unexpectedly empty")
    validate_record(best, names, graph_matches)
    independent_verify_record(best, names, graph_matches)
    strategy = eqsatl_artifact(best["order"])
    parsed_primary = eqsatl.parse_strategy(strategy)
    parsed_independent = independent_eqsatl.parse_strategy(strategy)
    if eqsatl.strategy_digest(parsed_primary) != independent_eqsatl.digest(
        parsed_independent
    ):
        raise RuntimeError("A8 EqSatL parsers disagree")
    lowered = eqsatl.lower(parsed_primary)
    independent_counts = independent_eqsatl.count_actions(
        parsed_independent["flow"]
    )
    if len(lowered) != 8 or independent_counts != (8, 8, 0):
        raise RuntimeError("A8 EqSatL lowering mismatch")

    hostile = []

    def record_case(name: str, mutate) -> None:
        value = copy.deepcopy(best)
        mutate(value)
        hostile.append(
            {
                "case": name,
                "primary_and_independent_rejected": rejected_record_twice(
                    value, names, graph_matches
                ),
            }
        )

    record_case("missing_tool", lambda row: row["order"].pop())
    record_case(
        "duplicate_tool",
        lambda row: row["order"].__setitem__(0, row["order"][1]),
    )
    record_case(
        "unknown_tool",
        lambda row: row["order"].__setitem__(0, "unknown_tool"),
    )

    frozen_match_digest = hashlib.sha256(
        canonical(graph_matches).encode()
    ).hexdigest()

    def portfolio_case(name: str, field: str, value: Any) -> None:
        mutated = copy.deepcopy(portfolio)
        mutated["tools"][0][field] = value
        mismatch_primary = mismatch_independent = False
        rebuilt_primary = []
        rebuilt_independent = []
        for (artifact_id, _), (suite, workload) in zip(
            graph_matches, instantiated, strict=True
        ):
            module = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            ).module()
            rebuilt_primary.append(
                (artifact_id, enumerate_matches(module.graph, mutated))
            )
            rebuilt_independent.append(
                (artifact_id, discover(module.graph, mutated))
            )
        mismatch_primary = (
            hashlib.sha256(canonical(rebuilt_primary).encode()).hexdigest()
            != frozen_match_digest
        )
        mismatch_independent = (
            hashlib.sha256(canonical(rebuilt_independent).encode()).hexdigest()
            != frozen_match_digest
        )
        hostile.append(
            {
                "case": name,
                "primary_and_independent_rejected": (
                    mismatch_primary and mismatch_independent
                ),
            }
        )

    portfolio_case(
        "changed_target_sequence",
        "targets",
        ["aten.mul.Tensor"],
    )
    portfolio_case("changed_rank", "rank", 99)
    portfolio_case("changed_dtype", "dtype", "torch.float64")
    portfolio_case("changed_layout", "layout", "torch.sparse_coo")
    record_case(
        "reversed_node_path",
        lambda row: row["selected"][0]["nodes"].reverse(),
    )
    record_case(
        "overlap_double_selection",
        lambda row: row["selected"].append(copy.deepcopy(row["selected"][0])),
    )
    record_case(
        "score_mutation",
        lambda row: row.update(direct_uses=row["direct_uses"] + 1),
    )
    alternative_same_score = next(
        evaluate(tuple(row["order"]), graph_matches)
        for row in table
        if (
            row["unique_covered_nodes"] == best["unique_covered_nodes"]
            and row["eligible_artifacts"] == best["eligible_artifacts"]
            and row["direct_uses"] == best["direct_uses"]
            and row["conflict_skips"] == best["conflict_skips"]
            and row["order"] != best["order"]
        )
    )
    hostile.append(
        {
            "case": "tie_break_mutation",
            "primary_and_independent_rejected": (
                objective_key(alternative_same_score) > objective_key(best)
                and rank_key(alternative_same_score) > rank_key(best)
            ),
        }
    )
    record_case(
        "unknown_strategy_field",
        lambda row: row.update(unknown=True),
    )

    positive = (
        best["unique_covered_nodes"] == baseline["unique_covered_nodes"]
        and best["eligible_artifacts"] == baseline["eligible_artifacts"]
        and best["direct_uses"] < baseline["direct_uses"]
        and best["order"] != baseline["order"]
    )
    payload = {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_REACHABILITY_WORKER_V1",
        "graphs": graph_rows,
        "baseline": baseline,
        "selected": best,
        "selected_eqsatl": strategy,
        "selected_eqsatl_sha256": eqsatl.strategy_digest(parsed_primary),
        "repository": {
            "pending_strategies": len(table),
            "promising_distinct_score_vectors": len(distinct_scores),
            "best_strategies": 1,
            "complete_score_table_sha256": hashlib.sha256(
                canonical(table).encode()
            ).hexdigest(),
        },
        "summary": {
            "graphs": len(graph_rows),
            "call_function_roots": call_roots,
            "candidate_strategies": len(table),
            "raw_fixed_matches": sum(
                row["raw_matches"] for row in graph_rows
            ),
            "baseline_covered_nodes": baseline["unique_covered_nodes"],
            "baseline_eligible_artifacts": baseline["eligible_artifacts"],
            "baseline_direct_uses": baseline["direct_uses"],
            "selected_covered_nodes": best["unique_covered_nodes"],
            "selected_eligible_artifacts": best["eligible_artifacts"],
            "selected_direct_uses": best["direct_uses"],
            "direct_use_reduction": (
                baseline["direct_uses"] - best["direct_uses"]
            ),
            "hostile_cases": len(hostile),
            "hostile_rejected_twice": sum(
                row["primary_and_independent_rejected"] for row in hostile
            ),
            "historically_unsupported_or_failed": len(unsupported),
        },
        "hostile_rejections": hostile,
        "positive": positive,
        "pristine_preregistration": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE152_WORKER"
        f" strategies={len(table)}"
        f" baseline_uses={baseline['direct_uses']}"
        f" selected_uses={best['direct_uses']}"
        f" coverage={best['unique_covered_nodes']}"
        f" hostile={payload['summary']['hostile_rejected_twice']}/12"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["tool_grammar"] == protocol["tool_grammar"]
        and freeze["match_and_execution_policy"]
        == protocol["match_and_execution_policy"]
        and freeze["repository_policy"] == protocol["repository_policy"]
        and freeze["objective"] == protocol["objective"]
        and freeze["decision_rule"] == protocol["decision_rule"]
        and freeze["pristine_preregistration"] is False
    )
    limits = {
        "wall_limit_seconds": protocol["resource_limits"]["wall_seconds"],
        "cpu_limit_seconds": protocol["resource_limits"]["cpu_seconds"],
        "rss_limit_kib": protocol["resource_limits"]["rss_kib"],
    }
    receipt = run_metered_tree(
        [
            str(pathlib.Path(sys.executable).resolve()),
            str(__file__),
            "--worker",
        ],
        cwd=HERE,
        environment={
            "PYTHONHASHSEED": "0",
            "PYTHONWARNINGS": "ignore",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE152_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    checks = {
        "protocol_freeze_and_providers_exact": providers_exact and freeze_exact,
        "metered_worker_terminated_naturally": natural,
        "complete_process_tree_accounting": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "complete_23_graph_surface": (
            summary.get("graphs") == 23
            and summary.get("call_function_roots") == 337
            and summary.get("historically_unsupported_or_failed") == 1
        ),
        "all_40320_strategies_evaluated_twice": (
            summary.get("candidate_strategies") == 40320
            and observed.get("repository", {}).get("pending_strategies")
            == 40320
        ),
        "selected_preserves_baseline_coverage": (
            summary.get("selected_covered_nodes")
            == summary.get("baseline_covered_nodes")
            and summary.get("selected_eligible_artifacts")
            == summary.get("baseline_eligible_artifacts")
        ),
        "selected_strictly_reduces_direct_uses": (
            summary.get("direct_use_reduction", 0) > 0
            and observed.get("selected", {}).get("order")
            != observed.get("baseline", {}).get("order")
        ),
        "selected_eqsatl_parsed_and_lowered_twice": (
            isinstance(observed.get("selected_eqsatl_sha256"), str)
            and len(observed["selected_eqsatl_sha256"]) == 64
        ),
        "twelve_hostile_cases_rejected_twice": (
            summary.get("hostile_cases") == 12
            and summary.get("hostile_rejected_twice") == 12
        ),
        "post_exploratory_disclosure_preserved": (
            observed.get("pristine_preregistration") is False
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    operationally_valid = all(checks.values())
    positive = operationally_valid and observed.get("positive") is True
    payload = {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_REACHABILITY_RESULT_V1",
        "status": (
            "A8_ADAPTED_STRATEGY_REACHABILITY_POSITIVE"
            if positive
            else (
                "A8_ADAPTED_STRATEGY_REACHABILITY_ZERO"
                if operationally_valid
                else "A8_ADAPTED_STRATEGY_REACHABILITY_INVALID"
            )
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {"path": pathlib.Path(__file__).name, "sha256": sha(pathlib.Path(__file__))},
            {
                "path": "a8_adapted_strategy_search.py",
                "sha256": sha(HERE / "a8_adapted_strategy_search.py"),
            },
            {
                "path": "independent_a8_adapted_strategy_search.py",
                "sha256": sha(
                    HERE / "independent_a8_adapted_strategy_search.py"
                ),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "observed": observed,
        "decision": {
            "A8_runtime_implementation_justified": positive,
            "selected_strategy_frozen_by_result": positive,
            "next_route": (
                protocol["decision_rule"]["positive_next_action"]
                if positive
                else protocol["decision_rule"]["zero_next_action"]
            ),
            "A8_production_integrated": False,
            "production_integrated_arms": 9,
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE152_A8_ADAPTED_STRATEGY"
        f" status={payload['status']}"
        f" strategies={summary.get('candidate_strategies', 0)}"
        f" baseline_uses={summary.get('baseline_direct_uses', 0)}"
        f" selected_uses={summary.get('selected_direct_uses', 0)}"
        f" coverage={summary.get('selected_covered_nodes', 0)}"
        " integrated=9/10 prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A8 reachability invalid: "
            + canonical(
                {
                    "failed": [
                        key for key, value in checks.items() if not value
                    ],
                    "stderr": receipt["stderr_text"],
                }
            )
        )


if __name__ == "__main__":
    main()
