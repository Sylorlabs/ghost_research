//! Framework revision vote harness — T8-AG-25 core.
const std = @import("std");
const cr = @import("closure_revision.zig");

pub const WitnessRecord = struct {
    witness_id: []const u8,
    approved: bool,
    timestamp_seed: u64,
};

pub const VoteResult = struct {
    recorded: bool,
    auto_retired: bool,
    message: []const u8,
};

pub fn voteOnProposal(
    proposal: cr.ClosureRevisionProposal,
    witness: WitnessRecord,
    allow_auto_retire: bool,
) VoteResult {
    if (proposal.witness_required and !witness.approved) {
        return .{
            .recorded = false,
            .auto_retired = false,
            .message = "blocked: witness_required but not approved",
        };
    }
    if (allow_auto_retire and !witness.approved) {
        return .{
            .recorded = false,
            .auto_retired = true,
            .message = "blocked: auto-retire without witness forbidden",
        };
    }
    _ = witness.timestamp_seed;
    return .{
        .recorded = true,
        .auto_retired = false,
        .message = "witness recorded; revision may proceed",
    };
}