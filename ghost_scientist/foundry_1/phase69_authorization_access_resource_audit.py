#!/usr/bin/env python3
"""Meter authorization and distinguish manifest reads from heldout access."""

from __future__ import annotations

import ast
import hashlib
import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"
AUTH_SOURCE = HERE / "phase68_pareto_authorization_audit.py"
RESULT = RESULTS / "phase69_authorization_access_resource_audit.json"


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    receipt = run_metered_tree(
        [str(python), str(AUTH_SOURCE)],
        cwd=HERE,
        wall_limit_seconds=30,
        cpu_limit_seconds=20,
        rss_limit_kib=512_000,
    )
    auth = json.loads(
        (RESULTS / "phase68_pareto_authorization_audit.json").read_text()
    )
    source_text = AUTH_SOURCE.read_text()
    tree = ast.parse(source_text, filename=str(AUTH_SOURCE))
    imported_modules = sorted(
        {
            alias.name
            for node in ast.walk(tree)
            if isinstance(node, ast.Import)
            for alias in node.names
        }
        | {
            node.module or ""
            for node in ast.walk(tree)
            if isinstance(node, ast.ImportFrom)
        }
    )
    string_literals = {
        node.value
        for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    }
    allowed_manifest = "external_validation_v6_intake_freeze.json"
    forbidden_runtime_tokens = {
        "external_validation_v6_runtime",
        "external_validation_v6.models",
        "external_validation_v6/SOURCE_INTAKE.json",
    }
    static_access = {
        "frozen_intake_manifest_literal_present": allowed_manifest
        in source_text,
        "heldout_runtime_import_present": any(
            token in imported_modules
            for token in {
                "external_validation_v6_runtime",
                "external_validation_v6.models",
            }
        ),
        "heldout_runtime_or_source_literal_present": any(
            token in source_text for token in forbidden_runtime_tokens
        ),
        "manifest_read_counted_by_coarse_audit": auth["access_audit"][
            "forbidden_open_count"
        ]
        == 1,
    }
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and "FOUNDRY_PHASE68_PARETO_AUTHORIZATION"
        in receipt["stdout_text"]
    )
    access_ok = (
        static_access["frozen_intake_manifest_literal_present"]
        and not static_access["heldout_runtime_import_present"]
        and not static_access["heldout_runtime_or_source_literal_present"]
        and static_access["manifest_read_counted_by_coarse_audit"]
        and auth["heldout_import_or_execution_observed"] is False
        and auth["prospective_trial_authorized"] is False
    )
    passed = meter_test["pass"] and receipt_ok and access_ok
    payload = {
        "version": "FOUNDRY_AUTHORIZATION_ACCESS_RESOURCE_AUDIT_V1",
        "status": (
            "AUTHORIZATION_ACCESS_RESOURCE_PASS"
            if passed
            else "AUTHORIZATION_ACCESS_RESOURCE_FAIL"
        ),
        "authorization_source_sha256": hashlib.sha256(
            AUTH_SOURCE.read_bytes()
        ).hexdigest(),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "static_access": static_access,
        "imported_modules": imported_modules,
        "heldout_manifest_accessed": True,
        "heldout_source_runtime_or_graph_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE69_AUTHORIZATION_ACCESS_RESOURCE"
        f" status={payload['status']}"
        " manifest_only=true heldout_runtime=false"
    )


if __name__ == "__main__":
    run()
