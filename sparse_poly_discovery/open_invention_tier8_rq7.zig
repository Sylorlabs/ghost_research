//! T8-AG-07 — RQ7 proposals with strict tax gate (engine sole judge).
//!
//! PASS: ≥5 tax-survivors from first 50 proposals.
//!
//! Run: zig build tier8-rq7-tax --release=fast

const std = @import("std");
const rq7 = @import("open_invention_rq7.zig");
const ui = @import("unified_invention.zig");
const eqtax = @import("equivalence_tax.zig");
const ie = @import("invention_engine.zig");

const PROPOSAL_LIMIT: usize = 50;
const CERT: f64 = 0.90;
const NT: usize = 5;

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

fn proposalToFeature(prop: rq7.Proposal) ?ui.Feature {
    return switch (prop.formula_kind) {
        .monomial => .{ .monomial = prop.params.mask },
        .walsh => .{ .walsh = prop.params.subset },
        .spectral_count => .{ .spectral_count = prop.params.omega },
        .clifford_g2 => .{ .clifford_g2 = {} },
        .sum_mod_indicator => .{ .world_sum_mod = prop.params.modulus },
        .sign_mod_indicator => .{ .world_sign_mod = prop.params.modulus },
        .xor_popcount => .{ .walsh = prop.params.mask },
        .oriented_indicator, .cell_diff_oriented => .{ .pair_relation = .{ .i = prop.params.i, .j = prop.params.j } },
        .hidden_xor => .{ .walsh = prop.params.mask },
        .count_parity => .{ .world_sum_mod = 2 },
        else => null,
    };
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const out = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(alloc);
    defer std.process.argsFree(alloc, args);
    const json_path = if (args.len > 1) args[1] else "rq7_proposals.json";

    const file = try std.fs.cwd().openFile(json_path, .{});
    defer file.close();
    const raw = try file.readToEndAlloc(alloc, 4 * 1024 * 1024);
    const parsed = try std.json.parseFromSlice(std.json.Value, alloc, raw, .{});
    defer parsed.deinit();
    const arr = parsed.value.array;

    const prep = try ie.prepareBlindBatterySeed(alloc, 0xA7C0DE20260629, SilentOut{});
    const grid = prep.ctx.grid;

    var lib: [32]ui.Feature = undefined;
    var nlib: usize = 0;
    ie.seedUiFromRq1(prep.trained_lib, &lib, &nlib);

    const Y_targets = try alloc.alloc([]f64, NT);
    for (0..NT) |ti| {
        Y_targets[ti] = try alloc.alloc(f64, ui.NSAMP);
        for (0..ui.NSAMP) |s| Y_targets[ti][s] = rq7.label(grid[s], @enumFromInt(ti));
    }

    var scratch: [ui.NSAMP]f64 = undefined;

    eqtax.strict_enabled = true;
    eqtax.basis_level = 3;
    eqtax.resetStats();
    eqtax.resetTaxLog();
    eqtax.resetReplay();

    try out.print("=== T8-AG-07: RQ7 proposals + strict tax gate ===\n\n", .{});
    try out.print("Proposals: {d} (cap {d}) | tax basis v{d}\n", .{ arr.items.len, PROPOSAL_LIMIT, eqtax.BASIS_VERSION });
    try out.print("PASS bar: ≥5 tax-survivors\n\n", .{});

    var certified: usize = 0;
    var tax_survivors: usize = 0;
    const limit = @min(PROPOSAL_LIMIT, arr.items.len);

    for (0..limit) |pi| {
        const item = arr.items[pi];
        if (item != .object) continue;
        const o = item.object;
        const name_v = o.get("name") orelse continue;
        const kind_v = o.get("formula_kind") orelse continue;
        if (name_v != .string or kind_v != .string) continue;
        const kind = rq7.parseFormulaKind(kind_v.string) catch continue;
        const params = if (o.get("params")) |pv| rq7.parseParams(pv) else rq7.Params{};
        const prop: rq7.Proposal = .{ .name = name_v.string, .formula_kind = kind, .params = params };

        const feat = proposalToFeature(prop) orelse continue;

        for (0..NT) |ti| {
            const Y = Y_targets[ti];
            for (0..ui.NSAMP) |s| scratch[s] = rq7.evalFeature(grid[s], prop.formula_kind, prop.params);
            const tst = rq7.accLogit(&scratch, Y, ui.NVA, ui.NSAMP);
            if (tst < CERT) continue;
            certified += 1;

            if (eqtax.gatePromoteEx(grid, lib[0..nlib], feat, Y, true, 0, 0)) {
                tax_survivors += 1;
                try out.print("  SURVIVOR: {s} target={d} test={d:.3}\n", .{ prop.name, ti, tst });
            }
        }
    }

    try out.print("\n════════════════════ SUMMARY ════════════════════\n", .{});
    try out.print("  certified pairs: {d}\n", .{certified});
    try out.print("  tax survivors: {d}\n", .{tax_survivors});
    try out.print("  tax checked={d} novel={d} blocked={d}\n", .{
        eqtax.stats.checked,
        eqtax.stats.novel_allowed,
        eqtax.stats.remix_blocked,
    });
    const pass = tax_survivors >= 5;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}