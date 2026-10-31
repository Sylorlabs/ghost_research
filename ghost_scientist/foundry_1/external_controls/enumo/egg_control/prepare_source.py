#!/usr/bin/env python3
"""Stage the exact Egg 0.9.5 core with auditable build-only adaptations."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


CONTROL = Path(__file__).resolve().parent
SOURCE = CONTROL.parent / "egg_0_9"
GENERATED = CONTROL / "generated"
FILES = (
    "src/lib.rs",
    "src/macros.rs",
    "src/dot.rs",
    "src/eclass.rs",
    "src/egraph.rs",
    "src/explain.rs",
    "src/extract.rs",
    "src/language.rs",
    "src/machine.rs",
    "src/multipattern.rs",
    "src/pattern.rs",
    "src/rewrite.rs",
    "src/run.rs",
    "src/subst.rs",
    "src/unionfind.rs",
    "src/util.rs",
)

PATCHES = {
    "lib.rs": (
        (
            b"#![doc = \"## Simple Example\\n```\"]\n"
            b"#![doc = include_str!(\"../tests/simple.rs\")]\n"
            b"#![doc = \"\\n```\"]\n\n",
            b"",
            "exclude generated-location-only documentation include",
        ),
        (
            b"#[doc(hidden)]\npub mod test;\n\npub mod tutorials;\n\n",
            b"",
            "exclude non-algorithm test and tutorial modules",
        ),
        (
            b"\n#[cfg(test)]\nfn init_logger() {\n"
            b"    let _ = env_logger::builder().is_test(true).try_init();\n}\n",
            b"\n",
            "exclude test-only logger initialization",
        ),
    ),
    "util.rs": (
        (
            b"    set: hashbrown::HashSet<T>,\n",
            b"    set: hashbrown::HashSet<T, BuildHasher>,\n",
            "use Egg's declared FxBuildHasher without Hashbrown default feature",
        ),
        (
            b"            set: hashbrown::HashSet::default(),\n",
            b"            set: hashbrown::HashSet::with_hasher(Default::default()),\n",
            "construct the explicitly typed Egg FxHash set",
        ),
    ),
}


def main() -> None:
    if GENERATED.exists():
        shutil.rmtree(GENERATED)
    GENERATED.mkdir()
    copied = {}
    for relative in FILES:
        data = (SOURCE / relative).read_bytes()
        destination = GENERATED / Path(relative).relative_to("src")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        copied[relative] = hashlib.sha256(data).hexdigest()

    applied = []
    for relative, changes in PATCHES.items():
        destination = GENERATED / relative
        data = destination.read_bytes()
        for before, after, reason in changes:
            if data.count(before) != 1:
                raise SystemExit(
                    f"Egg compatibility-patch precondition failed: "
                    f"{relative}: {reason}"
                )
            before_sha = hashlib.sha256(data).hexdigest()
            data = data.replace(before, after, 1)
            applied.append(
                {
                    "file": relative,
                    "before_sha256": before_sha,
                    "after_sha256": hashlib.sha256(data).hexdigest(),
                    "reason": reason,
                }
            )
        destination.write_bytes(data)

    manifest = {
        "release": "v0.9.5",
        "copied_byte_exact": copied,
        "generated_compatibility_patches": applied,
        "excluded_from_build": ["test.rs", "tutorials", "lp_extract"],
    }
    (GENERATED / "source_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "EGG_0_9_SOURCE_STAGE_PASS"
        f" release=v0.9.5 exact_modules={len(copied)}/16"
        f" build_edits={len(applied)}"
    )


if __name__ == "__main__":
    main()
