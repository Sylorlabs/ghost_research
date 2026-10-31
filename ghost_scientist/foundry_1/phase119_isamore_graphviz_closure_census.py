#!/usr/bin/env python3
"""Audit the exact locked graphviz-rust transitive closure."""

from __future__ import annotations

import hashlib
import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
PRIOR = HERE / "results/phase118_isamore_env_logger_roots_bridge_audit.json"
RESULT = HERE / "results/phase119_isamore_graphviz_closure_census.json"
ROOT = ("graphviz-rust", "0.8.0")
EXPECTED_MISSING = {
    ("dot-generator", "0.2.0"),
    ("dot-structures", "0.1.2"),
    ("getrandom", "0.4.1"),
    ("graphviz-rust", "0.8.0"),
    ("into-attr", "0.1.1"),
    ("into-attr-derive", "0.2.1"),
    ("itoa", "1.0.17"),
    ("libc", "0.2.182"),
    ("once_cell", "1.21.3"),
    ("pest", "2.8.6"),
    ("pest_derive", "2.8.6"),
    ("pest_generator", "2.8.6"),
    ("pest_meta", "2.8.6"),
    ("quote", "1.0.44"),
    ("tempfile", "3.26.0"),
    ("ucd-trie", "0.1.7"),
    ("wasip2", "1.0.1+wasi-0.2.4"),
    ("wit-bindgen", "0.46.0"),
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
    prior = json.loads(PRIOR.read_text(encoding="utf-8"))
    if not (
        prior["status"] == "ISAMORE_ENV_LOGGER_ROOTS_ADVANCE_STOP"
        and prior["next_build_stop"]["package"] == "graphviz-rust"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior graphviz-rust stop changed")
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
        len(records) != 77
        or len(present) != 57
        or actual_missing != EXPECTED_MISSING
    ):
        raise RuntimeError(
            "locked graphviz-rust closure changed; create a new phase "
            "rather than rewriting this census"
        )
    payload = {
        "version": "FOUNDRY_ISAMORE_GRAPHVIZ_CLOSURE_CENSUS_V1",
        "status": "ISAMORE_GRAPHVIZ_CLOSURE_AUTHENTICATED_INCOMPLETE",
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
        "already_bridged_tag_sources_not_counted_as_archives": [
            {"package": "itoa", "version": "1.0.17"},
            {"package": "quote", "version": "1.0.44"},
        ],
        "build_stop_after_phase": "graphviz-rust",
        "algorithm_compilation_reached": False,
        "algorithm_execution_reached": False,
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The exact graphviz-rust closure contains 77 locked packages. "
            "Fifty-seven have checksum-matching cached archives and twenty do "
            "not. Existing itoa and quote tag bridges are not counted as "
            "archive identity; no build stop advanced or algorithm ran."
        ),
        "next_action": (
            "acquire graphviz-rust, dot-generator, dot-structures, and "
            "into-attr family exact sources before addressing generic "
            "platform/tooling dependencies"
        ),
    }
    if RESULT.exists():
        if json.loads(RESULT.read_text(encoding="utf-8")) != payload:
            raise RuntimeError(
                "graphviz-rust closure census disagrees with frozen result"
            )
        mode = "VERIFY_FROZEN"
    else:
        RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE119_ISAMORE_GRAPHVIZ_CLOSURE"
        " status=AUTHENTICATED_INCOMPLETE exact=57/77 missing=20"
        " stop=graphviz-rust compiled=false executed=false P1=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
