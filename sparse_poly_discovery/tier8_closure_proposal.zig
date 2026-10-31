//! T8-AG-22 — ClosureRevisionProposal from tax taxonomy.
//! Run: zig build tier8-closure-proposal --release=fast

const std = @import("std");
const ie = @import("invention_engine.zig");
const eqtax = @import("equivalence_tax.zig");
const cr = @import("closure_revision.zig");

const SilentOut = struct {
    pub fn print(_: @This(), _: []const u8, _: anytype) !void {}
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    eqtax.strict_enabled = true;
    eqtax.resetStats();
    eqtax.resetTaxLog();

    _ = try ie.runBlindBattery(arena.allocator(), SilentOut{}, true, null);

    var mono: usize = 0;
    var walsh: usize = 0;
    var pipe: usize = 0;
    var novel: usize = 0;
    const family_name = [_][]const u8{
        "library", "monomial", "pair", "walsh", "world_sum", "world_sign",
        "clifford", "xor_popcount", "pipeline", "mod_synth",
    };
    for (0..eqtax.tax_log_n) |i| {
        const e = eqtax.tax_log[i];
        const fam = @intFromEnum(e.primary_family);
        if (e.verdict == .novel) {
            novel += 1;
        } else if (std.mem.eql(u8, family_name[fam], "monomial")) mono += 1
        else if (std.mem.eql(u8, family_name[fam], "walsh")) walsh += 1
        else if (std.mem.eql(u8, family_name[fam], "pipeline")) pipe += 1;
    }

    const inp: cr.TaxonomyInput = .{
        .mono_remix = mono,
        .walsh_remix = walsh,
        .pipe_remix = pipe,
        .novel_count = novel,
        .checked = eqtax.stats.checked,
    };
    const proposal = cr.proposeFromTaxonomy(inp, eqtax.BASIS_VERSION);

    try out.print("=== T8-AG-22: Closure revision proposal ===\n\n", .{});
    try out.print("Taxonomy: mono_remix={d} walsh_remix={d} pipe_remix={d} novel={d}/{d}\n\n", .{
        mono, walsh, pipe, novel, eqtax.stats.checked,
    });
    try out.print("Proposal JSON:\n", .{});
    try cr.writeJson(proposal, out);

    std.fs.cwd().makePath("/tmp/tier8-swarm") catch {};
    const jf = try std.fs.cwd().createFile("/tmp/tier8-swarm/closure_revision_proposal.json", .{});
    defer jf.close();
    try cr.writeJson(proposal, jf.writer());

    const pass = proposal.kind == .expand_basis_family and proposal.witness_required;
    try out.print("VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}