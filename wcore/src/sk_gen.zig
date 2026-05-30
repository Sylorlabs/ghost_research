//! Stream generators for the pure SK engine.
//!
//! The engine is driven by a stream it does not author and is never told the
//! structure of. `structuredCorpus` is produced by a hidden process that
//! happens to reuse two fixed combinators (`SKK` and `SK`) as opaque building
//! blocks — it never labels them. `noiseCorpus` is high-entropy random SK with
//! no injected reuse. The full corpus is logged verbatim, so "the structure was
//! in the data, not in the setup" is checkable.

const std = @import("std");
const sk = @import("sk.zig");
const Term = sk.Term;

fn randSK(al: std.mem.Allocator, r: std.Random, depth: usize) std.mem.Allocator.Error!*Term {
    if (depth == 0 or r.boolean()) {
        return if (r.boolean()) Term.s(al) else Term.k(al);
    }
    return Term.app(al, try randSK(al, r, depth - 1), try randSK(al, r, depth - 1));
}

/// A corpus whose hidden generator reuses the (unlabelled) combinators
/// `SKK` and `SK`. Each entry wraps random filler with these reused blocks.
pub fn structuredCorpus(al: std.mem.Allocator, seed: u64, n: usize) ![]*Term {
    var prng = std.Random.DefaultPrng.init(seed);
    const r = prng.random();

    const corpus = try al.alloc(*Term, n);
    for (corpus) |*c| {
        // freshly-built (structurally identical) copies of the reused blocks
        const i_block = try Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al)); // SKK
        const f_block = try Term.app(al, try Term.s(al), try Term.k(al)); // SK
        const left = try Term.app(al, i_block, try randSK(al, r, 2));
        const right = try Term.app(al, f_block, try randSK(al, r, 2));
        c.* = try Term.app(al, left, right);
    }
    return corpus;
}

fn identityBlock(al: std.mem.Allocator) !*Term { // SKK
    return Term.app(al, try Term.app(al, try Term.s(al), try Term.k(al)), try Term.k(al));
}
fn falseBlock(al: std.mem.Allocator) !*Term { // SK
    return Term.app(al, try Term.s(al), try Term.k(al));
}
fn duplicatorBlock(al: std.mem.Allocator) !*Term { // S I I  (= \x. x x)
    return Term.app(al, try Term.app(al, try Term.s(al), try identityBlock(al)), try identityBlock(al));
}

/// One stage of a teaching curriculum. The stages are authored to *contain*
/// reusable structure (like a teacher ordering lessons), but the engine is
/// never told which abstractions to form — it discovers them by compression.
///   stage 0: reuses identity (SKK) and false (SK)
///   stage 1: reuses identity and the duplicator (SII) -> duplicator builds on identity
///   stage 2: reuses the duplicator and identity heavily (reuse pays off)
pub fn curriculumStage(al: std.mem.Allocator, seed: u64, stage: usize, n: usize) ![]*Term {
    var prng = std.Random.DefaultPrng.init(seed +% stage *% 0x9E3779B97F4A7C15);
    const r = prng.random();
    const corpus = try al.alloc(*Term, n);
    for (corpus) |*c| {
        c.* = switch (stage) {
            0 => try Term.app(al, try Term.app(al, try identityBlock(al), try randSK(al, r, 2)), try Term.app(al, try falseBlock(al), try randSK(al, r, 2))),
            1 => try Term.app(al, try Term.app(al, try identityBlock(al), try randSK(al, r, 1)), try Term.app(al, try duplicatorBlock(al), try randSK(al, r, 1))),
            else => try Term.app(al, try Term.app(al, try duplicatorBlock(al), try identityBlock(al)), try Term.app(al, try duplicatorBlock(al), try randSK(al, r, 1))),
        };
    }
    return corpus;
}

/// High-entropy random SK with no injected reuse.
pub fn noiseCorpus(al: std.mem.Allocator, seed: u64, n: usize) ![]*Term {
    var prng = std.Random.DefaultPrng.init(seed ^ 0xA5A5A5A5);
    const r = prng.random();
    const corpus = try al.alloc(*Term, n);
    for (corpus) |*c| c.* = try randSK(al, r, 4);
    return corpus;
}
