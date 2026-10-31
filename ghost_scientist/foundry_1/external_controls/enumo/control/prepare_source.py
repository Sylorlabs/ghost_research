#!/usr/bin/env python3
"""Stage byte-exact Enumo core modules in their native Rust layout."""

from __future__ import annotations

import hashlib
import json
import shutil
from pathlib import Path


CONTROL = Path(__file__).resolve().parent
SOURCE = CONTROL.parent / "source"
GENERATED = CONTROL / "generated"
FILES = (
    "src/enumo/filter.rs",
    "src/enumo/metric.rs",
    "src/enumo/mod.rs",
    "src/enumo/pattern.rs",
    "src/enumo/rule.rs",
    "src/enumo/ruleset.rs",
    "src/enumo/scheduler.rs",
    "src/enumo/sexp.rs",
    "src/enumo/workload.rs",
    "src/language.rs",
    "src/recipe_utils.rs",
    "src/util.rs",
)
LIB_RS = """\
//! Foundry build index for the byte-exact Enumo rule-inference core.

use std::{
    fmt::{self, Display},
    hash::BuildHasherDefault,
};

use enumo::{Ruleset, Scheduler};
pub use language::*;
use serde::Serialize;
pub use util::*;

pub mod enumo;
mod language;
pub mod recipe_utils;
mod util;

pub type Id = egg::Id;
pub type Symbol = egg::Symbol;
pub type Var = egg::Var;
pub type EGraph<L, N> = egg::EGraph<L, N>;
pub type Pattern<L> = egg::Pattern<L>;
pub type HashMap<K, V> = rustc_hash::FxHashMap<K, V>;
pub type HashSet<K> = rustc_hash::FxHashSet<K>;
pub type IndexMap<K, V> =
    indexmap::IndexMap<K, V, BuildHasherDefault<rustc_hash::FxHasher>>;

#[derive(Debug, Clone)]
pub enum ValidationResult {
    Valid,
    Invalid,
    Unknown,
}

pub struct ExtractableAstSize;
impl<L: SynthLanguage> egg::CostFunction<L> for ExtractableAstSize {
    type Cost = usize;
    fn cost<C>(&mut self, enode: &L, mut costs: C) -> Self::Cost
    where
        C: FnMut(Id) -> Self::Cost,
    {
        if enode.is_allowed_op() {
            enode.fold(1, |sum, id| sum.saturating_add(costs(id)))
        } else {
            usize::MAX
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct Limits {
    pub iter: usize,
    pub node: usize,
    pub match_: usize,
}

#[derive(Debug, Clone, Copy, Serialize)]
pub enum DeriveType {
    Lhs,
    LhsAndRhs,
}

impl Limits {
    pub fn synthesis() -> Self {
        Self { iter: 2, node: 300_000, match_: 200_000 }
    }
    pub fn minimize() -> Self {
        Self { iter: 2, node: 300_000, match_: 200_000 }
    }
    pub fn deriving() -> Self {
        Self { iter: 5, node: 100_000, match_: 1000 }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Interval<T> {
    pub low: Option<T>,
    pub high: Option<T>,
}

impl<T: Ord + Display> Interval<T> {
    pub fn new(low: Option<T>, high: Option<T>) -> Self {
        if let (Some(a), Some(b)) = (&low, &high) {
            assert!(a.le(b), "Invalid interval: {} >= {}", a, b);
        }
        Self { low, high }
    }
}

impl<T> Default for Interval<T> {
    fn default() -> Self {
        Self { low: None, high: None }
    }
}

pub struct Phase<L: SynthLanguage> {
    pub rules: Ruleset<L>,
    pub rules_name: String,
    pub scheduler: Scheduler,
}

impl<L: SynthLanguage> fmt::Display for Phase<L> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let scheduler_name = match self.scheduler {
            Scheduler::Simple(_) => "eqsat",
            Scheduler::Saturating(_) => "sat",
            Scheduler::Compress(_) => "compress",
        };
        write!(f, "{} ({})", scheduler_name, self.rules_name)
    }
}
"""


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
    (GENERATED / "lib.rs").write_text(LIB_RS, encoding="utf-8")
    manifest = {
        "revision": "7ed456de94df26fdddc0c15417a987d101dc57b5",
        "copied_byte_exact": copied,
        "generated_module_index_sha256": hashlib.sha256(
            LIB_RS.encode()
        ).hexdigest(),
        "excluded_from_build": ["bv.rs", "logger.rs", "official Cargo CLI surface"],
    }
    (GENERATED / "source_manifest.json").write_text(
        json.dumps(manifest, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(
        "ENUMO_SOURCE_STAGE_PASS"
        f" revision={manifest['revision']} exact_modules={len(copied)}/12"
    )


if __name__ == "__main__":
    main()
