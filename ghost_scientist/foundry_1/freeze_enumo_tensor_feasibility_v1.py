#!/usr/bin/env python3
"""Create or verify the pre-execution Enumo tensor feasibility freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/ENUMO_TENSOR_DOMAIN_FEASIBILITY_PROTOCOL_V1.json"
MANIFEST = HERE / "results/enumo_tensor_feasibility_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def create() -> dict:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    if not (
        protocol["frozen_before_runner_implementation_or_execution"] is True
        and protocol["identity"]["is_frozen_boolean_A7"] is False
        and protocol["identity"]["may_promote_A7"] is False
        and protocol["identity"][
            "may_increase_production_integrated_arm_count"
        ]
        is False
        and protocol["domain"]["operators"] == ["add", "mul", "relu"]
        and protocol["domain"]["workload_atom_limits"] == [3, 4]
        and protocol["claim_boundary"]["validation_v6_source_runtime_graph_or_outcome_accessed"]
        is False
    ):
        raise RuntimeError("Enumo tensor feasibility protocol invalid")
    return {
        "version": "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_FREEZE_V1",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "provider_records_sha256": hashlib.sha256(
            json.dumps(
                protocol["provider_records"],
                sort_keys=True,
                separators=(",", ":"),
            ).encode()
        ).hexdigest(),
        "frozen_before_runner_implementation_or_execution": True,
        "experiment_name": "ENUMO_TENSOR_DOMAIN_FEASIBILITY",
        "is_frozen_boolean_A7": False,
        "may_promote_A7": False,
        "may_increase_production_integrated_arm_count": False,
        "operators": ["add", "mul", "relu"],
        "workload_atom_limits": [3, 4],
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"] == "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_FREEZE_V1"
        and payload["protocol_sha256"] == sha(PROTOCOL)
        and payload["frozen_before_runner_implementation_or_execution"] is True
        and payload["is_frozen_boolean_A7"] is False
        and payload["may_promote_A7"] is False
        and payload["may_increase_production_integrated_arm_count"] is False
        and payload["operators"] == ["add", "mul", "relu"]
        and payload["workload_atom_limits"] == [3, 4]
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("Enumo tensor feasibility freeze changed")
    for row in payload["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen provider mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    if existed:
        payload = verify()
    else:
        payload = create()
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_ENUMO_TENSOR_FEASIBILITY_V1_FREEZE_PASS"
        f" records={len(payload['provider_records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
