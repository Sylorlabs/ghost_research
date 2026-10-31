#!/usr/bin/env python3
"""Execute frozen A6 typed anti-unification reachability."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib
import sys
from itertools import combinations
from typing import Any

import torch

from a6_typed_anti_unification import (
    A6Reject,
    anti_unify,
    canonical,
    extract_roots,
    matches,
    statistics,
    validate_record,
)
from independent_a6_typed_anti_unification import (
    IndependentA6Reject,
    accepts as independent_matches,
    extract as independent_extract,
    generalize as independent_anti_unify,
    metrics as independent_statistics,
    verify_record as independent_validate,
)
from phase63_pareto_motif_calibration import workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A6_TYPED_ANTI_UNIFICATION_REACHABILITY_PROTOCOL_V1.json"
)
FREEZE = (
    HERE
    / "results/a6_typed_anti_unification_reachability_v1_freeze.json"
)
WORKER_RESULT = (
    HERE
    / "results/phase149_a6_typed_anti_unification_reachability_worker.json"
)
RESULT = (
    HERE
    / "results/phase149_a6_typed_anti_unification_reachability.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def pattern_record(
    pattern: dict[str, Any],
    source_pair: list[str],
    match_ids: list[str],
    universe: dict[str, dict[str, Any]],
) -> dict[str, Any]:
    stats = statistics(pattern)
    return {
        "pattern": pattern,
        "pattern_sha256": hashlib.sha256(canonical(pattern).encode()).hexdigest(),
        "source_pair": source_pair,
        "matches": match_ids,
        "matching_artifacts": sorted(
            {universe[item]["artifact_id"] for item in match_ids}
        ),
        **stats,
    }


def synthetic_fixture() -> tuple[
    dict[str, dict[str, Any]], dict[str, Any]
]:
    typ = {"kind": "tensor", "dtype": "torch.float32", "rank": 2}
    scalar = {"kind": "scalar", "type": "int"}

    def term(identity: str) -> dict[str, Any]:
        return {
            "kind": "op",
            "type": typ,
            "target": "aten.add.Tensor",
            "args": [
                {
                    "kind": "op",
                    "type": typ,
                    "target": "aten.relu.default",
                    "args": [
                        {
                            "kind": "boundary",
                            "type": typ,
                            "boundary": "placeholder",
                            "identity": identity,
                        }
                    ],
                    "kwargs": [],
                },
                {
                    "kind": "literal",
                    "type": scalar,
                    "value": 1,
                },
            ],
            "kwargs": [],
        }

    universe = {
        "r1": {"artifact_id": "fixture_a", "term": term("x")},
        "r2": {"artifact_id": "fixture_b", "term": term("y")},
        "r3": {"artifact_id": "fixture_a", "term": term("z")},
    }
    pattern = anti_unify(universe["r1"]["term"], universe["r2"]["term"])
    record = {
        "pattern": pattern,
        "source_pair": ["r1", "r2"],
        "matches": ["r1", "r2", "r3"],
    }
    return universe, record


def hostile_conformance() -> list[dict[str, Any]]:
    universe, valid = synthetic_fixture()
    validate_record(
        valid,
        universe,
        minimum_operators=2,
        minimum_holes=1,
        minimum_matches=3,
        minimum_artifacts=2,
    )
    independent_validate(valid, universe, 2, 1, 3, 2)
    mutations = []

    def case(name: str, mutate) -> None:
        value = copy.deepcopy(valid)
        mutate(value)
        primary = independent = False
        try:
            validate_record(
                value,
                universe,
                minimum_operators=2,
                minimum_holes=1,
                minimum_matches=3,
                minimum_artifacts=2,
            )
        except (A6Reject, KeyError, TypeError, ValueError):
            primary = True
        try:
            independent_validate(value, universe, 2, 1, 3, 2)
        except (
            IndependentA6Reject,
            KeyError,
            TypeError,
            ValueError,
        ):
            independent = True
        mutations.append(
            {
                "case": name,
                "primary_rejected": primary,
                "independent_rejected": independent,
            }
        )

    case(
        "operator_identity_mutation",
        lambda value: value["pattern"].update(target="aten.mul.Tensor"),
    )
    case(
        "argument_order_mutation",
        lambda value: value["pattern"]["args"].reverse(),
    )
    case(
        "type_mutation",
        lambda value: value["pattern"]["type"].update(rank=3),
    )

    def mutate_hole(value: dict, name: str) -> None:
        value["pattern"]["args"][0]["args"][0]["name"] = name

    case(
        "metavariable_inconsistency",
        lambda value: mutate_hole(value, "?99"),
    )
    case(
        "alpha_normalization_mutation",
        lambda value: mutate_hole(value, "?01"),
    )
    case(
        "concrete_only_candidate",
        lambda value: value.update(pattern=copy.deepcopy(universe["r1"]["term"])),
    )
    case(
        "variable_only_candidate",
        lambda value: value.update(
            pattern={
                "kind": "hole",
                "type": universe["r1"]["term"]["type"],
                "name": "?0",
            }
        ),
    )
    case(
        "single_operator_candidate",
        lambda value: value.update(
            pattern=copy.deepcopy(value["pattern"]["args"][0])
        ),
    )
    case(
        "insufficient_matches",
        lambda value: value.update(matches=["r1", "r2"]),
    )
    case(
        "single_artifact_matches",
        lambda value: value.update(matches=["r1", "r3"]),
    )
    case(
        "duplicate_source_pair",
        lambda value: value.update(source_pair=["r1", "r1"]),
    )
    case(
        "unknown_term_field",
        lambda value: value["pattern"].update(unknown=True),
    )
    return mutations


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    depth = protocol["typed_term_domain"][
        "maximum_recursive_operator_depth"
    ]
    instantiated, unsupported = workloads()
    roots: list[dict[str, Any]] = []
    graph_rows = []
    for suite, workload in instantiated:
        artifact_id = f"{suite}:{workload['family']}"
        module = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        ).module()
        primary = extract_roots(module, artifact_id, depth)
        independent = independent_extract(module, artifact_id, depth)
        if canonical(primary) != canonical(independent):
            raise RuntimeError(f"A6 term extractors disagree: {artifact_id}")
        roots.extend(primary)
        graph_rows.append(
            {
                "artifact_id": artifact_id,
                "roots": len(primary),
                "term_set_sha256": hashlib.sha256(
                    canonical(primary).encode()
                ).hexdigest(),
            }
        )
    universe = {row["root_id"]: row for row in roots}
    pair_count = 0
    type_incompatible = 0
    identical_pairs = 0
    nontrivial_pair_results = 0
    patterns: dict[str, dict[str, Any]] = {}
    for left, right in combinations(roots, 2):
        pair_count += 1
        if left["term"] == right["term"]:
            identical_pairs += 1
            continue
        try:
            primary_pattern = anti_unify(left["term"], right["term"])
        except A6Reject:
            try:
                independent_anti_unify(left["term"], right["term"])
            except IndependentA6Reject:
                type_incompatible += 1
                continue
            raise RuntimeError("A6 anti-unifiers disagree on type rejection")
        independent_pattern = independent_anti_unify(
            left["term"], right["term"]
        )
        if canonical(primary_pattern) != canonical(independent_pattern):
            raise RuntimeError("A6 anti-unifiers disagree")
        primary_stats = statistics(primary_pattern)
        independent_stats = independent_statistics(primary_pattern)
        if (
            primary_stats["operator_nodes"],
            primary_stats["distinct_metavariables"],
        ) != independent_stats:
            raise RuntimeError("A6 pattern statistics disagree")
        if (
            primary_stats["operator_nodes"]
            < protocol["candidate_contract"]["minimum_operator_nodes"]
            or primary_stats["distinct_metavariables"]
            < protocol["candidate_contract"][
                "minimum_distinct_metavariables"
            ]
        ):
            continue
        nontrivial_pair_results += 1
        serialized = canonical(primary_pattern)
        patterns.setdefault(
            serialized,
            {
                "pattern": primary_pattern,
                "source_pair": sorted(
                    [left["root_id"], right["root_id"]]
                ),
            },
        )
    candidates = []
    for serialized, seed in sorted(patterns.items()):
        primary_match_ids = sorted(
            row["root_id"]
            for row in roots
            if matches(seed["pattern"], row["term"])
        )
        independent_match_ids = sorted(
            row["root_id"]
            for row in roots
            if independent_matches(seed["pattern"], row["term"])
        )
        if primary_match_ids != independent_match_ids:
            raise RuntimeError("A6 matchers disagree")
        artifacts = {
            universe[item]["artifact_id"] for item in primary_match_ids
        }
        if (
            len(primary_match_ids)
            < protocol["candidate_contract"]["minimum_concrete_matches"]
            or len(artifacts)
            < protocol["candidate_contract"]["minimum_distinct_artifacts"]
        ):
            continue
        validation_record = {
            "pattern": seed["pattern"],
            "source_pair": seed["source_pair"],
            "matches": primary_match_ids,
        }
        validate_record(
            validation_record,
            universe,
            minimum_operators=protocol["candidate_contract"][
                "minimum_operator_nodes"
            ],
            minimum_holes=protocol["candidate_contract"][
                "minimum_distinct_metavariables"
            ],
            minimum_matches=protocol["candidate_contract"][
                "minimum_concrete_matches"
            ],
            minimum_artifacts=protocol["candidate_contract"][
                "minimum_distinct_artifacts"
            ],
        )
        independent_validate(
            validation_record,
            universe,
            protocol["candidate_contract"]["minimum_operator_nodes"],
            protocol["candidate_contract"][
                "minimum_distinct_metavariables"
            ],
            protocol["candidate_contract"]["minimum_concrete_matches"],
            protocol["candidate_contract"]["minimum_distinct_artifacts"],
        )
        candidates.append(
            pattern_record(
                seed["pattern"],
                seed["source_pair"],
                primary_match_ids,
                universe,
            )
        )
    candidates.sort(key=lambda row: row["pattern_sha256"])
    selected = None
    if candidates:
        selected = min(
            candidates,
            key=lambda row: (
                -len(row["matching_artifacts"]),
                -(len(row["matches"]) * row["operator_nodes"]),
                -row["operator_nodes"],
                row["distinct_metavariables"],
                canonical(row["pattern"]),
            ),
        )
    hostile = hostile_conformance()
    payload = {
        "version": "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_REACHABILITY_WORKER_V1",
        "graphs": graph_rows,
        "candidates": candidates,
        "selected_candidate": selected,
        "hostile_rejections": hostile,
        "summary": {
            "graphs": len(graph_rows),
            "roots": len(roots),
            "unordered_root_pairs": pair_count,
            "type_incompatible_pairs": type_incompatible,
            "byte_identical_pairs": identical_pairs,
            "nontrivial_pair_results_before_dedup": nontrivial_pair_results,
            "deduplicated_nontrivial_patterns_before_match_filter": len(
                patterns
            ),
            "contract_candidates": len(candidates),
            "selected": int(selected is not None),
            "selected_matches": len(selected["matches"]) if selected else 0,
            "selected_matching_artifacts": (
                len(selected["matching_artifacts"]) if selected else 0
            ),
            "unsupported_or_failed_workloads": len(unsupported),
            "hostile_cases": len(hostile),
            "hostile_rejected_twice": sum(
                row["primary_rejected"] and row["independent_rejected"]
                for row in hostile
            ),
        },
        "candidate_set_sha256": hashlib.sha256(
            canonical(candidates).encode()
        ).hexdigest(),
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE149_WORKER"
        f" roots={len(roots)} pairs={pair_count}"
        f" patterns={len(candidates)}"
        f" selected_matches={payload['summary']['selected_matches']}"
        f" selected_artifacts={payload['summary']['selected_matching_artifacts']}"
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
        and freeze["typed_term_domain"] == protocol["typed_term_domain"]
        and freeze["candidate_contract"] == protocol["candidate_contract"]
        and freeze["selection_rule"] == protocol["selection_rule"]
        and freeze["decision_rule"] == protocol["decision_rule"]
        and freeze["frozen_before_enumerator_implementation_or_execution"]
        is True
    )
    limits = {
        "wall_limit_seconds": protocol["resource_limits"]["wall_seconds"],
        "cpu_limit_seconds": protocol["resource_limits"]["cpu_seconds"],
        "rss_limit_kib": protocol["resource_limits"]["rss_kib"],
    }
    receipt = run_metered_tree(
        [str(pathlib.Path(sys.executable).resolve()), str(__file__), "--worker"],
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
        and "FOUNDRY_PHASE149_WORKER" in receipt["stdout_text"]
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
        "complete_calibration_surface_exact": (
            summary.get("graphs") == 23
            and summary.get("roots")
            == protocol["typed_term_domain"]["expected_roots"]
            and summary.get("unordered_root_pairs")
            == protocol["typed_term_domain"][
                "expected_unordered_root_pairs"
            ]
            and summary.get("unsupported_or_failed_workloads") == 1
        ),
        "two_extractors_anti_unifiers_and_matchers_agreed": natural,
        "all_reported_candidates_satisfy_contract": (
            len(observed.get("candidates", []))
            == summary.get("contract_candidates")
        ),
        "selection_cardinality_exact": summary.get("selected") in {0, 1},
        "twelve_hostile_cases_rejected_twice": (
            summary.get("hostile_cases") == 12
            and summary.get("hostile_rejected_twice") == 12
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    operationally_valid = all(checks.values())
    positive = operationally_valid and summary.get("contract_candidates", 0) > 0
    payload = {
        "version": "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_REACHABILITY_RESULT_V1",
        "status": (
            "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_POSITIVE"
            if positive
            else (
                "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_ZERO"
                if operationally_valid
                else "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_INVALID"
            )
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {
                "path": pathlib.Path(__file__).name,
                "sha256": sha(pathlib.Path(__file__)),
            },
            {
                "path": "a6_typed_anti_unification.py",
                "sha256": sha(HERE / "a6_typed_anti_unification.py"),
            },
            {
                "path": "independent_a6_typed_anti_unification.py",
                "sha256": sha(
                    HERE / "independent_a6_typed_anti_unification.py"
                ),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "observed": observed,
        "decision": {
            "A6_full_implementation_justified": positive,
            "selected_candidate_frozen_by_result": positive,
            "next_route": (
                protocol["decision_rule"]["positive_next_action"]
                if positive
                else protocol["decision_rule"]["zero_next_action"]
            ),
            "A6_production_integrated": False,
            "production_integrated_arms": 8,
        },
        "claim_boundary": protocol["claim_boundary"],
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE149_A6_TYPED_ANTI_UNIFICATION"
        f" status={payload['status']}"
        f" roots={summary.get('roots', 0)}"
        f" pairs={summary.get('unordered_root_pairs', 0)}"
        f" candidates={summary.get('contract_candidates', 0)}"
        f" selected_matches={summary.get('selected_matches', 0)}"
        f" selected_artifacts={summary.get('selected_matching_artifacts', 0)}"
        " integrated=8/10 prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A6 reachability invalid: "
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
