//! T8-AG-25 — Framework vote harness; no auto-retire without witness.
//! Run: zig build tier8-framework-vote --release=fast

const std = @import("std");
const cr = @import("closure_revision.zig");
const fv = @import("framework_vote.zig");
const eqtax = @import("equivalence_tax.zig");

pub fn main() !void {
    const out = std.io.getStdOut().writer();
    const proposal = cr.proposeFromTaxonomy(.{
        .mono_remix = 10,
        .walsh_remix = 6,
        .pipe_remix = 1,
        .novel_count = 1,
        .checked = 18,
    }, eqtax.BASIS_VERSION);

    try out.print("=== T8-AG-25: Framework vote harness ===\n\n", .{});

    const blocked = fv.voteOnProposal(proposal, .{
        .witness_id = "none",
        .approved = false,
        .timestamp_seed = 0,
    }, true);
    try out.print("  auto-retire attempt: {s}\n", .{blocked.message});

    const ok = fv.voteOnProposal(proposal, .{
        .witness_id = "human-agent",
        .approved = true,
        .timestamp_seed = 0x82520260706,
    }, false);
    try out.print("  witnessed approve: {s}\n", .{ok.message});

    const pass = !blocked.recorded and blocked.auto_retired == false and ok.recorded;
    try out.print("  VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}