#!/usr/bin/env python3
"""Freeze local total-cost and reachability evaluation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_TOOL_UTILITY_PROTOCOL_V1.json"
RESULT = HERE / "results/local_exact_tool_utility_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    p165 = json.loads((HERE / "results/phase165_local_exact_tool_execution.json").read_text())
    summary = p165["observed"]["summary"]
    if not (
        all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
        and p165["status"] == "LOCAL_EXACT_TOOL_EXECUTION_VALID_STOCK_DUPLICATE"
        and summary["source_matches"] == 17
        and summary["unique_bodies"] == 3
        and summary["normalized_inductor_duplicates"] == 3
        and summary["runtime_inventions_admitted"] == 0
        and protocol["abstract_cost"]["do_not_mix_cpu_nanoseconds_with_abstract_units"]
        is True
        and protocol["decision_rule"]["positive_is_not_prospective_real_world_discovery"]
        is True
        and len(protocol["hostile_requirements"]["must_cover"]) == 16
    ):
        raise RuntimeError("exact-tool utility protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_FREEZE_V1",
        "status": "FROZEN_BEFORE_TOTAL_COST_OR_REACHABILITY_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "evaluation_universe": protocol["evaluation_universe"],
        "abstract_cost": protocol["abstract_cost"],
        "resource_accounting": protocol["resource_accounting"],
        "reachability": protocol["reachability"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "cost_or_reachability_outcome_known_before_freeze": False
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_FREEZE"
        " status=FROZEN_BEFORE_TOTAL_COST_OR_REACHABILITY_IMPLEMENTATION"
        " matches=17 tools=3 graphs=23"
    )


if __name__ == "__main__":
    main()
