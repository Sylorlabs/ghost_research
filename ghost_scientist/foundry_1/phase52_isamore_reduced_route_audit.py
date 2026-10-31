#!/usr/bin/env python3
"""Reject an unfaithful reduced ISAMORE route from pinned core identities."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_control_four_route_v1 import verify as verify_route


HERE = pathlib.Path(__file__).resolve().parent
INTAKE = HERE / "external_controls/isamore/core_intake_v1.json"
RESULT = HERE / "results/phase52_isamore_reduced_route_audit.json"
EXPECTED = {
    "src/lib.rs": "25016eafa9fe0889d050c8f989ac42afd0e88543",
    "src/main.rs": "6e42b84792b0ba270c8bf819af402208ff00685a",
    "src/runner.rs": "c0e00094c7c7f90b55b2806d7418d5d871c0fefa",
    "src/egg_lang.rs": "ec62c3efc44c0cd0af1d7804233b466051a3c7ca",
    "src/experiment.rs": "55dfc99f571d2c6b9ff454aa259c84eb466b1349",
}


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run() -> None:
    route = verify_route()
    intake = json.loads(INTAKE.read_text())
    records = {
        row["path"]: row["blob_sha1"] for row in intake["core_records"]
    }
    if records != EXPECTED:
        raise RuntimeError("ISAMORE core connector identities changed")
    boundary = intake["evidence_boundary"]
    observations = intake["runner_observations"]
    reduced_route_faithful = (
        boundary["files_materialized_locally"]
        and boundary["recursive_submodule_identities_observed"]
        and observations[
            "hardware_selection_separable_from_library_learning"
        ]
    )
    payload = {
        "version": "FOUNDRY_ISAMORE_REDUCED_ROUTE_AUDIT_V1",
        "status": "ISAMORE_REDUCED_ROUTE_REJECTED",
        "route_freeze_sha256": sha(
            HERE / "results/control_four_route_v1_freeze.json"
        ),
        "intake_sha256": sha(INTAKE),
        "commit": intake["commit"],
        "core_records": intake["core_records"],
        "core_blob_identities_observed": len(records),
        "core_files_materialized_locally": boundary[
            "files_materialized_locally"
        ],
        "recursive_submodule_identities_observed": boundary[
            "recursive_submodule_identities_observed"
        ],
        "runner_observations": observations,
        "reduced_route_faithful": reduced_route_faithful,
        "control_executed": False,
        "controls_reproduced": route[
            "source_faithful_controls_reproduced"
        ],
        "controls_required": 4,
        "rejection_reasons": [
            "the exact core file bytes are not materialized locally",
            "the four recursive submodule commit identities remain unavailable",
            "ISAX run invokes prune and Babble-backed library selection before area/cycle Pareto scoring",
            "removing Babble or hardware-aware scoring would remove defining ISAMORE behavior",
            "a standalone Babble or Enumo execution would duplicate an existing control",
        ],
        "claim_boundary": (
            "Five connector-observed core blob identities and targeted runner "
            "source establish coupling, not executable source closure. A "
            "locally invented mock, replayed output, or subsystem-only build "
            "is forbidden as fourth-control conformance."
        ),
        "next_action": (
            "leave P1 at 3/4 until a recursive checkout is recoverable; pursue "
            "the independent P2 heterogeneous-reuse remediation in parallel"
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE52_ISAMORE_REDUCED_ROUTE"
        f" status={payload['status']}"
        f" core_identities={len(records)}"
        " faithful=false executed=false controls=3/4"
    )


if __name__ == "__main__":
    run()
