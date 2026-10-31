#!/usr/bin/env python3
"""Execute the frozen official Stitch conformance fixture, fail closed."""

from __future__ import annotations

import hashlib
import importlib
import json
import pathlib
import sys
import tempfile
import zipfile


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PROTOCOL = HERE / "CONTROL_EXECUTION_PROTOCOL_V1.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(payload: dict) -> None:
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "phase33_stitch_control_conformance.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text(encoding="utf-8"))
    fixture_path = HERE / protocol["conformance"]["fixture"]
    fixture = json.loads(fixture_path.read_text(encoding="utf-8"))
    artifact = protocol["artifact"]
    wheel = HERE / artifact["required_local_path"]
    base = {
        "version": "FOUNDRY_STITCH_CONTROL_CONFORMANCE_V1",
        "control": "stitch",
        "implementation_revision": protocol["control"][
            "implementation_revision"
        ],
        "binding_revision": protocol["control"]["binding_revision"],
        "fixture_sha256": sha256(fixture_path),
        "expected_artifact_sha256": artifact["sha256"],
        "artifact_path": str(wheel.relative_to(HERE)),
        "artifact_present": wheel.is_file(),
        "artifact_sha256_verified": False,
        "official_backend_executed": False,
        "conformance_executed": False,
        "conformance_passed": False,
    }
    if not wheel.is_file():
        payload = {
            **base,
            "status": "STITCH_CONTROL_INFRASTRUCTURE_FAILURE",
            "failure_class": "PINNED_WHEEL_UNAVAILABLE",
            "claim_boundary": (
                "No control result was observed. Official metadata and a "
                "frozen expected result are not an executable reproduction."
            ),
        }
        write(payload)
        print(
            "FOUNDRY_PHASE33_STITCH_CONTROL"
            " status=STITCH_CONTROL_INFRASTRUCTURE_FAILURE"
            " artifact_present=false conformance_executed=false"
        )
        return
    observed_sha = sha256(wheel)
    if observed_sha != artifact["sha256"]:
        payload = {
            **base,
            "status": "STITCH_CONTROL_INFRASTRUCTURE_FAILURE",
            "failure_class": "PINNED_WHEEL_HASH_MISMATCH",
            "observed_artifact_sha256": observed_sha,
            "claim_boundary": "An unverified binary was not imported or executed.",
        }
        write(payload)
        print(
            "FOUNDRY_PHASE33_STITCH_CONTROL"
            " status=STITCH_CONTROL_INFRASTRUCTURE_FAILURE"
            " artifact_present=true artifact_verified=false"
            " conformance_executed=false"
        )
        return
    with tempfile.TemporaryDirectory(prefix="foundry_stitch_") as tmp:
        with zipfile.ZipFile(wheel) as archive:
            archive.extractall(tmp)
        sys.path.insert(0, tmp)
        stitch_core = importlib.import_module("stitch_core")
        call = fixture["call"]
        result = stitch_core.compress(
            call["programs"],
            iterations=call["iterations"],
            max_arity=call["max_arity"],
            threads=call["threads"],
            silent=call["silent"],
        )
    expected = fixture["expected"]
    abstraction = result.abstractions[0] if result.abstractions else None
    checks = {
        "one_abstraction": len(result.abstractions)
        == expected["abstractions"],
        "name_exact": abstraction is not None
        and abstraction.name == expected["name"],
        "body_exact": abstraction is not None
        and abstraction.body == expected["body"],
        "arity_exact": abstraction is not None
        and abstraction.arity == expected["arity"],
        "rewritten_exact": result.rewritten == expected["rewritten"],
    }
    passed = all(checks.values())
    payload = {
        **base,
        "status": (
            "STITCH_CONTROL_CONFORMANCE_PASS"
            if passed
            else "STITCH_CONTROL_CONFORMANCE_FAIL"
        ),
        "artifact_sha256_verified": True,
        "observed_artifact_sha256": observed_sha,
        "official_backend_executed": True,
        "conformance_executed": True,
        "conformance_passed": passed,
        "checks": checks,
        "observed": {
            "abstractions": len(result.abstractions),
            "name": abstraction.name if abstraction is not None else None,
            "body": abstraction.body if abstraction is not None else None,
            "arity": abstraction.arity if abstraction is not None else None,
            "rewritten": result.rewritten,
        },
    }
    write(payload)
    print(
        "FOUNDRY_PHASE33_STITCH_CONTROL"
        f" status={payload['status']}"
        " artifact_present=true artifact_verified=true"
        " conformance_executed=true"
    )


if __name__ == "__main__":
    run()
