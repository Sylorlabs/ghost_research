#!/usr/bin/env python3
"""Audit the only pinned fourth-control route without claiming execution."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import shutil
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
RESULT = HERE / "results/phase51_control_four_route_audit.json"
REVISION = "5f51b1d432a61d8be01eac0e29445881d80395e2"
SOURCE_BLOBS = {
    "README.md": "6c972fed3287c2bdcc9d91ea1b66e2c670bfe049",
    "Cargo.toml": "2ee3e766fc0e5c3698d520b84a688d57049bd35b",
    ".gitmodules": "bfdc394c156ac11772fab164c7eb66713f9322af",
    "rust-toolchain.toml": "ced24011c45027a4fb378f8e789a694c4df694b6",
    "template.toml": "407c705d15284a0442b5b630dca64bbdb3484f9b",
    "benchmarks-profile.toml": "787e629e49c4bf840ab4791c1634e6c7f5aee12c",
}


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def version_tuple(text: str) -> tuple[int, ...]:
    values = tuple(int(value) for value in re.findall(r"\d+", text)[:3])
    return values + (0,) * (3 - len(values))


def compatible(requirement: str, version: str) -> bool:
    wanted = version_tuple(requirement)
    actual = version_tuple(version)
    if wanted[0] > 0:
        return actual[0] == wanted[0] and actual >= wanted
    return actual[:2] == wanted[:2] and actual >= wanted


def requirement(value: object) -> str | None:
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and isinstance(value.get("version"), str):
        return value["version"]
    return None


def cached_versions(package: str, filenames: list[str]) -> list[str]:
    prefix = f"{package}-"
    return sorted(
        filename[len(prefix) : -len(".crate")]
        for filename in filenames
        if filename.startswith(prefix) and filename.endswith(".crate")
    )


def run() -> None:
    source_records = []
    for relative, expected in SOURCE_BLOBS.items():
        actual = git_blob(SOURCE / relative)
        if actual != expected:
            raise RuntimeError(
                f"ISAMORE source mismatch: {relative}: {actual} != {expected}"
            )
        source_records.append(
            {"path": relative, "git_blob_sha1": actual}
        )

    manifest = tomllib.loads((SOURCE / "Cargo.toml").read_text())
    cache = pathlib.Path.home() / ".cargo/registry/cache"
    filenames = [path.name for path in cache.rglob("*.crate")]
    dependency_rows = []
    for package, value in manifest["dependencies"].items():
        source_kind = (
            "path"
            if isinstance(value, dict) and "path" in value
            else "git"
            if isinstance(value, dict) and "git" in value
            else "registry"
        )
        wanted = requirement(value)
        versions = cached_versions(package, filenames)
        matches = (
            [
                version
                for version in versions
                if wanted is not None and compatible(wanted, version)
            ]
            if source_kind == "registry"
            else []
        )
        dependency_rows.append(
            {
                "package": package,
                "source_kind": source_kind,
                "requirement": wanted,
                "compatible_cached": matches,
                "locally_available": bool(matches),
            }
        )

    submodules = ["babble", "enumo", "jlm", "profiler"]
    missing_submodules = [
        name for name in submodules if not (SOURCE / name).is_dir()
    ]
    required_workspace_paths = [
        "babble", "babble/experiments", "enumo", "estimator"
    ]
    missing_workspace_paths = [
        value for value in required_workspace_paths
        if not (SOURCE / value).exists()
    ]
    toolchain = "nightly-2024-12-25-x86_64-unknown-linux-gnu"
    toolchain_present = (
        pathlib.Path.home() / ".rustup/toolchains" / toolchain
    ).is_dir()
    clang = shutil.which("clang-18") or shutil.which("clang")
    jlm_opt = shutil.which("jlm-opt")
    registry_available = sum(
        row["locally_available"]
        for row in dependency_rows
        if row["source_kind"] == "registry"
    )
    registry_total = sum(
        row["source_kind"] == "registry" for row in dependency_rows
    )
    route_executable = (
        len(missing_submodules) == 0
        and len(missing_workspace_paths) == 0
        and toolchain_present
        and clang is not None
        and jlm_opt is not None
        and registry_available == registry_total
    )
    payload = {
        "version": "FOUNDRY_CONTROL_FOUR_ROUTE_AUDIT_V1",
        "status": (
            "CONTROL_FOUR_ROUTE_EXECUTABLE"
            if route_executable
            else "CONTROL_FOUR_ROUTE_SELECTED_NOT_EXECUTABLE"
        ),
        "source_records": source_records,
        "source_records_exact": True,
        "route": {
            "system": "ISAMORE",
            "repository": "pku-liang/ISAMORE",
            "revision": REVISION,
            "independent_top_level_implementation": True,
            "reuses_babble_and_enumo_as_subsystems": True,
            "distinct_published_workload": (
                "RVSDG domain programs plus profile data for reusable custom "
                "instruction discovery and hardware-aware selection"
            ),
            "selection_reason": (
                "ISAMORE is the only remaining pinned public implementation "
                "in the intake. EggMind has no located public repository."
            ),
        },
        "closure": {
            "cargo_lock_published_at_revision": False,
            "manifest_dependencies": len(dependency_rows),
            "registry_dependencies": registry_total,
            "registry_dependencies_locally_available": registry_available,
            "dependency_records": dependency_rows,
            "required_submodules": submodules,
            "missing_submodules": missing_submodules,
            "required_workspace_paths": required_workspace_paths,
            "missing_workspace_paths": missing_workspace_paths,
            "required_rust_toolchain": "nightly-2024-12-25",
            "required_rust_toolchain_present": toolchain_present,
            "clang_18_or_newer_present": clang is not None,
            "jlm_opt_present": jlm_opt is not None,
            "published_template_present": True,
            "published_benchmark_profile_config_present": True,
            "published_template_inputs_present": (
                (SOURCE / "tests/liquid-tests/rvsdgfiles/vector_ll").exists()
                and (
                    SOURCE
                    / "tests/liquid-tests/merged-profiled-minor-cache/"
                    "vector.profiled.csv"
                ).exists()
            ),
        },
        "control_executed": False,
        "conformance_executed": False,
        "controls_reproduced": 3,
        "controls_required": 4,
        "route_executable": route_executable,
        "claim_boundary": (
            "This freezes a fourth-control acquisition route, not a control "
            "result. Six exact top-level records establish the intended "
            "revision and workload shape, but the source tree, submodule "
            "commits, published inputs, pinned nightly toolchain, and JLM/LLVM "
            "compiler path must be recovered before conformance can execute."
        ),
        "next_action": (
            "recover the exact recursive ISAMORE revision including submodule "
            "commit identities and published vector workload; then audit a "
            "reduced core only if it preserves RII anti-unification and "
            "hardware-aware selection rather than merely rerunning Babble"
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE51_CONTROL_FOUR_ROUTE"
        f" status={payload['status']}"
        f" exact_records={len(source_records)}"
        f" registry_deps={registry_available}/{registry_total}"
        f" missing_submodules={len(missing_submodules)}"
        " selected=ISAMORE executed=false"
    )


if __name__ == "__main__":
    run()
