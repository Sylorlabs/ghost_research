#!/usr/bin/env python3
"""Audit the exact locked kiddo transitive closure."""

from __future__ import annotations

import hashlib
import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
PRIOR = HERE / "results/phase122_isamore_indicatif_family_bridge_audit.json"
RESULT = HERE / "results/phase123_isamore_kiddo_closure_census.json"
ROOT = ("kiddo", "5.2.4")
EXPECTED_MISSING = {
    ("array-init", "2.1.0"),
    ("az", "1.3.0"),
    ("cc", "1.2.56"),
    ("cmov", "0.4.6"),
    ("divrem", "1.0.0"),
    ("fixed", "1.30.0"),
    ("generator", "0.8.8"),
    ("kiddo", "5.2.4"),
    ("libc", "0.2.182"),
    ("nu-ansi-term", "0.50.3"),
    ("once_cell", "1.21.3"),
    ("ordered-float", "5.1.0"),
    ("pin-project-lite", "0.2.16"),
    ("quote", "1.0.44"),
    ("sharded-slab", "0.1.7"),
    ("sorted-vec", "0.8.10"),
    ("thread_local", "1.1.9"),
    ("tracing-log", "0.2.0"),
    ("tracing-subscriber", "0.3.22"),
    ("valuable", "0.1.1"),
    ("zerocopy", "0.8.39"),
    ("zerocopy-derive", "0.8.39"),
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
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"] == "ISAMORE_INDICATIF_FAMILY_ADVANCES_STOP"
        and prior["next_build_stop"]["package"] == "kiddo"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior kiddo stop changed")
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
    actual_missing = {(row["package"], row["version"]) for row in missing}
    if (
        len(records) != 56
        or len(present) != 34
        or actual_missing != EXPECTED_MISSING
    ):
        raise RuntimeError(
            "locked kiddo closure changed; create a new phase rather than "
            "rewriting this census"
        )
    payload = {
        "version": "FOUNDRY_ISAMORE_KIDDO_CLOSURE_CENSUS_V1",
        "status": "ISAMORE_KIDDO_CLOSURE_AUTHENTICATED_INCOMPLETE",
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
        "prior_tag_sources_not_counted_as_archive_identity": True,
        "build_stop_after_phase": "kiddo",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The exact kiddo closure contains 56 locked packages. Thirty-four "
            "have checksum-matching cached archives and twenty-two do not. "
            "Prior tag bridges are not counted as archive identity; no resolver "
            "stop advanced or algorithm ran."
        ),
        "next_action": (
            "acquire the kiddo-specific math and data-structure package family "
            "before generic tracing and platform dependencies"
        ),
    }
    if RESULT.exists():
        if json.loads(RESULT.read_text()) != payload:
            raise RuntimeError("kiddo census disagrees with frozen result")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE123_ISAMORE_KIDDO_CLOSURE"
        " status=AUTHENTICATED_INCOMPLETE exact=34/56 missing=22"
        " stop=kiddo compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
