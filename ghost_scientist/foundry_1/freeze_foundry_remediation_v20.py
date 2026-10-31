#!/usr/bin/env python3
"""Create or verify the phase-130/131 remediation freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/foundry_remediation_v20_freeze.json"
RECORDS = (
    "results/isamore_dependency_bridge_v19_freeze.json",
    "phase130_isamore_exact_archive_transport_recovery_audit.py",
    "results/phase130_isamore_exact_archive_transport_recovery_audit.json",
    "phase131_a1_reference_fallback_no_go_audit.py",
    "results/phase131_a1_reference_fallback_no_go_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(records: list[dict[str, str]]) -> str:
    raw = json.dumps(records, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    archive = json.loads(
        (
            HERE
            / "results/phase130_isamore_exact_archive_transport_recovery_audit.json"
        ).read_text()
    )
    a1 = json.loads(
        (
            HERE / "results/phase131_a1_reference_fallback_no_go_audit.json"
        ).read_text()
    )
    if not (
        archive["status"]
        == "ISAMORE_EXACT_ARCHIVE_TRANSPORT_STILL_UNAVAILABLE"
        and archive["checks"]["downloaded_exact_archives"] == 0
        and archive["checks"]["substitute_source_accepted"] is False
        and a1["status"] == "A1_OPAQUE_REFERENCE_FALLBACK_FORMALLY_REJECTED"
        and a1["checks"]["opaque_framework_call_rejected"] is True
        and a1["decision"]["A1_production_integrated"] is False
        and a1["decision"]["production_integrated_arms"] == 6
    ):
        raise RuntimeError("phase-130/131 remediation evidence invalid")
    records = rows()
    payload = {
        "version": "FOUNDRY_REMEDIATION_FREEZE_V20",
        "classification": "TRANSPORT_UNAVAILABLE_AND_A1_SHORTCUT_REJECTED",
        "records": records,
        "records_sha256": digest(records),
        "phases": [130, 131],
        "exact_archives_acquired": 0,
        "exact_archives_required": 4,
        "substitute_source_accepted": False,
        "next_stop": "kiddo",
        "A1_opaque_fallback_rejected": True,
        "A1_production_integrated": False,
        "production_integrated_arms": 6,
        "required_arms": 10,
        "P1_complete": False,
        "P3_complete": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"] == "FOUNDRY_REMEDIATION_FREEZE_V20"
        and payload["phases"] == [130, 131]
        and payload["exact_archives_acquired"] == 0
        and payload["exact_archives_required"] == 4
        and payload["substitute_source_accepted"] is False
        and payload["next_stop"] == "kiddo"
        and payload["A1_opaque_fallback_rejected"] is True
        and payload["A1_production_integrated"] is False
        and payload["production_integrated_arms"] == 6
        and payload["P1_complete"] is False
        and payload["P3_complete"] is True
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("phase-130/131 remediation freeze changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("phase-130/131 remediation digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"remediation-v20 freeze mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_REMEDIATION_V20_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
