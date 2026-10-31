#!/usr/bin/env python3
"""Create or verify the immutable ISAMORE ingress result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = (
    HERE
    / "results/phase136_isamore_exact_artifact_ingress_conformance.json"
)
MANIFEST = (
    HERE
    / "results/isamore_exact_artifact_ingress_result_v1_freeze.json"
)
RECORDS = [
    "arm_adapter_fixtures/ISAMORE_EXACT_ARTIFACT_INGRESS_PROTOCOL_V1.json",
    "isamore_exact_artifact_ingress.py",
    "phase136_isamore_exact_artifact_ingress_conformance.py",
]


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"]
        == "ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_PASS"
        and all(result["checks"].values())
        and result["locked_registry_identities"] == 310
        and len(result["hostile_rejections"]) == 11
        and result["real_inbox"]["exact_artifacts_acquired"] == 0
        and result["P1_complete"] is False
        and result["validation_v6_accessed"] is False
    ):
        raise RuntimeError("phase136 result is not the expected boundary")
    return {
        "version":
        "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": records(),
        "status": result["status"],
        "locked_registry_identities": 310,
        "hostile_rejections": 11,
        "real_exact_artifacts_acquired": 0,
        "P1_complete": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == records()
        and payload["status"]
        == "ISAMORE_EXACT_ARTIFACT_INGRESS_CONFORMANCE_PASS"
        and payload["locked_registry_identities"] == 310
        and payload["hostile_rejections"] == 11
        and payload["real_exact_artifacts_acquired"] == 0
        and payload["P1_complete"] is False
        and payload["production_integrated_arms"] == 6
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("ISAMORE ingress result freeze changed")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    if not existed:
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_RESULT_V1_FREEZE_PASS"
        f" mode={'VERIFY' if existed else 'CREATE'}"
        " exact=0 P1=false"
    )


if __name__ == "__main__":
    main()
