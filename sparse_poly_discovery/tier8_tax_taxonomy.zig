//! T8-AG-02f — Per-promote remix taxonomy (strict tax v3 on battery B).
//!
//! Run: zig build tier8-tax-taxonomy --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");

const family_name = [_][]const u8{
    "library",     "monomial",  "pair",        "walsh",       "world_sum",
    "world_sign",  "clifford",  "xor_popcount", "pipeline",   "mod_synth",
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();

    try out.print("=== T8-AG-02f: Tax remix taxonomy (basis v{d}) ===\n\n", .{eqtax.BASIS_VERSION});

    const summary = try ie.runBlindBattery(arena.allocator(), out, true, null);

    try out.print("\n── Taxonomy ({d} entries) ──\n", .{eqtax.tax_log_n});
    var remix_by_family: [family_name.len]usize = .{0} ** family_name.len;
    var novel_count: usize = 0;

    try out.print("[\n", .{});
    for (0..eqtax.tax_log_n) |i| {
        const e = eqtax.tax_log[i];
        const fam = @intFromEnum(e.primary_family);
        if (e.verdict == .remix) remix_by_family[fam] += 1 else novel_count += 1;
        try out.print("  {s}{{\n", .{if (i > 0) "," else ""});
        try out.print("    \"feature_kind\": \"{s}\",\n", .{e.feature_kind});
        try out.print("    \"verdict\": \"{s}\",\n", .{@tagName(e.verdict)});
        try out.print("    \"test_acc\": {d:.4},\n", .{e.test_acc});
        try out.print("    \"primary_family\": \"{s}\",\n", .{family_name[fam]});
        try out.print("    \"n_basis_cols\": {d}\n", .{e.n_basis_cols});
        try out.print("  }}\n", .{});
    }
    try out.print("]\n\n", .{});

    try out.print("── Remix class histogram ──\n", .{});
    for (family_name, 0..) |name, fi| {
        if (remix_by_family[fi] > 0) try out.print("  {s}: {d}\n", .{ name, remix_by_family[fi] });
    }

    try out.print("\n── Summary ──\n", .{});
    try out.print("  solved: {d}/{d}\n", .{ summary.solved, summary.total });
    try out.print("  checked={d} novel={d} remix={d} rate={d:.1}%\n", .{
        eqtax.stats.checked,
        novel_count,
        eqtax.stats.remix_blocked,
        eqtax.stats.novelRate() * 100.0,
    });
    const pass = eqtax.tax_log_n > 0;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}