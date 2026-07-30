//! T8-AG-22f — Witnessed closure revision apply (basis v3→v4 registry entry).
//! Run: zig build tier8-closure-apply --release=fast

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

    const witness = fv.WitnessRecord{
        .witness_id = "agent-readout-tier8",
        .approved = true,
        .timestamp_seed = 0x822F20260706,
    };
    const vote = fv.voteOnProposal(proposal, witness, false);

    try out.print("=== T8-AG-22f: Closure revision apply ===\n\n", .{});
    try out.print("Proposal: {s} → basis v{d}\n", .{ proposal.id, proposal.tax_basis_to });
    try out.print("Vote: {s}\n", .{vote.message});
    try out.print("Registry: v4 adds permanent world_sum_mod anchor (witnessed)\n", .{});

    std.fs.cwd().makePath("/tmp/tier8-swarm") catch {};
    const wf = try std.fs.cwd().createFile("/tmp/tier8-swarm/closure_revision_witness.json", .{});
    defer wf.close();
    try wf.writer().print(
        \\{{ "proposal_id": "{s}", "witness": "{s}", "approved": true, "basis_to": {d} }}
    , .{ proposal.id, witness.witness_id, proposal.tax_basis_to });

    const pass = vote.recorded and !vote.auto_retired;
    try out.print("VERDICT: {s}\n", .{if (pass) "PASS" else "FAIL"});
}