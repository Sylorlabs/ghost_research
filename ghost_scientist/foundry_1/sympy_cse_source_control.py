#!/usr/bin/env python3
"""Execute the pre-frozen source-faithful SymPy CSE control."""

from __future__ import annotations

import ast
import base64
import csv
import hashlib
import importlib.metadata
import json
import pathlib
import re
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/sympy_cse_control_v1_freeze.json"
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/SYMPY_CSE_CONTROL_EXECUTION_AMENDMENT_V1.json"
)
AMENDMENT_FREEZE = (
    HERE / "results/sympy_cse_control_execution_amendment_v1_freeze.json"
)
RESULT = HERE / "results/phase137_sympy_cse_source_control.json"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def record_digest(raw: bytes) -> str:
    return base64.urlsafe_b64encode(hashlib.sha256(raw).digest()).rstrip(
        b"="
    ).decode()


def verify_distribution(
    root: pathlib.Path, protocol: dict[str, object]
) -> dict[str, object]:
    metadata = root / "sympy-1.13.1.dist-info/METADATA"
    record = root / "sympy-1.13.1.dist-info/RECORD"
    expected_distribution = {
        row["path"]: row["sha256"]
        for row in protocol["distribution_provider_records"]
    }
    if (
        sha256(metadata) != expected_distribution[
            "sympy-1.13.1.dist-info/METADATA"
        ]
        or sha256(record)
        != expected_distribution["sympy-1.13.1.dist-info/RECORD"]
    ):
        raise RuntimeError("SymPy distribution metadata changed")
    text = metadata.read_text(encoding="utf-8")
    if "Name: sympy\n" not in text or "Version: 1.13.1\n" not in text:
        raise RuntimeError("SymPy distribution identity changed")
    checked = 0
    unhashed = 0
    for relative, encoded, size_text in csv.reader(
        record.read_text(encoding="utf-8").splitlines()
    ):
        path = root / relative
        if not encoded:
            unhashed += 1
            continue
        if not encoded.startswith("sha256="):
            raise RuntimeError(f"unsupported RECORD digest: {relative}")
        raw = path.read_bytes()
        if (
            record_digest(raw) != encoded.removeprefix("sha256=")
            or len(raw) != int(size_text)
        ):
            raise RuntimeError(f"installed RECORD mismatch: {relative}")
        checked += 1
    if checked < 1000:
        raise RuntimeError("too few hashed SymPy distribution files")
    return {
        "metadata_sha256": sha256(metadata),
        "record_sha256": sha256(record),
        "hashed_files_verified": checked,
        "unhashed_record_rows": unhashed,
        "all_hashed_files_exact": True,
    }


def verify_algorithm_sources(
    root: pathlib.Path, protocol: dict[str, object]
) -> list[dict[str, str]]:
    records = []
    for expected in protocol["repository_provider_records"]:
        path = root / expected["path"]
        actual = {
            "path": expected["path"],
            "git_blob_sha1": git_blob(path),
            "sha256": sha256(path),
        }
        if (
            actual["git_blob_sha1"] != expected["git_blob_sha1"]
            or actual["sha256"] != expected["installed_sha256"]
        ):
            raise RuntimeError(f"SymPy upstream source mismatch: {path}")
        records.append(actual)
    return records


def run_official_suite(
    test_path: pathlib.Path,
    gate: dict[str, object],
    amendment: dict[str, object],
) -> dict[str, object]:
    tree = ast.parse(test_path.read_text(encoding="utf-8"))
    source_declared_xfails = sum(
        any(
            isinstance(decorator, ast.Name) and decorator.id == "XFAIL"
            for decorator in node.decorator_list
        )
        for node in tree.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
    )
    accounting = amendment["clarified_expected_outcome_accounting"]
    if (
        source_declared_xfails
        != accounting["source_declared_xfail_decorators_required"]
    ):
        raise RuntimeError("official SymPy source XFAIL count changed")
    with tempfile.TemporaryDirectory(prefix="foundry-sympy-cse-suite-") as tmp:
        report = pathlib.Path(tmp) / "pytest.xml"
        completed = subprocess.run(
            [
                sys.executable,
                "-c",
                (
                    "import sys;"
                    "sys._running_pytest=True;"
                    "import pytest;"
                    "raise SystemExit(pytest.main(sys.argv[1:]))"
                ),
                str(test_path),
                "-q",
                "--disable-warnings",
                "--tb=no",
                f"--confcutdir={test_path.parent}",
                f"--junitxml={report}",
            ],
            text=True,
            capture_output=True,
            check=False,
            timeout=100,
            env={
                "PATH": "/usr/bin:/bin",
                "HOME": str(pathlib.Path.home()),
                "PYTHONPATH": str(
                    pathlib.Path.home()
                    / ".local/lib/python3.12/site-packages"
                ),
                "PYTHONHASHSEED": "0",
                "PYTHONDONTWRITEBYTECODE": "1",
            },
        )
        if not report.is_file():
            raise RuntimeError(
                "official SymPy CSE suite produced no JUnit report"
            )
        root = ET.parse(report).getroot()
        suite = root if root.tag == "testsuite" else root.find("testsuite")
        if suite is None:
            raise RuntimeError("malformed official-suite JUnit report")
        tests = int(suite.attrib["tests"])
        failures = int(suite.attrib.get("failures", "0"))
        errors = int(suite.attrib.get("errors", "0"))
        skipped = int(suite.attrib.get("skipped", "0"))
        passed = tests - failures - errors - skipped
        xfailed_match = re.search(r"(\d+) xfailed", completed.stdout)
        xpassed_match = re.search(r"(\d+) xpassed", completed.stdout)
        xfailed = int(xfailed_match.group(1)) if xfailed_match else 0
        xpassed = int(xpassed_match.group(1)) if xpassed_match else 0
        accepted_expected_outcomes = passed + xfailed
        amended_gate = amendment["unchanged_gates"]
        accepted = (
            completed.returncode == 0
            and tests >= gate["minimum_collected"]
            and accepted_expected_outcomes
            >= amended_gate["minimum_accepted_expected_outcomes"]
            and passed == accounting["ordinary_passes_required"]
            and xfailed
            == accounting["pytest_classified_xfails_required"]
            and failures <= amended_gate["maximum_unexpected_failures"]
            and errors <= amended_gate["maximum_errors"]
            and xpassed == 0
        )
        return {
            "returncode": completed.returncode,
            "tests": tests,
            "passed": passed,
            "source_declared_xfails": source_declared_xfails,
            "pytest_classified_xfails": xfailed,
            "other_skipped": skipped - xfailed,
            "accepted_expected_outcomes": accepted_expected_outcomes,
            "failures": failures,
            "errors": errors,
            "xpassed": xpassed,
            "stdout_sha256": hashlib.sha256(
                completed.stdout.encode()
            ).hexdigest(),
            "stderr_sha256": hashlib.sha256(
                completed.stderr.encode()
            ).hexdigest(),
            "summary": completed.stdout[-1000:],
            "accepted": accepted,
        }


def fixture(
    spec: dict[str, object], *, renamed: bool
) -> dict[str, object]:
    from sympy import numbered_symbols, symbols, sympify
    from sympy.simplify.cse_main import cse

    symbol_names = spec["symbols"]
    originals = {name: symbols(name) for name in symbol_names}
    expressions = [
        sympify(text, locals=originals) for text in spec["expressions"]
    ]
    point_rows = spec["sample_points"]
    if renamed:
        variant = spec["renamed_reordered_variant"]
        renamed_symbols = {
            old: symbols(new) for old, new in variant["renaming"].items()
        }
        expressions = [
            expressions[index].xreplace(
                {originals[key]: value for key, value in renamed_symbols.items()}
            )
            for index in variant["order"]
        ]
        point_rows = [
            {
                variant["renaming"][key]: value
                for key, value in row.items()
            }
            for row in point_rows
        ]
    replacements, reduced = cse(
        expressions, symbols=numbered_symbols("t"), order="canonical"
    )
    return {
        "expressions": [str(value) for value in expressions],
        "replacements": [
            {"symbol": str(symbol), "expression": str(value)}
            for symbol, value in replacements
        ],
        "reduced": [str(value) for value in reduced],
        "sample_points": point_rows,
    }


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    amendment = json.loads(AMENDMENT.read_text())
    amendment_freeze = json.loads(AMENDMENT_FREEZE.read_text())
    if not (
        freeze["protocol_sha256"] == sha256(PROTOCOL)
        and freeze["frozen_before_control_execution"] is True
        and freeze["validation_v6_accessed"] is False
        and amendment_freeze["amendment_sha256"] == sha256(AMENDMENT)
        and amendment_freeze["initial_infrastructure_failure_preserved"]
        is True
        and amendment_freeze["pristine_preregistration"] is False
    ):
        raise RuntimeError("SymPy CSE pre-execution freeze invalid")
    distribution = importlib.metadata.distribution("sympy")
    if distribution.version != "1.13.1":
        raise RuntimeError("wrong installed SymPy version")
    root = pathlib.Path(distribution.locate_file(""))
    source_records = verify_algorithm_sources(root, protocol)
    distribution_integrity = verify_distribution(root, protocol)
    official = run_official_suite(
        root / protocol["official_suite_gate"]["path"],
        protocol["official_suite_gate"],
        amendment,
    )
    baseline = fixture(protocol["independent_semantic_fixture"], renamed=False)
    renamed = fixture(protocol["independent_semantic_fixture"], renamed=True)
    gates = {
        "preexecution_freeze_authentic": True,
        "distribution_version_exact": distribution.version == "1.13.1",
        "three_official_git_blobs_exact": len(source_records) == 3,
        "installed_distribution_record_exact":
        distribution_integrity["all_hashed_files_exact"],
        "official_test_suite_passed": official["accepted"],
        "baseline_minimum_replacements": (
            len(baseline["replacements"])
            >= protocol["independent_semantic_fixture"][
                "minimum_replacements"
            ]
        ),
        "renamed_reordered_replacement_count_preserved": (
            len(renamed["replacements"]) == len(baseline["replacements"])
        ),
        "zero_llm_calls": protocol["control_identity"]["llm_calls"] == 0,
        "validation_v6_unread": protocol["claim_boundary"][
            "validation_v6_accessed"
        ]
        is False,
    }
    if not all(gates.values()):
        raise RuntimeError("SymPy CSE source control failed")
    payload = {
        "version": "FOUNDRY_SYMPY_CSE_SOURCE_CONTROL_V1",
        "status": "SYMPY_CSE_SOURCE_CONTROL_PRELIMINARY_PASS",
        "protocol_sha256": sha256(PROTOCOL),
        "freeze_sha256": sha256(FREEZE),
        "amendment_sha256": sha256(AMENDMENT),
        "amendment_freeze_sha256": sha256(AMENDMENT_FREEZE),
        "initial_infrastructure_failure": {
            "stage": "pytest_collection",
            "reason": "absent optional hypothesis dependency in package-level conftest",
            "test_outcome_observed": False,
            "preserved": True,
        },
        "identity": {
            "distribution": "sympy",
            "version": distribution.version,
            "official_tag": "sympy-1.13.1",
        },
        "source_records": source_records,
        "distribution_integrity": distribution_integrity,
        "official_suite": official,
        "baseline_fixture": baseline,
        "renamed_reordered_fixture": renamed,
        "gates": gates,
        "candidate_fourth_P1_control": True,
        "independent_semantic_check_pending": True,
        "process_tree_resource_check_pending": True,
        "P1_complete": False,
        "production_integrated_arms": 6,
        "A6_satisfied": False,
        "A8_satisfied": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "Exact installed SymPy 1.13.1 CSE algorithm and official-test "
            "sources match the official tag, the distribution RECORD is "
            "verified, and the official suite passes. P1 remains false until "
            "the frozen independent numeric and process-tree gates pass."
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE137_SYMPY_CSE_SOURCE"
        f" status={payload['status']}"
        f" official={official['passed']}/{official['tests']}"
        f" replacements={len(baseline['replacements'])}"
        " P1=pending"
    )


if __name__ == "__main__":
    main()
