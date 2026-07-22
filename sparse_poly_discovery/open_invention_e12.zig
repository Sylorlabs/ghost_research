//! EXPERIMENT E12 — propose-solve-verify self-play (POET curriculum).
//!
//! Loop:
//!   1. MUTATE  — random TargetSpec in the typed DSL (same kinds as unified_invention)
//!   2. SOLVE   — unified invention loop (forge → menu → world) on a shared growing library
//!   3. VERIFY  — held-out coverage + irreducible escape (certifier from unified_invention)
//!   4. CURATE  — keep targets whose solve-rate (held-out acc) lies in [0.10, 0.90]
//!
//! Run 50–100 rounds; measure whether the *solved frontier depth* ratchets upward.
//!
//! Run: zig build open-invention-e12 --release=fast

const std = @import("std");
const unified = @import("unified_invention.zig");

const N_ROUNDS: usize = 75;
const PROPOSALS_PER_ROUND: usize = 3;
const MAX_CURRICULUM: usize = 48;
const CURR_LO: f64 = 0.10;
const CURR_HI: f64 = 0.90;
const SEED: u64 = 0xE12C0FFEE12A11CE;

const WORLD_PRIMES = [_]usize{ 2, 3, 5, 7, 11, 13 };

pub const ExperimentResult = struct {
    rounds: usize,
    solved_frontier: usize,
    curriculum_peak: usize,
    curriculum_size: usize,
    solved_count: usize,
    proposals: usize,
    sustained_growth: bool,
    frontier_trace: [8]usize,
    depth_ratchet_events: usize,
};

const CurriculumEntry = struct {
    spec: unified.TargetSpec,
    coverage: f64,
    depth: usize,
    fingerprint: u64,
};

fn popcount(m: u8) usize {
    return @popCount(m);
}

/// Frontier depth tiers — monomial degree 1–4, then cross-family kinds.
pub fn targetDepth(spec: unified.TargetSpec) usize {
    return switch (spec.kind) {
        .monomial_sign => popcount(spec.mask),
        .parity_of_count, .oriented => 5,
        .sum_mod => 6,
        .sign_mod => 7,
    };
}

fn specFingerprint(spec: unified.TargetSpec) u64 {
    var h: u64 = @intFromEnum(spec.kind);
    h ^= @as(u64, spec.mask) *% 0x9E3779B97F4A7C15;
    h ^= @as(u64, spec.modulus) *% 0xC6A4A7935BD1E995;
    return h;
}

fn randomMonomial(rand: std.Random) unified.TargetSpec {
    const deg = rand.intRangeAtMost(usize, 1, 4);
    var mask: u8 = 0;
    var picked: usize = 0;
    while (picked < deg) {
        const bit = rand.intRangeAtMost(u8, 0, 7);
        const m = @as(u8, 1) << @intCast(bit);
        if (mask & m == 0) {
            mask |= m;
            picked += 1;
        }
    }
    if (mask == 0) mask = 1;
    return .{
        .name = "mut-mono",
        .kind = .monomial_sign,
        .mask = mask,
    };
}

fn randomModulus(rand: std.Random) usize {
    return WORLD_PRIMES[rand.intRangeAtMost(usize, 0, WORLD_PRIMES.len - 1)];
}

fn randomTarget(rand: std.Random) unified.TargetSpec {
    return switch (rand.intRangeAtMost(u8, 0, 4)) {
        0 => randomMonomial(rand),
        1 => .{ .name = "mut-parity", .kind = .parity_of_count },
        2 => .{ .name = "mut-oriented", .kind = .oriented },
        3 => .{ .name = "mut-sum-mod", .kind = .sum_mod, .modulus = randomModulus(rand) },
        else => .{ .name = "mut-sign-mod", .kind = .sign_mod, .modulus = randomModulus(rand) },
    };
}

fn mutateTarget(rand: std.Random, parent: ?unified.TargetSpec) unified.TargetSpec {
    if (parent == null or rand.float(f64) < 0.25) return randomTarget(rand);
    var spec = parent.?;
    switch (spec.kind) {
        .monomial_sign => {
            if (rand.float(f64) < 0.4) {
                const bit = rand.intRangeAtMost(u8, 0, 7);
                spec.mask ^= @as(u8, 1) << @intCast(bit);
                if (spec.mask == 0) spec.mask = 1;
            } else if (rand.float(f64) < 0.5) {
                return randomTarget(rand);
            } else {
                spec = randomMonomial(rand);
            }
        },
        .parity_of_count => spec = if (rand.float(f64) < 0.5)
            .{ .name = "mut-oriented", .kind = .oriented }
        else
            randomMonomial(rand),
        .oriented => spec = if (rand.float(f64) < 0.5)
            .{ .name = "mut-parity", .kind = .parity_of_count }
        else
            randomMonomial(rand),
        .sum_mod => {
            if (rand.float(f64) < 0.5) {
                spec.modulus = randomModulus(rand);
            } else {
                spec = .{ .name = "mut-sign-mod", .kind = .sign_mod, .modulus = randomModulus(rand) };
            }
        },
        .sign_mod => {
            if (rand.float(f64) < 0.5) {
                spec.modulus = randomModulus(rand);
            } else {
                spec = .{ .name = "mut-sum-mod", .kind = .sum_mod, .modulus = randomModulus(rand) };
            }
        },
    }
    return spec;
}

fn formatSpec(buf: []u8, spec: unified.TargetSpec) []const u8 {
    return switch (spec.kind) {
        .monomial_sign => std.fmt.bufPrint(buf, "mono(0x{X:0>2},d{d})", .{ spec.mask, popcount(spec.mask) }) catch "mono",
        .parity_of_count => "parity",
        .oriented => "oriented",
        .sum_mod => std.fmt.bufPrint(buf, "sum%{d}", .{spec.modulus}) catch "sum_mod",
        .sign_mod => std.fmt.bufPrint(buf, "sign%{d}", .{spec.modulus}) catch "sign_mod",
    };
}

fn curriculumHas(entries: []const CurriculumEntry, fp: u64) bool {
    for (entries) |e| if (e.fingerprint == fp) return true;
    return false;
}

fn pickCurriculumParent(rand: std.Random, entries: []const CurriculumEntry) ?unified.TargetSpec {
    if (entries.len == 0) return null;
    return entries[rand.intRangeAtMost(usize, 0, entries.len - 1)].spec;
}

fn tryAddCurriculum(
    entries: *std.ArrayList(CurriculumEntry),
    spec: unified.TargetSpec,
    cov: f64,
) !void {
    if (cov < CURR_LO or cov > CURR_HI) return;
    const fp = specFingerprint(spec);
    if (curriculumHas(entries.items, fp)) return;
    if (entries.items.len >= MAX_CURRICULUM) {
        // drop oldest entry (FIFO) to keep POET population moving
        _ = entries.orderedRemove(0);
    }
    try entries.append(.{
        .spec = spec,
        .coverage = cov,
        .depth = targetDepth(spec),
        .fingerprint = fp,
    });
}

fn curriculumPeakDepth(entries: []const CurriculumEntry) usize {
    var peak: usize = 0;
    for (entries) |e| peak = @max(peak, e.depth);
    return peak;
}

/// POET self-play: propose random/mutated targets, solve with unified loop, curate by band.
pub fn runExperiment(alloc: std.mem.Allocator, out: anytype, verbose: bool) !ExperimentResult {
    var prng = std.Random.DefaultPrng.init(SEED);
    const rand = prng.random();

    var curriculum = std.ArrayList(CurriculumEntry).init(alloc);
    defer curriculum.deinit();

    var solved_frontier: usize = 0;
    var solved_count: usize = 0;
    var proposals: usize = 0;
    var frontier_trace: [8]usize = .{0} ** 8;
    var depth_ratchet_events: usize = 0;
    var solved_depth_mask: u8 = 0;

    const NullOut = struct {
        pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
    };
    const null_out = NullOut{};

    if (verbose) {
        try out.print("=== EXPERIMENT E12: propose-solve-verify (POET curriculum) ===\n\n", .{});
        try out.print("Mutator: random TargetSpec {{kind, mask?, modulus?}} in unified DSL.\n", .{});
        try out.print("Solver:  unified loop (forge → menu → world), fresh library per target.\n", .{});
        try out.print("Verify:  held-out ≥{d:.2} AND irreducible escape R²<0.40 on promotion.\n", .{unified.COVER_THRESHOLD});
        try out.print("Curate:  keep targets with solve-rate ∈ [{d:.2}, {d:.2}].\n", .{ CURR_LO, CURR_HI });
        try out.print("Rounds:  {d} × {d} proposals = {d} total.\n\n", .{ N_ROUNDS, PROPOSALS_PER_ROUND, N_ROUNDS * PROPOSALS_PER_ROUND });
    }

    var round: usize = 0;
    while (round < N_ROUNDS) : (round += 1) {
        var p: usize = 0;
        while (p < PROPOSALS_PER_ROUND) : (p += 1) {
            const parent = pickCurriculumParent(rand, curriculum.items);
            const spec = mutateTarget(rand, parent);
            const depth = targetDepth(spec);

            const result = try unified.runSingleTarget(alloc, null_out, spec, SEED +% round *% 17 +% p, false);
            proposals += 1;
            const cov = result.cov;

            try tryAddCurriculum(&curriculum, spec, cov);

            if (result.solved) {
                solved_count += 1;
                if (depth > solved_frontier) solved_frontier = depth;
            }
            if (result.solved and depth >= 1 and depth <= 7) {
                const bit: u3 = @intCast(depth - 1);
                const flag = @as(u8, 1) << bit;
                if (solved_depth_mask & flag == 0) {
                    solved_depth_mask |= flag;
                    depth_ratchet_events += 1;
                }
            }

            if (verbose and (round < 5 or round >= N_ROUNDS - 3 or result.solved)) {
                var buf: [32]u8 = undefined;
                const sname = formatSpec(&buf, spec);
                try out.print("  r{d:>2} p{d} {s:<16} cov={d:.3}{s} depth={d}\n", .{
                    round,
                    p,
                    sname,
                    cov,
                    if (result.solved) " SOLVED" else "",
                    depth,
                });
            }
        }

        if (round % 10 == 9 or round == N_ROUNDS - 1) {
            const slot = round / 10;
            if (slot < frontier_trace.len) {
                frontier_trace[slot] = solved_frontier;
            }
        }

        if (verbose and round % 15 == 14) {
            try out.print("  … round {d}: curriculum={d} peak={d} solved_frontier={d}\n", .{
                round,
                curriculum.items.len,
                curriculumPeakDepth(curriculum.items),
                solved_frontier,
            });
        }
    }

    const curriculum_peak = curriculumPeakDepth(curriculum.items);

    // sustained growth: cross-family frontier (≥5) reached; ≥4 distinct depth tiers solved; held at checkpoints
    const sustained_growth = solved_frontier >= 5 and depth_ratchet_events >= 4 and frontier_trace[7] >= 5;

    if (verbose) {
        try out.print("\n── frontier depth trace (solved, every 10 rounds) ──\n", .{});
        for (frontier_trace, 0..) |d, i| {
            try out.print("  checkpoint {d:>2}: depth {d}\n", .{ (i + 1) * 10, d });
        }
        try out.print("\n════════════════════ VERDICT ════════════════════\n", .{});
        try out.print("rounds:            {d}\n", .{N_ROUNDS});
        try out.print("proposals:         {d}\n", .{proposals});
        try out.print("solved (≥{d:.2}):   {d}\n", .{ unified.COVER_THRESHOLD, solved_count });
        try out.print("solved frontier:   {d}  (max depth tier certified solved)\n", .{solved_frontier});
        try out.print("curriculum size:   {d}  (band [{d:.2},{d:.2}])\n", .{ curriculum.items.len, CURR_LO, CURR_HI });
        try out.print("curriculum peak:   {d}  (max depth in band)\n", .{curriculum_peak});
        try out.print("depth tiers hit:   {d}/7  (distinct solved depth tiers)\n", .{depth_ratchet_events});
        try out.print("sustained growth:  {s}\n", .{if (sustained_growth) "PASS" else "FAIL"});
        try out.print("\nDepth tiers: mono deg 1–4 | parity/oriented=5 | sum_mod=6 | sign_mod=7\n", .{});
        try out.print("See: unified_invention.zig, wcore inv_coevo (POET), inventable_substrate_design.md\n", .{});
    }

    return .{
        .rounds = N_ROUNDS,
        .solved_frontier = solved_frontier,
        .curriculum_peak = curriculum_peak,
        .curriculum_size = curriculum.items.len,
        .solved_count = solved_count,
        .proposals = proposals,
        .sustained_growth = sustained_growth,
        .frontier_trace = frontier_trace,
        .depth_ratchet_events = depth_ratchet_events,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();
    _ = try runExperiment(alloc, out, true);
}

test "E12 sustained growth on pinned seed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const NullOut = struct {
        pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
    };
    const result = try runExperiment(arena.allocator(), NullOut{}, false);
    try std.testing.expect(result.rounds == N_ROUNDS);
    try std.testing.expect(result.proposals == N_ROUNDS * PROPOSALS_PER_ROUND);
    try std.testing.expect(result.solved_frontier >= 4);
    try std.testing.expect(result.sustained_growth);
}