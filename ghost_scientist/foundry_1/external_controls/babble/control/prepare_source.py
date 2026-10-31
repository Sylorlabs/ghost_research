#!/usr/bin/env python3
"""Verify and stage the byte-exact Babble core used by the Foundry control."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


CONTROL = Path(__file__).resolve().parent
BABBLE = CONTROL.parent
SOURCE = BABBLE / "source"
GENERATED = CONTROL / "generated"

EXPECTED_BLOBS = {
    "Cargo.toml": "30b4a4b11b98108d93872cc2cf2d23fbe1bfc55f",
    "Cargo.lock": "1987ec660c8d8c1e00a5c9833df3166d9ced4e42",
    "README.md": "db20073af0eb007403a66640d29545a704135937",
    "POPL23.md": "259dc5e33fb767b940a375a6f3ad0a4fa79fe9e4",
    "src/lib.rs": "0b1532de77114f035ed736e9a9b054537a283ba1",
    "src/bin/list/main.rs": "2ddbb90f6dfd99315140664f59a5f597cbb1c8f4",
    "src/ast_node.rs": "78f8a21d1f263ce6670cca0f0165c894d3702ac8",
    "src/ast_node/expr.rs": "b211a460ed7133a1dd3ff8e299d47de253ec3075",
    "src/ast_node/partial_expr.rs": "ca5eb742b42fca0f1da4c03ee620c3adec1a4978",
    "src/ast_node/pretty.rs": "a7f03b4424026671112f62efdd1ebf8faed21bdc",
    "src/co_occurrence.rs": "c23a3e96bb036e9137b7839957fa7c7c48370ff5",
    "src/dfta.rs": "6d0ee9f71e8454eed429dec3faa7979704169da2",
    "src/extract/mod.rs": "b69d523b20fe2211c236e999a960dfa792b43f74",
    "src/extract/beam.rs": "ef6e67bc77539fce1d3a28aceb505f2b76c2273e",
    "src/learn.rs": "1a8e2cc7bea153184108655a7431398aa6018375",
    "src/rewrites.rs": "58f82e4d846f8e48b4f780444fd2224baa059abd",
    "src/sexp.rs": "c7590201331ec2b5a1eeb07006bd53c8a6dd18a6",
    "src/simple_lang.rs": "2034c7099ad99c45c46e609c273728bc16a17a03",
    "src/teachable.rs": "04804556b1407638164bed06110f54d709776967",
    "src/bin/list/lang.rs": "9fc38b4ae2edd3725bba4caa304994355dc61299",
    "babble-macros/Cargo.toml": "1ecec6fadb8bc6bf02e184b2a928c5b8ee06c805",
    "babble-macros/src/lib.rs": "63f626411b93f62d1007816bfc028c20104a75a3",
    "babble-macros/src/parse.rs": "15adc3fa43459e681af3ff508cba39f4b4aba33a",
}

DEPENDENCY_BLOBS = {
    "egg/Cargo.toml": "aa5b8fa45c6a136ff52a0f1542247c3385a6daf1",
    "egg/LICENSE": "6e6d258f048daa07590e9b32c113e262adfd92c1",
    "egg/README.md": "221f1cad784753c108af51bdee557893c1d555d2",
    "egg/src/dot.rs": "80f75a48fb156cca06653129f751e87410cbb805",
    "egg/src/eclass.rs": "54b76101380bb8e12de9c8ae2a64aef44f7a2736",
    "egg/src/egraph.rs": "06697fbe432a0ffad2710681b3136b2bab62ce36",
    "egg/src/explain.rs": "fba93bb5e125ce6b20d3d5f6f8370a46ace5f4cf",
    "egg/src/extract.rs": "f5d254dad1ef57cc394c6c209c76f296011bc04b",
    "egg/src/language.rs": "738ec08eb983d38793127949d9ac7f1cf83a072b",
    "egg/src/lib.rs": "84bb7835175620eeedc98fa1dbcb0e75a28eb2d7",
    "egg/src/machine.rs": "e1b4748324d94a1086f1118e9347b021d863c77a",
    "egg/src/macros.rs": "7d1ceb09980ae59b5ed266bda6ce67c4055b7553",
    "egg/src/pattern.rs": "f7a215eb6de154340bbf21066b6dc80a3029eb08",
    "egg/src/rewrite.rs": "5c836440ffbfd58cd4c27f5e24ee061c361d3b7c",
    "egg/src/run.rs": "ab5b4b7c06170236f0e7899c8f25ead0c8846bb6",
    "egg/src/subst.rs": "de31da8c4dac396b275ee00670b32854a89cfa87",
    "egg/src/test.rs": "cac3faf51f3a51f612f3488b3c4a8a0413f1a94d",
    "egg/src/tutorials/_01_background.rs": "db271e350d7ce80981c0a52e0be2ff67eabfbece",
    "egg/src/tutorials/_02_getting_started.rs": "3dbf87f40d02c1fe93d351177c74d67cc9e328e8",
    "egg/src/tutorials/_03_explanations.rs": "018e6b2dca336d9dede9afe174f671550e9dc11c",
    "egg/src/tutorials/mod.rs": "75dc8260218b4c89d807b0ce1f12fac87b758d31",
    "egg/src/unionfind.rs": "ee8618b09cbceaf1812a1e7f4e131b4f03cf0dfc",
    "egg/src/util.rs": "2b2f30b3cd2429a2065d0ff0137c3435f71be236",
    "symbolic_expressions/Cargo.toml": "e4d9a830b27edb807ebb6168f7c54005c67224fd",
    "symbolic_expressions/LICENSE-APACHE": "9bf06e471692966a1d1965880f15b616895813c2",
    "symbolic_expressions/LICENSE-MIT": "6872a0c10e03dded59cbbec36712542c644ebc7b",
    "symbolic_expressions/src/error.rs": "1e8b0166eb24d578ed6027fdf299dca35850b9e4",
    "symbolic_expressions/src/formatter.rs": "e8218e21bb0d487101a26181af7e5fce61cd6b9b",
    "symbolic_expressions/src/iteratom.rs": "21fc00e3a1edfb0a61b864a36b3f40d5bae7a14c",
    "symbolic_expressions/src/lib.rs": "64e3eba5341cc1ad9f84916c3c46bdc9cfd401c9",
    "symbolic_expressions/src/parser.rs": "dd759b28d6c1fafb685cde6175dae6cb5e2c8cca",
    "symbolic_expressions/src/ser.rs": "fdc79d1665df57758d001887f4c2e7de5aca3f67",
    "symbolic_expressions/src/sexp.rs": "92ad772815f1e96764d4ce03c7aa5a0233db005e",
    "symbolic_expressions/src/test.rs": "e012bfdc486fd45f3f6ebfaacdc317fbdc54732f",
    "instant/Cargo.toml": "d314ac1597300091100f19ab9fbce9b38c581d65",
    "instant/LICENSE": "4388af8c4688ae02bc87d6d9b9e73b98c76590e9",
    "instant/src/lib.rs": "bcf720a47ca8abeaec11d66864bbfc296d17e38c",
    "instant/src/native.rs": "a1412aabdc2c689238a9e750d71420846eab6047",
    "instant/src/wasm.rs": "3e416b453c1c86b98dd80b152617a8908de70f3a",
}

LIB_RS = """\
//! Foundry build index for the byte-exact Babble core modules.

pub mod ast_node;
pub mod co_occurrence;
mod dfta;
pub mod extract;
pub mod learn;
pub mod rewrites;
pub mod sexp;
pub mod simple_lang;
pub mod teachable;
"""

COMPATIBILITY_PATCHES = {
    "ast_node/expr.rs": (
        b"            Self(node)\n",
        b"            Expr(node)\n",
        "qualify nested helper constructor for modern rustc",
    ),
}


def git_blob(data: bytes) -> str:
    header = f"blob {len(data)}\0".encode()
    return hashlib.sha1(header + data).hexdigest()


def main() -> None:
    verified = {}
    for relative, expected in EXPECTED_BLOBS.items():
        source = SOURCE / relative
        data = source.read_bytes()
        actual = git_blob(data)
        if actual != expected:
            raise SystemExit(
                f"source-integrity failure for {relative}: "
                f"expected {expected}, observed {actual}"
            )
        verified[relative] = actual
    verified_dependencies = {}
    for relative, expected in DEPENDENCY_BLOBS.items():
        data = (BABBLE / relative).read_bytes()
        actual = git_blob(data)
        if actual != expected:
            raise SystemExit(
                f"dependency-integrity failure for {relative}: "
                f"expected {expected}, observed {actual}"
            )
        verified_dependencies[relative] = actual

    if GENERATED.exists():
        shutil.rmtree(GENERATED)
    GENERATED.mkdir()

    copied = {
        relative
        for relative in EXPECTED_BLOBS
        if relative.startswith("src/")
        and relative not in {"src/lib.rs", "src/bin/list/main.rs", "src/bin/list/lang.rs"}
    }
    for relative in copied:
        if relative == "src/bin/list/lang.rs":
            continue
        destination = GENERATED / Path(relative).relative_to("src")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(SOURCE / relative, destination)

    applied_patches = []
    for relative, (before, after, reason) in COMPATIBILITY_PATCHES.items():
        destination = GENERATED / relative
        data = destination.read_bytes()
        if data.count(before) != 1:
            raise SystemExit(
                f"compatibility-patch precondition failure for {relative}"
            )
        destination.write_bytes(data.replace(before, after, 1))
        applied_patches.append(
            {
                "file": relative,
                "before_sha256": hashlib.sha256(data).hexdigest(),
                "after_sha256": hashlib.sha256(
                    destination.read_bytes()
                ).hexdigest(),
                "reason": reason,
            }
        )

    (GENERATED / "lib.rs").write_text(LIB_RS, encoding="utf-8")
    manifest = {
        "upstream": "babble",
        "commit": "09ff03fd485a3e24178c1d706a5944a230123ba1",
        "verified_babble_git_blobs": verified,
        "verified_dependency_git_blobs": verified_dependencies,
        "copied_byte_exact": sorted(copied),
        "egg_commit": "caf623cad25cacba83193464dcf0d3dd4161ba7a",
        "symbolic_expressions_ref": "5.0.3",
        "instant_ref": "v0.1.12",
        "generated_module_index_sha256": hashlib.sha256(
            LIB_RS.encode()
        ).hexdigest(),
        "generated_compatibility_patches": applied_patches,
        "excluded_from_build": ["dreamcoder", "experiments", "cli binaries"],
    }
    (GENERATED / "source_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "BABBLE_SOURCE_STAGE_PASS "
        f"commit={manifest['commit']} exact_blobs="
        f"{len(verified) + len(verified_dependencies)}/"
        f"{len(EXPECTED_BLOBS) + len(DEPENDENCY_BLOBS)}"
    )


if __name__ == "__main__":
    main()
