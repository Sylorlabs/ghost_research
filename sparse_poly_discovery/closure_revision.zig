//! Closure revision proposal schema — T8-AG-22 core.
const std = @import("std");

pub const RevisionKind = enum {
    expand_basis_family,
    new_certifier,
    retire_rule,
};

pub const BasisFamily = enum {
    world_sum_mod,
    world_sign_mod,
    rank2,
    xor_popcount,
    pipeline,
    mod_synth,
};

pub const ClosureRevisionProposal = struct {
    id: []const u8,
    kind: RevisionKind,
    target_family: BasisFamily,
    tax_basis_from: u32,
    tax_basis_to: u32,
    remix_dominant: []const u8,
    novel_rate: f64,
    rationale: []const u8,
    witness_required: bool = true,
};

pub const TaxonomyInput = struct {
    mono_remix: usize,
    walsh_remix: usize,
    pipe_remix: usize,
    novel_count: usize,
    checked: usize,
};

pub fn novelRate(inp: TaxonomyInput) f64 {
    if (inp.checked == 0) return 0;
    return @as(f64, @floatFromInt(inp.novel_count)) / @as(f64, @floatFromInt(inp.checked));
}

/// Propose expanding world_sum_mod when remix dominates mono/walsh and novel rate is low.
pub fn proposeFromTaxonomy(inp: TaxonomyInput, basis_version: u32) ClosureRevisionProposal {
    const rate = novelRate(inp);
    const dominant = if (inp.mono_remix >= inp.walsh_remix) "monomial" else "walsh";
    return .{
        .id = "CRP-world-sum-v4",
        .kind = .expand_basis_family,
        .target_family = .world_sum_mod,
        .tax_basis_from = basis_version,
        .tax_basis_to = basis_version + 1,
        .remix_dominant = dominant,
        .novel_rate = rate,
        .rationale = "Sustained mono/walsh remix with arithmetic-world sole survivor; permanently anchor world_sum_mod in tax basis.",
        .witness_required = true,
    };
}

pub fn writeJson(proposal: ClosureRevisionProposal, out: anytype) !void {
    try out.print(
        \\{{
        \\  "id": "{s}",
        \\  "kind": "{s}",
        \\  "target_family": "{s}",
        \\  "tax_basis_from": {d},
        \\  "tax_basis_to": {d},
        \\  "remix_dominant": "{s}",
        \\  "novel_rate": {d:.4},
        \\  "rationale": "{s}",
        \\  "witness_required": {s}
        \\}}
        \\
    , .{
        proposal.id,
        @tagName(proposal.kind),
        @tagName(proposal.target_family),
        proposal.tax_basis_from,
        proposal.tax_basis_to,
        proposal.remix_dominant,
        proposal.novel_rate,
        proposal.rationale,
        if (proposal.witness_required) "true" else "false",
    });
}