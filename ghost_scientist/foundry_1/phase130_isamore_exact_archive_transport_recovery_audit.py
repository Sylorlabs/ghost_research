#!/usr/bin/env python3
"""Probe exact locked Kiddo-family archives without accepting substitutes."""

from __future__ import annotations

import hashlib
import json
import pathlib
import shutil
import subprocess
import tempfile
import tomllib


HERE = pathlib.Path(__file__).resolve().parent
LOCK = HERE / "external_controls/isamore/source/Cargo.lock"
VENDOR = HERE / "external_controls/isamore/vendor"
PRIOR = HERE / "results/phase129_isamore_native_lp_acquisition_channel_audit.json"
RESULT = HERE / "results/phase130_isamore_exact_archive_transport_recovery_audit.json"
PACKAGES = (
    ("kiddo", "5.2.4"),
    ("az", "1.3.0"),
    ("fixed", "1.30.0"),
    ("sorted-vec", "0.8.10"),
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def locked() -> dict[tuple[str, str], str]:
    payload = tomllib.loads(LOCK.read_text())
    rows = {
        (row["name"], row["version"]): row["checksum"]
        for row in payload["package"]
        if (row["name"], row["version"]) in PACKAGES
    }
    if set(rows) != set(PACKAGES):
        raise RuntimeError("locked Kiddo-family identities changed")
    return rows


def local_exact_archives(expected: dict[tuple[str, str], str]) -> list[dict]:
    roots = (
        pathlib.Path.home() / ".cargo/registry/cache",
        pathlib.Path("/root/.cargo/registry/cache"),
        VENDOR / "archives",
    )
    rows = []
    for package, version in PACKAGES:
        filename = f"{package}-{version}.crate"
        for root in roots:
            try:
                available = root.exists()
            except PermissionError:
                available = False
            if not available:
                continue
            try:
                matches = list(root.rglob(filename))
            except PermissionError:
                matches = []
            for path in matches:
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                if digest == expected[(package, version)]:
                    rows.append(
                        {
                            "package": package,
                            "version": version,
                            "path": str(path),
                            "sha256": digest,
                        }
                    )
    return sorted(rows, key=lambda row: (row["package"], row["path"]))


def download_probe(expected: dict[tuple[str, str], str]) -> list[dict]:
    curl = shutil.which("curl")
    if curl is None:
        raise RuntimeError("curl unavailable")
    rows = []
    with tempfile.TemporaryDirectory(prefix="foundry-kiddo-archive-") as tmp:
        root = pathlib.Path(tmp)
        for package, version in PACKAGES:
            url = (
                f"https://static.crates.io/crates/{package}/"
                f"{package}-{version}.crate"
            )
            target = root / f"{package}-{version}.crate"
            completed = subprocess.run(
                [
                    curl,
                    "--fail",
                    "--silent",
                    "--show-error",
                    "--location",
                    "--connect-timeout",
                    "5",
                    "--max-time",
                    "15",
                    "--output",
                    str(target),
                    url,
                ],
                text=True,
                capture_output=True,
                timeout=20,
                check=False,
            )
            digest = (
                hashlib.sha256(target.read_bytes()).hexdigest()
                if target.is_file()
                else None
            )
            rows.append(
                {
                    "package": package,
                    "version": version,
                    "url": url,
                    "returncode": completed.returncode,
                    "stdout": completed.stdout,
                    "stderr": completed.stderr,
                    "bytes": target.stat().st_size if target.is_file() else 0,
                    "sha256": digest,
                    "lock_checksum_match": digest
                    == expected[(package, version)],
                }
            )
    return rows


def create() -> dict:
    prior = json.loads(PRIOR.read_text())
    if not (
        prior["status"]
        == "ISAMORE_NATIVE_LP_CHANNELS_IDENTIFIED_TRANSPORT_UNAVAILABLE"
        and prior["next_build_stop"]["package"] == "kiddo"
        and prior["control_executed"] is False
    ):
        raise RuntimeError("prior ISAMORE boundary changed")
    expected = locked()
    local = local_exact_archives(expected)
    probes = download_probe(expected)
    acquired = [
        row for row in probes if row["lock_checksum_match"]
    ]
    if local or acquired:
        raise RuntimeError(
            "exact archive became available; stage and compile it in a new phase"
        )
    return {
        "version": "FOUNDRY_ISAMORE_EXACT_ARCHIVE_TRANSPORT_RECOVERY_AUDIT_V1",
        "status": "ISAMORE_EXACT_ARCHIVE_TRANSPORT_STILL_UNAVAILABLE",
        "locked_packages": [
            {
                "package": package,
                "version": version,
                "registry_sha256": expected[(package, version)],
            }
            for package, version in PACKAGES
        ],
        "local_exact_archives": local,
        "download_probes": probes,
        "checks": {
            "all_four_locked_identities_authenticated": True,
            "local_exact_archives_present": False,
            "downloaded_exact_archives": 0,
            "substitute_source_accepted": False,
            "kiddo_root_source_acquired": False,
            "isamore_algorithm_compilation_reached": False,
            "isamore_algorithm_execution_reached": False,
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
            "The exact immutable archive URLs were probed under bounded "
            "timeouts and no checksum-matching bytes were acquired. The "
            "official Git commit with the dependency change still declares "
            "Kiddo 5.2.1 and is not relabeled as the published 5.2.4 crate."
        ),
        "next_action": (
            "continue a non-network prerequisite: formally close the proposed "
            "A1 opaque-reference fallback before investing in an invalid adapter"
        ),
    }


def verify(payload: dict) -> None:
    if not (
        payload["status"]
        == "ISAMORE_EXACT_ARCHIVE_TRANSPORT_STILL_UNAVAILABLE"
        and len(payload["locked_packages"]) == 4
        and payload["local_exact_archives"] == []
        and len(payload["download_probes"]) == 4
        and all(
            row["lock_checksum_match"] is False
            for row in payload["download_probes"]
        )
        and payload["checks"]["downloaded_exact_archives"] == 0
        and payload["checks"]["substitute_source_accepted"] is False
        and payload["next_build_stop"]["package"] == "kiddo"
        and payload["control_executed"] is False
        and payload["validation_v6_accessed"] is False
    ):
        raise RuntimeError("exact-archive transport boundary changed")


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
        "FOUNDRY_PHASE130_ISAMORE_EXACT_ARCHIVE_TRANSPORT"
        " status=STILL_UNAVAILABLE exact=0/4 substitute=false"
        " stop=kiddo compiled=false executed=false"
        f" evidence={mode}"
    )


if __name__ == "__main__":
    main()
