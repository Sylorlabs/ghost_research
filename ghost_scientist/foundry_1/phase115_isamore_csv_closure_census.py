#!/usr/bin/env python3
"""Audit the exact locked csv closure without substituting nearby versions."""

from __future__ import annotations

import hashlib
import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
PRIOR = HERE / "results/phase114_isamore_crossbeam_bridge_audit.json"
RESULT = HERE / "results/phase115_isamore_csv_closure_census.json"
ROOT = ("csv", "1.4.0")


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def dependency_key(
    dependency: str,
    by_name: dict[str, list[dict]],
) -> tuple[str, str]:
    fields = dependency.split()
    if len(fields) >= 2 and fields[1][0].isdigit():
        return fields[0], fields[1]
    matches = by_name[fields[0]]
    if len(matches) != 1:
        raise RuntimeError(
            f"ambiguous locked dependency without version: {dependency}"
        )
    return matches[0]["name"], matches[0]["version"]


def main() -> None:
    prior = json.loads(PRIOR.read_text(encoding="utf-8"))
    if not (
        prior["next_build_stop"]["package"] == "csv"
        and prior["control_executed"] is False
        and prior["checks"]["algorithm_compilation_reached"] is False
    ):
        raise RuntimeError("prior csv stop changed")

    packages = tomllib.loads(
        (SOURCE / "Cargo.lock").read_text(encoding="utf-8")
    )["package"]
    by_key = {(row["name"], row["version"]): row for row in packages}
    by_name: dict[str, list[dict]] = {}
    for row in packages:
        by_name.setdefault(row["name"], []).append(row)

    closure: set[tuple[str, str]] = set()
    pending = [ROOT]
    while pending:
        key = pending.pop()
        if key in closure:
            continue
        if key not in by_key:
            raise RuntimeError(f"locked package absent: {key}")
        closure.add(key)
        for dependency in by_key[key].get("dependencies", []):
            pending.append(dependency_key(dependency, by_name))

    cache = pathlib.Path.home() / ".cargo/registry/cache"
    records = []
    for name, version in sorted(closure):
        package = by_key[(name, version)]
        expected = package.get("checksum")
        filename = f"{name}-{version}.crate"
        matches = sorted(cache.rglob(filename))
        exact = (
            expected is not None
            and len(matches) == 1
            and sha256(matches[0]) == expected
        )
        records.append(
            {
                "package": name,
                "version": version,
                "locked_checksum": expected,
                "exact_cached_archive": exact,
                "cached_archive_sha256": (
                    sha256(matches[0]) if len(matches) == 1 else None
                ),
            }
        )

    present = [row for row in records if row["exact_cached_archive"]]
    missing = [row for row in records if not row["exact_cached_archive"]]
    expected_missing = {
        ("csv", "1.4.0"),
        ("csv-core", "0.1.13"),
        ("itoa", "1.0.17"),
        ("quote", "1.0.44"),
    }
    actual_missing = {
        (row["package"], row["version"]) for row in missing
    }
    if len(records) != 11 or len(present) != 7 or actual_missing != expected_missing:
        raise RuntimeError(
            "locked csv closure changed; create a new phase rather than "
            "silently weakening or rewriting this census"
        )

    payload = {
        "version": "FOUNDRY_ISAMORE_CSV_CLOSURE_CENSUS_V1",
        "status": "ISAMORE_CSV_CLOSURE_AUTHENTICATED_INCOMPLETE",
        "root_package": {"package": ROOT[0], "version": ROOT[1]},
        "locked_closure": records,
        "summary": {
            "locked_packages": len(records),
            "exact_cached_archives": len(present),
            "missing_exact_archives": len(missing),
        },
        "missing_exact_packages": [
            {"package": row["package"], "version": row["version"]}
            for row in missing
        ],
        "nearby_versions_rejected": {
            "itoa": {
                "locked": "1.0.17",
                "available_but_not_substituted": "1.0.18",
            },
            "quote": {
                "locked": "1.0.44",
                "available_but_not_substituted": "1.0.45",
            },
        },
        "build_stop_after_phase": "csv",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "Seven of eleven packages in csv's exact locked transitive closure "
            "have checksum-matching local archives. Four exact versions are "
            "absent. Nearby versions were not substituted, no Cargo stop was "
            "claimed cleared, and no ISAMORE algorithm compiled or executed."
        ),
        "next_action": (
            "acquire the four exact checksum-authenticated archives or exact "
            "official-tag source with an explicit weaker provenance label"
        ),
    }
    if RESULT.exists():
        if json.loads(RESULT.read_text(encoding="utf-8")) != payload:
            raise RuntimeError("csv closure census disagrees with frozen result")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE115_ISAMORE_CSV_CLOSURE"
        " status=AUTHENTICATED_INCOMPLETE exact=7/11 missing=4"
        " stop=csv compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
