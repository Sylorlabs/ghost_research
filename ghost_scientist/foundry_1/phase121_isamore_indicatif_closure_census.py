#!/usr/bin/env python3
"""Audit the exact locked indicatif transitive closure."""

from __future__ import annotations

import hashlib
import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
PRIOR = HERE / "results/phase120_isamore_graphviz_family_bridge_audit.json"
RESULT = HERE / "results/phase121_isamore_indicatif_closure_census.json"
ROOT = ("indicatif", "0.17.11")
EXPECTED_MISSING = {
    ("console", "0.15.11"),
    ("encode_unicode", "1.0.0"),
    ("indicatif", "0.17.11"),
    ("js-sys", "0.3.90"),
    ("libc", "0.2.182"),
    ("number_prefix", "0.4.0"),
    ("once_cell", "1.21.3"),
    ("quote", "1.0.44"),
    ("wasm-bindgen", "0.2.113"),
    ("wasm-bindgen-macro", "0.2.113"),
    ("wasm-bindgen-macro-support", "0.2.113"),
    ("wasm-bindgen-shared", "0.2.113"),
    ("web-time", "1.1.0"),
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
        prior["status"] == "ISAMORE_GRAPHVIZ_FAMILY_ADVANCES_STOP"
        and prior["next_build_stop"]["package"] == "indicatif"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior indicatif stop changed")
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
    actual_missing = {
        (row["package"], row["version"]) for row in missing
    }
    if (
        len(records) != 31
        or len(present) != 18
        or actual_missing != EXPECTED_MISSING
    ):
        raise RuntimeError(
            "locked indicatif closure changed; create a new phase rather "
            "than rewriting this census"
        )
    payload = {
        "version": "FOUNDRY_ISAMORE_INDICATIF_CLOSURE_CENSUS_V1",
        "status": "ISAMORE_INDICATIF_CLOSURE_AUTHENTICATED_INCOMPLETE",
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
        "already_bridged_quote_tag_not_counted_as_archive": True,
        "build_stop_after_phase": "indicatif",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The exact indicatif closure contains 31 locked packages. Eighteen "
            "have checksum-matching cached archives and thirteen do not. The "
            "existing quote tag bridge is not counted as archive identity; no "
            "resolver stop advanced or algorithm ran."
        ),
        "next_action": (
            "acquire exact indicatif, console, number_prefix, and "
            "encode_unicode source before generic platform dependencies"
        ),
    }
    if RESULT.exists():
        if json.loads(RESULT.read_text()) != payload:
            raise RuntimeError("indicatif census disagrees with frozen result")
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE121_ISAMORE_INDICATIF_CLOSURE"
        " status=AUTHENTICATED_INCOMPLETE exact=18/31 missing=13"
        " stop=indicatif compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
