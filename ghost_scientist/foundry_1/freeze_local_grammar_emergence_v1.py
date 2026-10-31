#!/usr/bin/env python3
"""Freeze the local grammar-emergence experiment before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/LOCAL_GRAMMAR_EMERGENCE_PROTOCOL_V1.json"
)
RESULT = HERE / "results/local_grammar_emergence_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def assignment(graph_id: str) -> str:
    value = hashlib.sha256(
        ("ghost-foundry:grammar-v1:" + graph_id).encode()
    ).hexdigest()
    return "heldout" if int(value, 16) % 5 == 0 else "training"


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    pool = json.loads((HERE / "results/pareto_tool_pool.json").read_text())
    rows = [
        {
            "graph_id": row["graph_id"],
            "graph_sha256": row["graph_sha256"],
            "assignment": assignment(row["graph_id"]),
        }
        for row in pool["calibration_graphs"]
    ]
    heldout = sorted(
        row["graph_id"] for row in rows if row["assignment"] == "heldout"
    )
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and len(rows) == 23
        and sum(row["assignment"] == "training" for row in rows)
        == protocol["split"]["expected_training_graphs"]
        and sum(row["assignment"] == "heldout" for row in rows)
        == protocol["split"]["expected_heldout_graphs"]
        and heldout == sorted(protocol["split"]["heldout_graph_ids"])
        and protocol["classification"]["local_exploratory_only"] is True
        and protocol["classification"]["post_exploratory_not_pristine"] is True
        and protocol["training_rule"]["llm_calls"] == 0
        and protocol["training_rule"]["human_selected_topology_productions"]
        == 0
        and protocol["decision_rule"][
            "never_advance_P6_or_authorize_prospective_trial"
        ]
        is True
        and len(protocol["hostile_requirements"]["must_cover"]) == 18
    ):
        raise RuntimeError("local grammar-emergence protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_FREEZE_V1",
        "status": "FROZEN_BEFORE_ENUMERATOR_OR_OUTCOME_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "split_records": rows,
        "universal_typed_dag_metalanguage": protocol[
            "universal_typed_dag_metalanguage"
        ],
        "training_rule": protocol["training_rule"],
        "heldout_rule": protocol["heldout_rule"],
        "primary_endpoints": protocol["primary_endpoints"],
        "causal_tests": protocol["causal_tests"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "native_dedup_rule": protocol["native_dedup_rule"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_FREEZE"
        f" status={result['status']}"
        " split=16/7 max_nodes=5 topology_forms=machine_selected"
    )


if __name__ == "__main__":
    main()
