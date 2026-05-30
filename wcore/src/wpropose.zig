//! W-type proposal and cost-benefit — the heart of the engine's autonomy.
//!
//! ZERO-BIAS CONTRACT (read before editing):
//!   * We BLINDLY enumerate every small W-type over the finite shapes in the
//!     library (Unit, Bool) with every assignment of position type from
//!     {Bottom, Unit, Bool} to each shape inhabitant — i.e. constructor arities
//!     0, 1, and 2. Nothing is special-cased.
//!   * A candidate hosts a detected motif iff it has at least one arity-0
//!     constructor (a terminator) AND at least one constructor whose arity
//!     equals the motif's branching factor. That requirement is derived from
//!     the motif's structure, not from arithmetic or any notion of "number".
//!   * Acceptance is purely `new_total_nodes < old_total_nodes`. Nothing checks
//!     "is this Nat?" or "is this a tree?".
//!
//! `propose` evaluates one motif and returns the best W-type WITHOUT mutating
//! the library. `commit` installs a chosen proposal and behaviourally verifies
//! it by EXECUTING the invented recursor. The sleep phase proposes for several
//! motifs and commits only the node-count winner — so the SAME blind rule mints
//! Nat for linear data and a binary-tree type for branching data.

const std = @import("std");
const types = @import("types.zig");
const terms = @import("terms.zig");
const nodecount = @import("nodecount.zig");
const library = @import("library.zig");
const antiunify = @import("antiunify.zig");
const evaluator = @import("evaluator.zig");
const Type = types.Type;
const Term = terms.Term;
const Library = library.Library;
const Pattern = antiunify.Pattern;

pub const Proposal = struct {
    found: bool = false,
    pattern: ?Pattern = null,
    arity: usize = 0,
    shape: ?*Type = null,
    positions: []const *Type = &.{},
    shape_is_bool: bool = false,
    succ_idx: usize = 0,
    zero_idx: usize = 0,
    saved: usize = 0,
    old_total: usize = 0,
};

pub const Outcome = struct {
    invented: bool = false,
    name: []const u8 = "",
    saved: usize = 0,
    arity: usize = 0,
    is_naturals: bool = false,
    is_btree: bool = false,
    verified: bool = false,
    old_total: usize = 0,
    new_total: usize = 0,
};

/// Mirror an original program into a W-value of `wty`, using the motif's
/// recursive-child extraction. Leaves become the terminator constructor;
/// internal nodes become the brancher constructor with their children mirrored.
fn buildWValue(a: std.mem.Allocator, pat: *const Pattern, orig: *Term, succ_idx: usize, zero_idx: usize, wty: *Type) !*Term {
    if (Term.eql(orig, pat.base)) return Term.wIntro(a, zero_idx, &.{}, wty);
    var buf: [2]*Term = undefined;
    const n = antiunify.recChildren(pat, orig, &buf) orelse return Term.wIntro(a, zero_idx, &.{}, wty);
    var children: [2]*Term = undefined;
    for (buf[0..n], 0..) |child, i| {
        children[i] = try buildWValue(a, pat, child, succ_idx, zero_idx, wty);
    }
    return Term.wIntro(a, succ_idx, children[0..n], wty);
}

/// \n. WRec(motive, step = motif.head, target = n, base = motif.base).
/// The repeated head moves into the library ONCE, instead of being inlined in
/// every program.
fn buildRecursor(a: std.mem.Allocator, pat: *const Pattern, wty: *Type, unit: *Type) !*Term {
    const n_var = try Term.vr(a, 0, wty);
    const rec = try Term.wRec(a, unit, pat.head, n_var, pat.base, unit);
    const fun_ty = try Type.mkFun(a, wty, unit);
    return Term.lam(a, rec, fun_ty);
}

/// Evaluate every small W-type for hosting `pat`; return the best (lowest-cost)
/// without mutating the library. Logs each candidate.
pub fn propose(a: std.mem.Allocator, lib: *Library, pat: *const Pattern, w: anytype) !Proposal {
    const old_lib = lib.totalNodeCount();
    var old_batch: usize = 0;
    for (pat.programs) |p| old_batch += nodecount.nodeCountTerm(p);
    const old_total = old_lib + old_batch;

    const bottom_local = lib.bottom orelse try Type.mk(a, .Bottom);
    const bottom_present = lib.bottom != null;

    // Position-type alphabet: Bottom (arity 0), Unit (arity 1), Bool (arity 2).
    const pos_alphabet = [_]*Type{ bottom_local, lib.unit, lib.bool_ };

    // Candidate shapes: finite library types small enough to enumerate.
    var best: ?Proposal = null;

    for (lib.defs.items) |d| {
        if (!d.is_type) continue;
        const ninh = d.ty.inhabitantCount() orelse continue;
        if (ninh == 0) continue;
        if (nodecount.nodeCountType(d.ty) > 3) continue;
        const shape = d.ty;

        var combo: usize = 0;
        const total = std.math.pow(usize, pos_alphabet.len, ninh);
        while (combo < total) : (combo += 1) {
            const positions = try a.alloc(*Type, ninh);
            var has_terminator = false;
            var brancher_idx: ?usize = null;
            var zero_idx: usize = 0;
            var rem = combo;
            for (0..ninh) |i| {
                const digit = rem % pos_alphabet.len;
                rem /= pos_alphabet.len;
                positions[i] = pos_alphabet[digit];
                const ar = positions[i].inhabitantCount().?; // 0/1/2
                if (ar == 0 and !has_terminator) {
                    has_terminator = true;
                    zero_idx = i;
                }
                if (ar == pat.arity and brancher_idx == null) brancher_idx = i;
            }
            const wty = try Type.mkW(a, shape, positions);
            const capable = has_terminator and brancher_idx != null;

            var delta: i64 = 0;
            if (capable) {
                const succ_idx = brancher_idx.?;
                const wtype_nodes = nodecount.nodeCountType(wty);
                const recursor = try buildRecursor(a, pat, wty, lib.unit);
                const recursor_nodes = nodecount.nodeCountTerm(recursor);
                const bottom_add: usize = if (bottom_present) 0 else 1;
                var new_batch: usize = 0;
                for (pat.programs) |prog| {
                    const wval = try buildWValue(a, pat, prog, succ_idx, zero_idx, wty);
                    const recref = try Term.libRef(a, 0, null);
                    const refactored = try Term.app(a, recref, wval, null);
                    new_batch += nodecount.nodeCountTerm(refactored);
                }
                const new_total = old_lib + wtype_nodes + recursor_nodes + bottom_add + new_batch;
                delta = @as(i64, @intCast(old_total)) - @as(i64, @intCast(new_total));

                if (delta > 0 and (best == null or @as(i64, @intCast(best.?.saved)) < delta)) {
                    best = Proposal{
                        .found = true,
                        .pattern = pat.*,
                        .arity = pat.arity,
                        .shape = shape,
                        .positions = positions,
                        .shape_is_bool = shape.tag == .Bool,
                        .succ_idx = succ_idx,
                        .zero_idx = zero_idx,
                        .saved = @intCast(delta),
                        .old_total = old_total,
                    };
                }
            }
            try logCandidate(w, d.name, positions, pat.arity, capable, delta);
        }
    }

    return best orelse Proposal{ .old_total = old_total };
}

/// Install a proposal in the library and behaviourally verify it by executing
/// the invented recursor against every original program.
pub fn commit(a: std.mem.Allocator, lib: *Library, prop: *const Proposal, w: anytype) !Outcome {
    const pat = prop.pattern.?;
    if (lib.bottom == null) _ = try lib.ensureBottom();

    // Rebuild the W-type from the proposal's shape + positions.
    const committed_wty = try Type.mkW(a, prop.shape.?, prop.positions);

    const name = try std.fmt.allocPrint(a, "W_Type_0x{x}", .{lib.defs.items.len});
    _ = try lib.add(name, committed_wty, null, true);

    const recursor = try buildRecursor(a, &pat, committed_wty, lib.unit);
    const rec_ty = try Type.mkFun(a, committed_wty, lib.unit);
    const rec_name = try std.fmt.allocPrint(a, "rec_{s}", .{name});
    _ = try lib.add(rec_name, rec_ty, recursor, false);

    // Behavioural verification: fold each W-value to its internal-node count
    // (must equal the observed count) and run the recursor to REGENERATE the
    // original program (must be structurally identical). Proven by execution.
    var verified = true;
    try w.writeAll("[VERIFY] executing the invented type's recursor against the originals...\n");
    for (pat.programs, pat.counts, 0..) |orig, k, i| {
        const wval = try buildWValue(a, &pat, orig, prop.succ_idx, prop.zero_idx, committed_wty);
        const fold = evaluator.foldCount(wval);
        const rec = try Term.wRec(a, lib.unit, pat.head, wval, pat.base, lib.unit);
        const regen = try evaluator.eval(a, rec, 1_000_000);
        const ok = fold == k and Term.eql(regen, orig);
        if (!ok) verified = false;
        try w.print("  prog#{d}: observed={d} fold(W)={d} recursor_regen=={s} -> {s}\n", .{
            i, k, fold, if (Term.eql(regen, orig)) "original" else "DIFFERENT", if (ok) "OK" else "MISMATCH",
        });
    }

    const is_naturals = prop.shape_is_bool and prop.arity == 1;
    const is_btree = prop.shape_is_bool and prop.arity == 2;

    return Outcome{
        .invented = true,
        .name = name,
        .saved = prop.saved,
        .arity = prop.arity,
        .is_naturals = is_naturals,
        .is_btree = is_btree,
        .verified = verified,
        .old_total = prop.old_total,
        .new_total = prop.old_total - prop.saved,
    };
}

fn logCandidate(w: anytype, shape_name: []const u8, positions: []const *Type, arity: usize, capable: bool, delta: i64) !void {
    try w.print("  Candidate Shape={s}, Pos=[", .{shape_name});
    for (positions, 0..) |p, i| {
        if (i != 0) try w.writeAll(",");
        try p.write(w);
    }
    try w.writeAll("]");
    if (!capable) {
        try w.print(" -> Rejected (no arity-0 leaf and/or no arity-{d} constructor)\n", .{arity});
    } else if (delta > 0) {
        try w.print(" -> hosts arity-{d} motif, saves {d} nodes\n", .{ arity, delta });
    } else {
        try w.print(" -> hosts arity-{d} motif, but no net saving ({d} nodes)\n", .{ arity, delta });
    }
}

test "linear data: blind enumeration mints a one-leaf-one-unary Bool W-type (Nat) and verifies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();
    const mcts = @import("mcts.zig");
    const Logger = @import("logger.zig").Logger;
    var log = try Logger.init(a, 0x7E57);
    defer log.deinit();

    const programs = try mcts.run(a, &lib, &.{ 1, 2, 3, 4 }, &log);
    const pat = (try antiunify.detectLinear(a, programs)).?;
    const prop = try propose(a, &lib, &pat, &log);
    try std.testing.expect(prop.found);
    try std.testing.expectEqual(@as(usize, 1), prop.arity);
    const out = try commit(a, &lib, &prop, &log);
    try std.testing.expect(out.invented);
    try std.testing.expect(out.is_naturals);
    try std.testing.expect(out.verified);
}

test "branching data: same blind rule mints a binary-tree W-type (NOT Nat) and verifies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var lib = try Library.init(a);
    defer lib.deinit();
    const mcts = @import("mcts.zig");
    const Logger = @import("logger.zig").Logger;
    var log = try Logger.init(a, 0xB1234);
    defer log.deinit();

    const programs = try mcts.runBranching(a, &lib, &.{ 2, 3, 2 }, &log);

    // detectLinear must NOT match a batch of genuine binary trees
    try std.testing.expect((try antiunify.detectLinear(a, programs)) == null);

    const pat = (try antiunify.detectBranching(a, programs)).?;
    const prop = try propose(a, &lib, &pat, &log);
    try std.testing.expect(prop.found);
    try std.testing.expectEqual(@as(usize, 2), prop.arity);
    const out = try commit(a, &lib, &prop, &log);
    try std.testing.expect(out.invented);
    try std.testing.expect(out.is_btree);
    try std.testing.expect(!out.is_naturals);
    try std.testing.expect(out.verified);
}
