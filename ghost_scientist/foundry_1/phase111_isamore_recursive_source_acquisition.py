#!/usr/bin/env python3
"""Authenticate the recovered ISAMORE source and published workload."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
RESULT = HERE / "results/phase111_isamore_recursive_source_acquisition.json"
REVISION = "5f51b1d432a61d8be01eac0e29445881d80395e2"
LOCK_PARENT = "f6c5f10d72c2efaddae21ab71ac60d14cd30037b"

SUBMODULES = {
    "babble": "e69fb77d602870641e26d6b2a6a9bea25f8f788b",
    "enumo": "c409f80ddef33e4fc8a31c1c1e3cbe01a0f836a0",
    "jlm": "a555fff0333a8d5277e4d581e44b42952a1d3bac",
    "profiler": "c42df4499dad22a55ef9e8fa2c5e9e40ecd013a1",
}

# Connector-authenticated Git blob identities. This is a deliberately bounded
# executable-source intake, not a claim that every file in all four recursive
# repositories has been mirrored.
EXPECTED_BLOBS = {
    "Cargo.toml": "2ee3e766fc0e5c3698d520b84a688d57049bd35b",
    "Cargo.lock": "34e7c3e90052aa4f1059f24346ace7ffdd5af631",
    "src/lib.rs": "25016eafa9fe0889d050c8f989ac42afd0e88543",
    "src/main.rs": "6e42b84792b0ba270c8bf819af402208ff00685a",
    "src/runner.rs": "c0e00094c7c7f90b55b2806d7418d5d871c0fefa",
    "src/egg_lang.rs": "ec62c3efc44c0cd0af1d7804233b466051a3c7ca",
    "src/experiment.rs": "55dfc99f571d2c6b9ff454aa259c84eb466b1349",
    "babble/Cargo.toml": "cf98c7fff509bd6ca78bfab70fe39048323651ed",
    "babble/src/lib.rs": "1ac076fe34541da2c570625468eb63cc1760ce31",
    "babble/src/learn.rs": "68e52208dbf7fa266b80e3c1718a8c15a89b17dd",
    "babble/src/runner.rs": "7f5f4e206b5917eb6aedaca590e12d4228bfee9d",
    "babble/src/extract/beam_pareto.rs": (
        "6678fb8828ffe475585ed87c0218f64038ff75fe"
    ),
    "enumo/Cargo.toml": "9cc52c9a5222203004b0ca55627bd95088a801af",
    "enumo/src/lib.rs": "2038ffd5f144272ee17287908b763937f6f11d78",
    "enumo/src/enumo/ruleset.rs": (
        "b4c257f03905848a277ed48db87f27509cdaa006"
    ),
    "enumo/src/enumo/workload.rs": (
        "9d8de814aaf0c55ce39b4343f3648a23993555d0"
    ),
    "egg/Cargo.toml": "b56dc602ea0f00a985e3f464ffe1f9bfdc14e7e1",
    "egg/src/lib.rs": "3eeb9d8f1bd80ff29c18c8624b10d65d1b16f76b",
    "egg/src/egraph.rs": "335fab407f470151a82505eeb184ed0d8e0d4838",
    "egg/src/lp_extract.rs": "94c5b8b478527e632a98f2a4745e310a3e36eaa9",
    "estimator/Cargo.toml": "19a3dbe14baa27490b8830a20227019d52a77963",
    "estimator/src/lib.rs": "5cf0c46b2691ce0f73d19a5196d8f16fcb15b74c",
    "estimator/src/area_estimator.rs": (
        "e7c0f1f748b7e49e76f45f7b72d317621cbfeb6c"
    ),
    "estimator/src/delay_estimator.rs": (
        "d83e5390602f12b35c19f15591e871ba0ae31597"
    ),
    "estimator/models/area_asap7.bin": (
        "b95a81267d3f4f0ffda38ebe5a62fd4b04a4d02e"
    ),
    "estimator/models/delay_asap7.bin": (
        "6641858f0f415255de3ee0d2c55a182a2adcfc23"
    ),
    "tests/cdios/benchmarks-profile-minor-cache.toml": (
        "14078dd589674761e1a25dc44bea1339d9a957da"
    ),
    "tests/cdios/profiled-minor-cache/point-product.profile.csv": (
        "5f726b757e71fb7d6fa94b21b9570526df87bc31"
    ),
    "tests/cdios/profiled-minor-cache/point-product.rvsdg": (
        "310135c5f38b2ddae0b8077eb0b6c505f23b35a2"
    ),
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def git_blob(path: pathlib.Path) -> str:
    raw = path.read_bytes()
    return hashlib.sha1(f"blob {len(raw)}\0".encode() + raw).hexdigest()


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_count(relative: str) -> int:
    return sum(
        path.is_file()
        for path in (SOURCE / relative).rglob("*")
        if "target" not in path.parts
    )


def main() -> None:
    records = []
    for relative, expected in EXPECTED_BLOBS.items():
        path = SOURCE / relative
        if not path.is_file():
            raise RuntimeError(f"missing acquired ISAMORE record: {relative}")
        actual = git_blob(path)
        if actual != expected:
            raise RuntimeError(
                f"ISAMORE acquired blob mismatch: {relative}: "
                f"{actual} != {expected}"
            )
        records.append(
            {
                "path": relative,
                "git_blob_sha1": actual,
                "sha256": sha256(path),
                "bytes": path.stat().st_size,
            }
        )

    gitmodules = (SOURCE / ".gitmodules").read_text()
    for name in SUBMODULES:
        if f'[submodule "{name}"]' not in gitmodules:
            raise RuntimeError(f"missing ISAMORE submodule declaration: {name}")

    point_profile = (
        SOURCE
        / "tests/cdios/profiled-minor-cache/point-product.profile.csv"
    )
    point_rvsdg = (
        SOURCE / "tests/cdios/profiled-minor-cache/point-product.rvsdg"
    )
    profile_rows = [
        row for row in point_profile.read_text().splitlines() if row.strip()
    ]
    if len(profile_rows) < 2 or point_rvsdg.stat().st_size < 1000:
        raise RuntimeError("published point-product workload is incomplete")

    payload = {
        "version": "FOUNDRY_ISAMORE_RECURSIVE_SOURCE_ACQUISITION_V2",
        "status": "ISAMORE_SOURCE_ACQUISITION_COMPONENT_PASS",
        "repository": "pku-liang/ISAMORE",
        "revision": REVISION,
        "submodule_gitlinks": SUBMODULES,
        "recursive_submodule_identities_observed": True,
        "source_records": records,
        "source_records_exact": True,
        "source_record_count": len(records),
        "materialized_file_counts": {
            "isamore_top_level_src": source_count("src"),
            "babble_bounded_build_surface": source_count("babble"),
            "enumo_bounded_build_surface": source_count("enumo"),
            "egg_bounded_build_surface": source_count("egg"),
            "estimator_bounded_build_surface": source_count("estimator"),
        },
        "historical_lock_recovery": {
            "present_at_parent": True,
            "parent_revision": LOCK_PARENT,
            "removed_by_selected_revision": True,
            "git_blob_sha1": EXPECTED_BLOBS["Cargo.lock"],
            "egg_revision": "a3346860f4722974cb1147e640d4ce5473ef1b53",
            "classification": "AUTHENTICATED_PARENT_BUILD_CLOSURE",
        },
        "published_workload": {
            "family": "CDIOS_POINT_PRODUCT_MINOR_CACHE",
            "profile_path": str(point_profile.relative_to(SOURCE)),
            "rvsdg_path": str(point_rvsdg.relative_to(SOURCE)),
            "profile_nonempty_rows": len(profile_rows),
            "rvsdg_bytes": point_rvsdg.stat().st_size,
            "present": True,
        },
        "build_support": {
            "local_egg_patch_config_present": (
                SOURCE / ".cargo/config.toml"
            ).is_file(),
            "estimator_binary_models_byte_exact": True,
            "estimator_models_regenerated_from_published_textproto": True,
        },
        "control_executed": False,
        "conformance_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The prior source-unavailable finding is retired: the exact "
            "top-level runtime source, all four gitlink identities, an "
            "authenticated pre-removal lockfile, exact estimator models, and "
            "one published RVSDG/profile pair are now local. This is source "
            "acquisition, not an ISAMORE result or fourth-control conformance."
        ),
        "next_action": (
            "execute an offline locked build-closure audit; only pre-freeze "
            "and run ISAMORE conformance if the unmodified defining "
            "anti-unification, SMT validation, LP extraction, and hardware "
            "cost path can all compile and execute"
        ),
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE111_ISAMORE_SOURCE_ACQUISITION"
        f" status={payload['status']}"
        f" exact_records={len(records)}"
        " gitlinks=4 workload=PASS controls=3/4 P1=false"
    )


if __name__ == "__main__":
    main()
