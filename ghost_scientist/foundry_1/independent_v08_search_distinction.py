#!/usr/bin/env python3
"""Stdlib-only independent V08 search-distinction receipt verifier."""

from __future__ import annotations

import copy
import math
import random
import re
from collections import defaultdict
from typing import Any


ARMS = ("A2", "A3", "A9")
HEX64 = re.compile(r"[0-9a-f]{64}\Z")
REQUIRED_FIELDS = {
    "artifact_id",
    "arm_id",
    "candidate_or_control_state_sha256",
    "artifact_graph_sha256",
    "shape_seed_sha256",
    "search_started_monotonic_ns",
    "search_finished_monotonic_ns",
    "process_user_cpu_ns",
    "process_system_cpu_ns",
    "process_wall_ns",
    "peak_process_tree_rss_kib",
    "observed_process_count",
    "process_group_reaped",
    "states_generated",
    "states_verified",
    "states_rejected",
    "selector_comparisons",
    "exact_tool_digests_reused",
    "failures",
    "timeouts",
    "correctness_passed",
    "resource_receipt_sha256",
}


class V08Error(ValueError):
    """The trial ledger does not satisfy the frozen V08 contract."""


def _integer(row: dict[str, Any], key: str, *, positive: bool = False) -> int:
    value = row[key]
    if type(value) is not int or value < int(positive):
        raise V08Error(f"{key} must be a {'positive' if positive else 'nonnegative'} integer")
    return value


def parse_receipt(row: object) -> dict[str, Any]:
    if not isinstance(row, dict) or set(row) != REQUIRED_FIELDS:
        raise V08Error("receipt fields are not exact")
    if not isinstance(row["artifact_id"], str) or not row["artifact_id"]:
        raise V08Error("artifact_id invalid")
    if row["arm_id"] not in ARMS:
        raise V08Error("arm_id invalid")
    for key in (
        "candidate_or_control_state_sha256",
        "artifact_graph_sha256",
        "shape_seed_sha256",
        "resource_receipt_sha256",
    ):
        if not isinstance(row[key], str) or not HEX64.fullmatch(row[key]):
            raise V08Error(f"{key} invalid")
    started = _integer(row, "search_started_monotonic_ns")
    finished = _integer(row, "search_finished_monotonic_ns", positive=True)
    wall = _integer(row, "process_wall_ns", positive=True)
    if finished <= started or wall != finished - started:
        raise V08Error("search timeline does not reconcile")
    for key in (
        "process_user_cpu_ns",
        "process_system_cpu_ns",
        "peak_process_tree_rss_kib",
        "states_generated",
        "states_verified",
        "states_rejected",
        "selector_comparisons",
    ):
        _integer(row, key)
    if _integer(row, "observed_process_count", positive=True) < 1:
        raise V08Error("process tree empty")
    if row["process_group_reaped"] is not True:
        raise V08Error("process group not reaped")
    generated = row["states_generated"]
    verified = row["states_verified"]
    rejected = row["states_rejected"]
    if not 0 <= rejected <= verified <= generated:
        raise V08Error("state ledger does not reconcile")
    for key in ("failures", "timeouts"):
        if not isinstance(row[key], list) or not all(
            isinstance(item, str) and item for item in row[key]
        ):
            raise V08Error(f"{key} ledger invalid")
    reused = row["exact_tool_digests_reused"]
    if not isinstance(reused, list) or not all(
        isinstance(item, str) and HEX64.fullmatch(item) for item in reused
    ):
        raise V08Error("exact tool digest ledger invalid")
    if len(reused) != len(set(reused)):
        raise V08Error("duplicate exact tool digest receipt")
    if row["correctness_passed"] is not True:
        raise V08Error("correctness did not pass")
    return copy.deepcopy(row)


def _percentile_lower(values: list[float]) -> float:
    if not values:
        raise V08Error("empty bootstrap")
    ordered = sorted(values)
    return ordered[math.floor(0.025 * len(ordered))]


def verify_trial(
    document: object,
    *,
    candidate_tool_digests: set[str],
    bootstrap_resamples: int = 10000,
    bootstrap_seed: int = 812734,
) -> dict[str, object]:
    if not isinstance(document, dict) or set(document) != {
        "version",
        "receipts",
        "runtime_inventions_admitted",
        "stock_decomposition_duplicates",
        "fixed_and_stock_total_cost_reported",
        "complete_total_cost_accounting_unchanged",
    }:
        raise V08Error("trial document fields are not exact")
    if document["version"] != "FOUNDRY_V08_SEARCH_DISTINCTION_TRIAL_V1":
        raise V08Error("trial version invalid")
    if document["runtime_inventions_admitted"] != 0:
        raise V08Error("runtime duplicate disclosure changed")
    if document["stock_decomposition_duplicates"] != 4:
        raise V08Error("stock duplicate count changed")
    if document["fixed_and_stock_total_cost_reported"] is not True:
        raise V08Error("fixed or stock result omitted")
    if document["complete_total_cost_accounting_unchanged"] is not True:
        raise V08Error("complete total-cost accounting changed")
    if not isinstance(document["receipts"], list):
        raise V08Error("receipts must be a list")
    receipts = [parse_receipt(row) for row in document["receipts"]]
    if len(receipts) != 12:
        raise V08Error("exactly twelve arm-artifact receipts required")
    indexed: dict[tuple[str, str], dict[str, Any]] = {}
    artifacts: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in receipts:
        key = (row["artifact_id"], row["arm_id"])
        if key in indexed:
            raise V08Error("duplicate artifact-arm receipt")
        indexed[key] = row
        artifacts[row["artifact_id"]].append(row)
    if len(artifacts) != 4:
        raise V08Error("exactly four paired artifacts required")
    for artifact_id, rows in artifacts.items():
        if {row["arm_id"] for row in rows} != set(ARMS):
            raise V08Error(f"artifact {artifact_id} has incomplete arms")
        if len({row["artifact_graph_sha256"] for row in rows}) != 1:
            raise V08Error("artifact graph differs across arms")
        if len({row["shape_seed_sha256"] for row in rows}) != 1:
            raise V08Error("shape seed differs across arms")
    cpu_by_arm: dict[str, int] = {}
    states_by_arm: dict[str, int] = {}
    per_artifact_cpu: dict[str, dict[str, int]] = {}
    for arm in ARMS:
        arm_rows = [row for row in receipts if row["arm_id"] == arm]
        cpu_by_arm[arm] = sum(
            row["process_user_cpu_ns"] + row["process_system_cpu_ns"]
            for row in arm_rows
        )
        states_by_arm[arm] = sum(row["states_generated"] for row in arm_rows)
    if min(cpu_by_arm["A3"], cpu_by_arm["A9"]) <= 0:
        raise V08Error("control CPU must be positive")
    control_cpu = min(cpu_by_arm["A3"], cpu_by_arm["A9"])
    delta = 1.0 - cpu_by_arm["A2"] / control_cpu
    for artifact_id in sorted(artifacts):
        per_artifact_cpu[artifact_id] = {
            arm: (
                indexed[(artifact_id, arm)]["process_user_cpu_ns"]
                + indexed[(artifact_id, arm)]["process_system_cpu_ns"]
            )
            for arm in ARMS
        }
    rng = random.Random(bootstrap_seed)
    artifact_ids = sorted(artifacts)
    bootstrap: list[float] = []
    for _ in range(bootstrap_resamples):
        sample = [rng.choice(artifact_ids) for _ in artifact_ids]
        a2 = sum(per_artifact_cpu[item]["A2"] for item in sample)
        a3 = sum(per_artifact_cpu[item]["A3"] for item in sample)
        a9 = sum(per_artifact_cpu[item]["A9"] for item in sample)
        bootstrap.append(1.0 - a2 / min(a3, a9))
    lower = _percentile_lower(bootstrap)
    exact_reuse = sorted(
        {
            digest
            for row in receipts
            if row["arm_id"] == "A2"
            for digest in row["exact_tool_digests_reused"]
            if digest in candidate_tool_digests
        }
    )
    checks = {
        "point_estimate_at_least_five_percent": delta >= 0.05,
        "bootstrap_lower_95_strictly_positive": lower > 0.0,
        "A2_states_no_greater_than_A3": states_by_arm["A2"]
        <= states_by_arm["A3"],
        "A2_states_no_greater_than_A9": states_by_arm["A2"]
        <= states_by_arm["A9"],
        "exact_frozen_digest_reused": len(exact_reuse) >= 1,
    }
    if not all(checks.values()):
        failed = sorted(name for name, passed in checks.items() if not passed)
        raise V08Error("V08 endpoint failed: " + ",".join(failed))
    return {
        "version": "FOUNDRY_INDEPENDENT_V08_SEARCH_RESULT_V1",
        "artifacts": len(artifacts),
        "receipts": len(receipts),
        "cpu_ns_by_arm": cpu_by_arm,
        "states_generated_by_arm": states_by_arm,
        "control_cpu_ns": control_cpu,
        "delta_search": delta,
        "bootstrap_resamples": bootstrap_resamples,
        "bootstrap_seed": bootstrap_seed,
        "bootstrap_lower_95": lower,
        "exact_frozen_tool_digests_reused": exact_reuse,
        "checks": checks,
        "passed": True,
    }


def synthetic_document(candidate_digest: str) -> dict[str, object]:
    receipts: list[dict[str, object]] = []
    cpu = {
        "A2": [40, 42, 44, 46],
        "A3": [100, 105, 110, 115],
        "A9": [90, 95, 100, 105],
    }
    states = {"A2": 12, "A3": 80, "A9": 72}
    for artifact_index in range(4):
        for arm_index, arm in enumerate(ARMS):
            value = cpu[arm][artifact_index]
            started = 1_000_000 * (1 + artifact_index * 3 + arm_index)
            wall = value * 2
            receipts.append(
                {
                    "artifact_id": f"synthetic-{artifact_index}",
                    "arm_id": arm,
                    "candidate_or_control_state_sha256": (
                        f"{artifact_index + arm_index + 1:064x}"[-64:]
                    ),
                    "artifact_graph_sha256": f"{artifact_index + 20:064x}"[-64:],
                    "shape_seed_sha256": f"{artifact_index + 40:064x}"[-64:],
                    "search_started_monotonic_ns": started,
                    "search_finished_monotonic_ns": started + wall,
                    "process_user_cpu_ns": value,
                    "process_system_cpu_ns": 0,
                    "process_wall_ns": wall,
                    "peak_process_tree_rss_kib": 1024,
                    "observed_process_count": 1,
                    "process_group_reaped": True,
                    "states_generated": states[arm],
                    "states_verified": states[arm] - 2,
                    "states_rejected": states[arm] - 4,
                    "selector_comparisons": states[arm],
                    "exact_tool_digests_reused": (
                        [candidate_digest]
                        if arm == "A2" and artifact_index == 0
                        else []
                    ),
                    "failures": [],
                    "timeouts": [],
                    "correctness_passed": True,
                    "resource_receipt_sha256": f"{artifact_index + 60 + arm_index:064x}"[-64:],
                }
            )
    return {
        "version": "FOUNDRY_V08_SEARCH_DISTINCTION_TRIAL_V1",
        "receipts": receipts,
        "runtime_inventions_admitted": 0,
        "stock_decomposition_duplicates": 4,
        "fixed_and_stock_total_cost_reported": True,
        "complete_total_cost_accounting_unchanged": True,
    }


def hostile_selftest(candidate_digest: str) -> dict[str, object]:
    base = synthetic_document(candidate_digest)
    mutations: list[tuple[str, dict[str, object]]] = []

    def mutate(name: str, action: Any) -> None:
        value = copy.deepcopy(base)
        action(value)
        mutations.append((name, value))

    mutate("missing_field", lambda x: x["receipts"][0].pop("timeouts"))
    mutate("extra_field", lambda x: x["receipts"][0].update({"hidden": 1}))
    mutate("bad_arm", lambda x: x["receipts"][0].update({"arm_id": "A8"}))
    mutate(
        "bad_hash",
        lambda x: x["receipts"][0].update({"artifact_graph_sha256": "bad"}),
    )
    mutate(
        "bad_timeline",
        lambda x: x["receipts"][0].update({"process_wall_ns": 1}),
    )
    mutate(
        "unreaped",
        lambda x: x["receipts"][0].update({"process_group_reaped": False}),
    )
    mutate(
        "incorrect",
        lambda x: x["receipts"][0].update({"correctness_passed": False}),
    )
    mutate(
        "state_mismatch",
        lambda x: x["receipts"][0].update({"states_verified": 999}),
    )
    mutate(
        "duplicate_pair",
        lambda x: x["receipts"].__setitem__(1, copy.deepcopy(x["receipts"][0])),
    )
    mutate(
        "artifact_mismatch",
        lambda x: x["receipts"][1].update({"artifact_graph_sha256": "f" * 64}),
    )
    mutate(
        "no_exact_reuse",
        lambda x: [
            row.update({"exact_tool_digests_reused": []})
            for row in x["receipts"]
        ],
    )
    mutate(
        "cpu_threshold_failure",
        lambda x: [
            row.update({"process_user_cpu_ns": 100})
            for row in x["receipts"]
            if row["arm_id"] == "A2"
        ],
    )
    mutate(
        "state_threshold_failure",
        lambda x: [
            row.update(
                {
                    "states_generated": 1000,
                    "states_verified": 999,
                    "states_rejected": 998,
                }
            )
            for row in x["receipts"]
            if row["arm_id"] == "A2"
        ],
    )
    mutate(
        "runtime_novelty_inflated",
        lambda x: x.update({"runtime_inventions_admitted": 1}),
    )
    mutate(
        "fixed_reporting_omitted",
        lambda x: x.update({"fixed_and_stock_total_cost_reported": False}),
    )
    rejected: dict[str, str] = {}
    for name, document in mutations:
        try:
            verify_trial(document, candidate_tool_digests={candidate_digest})
        except V08Error as error:
            rejected[name] = str(error)
    return {
        "hostile_cases": len(mutations),
        "rejected_cases": len(rejected),
        "all_rejected": set(rejected) == {name for name, _ in mutations},
        "rejections": rejected,
    }

