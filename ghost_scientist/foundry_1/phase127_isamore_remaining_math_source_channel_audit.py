#!/usr/bin/env python3
"""Freeze the remaining Kiddo math-source boundary without substituting mirrors."""

from __future__ import annotations

import json
import pathlib
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
SOURCE = HERE / "external_controls/isamore/source"
VENDOR = HERE / "external_controls/isamore/vendor"
PRIOR = HERE / "results/phase126_isamore_divrem_family_bridge_audit.json"
ROOT_PRIOR = (
    HERE / "results/phase125_isamore_kiddo_root_acquisition_channel_audit.json"
)
RESULT = HERE / "results/phase127_isamore_remaining_math_source_channel_audit.json"

LOCKED = {
    "az": {
        "version": "1.3.0",
        "sha256": "be5eb007b7cacc6c660343e96f650fedf4b5a77512399eb952ca6642cf8d13f7",
        "repository": "https://gitlab.com/tspiteri/az",
        "official_revision": "v1.3.0",
        "observed_short_commit": "22c97852",
        "docs_rs_source": "https://docs.rs/crate/az/1.3.0/source/",
    },
    "fixed": {
        "version": "1.30.0",
        "sha256": "c566da967934c6c7ee0458a9773de9b2a685bd2ce26a3b28ddfc740e640182f5",
        "repository": "https://gitlab.com/tspiteri/fixed",
        "official_revision": "v1.30.0",
        "observed_short_commit": "f176e0cd",
        "docs_rs_source": "https://docs.rs/crate/fixed/1.30.0/source/",
    },
    "sorted-vec": {
        "version": "0.8.10",
        "sha256": "19f58d7b0190c7f12df7e8be6b79767a0836059159811b869d5ab55721fe14d0",
        "repository": "https://gitlab.com/spearman/sorted-vec",
        "official_revision": "66950c05ff8061b7a8e0f1810a117c508e21ecb6",
        "observed_short_commit": "66950c05",
        "docs_rs_source": "https://docs.rs/crate/sorted-vec/0.8.10/source/",
    },
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def locked_rows() -> dict[str, dict]:
    packages = tomllib.loads((SOURCE / "Cargo.lock").read_text())["package"]
    rows = {}
    for name, expected in LOCKED.items():
        matches = [
            row
            for row in packages
            if row["name"] == name and row["version"] == expected["version"]
        ]
        if len(matches) != 1 or matches[0].get("checksum") != expected["sha256"]:
            raise RuntimeError(f"locked {name} identity changed")
        rows[name] = matches[0]
    return rows


def local_exact_sources() -> dict[str, list[str]]:
    cache = pathlib.Path.home() / ".cargo/registry/cache"
    found = {}
    for name, expected in LOCKED.items():
        version = expected["version"]
        candidates = list(cache.rglob(f"{name}-{version}.crate"))
        vendor = VENDOR / f"{name}-{version}"
        if vendor.exists():
            candidates.append(vendor)
        found[name] = sorted(str(path) for path in candidates)
    return found


def validate_current_boundary() -> None:
    locked_rows()
    found = local_exact_sources()
    if any(found.values()):
        raise RuntimeError(
            "a remaining exact math source became local; advance instead of "
            "replaying the source-channel boundary"
        )


def create() -> dict:
    prior = json.loads(PRIOR.read_text())
    root_prior = json.loads(ROOT_PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_DIVREM_EXACT_TAG_AUTHENTICATED_NO_STOP_ADVANCE"
        and prior["accumulated_kiddo_family"]["packages_bridged"] == 4
        and prior["next_build_stop"]["package"] == "kiddo"
        and root_prior["checks"]["shell_registry_transport_available"] is False
    ):
        raise RuntimeError("prior source-acquisition boundary changed")
    rows = locked_rows()
    found = local_exact_sources()
    if any(found.values()):
        raise RuntimeError("exact remaining source unexpectedly present")
    identities = []
    for name, expected in LOCKED.items():
        identities.append(
            {
                "package": name,
                "version": expected["version"],
                "registry_sha256": rows[name]["checksum"],
                "official_repository": expected["repository"],
                "official_revision": expected["official_revision"],
                "observed_short_commit": expected["observed_short_commit"],
                "docs_rs_published_source": expected["docs_rs_source"],
                "evidence_classification": (
                    "LOCK_AND_OFFICIAL_RELEASE_METADATA_NO_LOCAL_SOURCE_BYTES"
                ),
                "exact_local_archive_or_source": False,
            }
        )
    return {
        "version": "FOUNDRY_ISAMORE_REMAINING_MATH_SOURCE_CHANNEL_AUDIT_V1",
        "status": "ISAMORE_REMAINING_MATH_CHANNELS_AUDITED_NO_EXACT_SOURCE",
        "locked_identities": identities,
        "local_search": found,
        "transport": {
            "shell_registry_transport_available": False,
            "inherited_probe_version": root_prior["version"],
            "docs_rs_source_pages_observed": 3,
            "official_gitlab_repositories_observed": 3,
        },
        "rejected_substitution": {
            "repository": "JohnScience/sorted-vec2",
            "revision": "9b55aaea863312f56924fc81afd7bc6800079b62",
            "reason": (
                "the mirror declares package sorted-vec2 version 0.1.0 and "
                "its source diverges from published sorted-vec 0.8.10"
            ),
            "accepted": False,
        },
        "checks": {
            "all_locked_registry_identities_authenticated": True,
            "official_release_metadata_located": True,
            "exact_local_archives_present": False,
            "exact_local_source_bytes_present": False,
            "third_party_mirror_substituted": False,
            "kiddo_family_count_advanced": False,
            "kiddo_root_source_acquired": False,
            "isamore_algorithm_compilation_reached": False,
            "isamore_algorithm_execution_reached": False,
        },
        "accumulated_kiddo_family": {
            "packages_bridged": 4,
            "packages_required": 8,
            "source_records_authenticated": 20,
        },
        "next_build_stop": {
            "class": "MISSING_OFFLINE_REGISTRY_PACKAGE",
            "package": "kiddo",
            "version": "5.2.4",
        },
        "control_executed": False,
        "source_faithful_controls_reproduced": 3,
        "controls_required": 4,
        "P1_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
        "claim_boundary": (
            "The lock authenticates all three remaining package identities, "
            "and official release/source metadata was located. No exact "
            "archive or source bytes are local. The divergent GitHub fork is "
            "explicitly rejected, so the Kiddo family remains 4/8 and no "
            "compilation or control execution is claimed."
        ),
        "next_action": (
            "advance the independent native LP closure by authenticating the "
            "locked coin_cbc Rust bindings and auditing pinned-nightly/CBC "
            "runtime availability"
        ),
    }


def verify(payload: dict) -> None:
    validate_current_boundary()
    if not (
        payload["status"]
        == "ISAMORE_REMAINING_MATH_CHANNELS_AUDITED_NO_EXACT_SOURCE"
        and len(payload["locked_identities"]) == 3
        and all(
            row["exact_local_archive_or_source"] is False
            for row in payload["locked_identities"]
        )
        and payload["rejected_substitution"]["accepted"] is False
        and payload["checks"]["kiddo_family_count_advanced"] is False
        and payload["checks"]["isamore_algorithm_execution_reached"] is False
        and payload["accumulated_kiddo_family"]["packages_bridged"] == 4
        and payload["next_build_stop"]["package"] == "kiddo"
        and payload["control_executed"] is False
        and payload["validation_v6_accessed"] is False
    ):
        raise RuntimeError("frozen remaining-math boundary changed")


def main() -> None:
    if RESULT.exists():
        payload = json.loads(RESULT.read_text())
        verify(payload)
        mode = "VERIFY_FROZEN"
    else:
        payload = create()
        verify(payload)
        RESULT.write_text(canonical(payload) + "\n")
        mode = "CREATE"
    print(
        "FOUNDRY_PHASE127_ISAMORE_REMAINING_MATH_CHANNELS"
        " status=AUDITED_NO_EXACT_SOURCE packages=3 acquired=0"
        " mirror_substituted=false kiddo_family=4/8 stop=kiddo"
        " compiled=false executed=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
