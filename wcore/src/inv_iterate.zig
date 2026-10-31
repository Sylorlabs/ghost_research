//! A1–A6: ITERATED atom promotion — standalone research runner.
//!
//! Research questions (RESEARCH_QUESTIONS.md §A, run 2026-07-10):
//!   A1  does each round still find behaviours irreducible to the CURRENT atom set?
//!   A2  does iterated promotion terminate (fixed point) or grow unboundedly?
//!   A3  library growth per round (size, promoted-atom program length).
//!   A4  GENERALISATION: a held-out battery of target behaviours is fixed BEFORE
//!       round 1; after each promotion we re-measure how many held-out targets are
//!       composable from the current library at a fixed depth budget. If promoted
//!       atoms only "solve themselves" (witness = the atom alone, depth 1) and never
//!       enable a *composition* that reaches a held-out target, that is the key
//!       negative result and is counted separately.
//!   A5/A6 retro-reduction audit: every promoted atom is re-certified at DEEPER
//!       budgets at the end — (a) against its promotion-time library prefix (did a
//!       trivial composition sneak past the depth-3 certifier?), and (b) against the
//!       final library minus itself (did it become redundant given later atoms?).
//!
//! This file is intentionally standalone: it IMPORTS the existing wcore sources
//! read-only (inv_alien / inv_coevo / inv_open / inv_atomforge) and PORTS the two
//! private helpers it needs (chain-vs-chain agreement, chain-solvable search) from
//! inv_atomforge.zig rather than modifying it.
//!
//! Build:  zig build-exe -O ReleaseFast src/inv_iterate.zig
//! Run:    ./inv_iterate <csv_path> [seed...] [--pop=N] [--gens=N] [--rounds=N]
//! Single-threaded. Deterministic given the seed list.

const std = @import("std");
const alien = @import("inv_alien.zig");
const coevo = @import("inv_coevo.zig");
const open = @import("inv_open.zig");
const forge = @import("inv_atomforge.zig");

const V: usize = alien.CANON_BASE;
const DEPTH: usize = forge.COMPOSE_DEPTH; // certifier / reachability depth budget = 3
const CENSUS_CAP: usize = 80; // irreducibility census over the 80 shortest clean candidates
const MATCH_SEQ: usize = 8; // random streams per behaviour comparison (same as forge)
const MATCH_L: usize = 28; // stream length (same as forge)
const RSEED: u64 = 0x0F17ED; // fixed reachability-check seed (identical across rounds/seeds)
const BATTERY_SEED: u64 = 0xBA77E71; // fixed battery-definition seed (decoy programs)

// =============================================================================
// Ported from inv_atomforge.zig (private there): chain-vs-chain agreement and
// "is this hidden-lib chain composable from the search lib at depth <= D?".
// =============================================================================

fn chainAgreement(
    lib_a: []const alien.Program,
    a_idxs: []const usize,
    lib_b: []const alien.Program,
    b_idxs: []const usize,
    n: usize,
    L: usize,
    seed: u64,
) f64 {
    var prng = std.Random.DefaultPrng.init(seed);
    const rng = prng.random();
    var syms: [256]u8 = undefined;
    var out_a: [256]u8 = undefined;
    var out_b: [256]u8 = undefined;
    var agree: usize = 0;
    var total: usize = 0;
    for (0..n) |_| {
        for (0..L) |i| syms[i] = @intCast(rng.uintLessThan(usize, V));
        forge.applyChain(lib_a, a_idxs, syms[0..L], out_a[0..L]);
        forge.applyChain(lib_b, b_idxs, syms[0..L], out_b[0..L]);
        for (0..L) |i| {
            total += 1;
            if (out_a[i] == out_b[i]) agree += 1;
        }
    }
    return @as(f64, @floatFromInt(agree)) / @as(f64, @floatFromInt(total));
}

/// Is the hidden chain `t_idxs` (into `hidden`) composable from `lib` at depth <= max_depth?
/// On success, the first (deterministic enumeration order) witness chain is returned.
fn targetSolvable(
    hidden: []const alien.Program,
    t_idxs: []const usize,
    lib: []const alien.Program,
    max_depth: usize,
    seed: u64,
    witness: []usize,
    wlen: *usize,
) bool {
    const n = lib.len;
    if (n == 0) return false;
    var d: usize = 1;
    while (d <= max_depth) : (d += 1) {
        var total: usize = 1;
        for (0..d) |_| total *= n;
        var idx: usize = 0;
        while (idx < total) : (idx += 1) {
            var idxs: [8]usize = undefined;
            var x = idx;
            for (0..d) |j| {
                idxs[j] = x % n;
                x /= n;
            }
            if (chainAgreement(hidden, t_idxs, lib, idxs[0..d], MATCH_SEQ, MATCH_L, seed) >= forge.MATCH_THRESHOLD) {
                for (0..d) |j| witness[j] = idxs[j];
                wlen.* = d;
                return true;
            }
        }
    }
    return false;
}

// =============================================================================
// The held-out battery — fixed BEFORE round 1, identical across all run seeds.
// Hidden library indices:
//   0 g_xor  1 g_add  2 pk_xor  3 pk_add  4 shift   (the 5 base atoms)
//   5 distinct-count  6 rmw-counter  7 xor-scan  8 hash-table  9 union
//   10..12 decoy programs (random clean programs, fixed seed 0xBA77E71)
// Chains apply left-to-right (applyChain order). Every target involves at least
// one non-base hidden atom, so none is trivially "already in the library".
// =============================================================================

const HIDDEN_N: usize = 13;

fn buildHidden() [HIDDEN_N]alien.Program {
    var h: [HIDDEN_N]alien.Program = undefined;
    h[0] = coevo.refSolver(.g_xor);
    h[1] = coevo.refSolver(.g_add);
    h[2] = coevo.refSolver(.pk_xor);
    h[3] = coevo.refSolver(.pk_add);
    h[4] = forge.shiftAtom();
    h[5] = coevo.distinctCountProg();
    h[6] = alien.alienRMWCounter();
    h[7] = alien.alienXorScan();
    h[8] = alien.alienHashTable();
    h[9] = alien.alienUnion();
    // decoys: first 3 random programs passing the "clean" (structured-output) filter
    var sp = alien.Params{ .active_regs = 8 };
    var prng = std.Random.DefaultPrng.init(BATTERY_SEED);
    const rng = prng.random();
    var n: usize = 10;
    while (n < HIDDEN_N) {
        const p = alien.randProg(rng, &sp);
        if (forge.clean(&p, BATTERY_SEED)) {
            h[n] = p;
            n += 1;
        }
    }
    return h;
}

const TSpec = struct { name: []const u8, idxs: []const usize };

const SPECS = [_]TSpec{
    .{ .name = "distinct", .idxs = &.{5} },
    .{ .name = "rmw", .idxs = &.{6} },
    .{ .name = "xorscan", .idxs = &.{7} },
    .{ .name = "hashtbl", .idxs = &.{8} },
    .{ .name = "union", .idxs = &.{9} },
    .{ .name = "decoy1", .idxs = &.{10} },
    .{ .name = "decoy2", .idxs = &.{11} },
    .{ .name = "decoy3", .idxs = &.{12} },
    .{ .name = "dist->gxor", .idxs = &.{ 5, 0 } },
    .{ .name = "gadd->dist", .idxs = &.{ 1, 5 } },
    .{ .name = "dist->dist", .idxs = &.{ 5, 5 } },
    .{ .name = "rmw->pkxor", .idxs = &.{ 6, 2 } },
    .{ .name = "dist->rmw", .idxs = &.{ 5, 6 } },
    .{ .name = "shift->dist", .idxs = &.{ 4, 5 } },
    .{ .name = "shift->dist->gxor", .idxs = &.{ 4, 5, 0 } },
    .{ .name = "pkadd->dist->pkadd", .idxs = &.{ 3, 5, 3 } },
    .{ .name = "rmw->rmw->gadd", .idxs = &.{ 6, 6, 1 } },
    .{ .name = "dist->shift->rmw", .idxs = &.{ 5, 4, 6 } },
};
const N_TARGETS: usize = SPECS.len;

const TState = struct {
    first_round: ?usize = null, // round at which it first became reachable (0 = baseline)
    wlen: usize = 0,
    witness: [DEPTH]usize = undefined,
    self_flip: bool = false, // witness == [the new atom] alone
};

// =============================================================================
// The iterated promotion loop
// =============================================================================

const PromotedAtom = struct {
    prog: alien.Program,
    round: usize, // promotion round (1-based)
    prefix_len: usize, // library size at certification time (atoms before it)
};

fn runSeed(
    al: std.mem.Allocator,
    out: anytype,
    cw: anytype,
    seed: u64,
    hidden: []const alien.Program,
    pop: usize,
    gens: usize,
    max_rounds: usize,
) !void {
    const dseed = seed ^ 0x1F0; // descriptor seed (mirrors forge.runPromotionSnapshots)
    const fseed = seed +% 0xA70F; // certifier seed (mirrors forge)

    var atoms = forge.baseAtoms();
    var promoted = std.ArrayList(PromotedAtom).init(al);
    defer promoted.deinit();

    var tstate: [N_TARGETS]TState = .{TState{}} ** N_TARGETS;

    try out.print("\n================ SEED 0x{X} ================\n", .{seed});
    try out.print("params: pop={d} gens={d} depth_budget={d} census_cap={d} max_rounds={d}\n", .{ pop, gens, DEPTH, CENSUS_CAP, max_rounds });

    // ---- round 0: baseline reachability of the battery from the base atoms ----
    var reachable: usize = 0;
    for (SPECS, 0..) |spec, ti| {
        var wit: [DEPTH]usize = undefined;
        var wl: usize = 0;
        if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
            tstate[ti].first_round = 0;
            tstate[ti].wlen = wl;
            tstate[ti].witness = wit;
            reachable += 1;
        }
    }
    try out.print("[round 0] baseline: lib={d} heldout {d}/{d} reachable\n", .{ atoms.len, reachable, N_TARGETS });
    try cw.print("0x{X},0,{d},{d},{d},0,0,0,0,0,0,{d},{d},0,0,0,0\n", .{ seed, DEPTH, atoms.len, atoms.len, reachable, N_TARGETS });

    var fixed_point = false;
    var round: usize = 1;
    while (round <= max_rounds) : (round += 1) {
        var timer = try std.time.Timer.start();
        const lib_before = atoms.len;

        // ---- forge: novelty search over the substrate (info descriptor) ----
        var prng = std.Random.DefaultPrng.init(seed +% round *% 0x9E3779B97F4A7C15);
        var archive = try open.search(al, prng.random(), .{ .pop = pop, .gens = gens, .info = true, .seed = dseed });
        defer archive.deinit();

        // clean candidates, shortest-first
        var cleanlist = std.ArrayList(open.Member).init(al);
        defer cleanlist.deinit();
        for (archive.items) |m| {
            if (forge.clean(&m.prog, dseed)) try cleanlist.append(m);
        }
        std.mem.sort(open.Member, cleanlist.items, {}, struct {
            fn lt(_: void, a: open.Member, b: open.Member) bool {
                return a.prog.len() < b.prog.len();
            }
        }.lt);

        // ---- A1 census: irreducibility of the CENSUS_CAP shortest clean candidates ----
        const n_checked = @min(CENSUS_CAP, cleanlist.items.len);
        var n_irred: usize = 0;
        var first_irred: ?alien.Program = null;
        for (cleanlist.items[0..n_checked]) |m| {
            if (!forge.reducibleLib(&m.prog, atoms.slice(), DEPTH, fseed)) {
                n_irred += 1;
                if (first_irred == null) first_irred = m.prog;
            }
        }

        if (first_irred == null or atoms.len >= forge.MAX_ATOMS) {
            const ms = timer.read() / std.time.ns_per_ms;
            try out.print("[round {d}] archive={d} clean={d} checked={d} irreducible=0 -> FIXED POINT at depth {d} ({d} ms)\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, DEPTH, ms });
            try cw.print("0x{X},{d},{d},{d},{d},{d},{d},{d},0,0,0,{d},{d},0,0,0,{d}\n", .{ seed, round, DEPTH, lib_before, atoms.len, archive.items.len, cleanlist.items.len, n_checked, reachable, N_TARGETS, ms });
            fixed_point = true;
            break;
        }

        // ---- promote the shortest irreducible candidate ----
        const new_atom = first_irred.?;
        const new_idx = atoms.len;
        atoms.appendAssumeCapacity(new_atom);
        try promoted.append(.{ .prog = new_atom, .round = round, .prefix_len = lib_before });

        // ---- A4: re-measure held-out reachability with the enlarged library ----
        var new_flips: usize = 0;
        var new_self: usize = 0;
        var new_comp: usize = 0;
        for (SPECS, 0..) |spec, ti| {
            if (tstate[ti].first_round != null) continue;
            var wit: [DEPTH]usize = undefined;
            var wl: usize = 0;
            if (targetSolvable(hidden, spec.idxs, atoms.slice(), DEPTH, RSEED, &wit, &wl)) {
                tstate[ti].first_round = round;
                tstate[ti].wlen = wl;
                tstate[ti].witness = wit;
                new_flips += 1;
                const is_self = (wl == 1 and wit[0] == new_idx);
                tstate[ti].self_flip = is_self;
                if (is_self) new_self += 1 else new_comp += 1;
            }
        }
        reachable += new_flips;

        const ms = timer.read() / std.time.ns_per_ms;
        try out.print("[round {d}] archive={d} clean={d} checked={d} irreducible={d} PROMOTE len={d} -> lib={d} | heldout {d}/{d} (+{d}: {d} self, {d} composed) ({d} ms)\n", .{ round, archive.items.len, cleanlist.items.len, n_checked, n_irred, new_atom.len(), atoms.len, reachable, N_TARGETS, new_flips, new_self, new_comp, ms });
        try cw.print("0x{X},{d},{d},{d},{d},{d},{d},{d},{d},1,{d},{d},{d},{d},{d},{d},{d}\n", .{ seed, round, DEPTH, lib_before, atoms.len, archive.items.len, cleanlist.items.len, n_checked, n_irred, new_atom.len(), reachable, N_TARGETS, new_flips, new_self, new_comp, ms });
    }

    if (!fixed_point) {
        try out.print("[end] round cap {d} reached WITHOUT fixed point (library still growing)\n", .{max_rounds});
    }

    // ---- per-target table ----
    try out.writeAll("\nheld-out battery (fixed before round 1):\n");
    try out.writeAll("  target               first_reachable_round  witness\n");
    for (SPECS, 0..) |spec, ti| {
        const st = tstate[ti];
        if (st.first_round) |r| {
            try out.print("  {s:<20} {d:>5}                 [", .{ spec.name, r });
            for (0..st.wlen) |j| {
                if (j > 0) try out.writeAll(",");
                try out.print("{d}", .{st.witness[j]});
            }
            try out.print("]{s}\n", .{if (st.self_flip) "  (SELF: new atom alone)" else ""});
        } else {
            try out.print("  {s:<20}  never\n", .{spec.name});
        }
    }

    // ---- A5/A6: retro-reduction audit at deeper budgets ----
    try out.writeAll("\nretro-reduction audit (deeper certifier on every promoted atom):\n");
    try out.writeAll("  atom  round  len  prefix_d4  prefix_d5  final-minus-self_d3  final-minus-self_d4\n");
    for (promoted.items, 0..) |pa, k| {
        // (a) against its promotion-time library prefix, at depth 4 then 5
        var prefix = forge.AtomLib{};
        for (0..pa.prefix_len) |j| prefix.appendAssumeCapacity(atoms.slice()[j]);
        var timer = try std.time.Timer.start();
        const p4 = forge.reducibleLib(&pa.prog, prefix.slice(), 4, fseed);
        const p5: ?bool = if (pa.prefix_len <= 13) forge.reducibleLib(&pa.prog, prefix.slice(), 5, fseed) else null;

        // (b) against the FINAL library minus itself, at depth 3 then 4
        var minus = forge.AtomLib{};
        const self_idx = forge.BASE_ATOMS + k;
        for (0..atoms.len) |j| {
            if (j != self_idx) minus.appendAssumeCapacity(atoms.slice()[j]);
        }
        const f3 = forge.reducibleLib(&pa.prog, minus.slice(), 3, fseed);
        const f4 = forge.reducibleLib(&pa.prog, minus.slice(), 4, fseed);
        const ms = timer.read() / std.time.ns_per_ms;

        try out.print("  inv{d:<3} {d:>4} {d:>4}  {s:<9}  {s:<9}  {s:<19}  {s:<19} ({d} ms)\n", .{
            k,
            pa.round,
            pa.prog.len(),
            if (p4) "REDUCED" else "holds",
            if (p5) |v| (if (v) "REDUCED" else "holds") else "skipped",
            if (f3) "REDUNDANT" else "holds",
            if (f4) "REDUNDANT" else "holds",
            ms,
        });
    }

    try out.print("\nseed 0x{X} summary: rounds_run={d} fixed_point={} lib {d}->{d} heldout {d}/{d}\n", .{
        seed,
        if (fixed_point) round else max_rounds,
        fixed_point,
        forge.BASE_ATOMS,
        atoms.len,
        reachable,
        N_TARGETS,
    });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const al = gpa.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(al);
    defer std.process.argsFree(al, args);
    if (args.len < 2) {
        try out.writeAll("usage: inv_iterate <csv_path> [seed...] [--pop=N] [--gens=N] [--rounds=N]\n");
        return;
    }
    const csv_path = args[1];

    var seeds = std.ArrayList(u64).init(al);
    defer seeds.deinit();
    var pop: usize = 90;
    var gens: usize = 45;
    var rounds: usize = 10;
    for (args[2..]) |a| {
        if (std.mem.startsWith(u8, a, "--pop=")) {
            pop = try std.fmt.parseInt(usize, a[6..], 10);
        } else if (std.mem.startsWith(u8, a, "--gens=")) {
            gens = try std.fmt.parseInt(usize, a[7..], 10);
        } else if (std.mem.startsWith(u8, a, "--rounds=")) {
            rounds = try std.fmt.parseInt(usize, a[9..], 10);
        } else {
            try seeds.append(try std.fmt.parseInt(u64, a, 0));
        }
    }
    if (seeds.items.len == 0) try seeds.append(0xA70F);

    const csv = try std.fs.cwd().createFile(csv_path, .{});
    defer csv.close();
    const cw = csv.writer();
    try cw.writeAll("seed,round,depth_budget,lib_before,lib_after,archive,n_clean,n_checked,n_irreducible,promoted,promoted_len,heldout_reachable,heldout_total,new_flips,new_self,new_composed,round_ms\n");

    const hidden = buildHidden();
    try out.print("held-out battery: {d} targets over a hidden library of {d} behaviours (fixed, seed 0x{X})\n", .{ N_TARGETS, HIDDEN_N, BATTERY_SEED });

    for (seeds.items) |s| {
        try runSeed(al, out, cw, s, &hidden, pop, gens, rounds);
    }
}
