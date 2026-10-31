#!/usr/bin/env python3
"""Audit pinned Enumo sources and the locally executable dependency closure."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/enumo/source"
RESULT = HERE / "results/phase39_enumo_source_closure.json"

GIT_BLOBS = {
    "Cargo.toml": "2e9ceaac101d07fed5aeaa35b098de98a9cfd1f9",
    "LICENSE": "e51dfd3359921e0bad245f44b497538c3bb601c0",
    "README.md": "c93a4bf2faf3b39ac4144e2980f33cf2927a270b",
    "src/bv.rs": "99323e947e7fb125ee12fee140cff5a2b0b365a6",
    "src/enumo/filter.rs": "78256c22656ca17c3d00f0d322de84223af9cd91",
    "src/enumo/metric.rs": "c8b43ed9ebae036bbd30cc5ae57b0baa98fa402d",
    "src/enumo/mod.rs": "8157f59d983216c87986dbb3b777a69e99687f61",
    "src/enumo/pattern.rs": "28d3bda2356c97d3e1fcf838f3fdf90870d6b379",
    "src/enumo/rule.rs": "9ebdf2d64207b7e69eda514a18d3857cd63af755",
    "src/enumo/ruleset.rs": "ac0130e5c01dc3f09cc154be14b707f9a57ed9f6",
    "src/enumo/scheduler.rs": "f2bf9607073e1d7c2d58ab6d30a053f3052fd7a7",
    "src/enumo/sexp.rs": "597e618ad3738fe105cc439e6ddbd49db3cfb1dc",
    "src/enumo/workload.rs": "913d33389f0746499918d5764991f2aef964acdc",
    "src/language.rs": "7339c4404a9ff41c473a59bf41a3921c619f3126",
    "src/lib.rs": "1363147789d6f5591b242296386b820c6b57956f",
    "src/logger.rs": "17be3f295bdfd126aad594fb7e43b8c7a3a341fa",
    "src/recipe_utils.rs": "af9771febffeb7733af1017400ce77c3ce3c8d1f",
    "src/util.rs": "1f37637e266a2e3479d073a57f406e058502e84b",
}

DIRECT_DEPENDENCIES = {
    "clap": "3.0",
    "log": "0.4",
    "env_logger": "0.7",
    "rand_pcg": "0.2",
    "rand": "0.7",
    "serde": "1",
    "serde_json": "1",
    "indexmap": "1",
    "num": "0.3",
    "num-bigint": "0.3",
    "ordered-float": "2",
    "libm": "0.2",
    "float-cmp": "0.8",
    "lazy_static": "1",
    "itertools": "0.9",
    "z3": "0.12",
    "rustc-hash": "1",
    "symbolic_expressions": "5",
    "rayon": "1",
    "smallstr": "0.3",
    "egg": "0.9",
}


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def versions_for(package: str, filenames: list[str]) -> list[str]:
    prefix = f"{package}-"
    return sorted(
        filename[len(prefix) : -len(".crate")]
        for filename in filenames
        if filename.startswith(prefix) and filename.endswith(".crate")
    )


def compatible(requirement: str, version: str) -> bool:
    numbers = tuple(int(value) for value in re.findall(r"\d+", version)[:2])
    wanted = tuple(int(value) for value in requirement.split("."))
    if len(wanted) == 1:
        return bool(numbers) and numbers[0] == wanted[0]
    return len(numbers) >= 2 and numbers[:2] == wanted[:2]


def run() -> None:
    source_records = []
    for relative, expected in GIT_BLOBS.items():
        actual = git_blob(SOURCE / relative)
        if actual != expected:
            raise RuntimeError(
                f"Enumo source mismatch: {relative}: {actual} != {expected}"
            )
        source_records.append(
            {
                "path": relative,
                "git_blob_sha1": actual,
                "revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
            }
        )
    cache = pathlib.Path.home() / ".cargo/registry/cache"
    crate_files = (
        [path.name for path in cache.rglob("*.crate")] if cache.is_dir() else []
    )
    dependency_records = []
    for package, requirement in DIRECT_DEPENDENCIES.items():
        versions = versions_for(package, crate_files)
        matching = [
            version for version in versions if compatible(requirement, version)
        ]
        dependency_records.append(
            {
                "package": package,
                "required_series": requirement,
                "cached_versions": versions,
                "compatible_cached": matching,
                "locally_available": bool(matching),
            }
        )
    available = [
        row["package"] for row in dependency_records if row["locally_available"]
    ]
    missing = [
        row["package"] for row in dependency_records if not row["locally_available"]
    ]
    system_z3 = any(
        pathlib.Path("/lib/x86_64-linux-gnu").glob("libz3.so*")
    )
    payload = {
        "version": "FOUNDRY_ENUMO_SOURCE_CLOSURE_V1",
        "status": "ENUMO_SOURCE_READY_DEPENDENCY_CLOSURE_BLOCKED",
        "repository": "uwplse/ruler",
        "revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
        "readme_git_blob_sha1": GIT_BLOBS["README.md"],
        "cargo_git_blob_sha1": GIT_BLOBS["Cargo.toml"],
        "license_git_blob_sha1": GIT_BLOBS["LICENSE"],
        "source_records": source_records,
        "source_checkout_complete": True,
        "source_files_exact": len(source_records),
        "direct_dependencies": dependency_records,
        "direct_dependencies_total": len(dependency_records),
        "direct_dependencies_locally_available": len(available),
        "direct_dependencies_missing": len(missing),
        "available_packages": available,
        "missing_packages": missing,
        "system_libz3_present": system_z3,
        "rust_z3_binding_available": "z3" in available,
        "first_offline_cargo_failure": "no matching package named `clap` found",
        "control_executed": False,
        "conformance_executed": False,
        "controls_reproduced": 1,
        "controls_required": 4,
        "claim_boundary": (
            "The complete Enumo library source closure is pinned and locally "
            "present, but eleven direct dependency series are absent from the "
            "offline crate cache. A system Z3 library does not replace the "
            "missing Rust Z3 binding. No Enumo algorithm was executed, and no "
            "Ghost-authored substitute counts as control two."
        ),
        "next_action": (
            "compare Babble/ISAMORE's pinned source dependency closure before "
            "choosing whether to recover Enumo's eleven missing upstream "
            "packages or execute a lower-closure second public control"
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE39_ENUMO_SOURCE"
        f" status={payload['status']}"
        f" source_files={len(source_records)}"
        f" deps={len(available)}/{len(dependency_records)}"
        f" missing={len(missing)}"
        " executed=false"
    )


if __name__ == "__main__":
    run()
