#!/usr/bin/env python3
"""Compare legitimate upstream acquisition routes for the second control."""

from __future__ import annotations

import hashlib
import json
import pathlib
import re
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
BABBLE = HERE / "external_controls/babble/source"
ISAMORE = HERE / "external_controls/isamore/source"
RESULT = HERE / "results/phase40_control_two_route_audit.json"

FILE_BLOBS = {
    "babble/README.md": "db20073af0eb007403a66640d29545a704135937",
    "babble/Cargo.toml": "30b4a4b11b98108d93872cc2cf2d23fbe1bfc55f",
    "babble/Cargo.lock": "1987ec660c8d8c1e00a5c9833df3166d9ced4e42",
    "isamore/README.md": "6c972fed3287c2bdcc9d91ea1b66e2c670bfe049",
    "isamore/Cargo.toml": "2ee3e766fc0e5c3698d520b84a688d57049bd35b",
}


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def version_tuple(text: str) -> tuple[int, ...]:
    return tuple(int(value) for value in re.findall(r"\d+", text)[:3])


def cargo_compatible(requirement: str, version: str) -> bool:
    wanted = version_tuple(requirement)
    actual = version_tuple(version)
    if not wanted or not actual:
        return False
    wanted = wanted + (0,) * (3 - len(wanted))
    actual = actual + (0,) * (3 - len(actual))
    if wanted[0] > 0:
        return actual[0] == wanted[0] and actual >= wanted
    return actual[:2] == wanted[:2] and actual >= wanted


def crate_versions(package: str, filenames: list[str]) -> list[str]:
    prefix = f"{package}-"
    return sorted(
        filename[len(prefix) : -len(".crate")]
        for filename in filenames
        if filename.startswith(prefix) and filename.endswith(".crate")
    )


def dependency_version(value: object) -> str | None:
    if isinstance(value, str):
        return value
    if isinstance(value, dict) and isinstance(value.get("version"), str):
        return value["version"]
    return None


def run() -> None:
    roots = {"babble": BABBLE, "isamore": ISAMORE}
    source_records = []
    for key, expected in FILE_BLOBS.items():
        project, relative = key.split("/", 1)
        actual = git_blob(roots[project] / relative)
        if actual != expected:
            raise RuntimeError(
                f"control route source mismatch: {key}: {actual} != {expected}"
            )
        source_records.append({"path": key, "git_blob_sha1": actual})

    cache = pathlib.Path.home() / ".cargo/registry/cache"
    filenames = [path.name for path in cache.rglob("*.crate")]
    babble_manifest = tomllib.loads(
        (BABBLE / "Cargo.toml").read_text(encoding="utf-8")
    )
    babble_rows = []
    for package, value in babble_manifest["dependencies"].items():
        if isinstance(value, dict) and value.get("optional") is True:
            continue
        source_kind = (
            "path"
            if isinstance(value, dict) and "path" in value
            else "git"
            if isinstance(value, dict) and "git" in value
            else "registry"
        )
        requirement = dependency_version(value)
        versions = crate_versions(package, filenames)
        matching = (
            [
                version
                for version in versions
                if requirement is not None
                and cargo_compatible(requirement, version)
            ]
            if source_kind == "registry"
            else []
        )
        babble_rows.append(
            {
                "package": package,
                "source_kind": source_kind,
                "requirement": requirement,
                "compatible_cached": matching,
                "locally_available": bool(matching),
            }
        )
    babble_available = sum(row["locally_available"] for row in babble_rows)
    babble_missing = [
        row["package"] for row in babble_rows if not row["locally_available"]
    ]

    isamore_manifest = tomllib.loads(
        (ISAMORE / "Cargo.toml").read_text(encoding="utf-8")
    )
    isamore_dependencies = isamore_manifest["dependencies"]
    isamore_path = [
        package
        for package, value in isamore_dependencies.items()
        if isinstance(value, dict) and "path" in value
    ]
    isamore_git = [
        package
        for package, value in isamore_dependencies.items()
        if isinstance(value, dict) and "git" in value
    ]

    payload = {
        "version": "FOUNDRY_CONTROL_TWO_ROUTE_AUDIT_V1",
        "status": "CONTROL_TWO_ROUTE_SELECTED_NOT_EXECUTABLE",
        "source_records": source_records,
        "enumo": {
            "revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
            "source_checkout_complete": True,
            "required_direct_dependencies": 21,
            "locally_available": 10,
            "missing": 11,
            "control_executed": False,
        },
        "babble": {
            "repository": "dcao/babble",
            "branch": "popl23",
            "resolved_commit": "09ff03fd485a3e24178c1d706a5944a230123ba1",
            "egg_fork_commit_from_lock": "caf623cad25cacba83193464dcf0d3dd4161ba7a",
            "manifest_dependencies": 22,
            "optional_dependencies_excluded": ["grb"],
            "required_direct_dependencies": len(babble_rows),
            "locally_available": babble_available,
            "missing": len(babble_missing),
            "missing_packages": babble_missing,
            "dependency_records": babble_rows,
            "source_checkout_complete": False,
            "control_executed": False,
        },
        "isamore": {
            "repository": "pku-liang/ISAMORE",
            "revision": "5f51b1d432a61d8be01eac0e29445881d80395e2",
            "manifest_dependencies": len(isamore_dependencies),
            "required_path_workspaces": isamore_path,
            "required_git_dependencies": isamore_git,
            "nightly_toolchain": "nightly-2024-12-25",
            "external_compiler_stack": "JLM with LLVM/Clang 18+",
            "source_checkout_complete": False,
            "control_executed": False,
        },
        "selection": {
            "route": "babble_popl23",
            "reason": (
                "Babble has 13/21 required direct dependencies locally "
                "available versus Enumo's 10/21, while ISAMORE additionally "
                "requires four path workspaces, a Git Egg fork, a pinned "
                "nightly toolchain, and the JLM compiler stack."
            ),
            "selection_is_execution": False,
            "controls_reproduced": 1,
            "controls_required": 4,
        },
        "claim_boundary": (
            "This is an acquisition-cost audit, not a control result. Babble "
            "is selected only as the smallest currently observed legitimate "
            "upstream closure. Its full source, local macro crate, and pinned "
            "Egg fork must be recovered and conformance-tested before the "
            "control count can change."
        ),
        "next_action": (
            "recover byte-exact Babble popl23 source at resolved commit "
            "09ff03fd485a3e24178c1d706a5944a230123ba1, its babble-macros "
            "workspace, and Egg fork commit caf623cad25cacba83193464dcf0d3dd4161ba7a"
        ),
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE40_CONTROL_TWO_ROUTE"
        f" status={payload['status']}"
        f" babble_deps={babble_available}/{len(babble_rows)}"
        " enumo_deps=10/21 selected=babble_popl23 executed=false"
    )


if __name__ == "__main__":
    run()
