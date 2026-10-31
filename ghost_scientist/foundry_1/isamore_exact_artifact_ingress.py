#!/usr/bin/env python3
"""Fail-closed, checksum-authenticated Cargo archive ingress for ISAMORE."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import tarfile
import tempfile
import tomllib
from dataclasses import dataclass


HERE = pathlib.Path(__file__).resolve().parent
DEFAULT_LOCK = HERE / "external_controls/isamore/source/Cargo.lock"
DEFAULT_INBOX = HERE / "external_controls/isamore/artifact_inbox"
DEFAULT_STAGE = HERE / "external_controls/isamore/vendor"


class IngressReject(ValueError):
    """Artifact or batch did not satisfy the frozen ingress contract."""


@dataclass(frozen=True)
class Identity:
    name: str
    version: str
    checksum: str

    @property
    def stem(self) -> str:
        return f"{self.name}-{self.version}"

    @property
    def filename(self) -> str:
        return f"{self.stem}.crate"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def locked_identities(lock_path: pathlib.Path) -> dict[str, Identity]:
    rows: dict[str, Identity] = {}
    for package in tomllib.loads(lock_path.read_text())["package"]:
        checksum = package.get("checksum")
        source = package.get("source", "")
        if not checksum or not source.startswith("registry+"):
            continue
        identity = Identity(
            name=package["name"],
            version=package["version"],
            checksum=checksum,
        )
        if identity.filename in rows:
            raise IngressReject(f"ambiguous lock identity: {identity.filename}")
        rows[identity.filename] = identity
    return rows


def _safe_member_name(raw: str, prefix: str) -> pathlib.PurePosixPath:
    path = pathlib.PurePosixPath(raw)
    if (
        not raw
        or path.is_absolute()
        or ".." in path.parts
        or path.parts[0] != prefix
    ):
        raise IngressReject(f"unsafe or wrong-root archive member: {raw!r}")
    return path


def validate_archive(
    archive: pathlib.Path,
    identity: Identity,
    *,
    enforce_checksum: bool = True,
) -> list[tarfile.TarInfo]:
    if archive.name != identity.filename:
        raise IngressReject(f"filename is not locked identity: {archive.name}")
    if enforce_checksum and sha256(archive) != identity.checksum:
        raise IngressReject(f"registry checksum mismatch: {archive.name}")
    try:
        with tarfile.open(archive, mode="r:gz") as bundle:
            members = bundle.getmembers()
    except (tarfile.TarError, OSError) as exc:
        raise IngressReject(f"malformed crate archive: {archive.name}") from exc
    seen: set[str] = set()
    manifest = f"{identity.stem}/Cargo.toml"
    for member in members:
        _safe_member_name(member.name, identity.stem)
        if member.name in seen:
            raise IngressReject(f"duplicate archive member: {member.name}")
        seen.add(member.name)
        if not (member.isfile() or member.isdir()):
            raise IngressReject(
                f"unsupported archive member type: {member.name}"
            )
    if manifest not in seen:
        raise IngressReject(f"required manifest absent: {manifest}")
    return members


def inspect_batch(
    inbox: pathlib.Path,
    lock_path: pathlib.Path = DEFAULT_LOCK,
) -> tuple[list[tuple[pathlib.Path, Identity]], list[str]]:
    identities = locked_identities(lock_path)
    accepted: list[tuple[pathlib.Path, Identity]] = []
    rejected: list[str] = []
    if not inbox.exists():
        return accepted, rejected
    for path in sorted(inbox.iterdir()):
        if not path.is_file():
            rejected.append(f"{path.name}: non-file inbox entry")
            continue
        identity = identities.get(path.name)
        if identity is None:
            rejected.append(f"{path.name}: unknown locked artifact")
            continue
        try:
            validate_archive(path, identity)
        except IngressReject as exc:
            rejected.append(f"{path.name}: {exc}")
        else:
            accepted.append((path, identity))
    return accepted, rejected


def _extract_one(
    archive: pathlib.Path, identity: Identity, scratch: pathlib.Path
) -> pathlib.Path:
    validate_archive(archive, identity)
    with tarfile.open(archive, mode="r:gz") as bundle:
        for member in bundle.getmembers():
            relative = _safe_member_name(member.name, identity.stem)
            target = scratch.joinpath(*relative.parts)
            if member.isdir():
                target.mkdir(parents=True, exist_ok=True)
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            source = bundle.extractfile(member)
            if source is None:
                raise IngressReject(f"unreadable member: {member.name}")
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            os.chmod(target, member.mode & 0o777)
    return scratch / identity.stem


def stage_batch(
    accepted: list[tuple[pathlib.Path, Identity]],
    destination: pathlib.Path,
) -> list[pathlib.Path]:
    if not accepted:
        return []
    duplicate_stems = [
        stem
        for stem in {identity.stem for _, identity in accepted}
        if sum(identity.stem == stem for _, identity in accepted) != 1
    ]
    if duplicate_stems:
        raise IngressReject(f"duplicate batch identities: {duplicate_stems}")
    conflicts = [
        identity.stem
        for _, identity in accepted
        if (destination / identity.stem).exists()
    ]
    if conflicts:
        raise IngressReject(f"destinations already exist: {conflicts}")
    destination.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(
        prefix=".foundry-isamore-ingress-", dir=destination
    ) as raw:
        scratch = pathlib.Path(raw)
        staged = [
            _extract_one(archive, identity, scratch)
            for archive, identity in accepted
        ]
        published: list[pathlib.Path] = []
        try:
            for path in staged:
                target = destination / path.name
                path.rename(target)
                published.append(target)
        except BaseException:
            for path in reversed(published):
                path.rename(scratch / path.name)
            raise
    return published


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock", type=pathlib.Path, default=DEFAULT_LOCK)
    parser.add_argument("--inbox", type=pathlib.Path, default=DEFAULT_INBOX)
    parser.add_argument("--stage-root", type=pathlib.Path, default=DEFAULT_STAGE)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    accepted, rejected = inspect_batch(args.inbox, args.lock)
    staged: list[pathlib.Path] = []
    if args.apply:
        if rejected:
            raise IngressReject(
                "atomic batch rejected: " + "; ".join(rejected)
            )
        staged = stage_batch(accepted, args.stage_root)
    report = {
        "version": "FOUNDRY_ISAMORE_EXACT_ARTIFACT_INGRESS_REPORT_V1",
        "lock": str(args.lock),
        "inbox": str(args.inbox),
        "accepted": [
            {
                "filename": path.name,
                "name": identity.name,
                "version": identity.version,
                "sha256": sha256(path),
            }
            for path, identity in accepted
        ],
        "rejected": rejected,
        "apply": args.apply,
        "staged": [str(path) for path in staged],
    }
    print(json.dumps(report, sort_keys=True, separators=(",", ":")))


if __name__ == "__main__":
    main()
