//! Swarm EXP-7 — verify-learn generalization on held-out target classes.
//!
//! After a curriculum of certified discovery episodes (unified promote→reuse),
//! measure iters-to-certify on held-out spec fingerprints vs cold baseline.
//!
//! Run: zig build swarm-exp07 --release=fast

const std = @import("std");
const unified = @import("unified_invention");

const SEED: u64 = 0xE0077E4A6E01;

/// 24 hidden curriculum specs — monomials, cross-family, mod_p (verify-learn episodes).
const CURRICULUM = [_]unified.TargetSpec{
    .{ .name = "C01 mono c0", .kind = .monomial_sign, .mask = 0x01 },
    .{ .name = "C02 mono c1", .kind = .monomial_sign, .mask = 0x02 },
    .{ .name = "C03 mono c2", .kind = .monomial_sign, .mask = 0x04 },
    .{ .name = "C04 mono c3", .kind = .monomial_sign, .mask = 0x08 },
    .{ .name = "C05 mono c0c1", .kind = .monomial_sign, .mask = 0x03 },
    .{ .name = "C06 mono c0c2", .kind = .monomial_sign, .mask = 0x05 },
    .{ .name = "C07 mono c1c2", .kind = .monomial_sign, .mask = 0x06 },
    .{ .name = "C08 mono c0c3", .kind = .monomial_sign, .mask = 0x09 },
    .{ .name = "C09 mono c1c3", .kind = .monomial_sign, .mask = 0x0A },
    .{ .name = "C10 mono c2c3", .kind = .monomial_sign, .mask = 0x0C },
    .{ .name = "C11 mono deg3", .kind = .monomial_sign, .mask = 0x07 },
    .{ .name = "C12 mono deg3", .kind = .monomial_sign, .mask = 0x0E },
    .{ .name = "C13 mono deg4", .kind = .monomial_sign, .mask = 0x0F },
    .{ .name = "C14 mono deg4", .kind = .monomial_sign, .mask = 0x17 },
    .{ .name = "C15 parity", .kind = .parity_of_count },
    .{ .name = "C16 oriented", .kind = .oriented },
    .{ .name = "C17 sum%2", .kind = .sum_mod, .modulus = 2 },
    .{ .name = "C18 sum%3", .kind = .sum_mod, .modulus = 3 },
    .{ .name = "C19 sum%5", .kind = .sum_mod, .modulus = 5 },
    .{ .name = "C20 sum%7", .kind = .sum_mod, .modulus = 7 },
    .{ .name = "C21 sign%2", .kind = .sign_mod, .modulus = 2 },
    .{ .name = "C22 sign%3", .kind = .sign_mod, .modulus = 3 },
    .{ .name = "C23 sign%5", .kind = .sign_mod, .modulus = 5 },
    .{ .name = "C24 mono c4c5", .kind = .monomial_sign, .mask = 0x30 },
};

/// 10 held-out spec hashes — disjoint fingerprints from curriculum.
const HELD_OUT = [_]unified.TargetSpec{
    .{ .name = "H01 mono c4", .kind = .monomial_sign, .mask = 0x10 },
    .{ .name = "H02 mono c5", .kind = .monomial_sign, .mask = 0x20 },
    .{ .name = "H03 mono c0c4", .kind = .monomial_sign, .mask = 0x11 },
    .{ .name = "H04 mono deg3", .kind = .monomial_sign, .mask = 0x1A },
    .{ .name = "H05 mono deg4", .kind = .monomial_sign, .mask = 0x2D },
    .{ .name = "H06 sum%11", .kind = .sum_mod, .modulus = 11 },
    .{ .name = "H07 sum%13", .kind = .sum_mod, .modulus = 13 },
    .{ .name = "H08 sign%7", .kind = .sign_mod, .modulus = 7 },
    .{ .name = "H09 sign%11", .kind = .sign_mod, .modulus = 11 },
    .{ .name = "H10 sign%13", .kind = .sign_mod, .modulus = 13 },
};

fn assertDisjointFingerprints() void {
    for (HELD_OUT) |h| {
        const hf = unified.specFingerprint(h);
        for (CURRICULUM) |c| {
            std.debug.assert(unified.specFingerprint(c) != hf);
        }
    }
}

pub fn main() !void {
    assertDisjointFingerprints();

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const out = std.io.getStdOut().writer();

    try out.print("=== Swarm EXP-7 — verify-learn generalization (held-out target classes) ===\n\n", .{});
    try out.print("Protocol: {d} curriculum hidden specs → certify+promote → {d} held-out spec hashes\n", .{
        CURRICULUM.len, HELD_OUT.len,
    });
    try out.print("Metric: iters-to-certify (forge rounds + menu + world); Δ = cold_mean − warm_mean\n", .{});
    try out.print("Seed: 0x{X:0>16}\n\n", .{SEED});

    const gen = try unified.runVerifyLearnGenBenchmark(a, out, CURRICULUM[0..], HELD_OUT[0..], SEED, true);

    try out.print("\n════════════════════ EXP-7 SUMMARY ════════════════════\n", .{});
    try out.print("Curriculum: {d}/{d} certified, iters_sum={d}, final_library={d}\n", .{
        gen.curriculum_solved, gen.curriculum_len, gen.curriculum_iters_sum, gen.final_nlib,
    });
    try out.print("Held-out cold iters mean:  {d:.2}\n", .{gen.cold_iters_mean});
    try out.print("Held-out warm iters mean:  {d:.2}\n", .{gen.warm_iters_mean});
    try out.print("Held-out iters Δ (cold−warm): {d:.2}\n", .{gen.iters_delta_mean});
    try out.print("Library hits (warm iters=0): {d}/{d}\n", .{ gen.library_hits, gen.held_out_len });
    try out.print("Compositional generalization:  {s}\n\n", .{if (gen.compositional_generalization) "Y" else "N"});

    try out.print("{s:<20} | {s:>12} | {s:>12} | {s:>6} | {s}\n", .{ "held-out", "fp", "cold→warm", "Δ", "warm" });
    try out.print("{s}\n", .{"---------------------+--------------+--------------+--------+---------"});
    for (gen.held_out) |h| {
        try out.print("{s:<20} | 0x{X:0>12} | {d:>5} → {d:<5} | {d:>6} | {s}{s}\n", .{
            h.name,
            h.fingerprint,
            h.cold_iters,
            h.warm_iters,
            @as(i64, @intCast(h.cold_iters)) - @as(i64, @intCast(h.warm_iters)),
            if (h.warm_solved) "CERT" else "fail",
            if (h.warm_library_hit) " LIB" else "",
        });
    }

    // verify_learn_invent discover_feature path uses unified.runSingleTarget (parity sanity).
    const parity = try unified.runSingleTarget(a, out, .{ .name = "parity-sanity", .kind = .parity_of_count }, SEED ^ 0xBEEF, false);
    try out.print("\n[verify_learn_invent path] runSingleTarget parity: cov={d:.3} solved={}\n", .{ parity.cov, parity.solved });

    try out.print("\nDoc: boundary_crossing/docs/research/swarm_exp07_verify_learn_gen.md\n", .{});
}