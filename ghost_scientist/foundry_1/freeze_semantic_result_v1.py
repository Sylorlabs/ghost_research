#!/usr/bin/env python3
"""Create or verify the closed semantic-construction result component."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
MANIFEST = HERE / "results/semantic_result_v1_freeze.json"
RECORDS = (
    "freeze_semantic_result_v1.py",
    "results/semantic_prospective_v1_freeze.json",
    "results/phase25_semantic_grammar_forge.json",
    "results/forged_semantic_tools.json",
    "results/phase26_independent_semantic_eval.json",
    "results/phase27_semantic_native_dedup.json",
    "results/phase28_semantic_resource_audit.json",
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rows() -> list[dict[str, str]]:
    return [{"path": path, "sha256": sha(HERE / path)} for path in RECORDS]


def digest(value: list[dict[str, str]]) -> str:
    raw = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(raw).hexdigest()


def create() -> dict:
    if MANIFEST.exists():
        raise RuntimeError("semantic result-v1 freeze already exists")
    records = rows()
    payload = {
        "version": "FOUNDRY_SEMANTIC_RESULT_FREEZE_V1",
        "records": records,
        "records_sha256": digest(records),
        "classification": "PROSPECTIVE_VALID_NEGATIVE",
    }
    MANIFEST.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    return payload


def verify() -> dict:
    payload = json.loads(MANIFEST.read_text(encoding="utf-8"))
    if payload["version"] != "FOUNDRY_SEMANTIC_RESULT_FREEZE_V1":
        raise RuntimeError("semantic result freeze version changed")
    if payload["classification"] != "PROSPECTIVE_VALID_NEGATIVE":
        raise RuntimeError("semantic result classification changed")
    if [row["path"] for row in payload["records"]] != list(RECORDS):
        raise RuntimeError("semantic result record order changed")
    if payload["records_sha256"] != digest(payload["records"]):
        raise RuntimeError("semantic result digest changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"semantic result mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    payload = verify() if existed else create()
    verify()
    print(
        "FOUNDRY_SEMANTIC_RESULT_V1_FREEZE_PASS"
        f" records={len(payload['records'])}"
        f" records_sha256={payload['records_sha256']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
