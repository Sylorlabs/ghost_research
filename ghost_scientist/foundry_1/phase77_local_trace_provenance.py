#!/usr/bin/env python3
"""Authenticate locally frozen production-trace bytes and use provenance."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "external_traces/LOCAL_TRACE_BYTE_PROTOCOL_V1.json"
RESULT = HERE / "results/phase77_local_trace_provenance.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def git_blob_sha1(raw: bytes) -> str:
    header = f"blob {len(raw)}\0".encode()
    return hashlib.sha1(header + raw).hexdigest()


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    records = []
    for expected in protocol["upstream"]["records"]:
        path = HERE / expected["local_path"]
        raw = path.read_bytes()
        records.append(
            {
                **expected,
                "bytes": len(raw),
                "sha256": hashlib.sha256(raw).hexdigest(),
                "computed_git_blob_sha1": git_blob_sha1(raw),
                "git_blob_exact": (
                    git_blob_sha1(raw) == expected["git_blob_sha1"]
                ),
            }
        )
    root_readme = (
        HERE / "external_traces/source/alibaba_clusterdata_ROOT_README.md"
    ).read_text(encoding="utf-8")
    trace_readme = (
        HERE / "external_traces/source/alibaba_GenTD26_README.md"
    ).read_text(encoding="utf-8")
    checks = {
        "protocol_frozen": protocol[
            "frozen_before_local_provenance_audit"
        ],
        "three_records_present": len(records) == 3,
        "all_git_blobs_exact": all(row["git_blob_exact"] for row in records),
        "trace_bytes_exact": (
            records[2]["bytes"] == 2012418
            and records[2]["sha256"]
            == "263fb88f1095f62d360cf89ded8cfc24fa2c5d111c1b16e7aaa9ccbfc4b37d78"
        ),
        "production_origin_documented": (
            "Data originates from real production environment"
            in trace_readme
        ),
        "research_use_grant_documented": (
            "You may use trace however you want as long as it is for reseach "
            "or study purpose." in root_readme
        ),
        "license_path_error_preserved": (
            protocol["provenance_correction"]["classification"]
            == "RESEARCH_USE_GRANT_NOT_STANDARD_LICENSE_FILE"
        ),
        "validation_v6_access_forbidden": (
            protocol["validation_v6_access_allowed"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("local trace provenance audit failed")
    payload = {
        "version": "FOUNDRY_LOCAL_TRACE_PROVENANCE_V1",
        "status": "LOCAL_TRACE_BYTES_AUTHENTICATED",
        "classification": "EXACT_UPSTREAM_GIT_BLOBS_RESEARCH_USE_ONLY",
        "repository": protocol["upstream"]["repository"],
        "commit": protocol["upstream"]["commit"],
        "records": records,
        "checks": checks,
        "provenance_correction": protocol["provenance_correction"],
        "P2": {
            "trace_source_bytes_locally_frozen": True,
            "trace_documentation_locally_frozen": True,
            "use_grant_locally_frozen": True,
            "standard_license_file_present": False,
            "offline_aggregate_replayed": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE77_LOCAL_TRACE_PROVENANCE"
        f" status={payload['status']}"
        f" blobs={len(records)}/3"
        f" trace_bytes={records[2]['bytes']}"
        " P2=false prospective=false"
    )


if __name__ == "__main__":
    run()
