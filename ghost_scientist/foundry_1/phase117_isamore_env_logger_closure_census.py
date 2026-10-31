#!/usr/bin/env python3
"""Audit the union of all three locked env_logger dependency closures."""

from __future__ import annotations

import hashlib
import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
PRIOR = HERE / "results/phase116_isamore_csv_tag_bridge_audit.json"
RESULT = HERE / "results/phase117_isamore_env_logger_closure_census.json"
ROOTS = (
    ("env_logger", "0.7.1"),
    ("env_logger", "0.9.3"),
    ("env_logger", "0.11.9"),
)
EXPECTED_MISSING = {
    ("anstream", "0.6.21"),
    ("anstyle", "1.0.13"),
    ("anstyle-parse", "0.2.7"),
    ("anstyle-query", "1.1.5"),
    ("anstyle-wincon", "3.0.11"),
    ("colorchoice", "1.0.4"),
    ("env_filter", "1.0.0"),
    ("env_logger", "0.7.1"),
    ("env_logger", "0.9.3"),
    ("env_logger", "0.11.9"),
    ("is_terminal_polyfill", "1.70.2"),
    ("jiff", "0.2.21"),
    ("jiff-static", "0.2.21"),
    ("once_cell_polyfill", "1.70.2"),
    ("portable-atomic-util", "0.2.5"),
    ("quote", "1.0.44"),
    ("utf8parse", "0.2.2"),
}


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
        prior["status"] == "ISAMORE_CSV_CLOSURE_ADVANCES_STOP"
        and prior["next_build_stop"]["package"] == "env_logger"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior env_logger stop changed")

    packages = tomllib.loads(
        (SOURCE / "Cargo.lock").read_text(encoding="utf-8")
    )["package"]
    by_key = {(row["name"], row["version"]): row for row in packages}
    by_name: dict[str, list[dict]] = {}
    for row in packages:
        by_name.setdefault(row["name"], []).append(row)

    closure: set[tuple[str, str]] = set()
    pending = list(ROOTS)
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
        matches = sorted(cache.rglob(f"{name}-{version}.crate"))
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
    actual_missing = {
        (row["package"], row["version"]) for row in missing
    }
    if (
        len(records) != 31
        or len(present) != 14
        or actual_missing != EXPECTED_MISSING
    ):
        raise RuntimeError(
            "locked env_logger union closure changed; create a new phase "
            "rather than rewriting this census"
        )

    payload = {
        "version": "FOUNDRY_ISAMORE_ENV_LOGGER_CLOSURE_CENSUS_V1",
        "status": "ISAMORE_ENV_LOGGER_CLOSURE_AUTHENTICATED_INCOMPLETE",
        "root_packages": [
            {"package": name, "version": version} for name, version in ROOTS
        ],
        "locked_union_closure": records,
        "summary": {
            "root_versions": 3,
            "locked_packages": len(records),
            "exact_cached_archives": len(present),
            "missing_exact_archives": len(missing),
        },
        "missing_exact_packages": [
            {"package": row["package"], "version": row["version"]}
            for row in missing
        ],
        "single_version_patch_rejected": True,
        "build_stop_after_phase": "env_logger",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The lock contains three env_logger generations whose union closure "
            "contains 31 exact packages. Fourteen have checksum-matching local "
            "archives and seventeen do not. A single-version patch was "
            "rejected; no Cargo stop advanced and no algorithm compiled or ran."
        ),
        "next_action": (
            "acquire all three exact env_logger roots and the unresolved 0.11.9 "
            "closure, using package aliases where Cargo patching needs multiple "
            "versions of the same crate"
        ),
    }
    if RESULT.exists():
        if json.loads(RESULT.read_text(encoding="utf-8")) != payload:
            raise RuntimeError(
                "env_logger closure census disagrees with frozen result"
            )
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE117_ISAMORE_ENV_LOGGER_CLOSURE"
        " status=AUTHENTICATED_INCOMPLETE roots=3 exact=14/31 missing=17"
        " stop=env_logger compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
