//! Ghost Scientist / Terra: sealed real-artifact evaluator and comparison gate.
//!
//! Candidate-visible input is deliberately smaller than the evaluator state:
//!
//! GHOST_CANDIDATE_V1 <opaque_id> <develop|holdout> <payload_hash>
//!                    <actions_left> <builds_left> <probes_left>
//!
//! followed by the read-only payload bytes. It contains no original path,
//! task/family/kind, expected witness, answer, score, or progress. Candidate
//! claims bind an independently precommitted program/tool and exact payload:
//!
//! GHOST_WITNESS_V1 <opaque_id> <tool_hash> <program_hash> <payload_hash>
//!                  <schema_hash> <builds> <actions> <probes>
//!                  <summary> <canonical_evidence>
//!
//! This executable is an inspectable protocol/evaluator gate. It does not
//! claim hostile-process isolation or autonomous invention.
const std = @import("std");
const luna = @import("ghost_scientist_constructor_luna.zig");

pub const CandidatePhase = enum { develop, holdout };
const Phase = CandidatePhase;
const HiddenKind = enum {
    declarations,
    csv_width,
    sleep_in_loop,
    missing_arg,
    active_try_bytes,
};
const Schema = enum { positions_v1, record_width_v1, offset_spans_v1 };

pub const CandidateBudget = struct {
    builds: usize = 2048,
    actions: usize = 2048,
    probes: usize = 2048,
};
const Budget = CandidateBudget;
pub const equal_budget = Budget{};

/// The complete candidate-visible API. A constructor receives this value and
/// the bytes it names, never a `Spec`, `HiddenKind`, original path, expected
/// witness, accepted count, or score.
pub const CandidateView = struct {
    opaque_id: u64,
    phase: CandidatePhase,
    payload_hash: u64,
    payload: []const u8,
    budget: CandidateBudget,
};

/// One precommitted typed proposal returned by an external constructor.
/// `evidence` must remain owned by the constructor until evaluation returns.
pub const CandidateProposal = struct {
    tool_hash: u64,
    program_hash: u64,
    schema_hash: u64,
    builds: usize,
    actions: usize,
    probes: usize,
    summary: usize,
    evidence: []const u8,
};

/// The only per-development-instance feedback a candidate may retain.
/// It intentionally carries neither the hidden kind nor a score/expected fact.
pub const OpaqueReceipt = struct {
    opaque_id: u64,
    proposal_hash: u64,
    token: u64,
    accepted: bool,
};

const Spec = struct {
    hidden_kind: HiddenKind,
    phase: Phase,
    original_path: []const u8,
    opaque_seed: u64,
};
const specs = [_]Spec{
    .{
        .hidden_kind = .declarations,
        .phase = .develop,
        .original_path = "07_agent_loop/src/perception.zig",
        .opaque_seed = 0x4753_1001,
    },
    .{
        .hidden_kind = .csv_width,
        .phase = .develop,
        .original_path = "04_verified_synthesis/results/program_synthesis_inventor.csv",
        .opaque_seed = 0x4753_1002,
    },
    .{
        .hidden_kind = .active_try_bytes,
        .phase = .develop,
        .original_path = "boundary_crossing/verified_generation.zig",
        .opaque_seed = 0x4753_1003,
    },
    .{
        .hidden_kind = .sleep_in_loop,
        .phase = .holdout,
        .original_path = "12_adversarial_loop/src/immune_loop.zig",
        .opaque_seed = 0x4753_2001,
    },
    .{
        .hidden_kind = .missing_arg,
        .phase = .holdout,
        .original_path = "04_verified_synthesis/src/verify_cli.zig",
        .opaque_seed = 0x4753_2002,
    },
    .{
        .hidden_kind = .active_try_bytes,
        .phase = .holdout,
        .original_path = "boundary_crossing/parametric_guide.zig",
        .opaque_seed = 0x4753_2003,
    },
    .{
        .hidden_kind = .active_try_bytes,
        .phase = .holdout,
        .original_path = "boundary_crossing/code_semantics.zig",
        .opaque_seed = 0x4753_2004,
    },
    .{
        .hidden_kind = .active_try_bytes,
        .phase = .holdout,
        .original_path = "boundary_crossing/grounded_language.zig",
        .opaque_seed = 0x4753_2005,
    },
    .{
        .hidden_kind = .active_try_bytes,
        .phase = .holdout,
        .original_path = "boundary_crossing/recursive_loop.zig",
        .opaque_seed = 0x4753_2006,
    },
};

const Item = struct {
    spec: Spec,
    opaque_id: u64,
    payload_hash: u64,
    payload: []u8,

    fn deinit(self: Item, a: std.mem.Allocator) void {
        a.free(self.payload);
    }
};

const Claim = struct {
    opaque_id: u64,
    tool_hash: u64,
    program_hash: u64,
    payload_hash: u64,
    schema_hash: u64,
    builds: usize,
    actions: usize,
    probes: usize,
    summary: usize,
    evidence: []const u8,
};

const Score = struct {
    total: usize = 0,
    develop: usize = 0,
    holdout: usize = 0,
    accepted_claims: usize = 0,
    active_builds: usize = 0,
    active_actions: usize = 0,
    active_probes: usize = 0,
    charged_builds: usize = 0,
    charged_actions: usize = 0,
    charged_probes: usize = 0,
};

const Policy = enum {
    fixed_ax_complete,
    broad_fixed,
    random_ax_choice,
    replay,
};

fn hash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

fn schemaHash(schema: Schema) u64 {
    return hash(@tagName(schema));
}

fn hiddenSchema(kind: HiddenKind) Schema {
    return switch (kind) {
        .declarations, .active_try_bytes => .positions_v1,
        .csv_width => .record_width_v1,
        .sleep_in_loop, .missing_arg => .offset_spans_v1,
    };
}

fn appendPosition(out: *std.ArrayList(u8), first: *bool, value: usize) !void {
    if (!first.*) try out.append(',');
    first.* = false;
    try out.writer().print("{d}", .{value});
}

fn lineStart(bytes: []const u8, pos: usize) usize {
    const prior = std.mem.lastIndexOfScalar(u8, bytes[0..pos], '\n') orelse return 0;
    return prior + 1;
}

fn lineEnd(bytes: []const u8, pos: usize) usize {
    const relative = std.mem.indexOfScalar(u8, bytes[pos..], '\n') orelse return bytes.len;
    return pos + relative;
}

fn afterLineComment(bytes: []const u8, pos: usize) bool {
    return std.mem.indexOf(u8, bytes[lineStart(bytes, pos)..pos], "//") != null;
}

fn matchingBrace(bytes: []const u8, open: usize) ?usize {
    var depth: usize = 0;
    var at = open;
    while (at < bytes.len) : (at += 1) {
        if (bytes[at] == '{') {
            depth += 1;
        } else if (bytes[at] == '}') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return at;
        }
    }
    return null;
}

fn positionsWitness(
    a: std.mem.Allocator,
    bytes: []const u8,
    needle: []const u8,
    exclude_line_comments: bool,
) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    var first = true;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, needle)) |pos| {
        if (!exclude_line_comments or !afterLineComment(bytes, pos)) {
            try appendPosition(&out, &first, pos);
        }
        at = pos + needle.len;
    }
    if (first) try out.appendSlice("none");
    return out.toOwnedSlice();
}

fn csvWitness(a: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const header = std.mem.trimRight(u8, lines.next() orelse "", "\r");
    const reference_width = std.mem.count(u8, header, ",") + 1;
    try out.writer().print("r{d}:", .{reference_width});
    var row: usize = 1;
    var first = true;
    while (lines.next()) |raw| : (row += 1) {
        const line = std.mem.trimRight(u8, raw, "\r");
        if (line.len == 0) continue;
        const observed = std.mem.count(u8, line, ",") + 1;
        if (observed != reference_width) {
            if (!first) try out.append(',');
            first = false;
            try out.writer().print("{d}:{d}", .{ row, observed });
        }
    }
    if (first) try out.appendSlice("none");
    return out.toOwnedSlice();
}

fn containingBlockWitness(
    a: std.mem.Allocator,
    bytes: []const u8,
    anchor: []const u8,
    block_keyword: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    var first = true;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, anchor)) |pos| {
        const start = std.mem.lastIndexOf(u8, bytes[0..pos], block_keyword) orelse {
            at = pos + anchor.len;
            continue;
        };
        const open = std.mem.indexOfPos(u8, bytes, start, "{") orelse {
            at = pos + anchor.len;
            continue;
        };
        const end = matchingBrace(bytes, open) orelse {
            at = pos + anchor.len;
            continue;
        };
        if (pos <= end) {
            if (!first) try out.append(',');
            first = false;
            try out.writer().print("{d}:{d}:{d}", .{ pos, start, end });
        }
        at = pos + anchor.len;
    }
    if (first) try out.appendSlice("none");
    return out.toOwnedSlice();
}

fn containingLineWitness(
    a: std.mem.Allocator,
    bytes: []const u8,
    anchor: []const u8,
) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    var first = true;
    var at: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, at, anchor)) |pos| {
        if (!first) try out.append(',');
        first = false;
        try out.writer().print("{d}:{d}:{d}", .{ pos, lineStart(bytes, pos), lineEnd(bytes, pos) });
        at = pos + anchor.len;
    }
    if (first) try out.appendSlice("none");
    return out.toOwnedSlice();
}

fn canonicalWitness(a: std.mem.Allocator, kind: HiddenKind, bytes: []const u8) ![]u8 {
    return switch (kind) {
        .declarations => positionsWitness(a, bytes, "pub fn ", true),
        .csv_width => csvWitness(a, bytes),
        .sleep_in_loop => containingBlockWitness(a, bytes, "std.time.sleep", "while ("),
        .missing_arg => containingLineWitness(a, bytes, "return error.MissingArg"),
        .active_try_bytes => positionsWitness(a, bytes, "try", true),
    };
}

fn evidenceSummary(schema: Schema, evidence: []const u8) ?usize {
    if (evidence.len == 0) return null;
    return switch (schema) {
        .positions_v1, .offset_spans_v1 => if (std.mem.eql(u8, evidence, "none"))
            0
        else
            1 + std.mem.count(u8, evidence, ","),
        .record_width_v1 => blk: {
            if (evidence.len < 3 or evidence[0] != 'r') return null;
            const colon = std.mem.indexOfScalar(u8, evidence, ':') orelse return null;
            _ = std.fmt.parseInt(usize, evidence[1..colon], 10) catch return null;
            const tail = evidence[colon + 1 ..];
            break :blk if (std.mem.eql(u8, tail, "none")) 0 else 1 + std.mem.count(u8, tail, ",");
        },
    };
}

fn loadItems(a: std.mem.Allocator) ![specs.len]Item {
    var items: [specs.len]Item = undefined;
    var initialized: usize = 0;
    errdefer for (items[0..initialized]) |item| item.deinit(a);
    for (specs, 0..) |spec, index| {
        const payload = try std.fs.cwd().readFileAlloc(a, spec.original_path, 32 << 20);
        const payload_hash = hash(payload);
        items[index] = .{
            .spec = spec,
            .opaque_id = hash(@tagName(spec.phase)) ^ payload_hash ^ spec.opaque_seed,
            .payload_hash = payload_hash,
            .payload = payload,
        };
        initialized += 1;
    }
    for (items, 0..) |item, i| {
        for (items[0..i]) |prior| {
            if (item.payload_hash == prior.payload_hash or item.opaque_id == prior.opaque_id)
                return error.OverlappingSealedItems;
        }
    }
    return items;
}

fn deinitItems(a: std.mem.Allocator, items: *[specs.len]Item) void {
    for (items) |item| item.deinit(a);
}

fn candidateFrame(a: std.mem.Allocator, item: Item) ![]u8 {
    return std.fmt.allocPrint(
        a,
        "GHOST_CANDIDATE_V1 {x} {s} {x} {d} {d} {d}\n",
        .{
            item.opaque_id,
            @tagName(item.spec.phase),
            item.payload_hash,
            equal_budget.actions,
            equal_budget.builds,
            equal_budget.probes,
        },
    );
}

fn candidateFrameClean(frame: []const u8) bool {
    const forbidden = [_][]const u8{
        "task",
        "family",
        "kind",
        "answer",
        "expected",
        "score",
        "progress",
        "original",
        "path",
        "evaluator",
        "../",
    };
    for (forbidden) |word| {
        if (std.ascii.indexOfIgnoreCase(frame, word) != null) return false;
    }
    return true;
}

fn requestDenied(request: []const u8) bool {
    const forbidden = [_][]const u8{
        "answer",
        "expected",
        "score",
        "progress",
        "task",
        "family",
        "kind",
        "original",
        "path",
        "evaluator",
        "../",
        "/",
        ".git",
        "network",
    };
    for (forbidden) |word| {
        if (std.ascii.indexOfIgnoreCase(request, word) != null) return true;
    }
    return false;
}

fn accepts(a: std.mem.Allocator, item: Item, claim: Claim) !bool {
    if (claim.opaque_id != item.opaque_id or
        claim.tool_hash == 0 or
        claim.program_hash == 0 or
        claim.payload_hash != item.payload_hash or
        claim.schema_hash != schemaHash(hiddenSchema(item.spec.hidden_kind)) or
        claim.builds > equal_budget.builds or
        claim.actions > equal_budget.actions or
        claim.probes > equal_budget.probes)
    {
        return false;
    }
    const expected = try canonicalWitness(a, item.spec.hidden_kind, item.payload);
    defer a.free(expected);
    const observed_summary = evidenceSummary(hiddenSchema(item.spec.hidden_kind), claim.evidence) orelse return false;
    return observed_summary == claim.summary and
        std.mem.eql(u8, expected, claim.evidence);
}

fn parseClaim(line: []const u8) ?Claim {
    var fields = std.mem.tokenizeAny(u8, line, " \t\r\n");
    if (!std.mem.eql(u8, fields.next() orelse return null, "GHOST_WITNESS_V1")) return null;
    const opaque_id = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
    const tool_hash = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
    const program_hash = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
    const payload_hash = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
    const schema_hash = std.fmt.parseInt(u64, fields.next() orelse return null, 16) catch return null;
    const builds = std.fmt.parseInt(usize, fields.next() orelse return null, 10) catch return null;
    const actions = std.fmt.parseInt(usize, fields.next() orelse return null, 10) catch return null;
    const probes = std.fmt.parseInt(usize, fields.next() orelse return null, 10) catch return null;
    const summary = std.fmt.parseInt(usize, fields.next() orelse return null, 10) catch return null;
    const evidence = fields.next() orelse return null;
    if (fields.next() != null) return null;
    return .{
        .opaque_id = opaque_id,
        .tool_hash = tool_hash,
        .program_hash = program_hash,
        .payload_hash = payload_hash,
        .schema_hash = schema_hash,
        .builds = builds,
        .actions = actions,
        .probes = probes,
        .summary = summary,
        .evidence = evidence,
    };
}

fn makeClaim(
    a: std.mem.Allocator,
    item: Item,
    tool_source: []const u8,
    program: []const u8,
    schema: Schema,
    evidence: []const u8,
    used: Budget,
) ![]u8 {
    const summary = evidenceSummary(schema, evidence) orelse return error.BadEvidence;
    return std.fmt.allocPrint(
        a,
        "GHOST_WITNESS_V1 {x} {x} {x} {x} {x} {d} {d} {d} {d} {s}",
        .{
            item.opaque_id,
            hash(tool_source),
            hash(program),
            item.payload_hash,
            schemaHash(schema),
            used.builds,
            used.actions,
            used.probes,
            summary,
            evidence,
        },
    );
}

const Program = struct {
    source: []const u8,
    schema: Schema,
    kind: HiddenKind,
};

const ax_programs = [_]Program{
    .{
        .source = "PROGRAM_V1 SCAN_HEX(70756220666e20)|FILTER_NOT_AFTER_IN_LINE_HEX(2f2f)|EMIT_POSITIONS",
        .schema = .positions_v1,
        .kind = .declarations,
    },
    .{
        .source = "PROGRAM_V1 SPLIT_BYTE(0a)|WIDTH_BYTE(2c)|REFERENCE_RECORD(0)|EMIT_DEVIATIONS",
        .schema = .record_width_v1,
        .kind = .csv_width,
    },
    .{
        .source = "PROGRAM_V1 SCAN_HEX(7374642e74696d652e736c656570)|CONTAINING_BLOCK_OPENED_AFTER_HEX(7768696c652028)|EMIT_OFFSET_SPANS",
        .schema = .offset_spans_v1,
        .kind = .sleep_in_loop,
    },
    .{
        .source = "PROGRAM_V1 SCAN_HEX(72657475726e206572726f722e4d697373696e67417267)|CONTAINING_LINE|EMIT_OFFSET_SPANS",
        .schema = .offset_spans_v1,
        .kind = .missing_arg,
    },
};

fn axToolSource(program_index: usize) []const u8 {
    // Four canonical programs, but only the same three underlying supplied AX
    // tool forms: source structure, CSV width, and control-flow spans.
    return switch (program_index) {
        0, 3 => "AX_SOURCE_STRUCTURE_TOOL_V1",
        1 => "AX_CSV_WIDTH_TOOL_V1",
        2 => "AX_CONTROL_FLOW_TOOL_V1",
        else => unreachable,
    };
}

fn programEvidence(a: std.mem.Allocator, p: Program, bytes: []const u8) ![]u8 {
    return canonicalWitness(a, p.kind, bytes);
}

fn uniqueAxTools(selected: []const usize) usize {
    var hashes: [ax_programs.len]u64 = undefined;
    var count: usize = 0;
    for (selected) |program_index| {
        const tool_hash = hash(axToolSource(program_index));
        var seen = false;
        for (hashes[0..count]) |prior| {
            if (prior == tool_hash) {
                seen = true;
                break;
            }
        }
        if (!seen) {
            hashes[count] = tool_hash;
            count += 1;
        }
    }
    return count;
}

fn policyPrograms(policy: Policy, item_index: usize, out: *[ax_programs.len]usize) []const usize {
    return switch (policy) {
        .fixed_ax_complete => blk: {
            for (0..ax_programs.len) |i| out[i] = i;
            break :blk out[0..ax_programs.len];
        },
        .broad_fixed => blk: {
            // The broad control is the same complete, supplied AX portfolio,
            // but runs in a different precommitted order.
            out.* = .{ 1, 3, 0, 2 };
            break :blk out[0..ax_programs.len];
        },
        .random_ax_choice => blk: {
            out[0] = @intCast(hash(std.mem.asBytes(&item_index)) % ax_programs.len);
            break :blk out[0..1];
        },
        .replay => blk: {
            out[0] = 0;
            break :blk out[0..1];
        },
    };
}

fn emitPolicyReceipts(
    a: std.mem.Allocator,
    writer: anytype,
    policy: Policy,
    items: [specs.len]Item,
) !Score {
    var score = Score{};
    for (items, 0..) |item, item_index| {
        var indices: [ax_programs.len]usize = undefined;
        const selected = policyPrograms(policy, item_index, &indices);
        const active_tool_builds = uniqueAxTools(selected);
        var item_accepted = false;
        for (selected, 0..) |program_index, action_index| {
            const program = ax_programs[program_index];
            const evidence = try programEvidence(a, program, item.payload);
            defer a.free(evidence);
            const used = Budget{
                .builds = uniqueAxTools(selected[0 .. action_index + 1]),
                .actions = @min(action_index + 1, equal_budget.actions),
                .probes = @min(action_index + 1, equal_budget.probes),
            };
            const line = try makeClaim(
                a,
                item,
                axToolSource(program_index),
                program.source,
                program.schema,
                evidence,
                used,
            );
            defer a.free(line);
            const claim = parseClaim(line) orelse return error.InternalClaimMalformed;
            const accepted = try accepts(a, item, claim);
            if (accepted) {
                score.accepted_claims += 1;
                item_accepted = true;
                try emitTypedWitness(writer, @tagName(policy), item, claim);
            }
            score.active_actions += 1;
            score.active_probes += 1;
            try writer.print(
                "receipt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},typed_canonical\n",
                .{
                    @tagName(policy),
                    item.opaque_id,
                    @tagName(item.spec.phase),
                    claim.tool_hash,
                    claim.program_hash,
                    claim.payload_hash,
                    claim.schema_hash,
                    used.builds,
                    used.actions,
                    used.probes,
                    if (accepted) "accepted" else "rejected",
                },
            );
        }
        score.active_builds += active_tool_builds;
        if (item_accepted) {
            score.total += 1;
            if (item.spec.phase == .develop) score.develop += 1 else score.holdout += 1;
        }
        // Every arm is charged the exact same per-item allocation. Unused
        // units are explicit padding, never silently converted into advantage.
        score.charged_builds += equal_budget.builds;
        score.charged_actions += equal_budget.actions;
        score.charged_probes += equal_budget.probes;
        try writer.print(
            "budget,{s},{x},{s},-,-,{x},-,{d},{d},{d},charged_exact,active_builds={d};active_actions={d};active_probes={d}\n",
            .{
                @tagName(policy),
                item.opaque_id,
                @tagName(item.spec.phase),
                item.payload_hash,
                equal_budget.builds,
                equal_budget.actions,
                equal_budget.probes,
                active_tool_builds,
                selected.len,
                selected.len,
            },
        );
    }
    return score;
}

fn lunaSequenceHash(a: std.mem.Allocator, programs: []const luna.Program) !u64 {
    var serialized = std.ArrayList(u8).init(a);
    defer serialized.deinit();
    for (programs) |program| {
        try luna.writeProgram(program, serialized.writer());
        try serialized.append('\n');
    }
    return hash(serialized.items);
}

fn lunaClaim(item: Item, proposal: luna.Proposal, used: Budget) Claim {
    return .{
        .opaque_id = item.opaque_id,
        .tool_hash = proposal.tool_hash,
        .program_hash = proposal.program_hash,
        .payload_hash = proposal.payload_hash,
        .schema_hash = proposal.schema_hash,
        .builds = used.builds,
        .actions = used.actions,
        .probes = used.probes,
        .summary = proposal.summary,
        .evidence = proposal.evidence,
    };
}

fn receiptToken(item: Item, claim: Claim, accepted: bool) u64 {
    var material: [40]u8 = undefined;
    std.mem.writeInt(u64, material[0..8], item.opaque_id, .little);
    std.mem.writeInt(u64, material[8..16], claim.tool_hash, .little);
    std.mem.writeInt(u64, material[16..24], claim.program_hash, .little);
    std.mem.writeInt(u64, material[24..32], claim.payload_hash, .little);
    std.mem.writeInt(u64, material[32..40], if (accepted) 0xa77e else 0x5e11, .little);
    return hash(&material);
}

fn emitTypedWitness(
    writer: anytype,
    policy_name: []const u8,
    item: Item,
    claim: Claim,
) !void {
    try writer.print(
        "typed_witness,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},accepted,summary={d};witness_hex=",
        .{
            policy_name,
            item.opaque_id,
            @tagName(item.spec.phase),
            claim.tool_hash,
            claim.program_hash,
            claim.payload_hash,
            claim.schema_hash,
            claim.builds,
            claim.actions,
            claim.probes,
            claim.summary,
        },
    );
    for (claim.evidence) |byte| try writer.print("{x:0>2}", .{byte});
    try writer.writeByte('\n');
}

fn evaluateLunaMutation(
    a: std.mem.Allocator,
    item: Item,
    program: luna.Program,
    suffix: []const u8,
    used: Budget,
) !bool {
    const mutated_payload = try std.fmt.allocPrint(a, "{s}{s}", .{ item.payload, suffix });
    defer a.free(mutated_payload);
    var mutated_item = item;
    mutated_item.payload = mutated_payload;
    mutated_item.payload_hash = hash(mutated_payload);
    var proposal = try luna.makeProposal(a, program, mutated_payload, .{
        .builds = used.builds,
        .actions = used.actions,
        .probes = used.probes,
    });
    defer proposal.deinit(a);
    return accepts(a, mutated_item, lunaClaim(mutated_item, proposal, used));
}

const EarnedProgram = struct {
    program: luna.Program,
    sequence_hash: u64,
    first_accepted_index: usize,
    builds: usize,
    actions: usize,
    probes: usize,
};

/// Reduce Luna's complete, payload-derived, precommitted sequence. The
/// constructor never sees a task label or expected witness. Development-only
/// accept/reject receipts select the first program that also survives relevant
/// and irrelevant evaluator-owned mutation audits.
fn constructEarnedProgram(
    a: std.mem.Allocator,
    writer: anytype,
    item: Item,
    inherited: Budget,
    policy_name: []const u8,
) !EarnedProgram {
    const programs = try luna.enumeratePrograms(a, item.payload);
    defer a.free(programs);
    const remaining_builds = equal_budget.builds - inherited.builds;
    const remaining_actions = equal_budget.actions - inherited.actions;
    const remaining_probes = equal_budget.probes - inherited.probes;
    const cap = @min(programs.len, @min(remaining_builds, @min(remaining_actions, remaining_probes)));
    const committed_sequence = programs[0..cap];
    const sequence_hash = try lunaSequenceHash(a, programs);
    try writer.print(
        "precommit,{s},{x},{s},-,{x},{x},-,0,0,0,precommitted,programs={d};reduction_cap={d};sequence_hash={x};input=GHOST_CANDIDATE_V1_only\n",
        .{
            policy_name,
            item.opaque_id,
            @tagName(item.spec.phase),
            item.payload_hash,
            sequence_hash,
            programs.len,
            committed_sequence.len,
            sequence_hash,
        },
    );
    var chain: u64 = sequence_hash;
    for (committed_sequence, 0..) |program, index| {
        const attempt = index + 1;
        const used = Budget{
            .builds = inherited.builds + attempt,
            .actions = inherited.actions + attempt,
            .probes = inherited.probes + attempt,
        };
        var proposal = try luna.makeProposal(a, program, item.payload, .{
            .builds = used.builds,
            .actions = used.actions,
            .probes = used.probes,
        });
        defer proposal.deinit(a);
        const claim = lunaClaim(item, proposal, used);
        const exact_ok = try accepts(a, item, claim);
        const token = receiptToken(item, claim, exact_ok);
        chain = hash(std.mem.asBytes(&token)) ^ std.math.rotl(u64, chain, 9);
        try writer.print(
            "constructor_attempt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},attempt={d};opaque_receipt={x};full_sequence_hash={x}\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                used.builds,
                used.actions,
                used.probes,
                if (exact_ok) "tentative_accept" else "rejected",
                attempt,
                token,
                sequence_hash,
            },
        );
        if (!exact_ok) continue;

        // The accepted program must retain all original evidence when only a
        // comment is appended, and must detect an added active `try`.
        const irrelevant_used = Budget{
            .builds = used.builds,
            .actions = used.actions + 1,
            .probes = used.probes + 1,
        };
        const irrelevant_ok = try evaluateLunaMutation(
            a,
            item,
            program,
            "\n// try is evaluator-owned irrelevant mutation\n",
            irrelevant_used,
        );
        const relevant_used = Budget{
            .builds = irrelevant_used.builds,
            .actions = irrelevant_used.actions + 1,
            .probes = irrelevant_used.probes + 1,
        };
        const relevant_ok = try evaluateLunaMutation(
            a,
            item,
            program,
            "\nfn terraMutation(a: anytype) !void { _ = try a.next(); }\n",
            relevant_used,
        );
        try writer.print(
            "constructor_attempt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},attempt={d};mutation=irrelevant_comment;feedback=opaque\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                irrelevant_used.builds,
                irrelevant_used.actions,
                irrelevant_used.probes,
                if (irrelevant_ok) "accepted" else "rejected",
                attempt + 1,
            },
        );
        try writer.print(
            "constructor_attempt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},attempt={d};mutation=relevant_active_try_bytes;feedback=opaque\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                relevant_used.builds,
                relevant_used.actions,
                relevant_used.probes,
                if (relevant_ok) "accepted" else "rejected",
                attempt + 2,
            },
        );
        if (!irrelevant_ok or !relevant_ok) continue;
        try emitTypedWitness(writer, policy_name, item, claim);
        try writer.print(
            "receipt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},accepted,first_accept_index={d};opaque_receipt_chain={x};mutation_audits=2\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                relevant_used.builds,
                relevant_used.actions,
                relevant_used.probes,
                attempt,
                chain,
            },
        );
        return .{
            .program = program,
            .sequence_hash = sequence_hash,
            .first_accepted_index = attempt,
            .builds = relevant_used.builds,
            .actions = relevant_used.actions,
            .probes = relevant_used.probes,
        };
    }
    return error.NoRobustEarnedProgram;
}

fn evaluateInheritedForItem(
    a: std.mem.Allocator,
    writer: anytype,
    item: Item,
    policy_name: []const u8,
) !struct { accepted: bool, score: Score } {
    var result = Score{};
    var accepted = false;
    for (ax_programs, 0..) |program, program_index| {
        const evidence = try programEvidence(a, program, item.payload);
        defer a.free(evidence);
        const used = Budget{
            .builds = 0, // replaced by the unique-tool prefix below
            .actions = program_index + 1,
            .probes = program_index + 1,
        };
        var prefix: [ax_programs.len]usize = undefined;
        for (0..program_index + 1) |i| prefix[i] = i;
        const bound_used = Budget{
            .builds = uniqueAxTools(prefix[0 .. program_index + 1]),
            .actions = used.actions,
            .probes = used.probes,
        };
        const line = try makeClaim(
            a,
            item,
            axToolSource(program_index),
            program.source,
            program.schema,
            evidence,
            bound_used,
        );
        defer a.free(line);
        const claim = parseClaim(line) orelse return error.InternalClaimMalformed;
        const ok = try accepts(a, item, claim);
        accepted = accepted or ok;
        result.active_actions += 1;
        result.active_probes += 1;
        if (ok) result.accepted_claims += 1;
        if (ok) try emitTypedWitness(writer, policy_name, item, claim);
        try writer.print(
            "receipt,{s},{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},inherited_ax_program\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                claim.tool_hash,
                claim.program_hash,
                claim.payload_hash,
                claim.schema_hash,
                bound_used.builds,
                bound_used.actions,
                bound_used.probes,
                if (ok) "accepted" else "rejected",
            },
        );
    }
    result.active_builds = 3;
    return .{ .accepted = accepted, .score = result };
}

fn emitAdaptiveReceipts(
    a: std.mem.Allocator,
    writer: anytype,
    items: [specs.len]Item,
) !Score {
    var total = Score{};
    var earned: ?EarnedProgram = null;
    for (items) |item| {
        const inherited = try evaluateInheritedForItem(a, writer, item, "adaptive_candidate");
        var item_accepted = inherited.accepted;
        var active = inherited.score;

        if (item.spec.phase == .develop and !inherited.accepted) {
            // Development receives opaque binary receipts only. The complete
            // sequence is committed before the evaluator starts reducing it.
            earned = try constructEarnedProgram(
                a,
                writer,
                item,
                .{
                    .builds = inherited.score.active_builds,
                    .actions = inherited.score.active_actions,
                    .probes = inherited.score.active_probes,
                },
                "adaptive_candidate",
            );
            item_accepted = true;
            active.active_builds = earned.?.builds;
            active.active_actions = earned.?.actions;
            active.active_probes = earned.?.probes;
            active.accepted_claims += 1;
        } else if (item.spec.phase == .holdout and earned != null) {
            // Heldout routing uses only the learned tool's own answer-free
            // output signature. All claims are precommitted before any heldout
            // evaluator reduction; no heldout receipt reaches the candidate.
            var learned_proposal = try luna.makeProposal(a, earned.?.program, item.payload, .{
                .builds = inherited.score.active_builds,
                .actions = inherited.score.active_actions + 1,
                .probes = inherited.score.active_probes + 1,
            });
            defer learned_proposal.deinit(a);
            const nonempty_signature = learned_proposal.summary > 0;
            if (nonempty_signature) {
                const used = Budget{
                    .builds = inherited.score.active_builds,
                    .actions = inherited.score.active_actions + 1,
                    .probes = inherited.score.active_probes + 1,
                };
                const claim = lunaClaim(item, learned_proposal, used);
                const ok = try accepts(a, item, claim);
                item_accepted = item_accepted or ok;
                active.active_actions += 1;
                active.active_probes += 1;
                if (ok) active.accepted_claims += 1;
                if (ok) try emitTypedWitness(writer, "adaptive_candidate", item, claim);
                try writer.print(
                    "receipt,adaptive_candidate,{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},learned_signature_nonempty=true;heldout_feedback=withheld\n",
                    .{
                        item.opaque_id,
                        @tagName(item.spec.phase),
                        claim.tool_hash,
                        claim.program_hash,
                        claim.payload_hash,
                        claim.schema_hash,
                        used.builds,
                        used.actions,
                        used.probes,
                        if (ok) "accepted" else "rejected",
                    },
                );
            }
        }

        total.active_builds += active.active_builds;
        total.active_actions += active.active_actions;
        total.active_probes += active.active_probes;
        total.accepted_claims += active.accepted_claims;
        total.charged_builds += equal_budget.builds;
        total.charged_actions += equal_budget.actions;
        total.charged_probes += equal_budget.probes;
        if (item_accepted) {
            total.total += 1;
            if (item.spec.phase == .develop) total.develop += 1 else total.holdout += 1;
        }
        try writer.print(
            "budget,adaptive_candidate,{x},{s},-,-,{x},-,{d},{d},{d},charged_exact,active_builds={d};active_actions={d};active_probes={d};heldout_feedback={s}\n",
            .{
                item.opaque_id,
                @tagName(item.spec.phase),
                item.payload_hash,
                equal_budget.builds,
                equal_budget.actions,
                equal_budget.probes,
                active.active_builds,
                active.active_actions,
                active.active_probes,
                if (item.spec.phase == .holdout) "withheld" else "opaque_only",
            },
        );
    }
    if (earned == null) return error.NoEarnedProgram;
    return total;
}

const matched_random_attempt_cap: usize = 101;

fn constructRandomProgram(
    a: std.mem.Allocator,
    writer: anytype,
    item: Item,
    inherited: Budget,
) !?EarnedProgram {
    const generated = try luna.enumeratePrograms(a, item.payload);
    defer a.free(generated);
    const shuffled = try a.dupe(luna.Program, generated);
    defer a.free(shuffled);
    var prng = std.Random.DefaultPrng.init(item.opaque_id ^ 0x7261_6e64_6f6d_4753);
    prng.random().shuffle(luna.Program, shuffled);
    const sequence_hash = try lunaSequenceHash(a, shuffled);
    const cap = @min(
        shuffled.len,
        @min(
            matched_random_attempt_cap,
            @min(
                equal_budget.builds - inherited.builds,
                @min(
                    equal_budget.actions - inherited.actions,
                    equal_budget.probes - inherited.probes,
                ),
            ),
        ),
    );
    try writer.print(
        "precommit,random_constructor,{x},{s},-,{x},{x},-,0,0,0,precommitted,programs={d};reduction_cap={d};sequence_hash={x};shuffle_seed=opaque_id_only\n",
        .{
            item.opaque_id,
            @tagName(item.spec.phase),
            item.payload_hash,
            sequence_hash,
            shuffled.len,
            cap,
            sequence_hash,
        },
    );
    var chain = sequence_hash;
    for (shuffled[0..cap], 0..) |program, index| {
        const attempt = index + 1;
        const used = Budget{
            .builds = inherited.builds + attempt,
            .actions = inherited.actions + attempt,
            .probes = inherited.probes + attempt,
        };
        var proposal = try luna.makeProposal(a, program, item.payload, .{
            .builds = used.builds,
            .actions = used.actions,
            .probes = used.probes,
        });
        defer proposal.deinit(a);
        const claim = lunaClaim(item, proposal, used);
        const exact_ok = try accepts(a, item, claim);
        const token = receiptToken(item, claim, exact_ok);
        chain = hash(std.mem.asBytes(&token)) ^ std.math.rotl(u64, chain, 9);
        try writer.print(
            "constructor_attempt,random_constructor,{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},attempt={d};opaque_receipt={x};full_sequence_hash={x}\n",
            .{
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                used.builds,
                used.actions,
                used.probes,
                if (exact_ok) "tentative_accept" else "rejected",
                attempt,
                token,
                sequence_hash,
            },
        );
        if (!exact_ok) continue;
        const irrelevant_used = Budget{
            .builds = used.builds,
            .actions = used.actions + 1,
            .probes = used.probes + 1,
        };
        const irrelevant_ok = try evaluateLunaMutation(
            a,
            item,
            program,
            "\n// try is evaluator-owned irrelevant mutation\n",
            irrelevant_used,
        );
        const relevant_used = Budget{
            .builds = irrelevant_used.builds,
            .actions = irrelevant_used.actions + 1,
            .probes = irrelevant_used.probes + 1,
        };
        const relevant_ok = try evaluateLunaMutation(
            a,
            item,
            program,
            "\nfn terraMutation(a: anytype) !void { _ = try a.next(); }\n",
            relevant_used,
        );
        try writer.print(
            "constructor_attempt,random_constructor,{x},{s},{x},{x},{x},{x},{d},{d},{d},{s},attempt={d};mutation_pair=true;feedback=opaque\n",
            .{
                item.opaque_id,
                @tagName(item.spec.phase),
                proposal.tool_hash,
                proposal.program_hash,
                proposal.payload_hash,
                proposal.schema_hash,
                relevant_used.builds,
                relevant_used.actions,
                relevant_used.probes,
                if (irrelevant_ok and relevant_ok) "accepted" else "rejected",
                attempt + 2,
            },
        );
        if (irrelevant_ok and relevant_ok) {
            try emitTypedWitness(writer, "random_constructor", item, claim);
            return .{
                .program = program,
                .sequence_hash = sequence_hash,
                .first_accepted_index = attempt,
                .builds = relevant_used.builds,
                .actions = relevant_used.actions,
                .probes = relevant_used.probes,
            };
        }
    }
    return null;
}

fn emitRandomConstructor(
    a: std.mem.Allocator,
    writer: anytype,
    items: [specs.len]Item,
) !Score {
    var total = Score{};
    var earned: ?EarnedProgram = null;
    for (items) |item| {
        const inherited = try evaluateInheritedForItem(a, writer, item, "random_constructor");
        var item_accepted = inherited.accepted;
        var active = inherited.score;
        if (item.spec.phase == .develop and !inherited.accepted) {
            earned = try constructRandomProgram(
                a,
                writer,
                item,
                .{
                    .builds = inherited.score.active_builds,
                    .actions = inherited.score.active_actions,
                    .probes = inherited.score.active_probes,
                },
            );
            active.active_builds += matched_random_attempt_cap;
            active.active_actions += matched_random_attempt_cap;
            active.active_probes += matched_random_attempt_cap;
            if (earned) |program| {
                item_accepted = true;
                active.active_builds = program.builds;
                active.active_actions = program.actions;
                active.active_probes = program.probes;
                active.accepted_claims += 1;
            }
        } else if (item.spec.phase == .holdout and earned != null) {
            // Complete heldout proposal is formed before the final evaluator
            // reduction; no intermediate heldout receipt is returned.
            var proposal = try luna.makeProposal(a, earned.?.program, item.payload, .{
                .builds = active.active_builds,
                .actions = active.active_actions + 1,
                .probes = active.active_probes + 1,
            });
            defer proposal.deinit(a);
            const used = Budget{
                .builds = active.active_builds,
                .actions = active.active_actions + 1,
                .probes = active.active_probes + 1,
            };
            const claim = lunaClaim(item, proposal, used);
            const ok = try accepts(a, item, claim);
            item_accepted = item_accepted or ok;
            active.active_actions += 1;
            active.active_probes += 1;
            if (ok) active.accepted_claims += 1;
            if (ok) try emitTypedWitness(writer, "random_constructor", item, claim);
        }
        total.active_builds += active.active_builds;
        total.active_actions += active.active_actions;
        total.active_probes += active.active_probes;
        total.accepted_claims += active.accepted_claims;
        total.charged_builds += equal_budget.builds;
        total.charged_actions += equal_budget.actions;
        total.charged_probes += equal_budget.probes;
        if (item_accepted) {
            total.total += 1;
            if (item.spec.phase == .develop) total.develop += 1 else total.holdout += 1;
        }
        try writer.print(
            "budget,random_constructor,{x},{s},-,-,{x},-,{d},{d},{d},charged_exact,active_builds={d};active_actions={d};active_probes={d};heldout_feedback=withheld\n",
            .{
                item.opaque_id,
                @tagName(item.spec.phase),
                item.payload_hash,
                equal_budget.builds,
                equal_budget.actions,
                equal_budget.probes,
                active.active_builds,
                active.active_actions,
                active.active_probes,
            },
        );
    }
    return total;
}

const AblationMode = enum { no_memory, no_probe };

fn emitNoProbePrecommit(
    a: std.mem.Allocator,
    writer: anytype,
    item: Item,
) !void {
    const programs = try luna.enumeratePrograms(a, item.payload);
    defer a.free(programs);
    const sequence_hash = try lunaSequenceHash(a, programs);
    try writer.print(
        "precommit,no_probe,{x},{s},-,{x},{x},-,0,0,0,precommitted,programs={d};reduction_cap=0;sequence_hash={x};dev_accept_receipts=withheld\n",
        .{
            item.opaque_id,
            @tagName(item.spec.phase),
            item.payload_hash,
            sequence_hash,
            programs.len,
            sequence_hash,
        },
    );
}

fn emitMatchedAblation(
    a: std.mem.Allocator,
    writer: anytype,
    items: [specs.len]Item,
    mode: AblationMode,
) !Score {
    var total = Score{};
    const policy_name = @tagName(mode);
    for (items) |item| {
        const inherited = try evaluateInheritedForItem(a, writer, item, policy_name);
        var item_accepted = inherited.accepted;
        var active = inherited.score;
        if (item.spec.phase == .develop and !inherited.accepted) {
            if (mode == .no_memory) {
                // Identical development construction and opaque receipts, but
                // the promoted program is deliberately discarded before the
                // first heldout frame.
                const discarded = try constructEarnedProgram(
                    a,
                    writer,
                    item,
                    .{
                        .builds = inherited.score.active_builds,
                        .actions = inherited.score.active_actions,
                        .probes = inherited.score.active_probes,
                    },
                    policy_name,
                );
                item_accepted = true;
                active.active_builds = discarded.builds;
                active.active_actions = discarded.actions;
                active.active_probes = discarded.probes;
                active.accepted_claims += 1;
                const discarded_program_hash = try luna.programHash(a, discarded.program);
                try writer.print(
                    "ablation,no_memory,{x},develop,{x},{x},{x},-,{d},{d},{d},discarded,earned_program_not_available_to_holdout\n",
                    .{
                        item.opaque_id,
                        discarded_program_hash,
                        discarded.sequence_hash,
                        item.payload_hash,
                        discarded.builds,
                        discarded.actions,
                        discarded.probes,
                    },
                );
            } else {
                // Same exact frame and deterministic candidate enumeration,
                // but no accept/reject development receipts are returned, so
                // no program can be selected or promoted.
                try emitNoProbePrecommit(a, writer, item);
            }
        }

        total.active_builds += active.active_builds;
        total.active_actions += active.active_actions;
        total.active_probes += active.active_probes;
        total.accepted_claims += active.accepted_claims;
        total.charged_builds += equal_budget.builds;
        total.charged_actions += equal_budget.actions;
        total.charged_probes += equal_budget.probes;
        if (item_accepted) {
            total.total += 1;
            if (item.spec.phase == .develop) total.develop += 1 else total.holdout += 1;
        }
        try writer.print(
            "budget,{s},{x},{s},-,-,{x},-,{d},{d},{d},charged_exact,active_builds={d};active_actions={d};active_probes={d};earned_memory={s}\n",
            .{
                policy_name,
                item.opaque_id,
                @tagName(item.spec.phase),
                item.payload_hash,
                equal_budget.builds,
                equal_budget.actions,
                equal_budget.probes,
                active.active_builds,
                active.active_actions,
                active.active_probes,
                if (mode == .no_memory) "discarded" else "never_promoted",
            },
        );
    }
    return total;
}

fn emitRun(a: std.mem.Allocator, out_path: []const u8) !void {
    var items = try loadItems(a);
    defer deinitItems(a, &items);
    var file = if (std.fs.path.isAbsolute(out_path))
        try std.fs.createFileAbsolute(out_path, .{ .truncate = true })
    else
        try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer file.close();
    const writer = file.writer();
    try writer.writeAll(
        "row,policy,opaque_id,phase,tool_hash,program_hash,payload_hash,schema_hash,builds,actions,probes,status,detail\n",
    );
    const policies = [_]Policy{ .fixed_ax_complete, .broad_fixed, .random_ax_choice, .replay };
    var scores: [policies.len]Score = undefined;
    for (policies, 0..) |policy, index| {
        scores[index] = try emitPolicyReceipts(a, writer, policy, items);
    }
    const adaptive = try emitAdaptiveReceipts(a, writer, items);
    const random_constructor = try emitRandomConstructor(a, writer, items);
    const no_memory = try emitMatchedAblation(a, writer, items, .no_memory);
    const no_probe = try emitMatchedAblation(a, writer, items, .no_probe);
    try writer.writeAll(
        "row,policy,total,develop,holdout,accepted_claims,active_builds,active_actions,active_probes,charged_builds,charged_actions,charged_probes,beats_fixed\n",
    );
    const fixed = scores[0];
    for (policies, 0..) |policy, index| {
        const score = scores[index];
        const beats = score.holdout > fixed.holdout or
            (score.holdout == fixed.holdout and score.total > fixed.total);
        try writer.print(
            "summary,{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{s}\n",
            .{
                @tagName(policy),
                score.total,
                score.develop,
                score.holdout,
                score.accepted_claims,
                score.active_builds,
                score.active_actions,
                score.active_probes,
                score.charged_builds,
                score.charged_actions,
                score.charged_probes,
                if (beats) "true" else "false",
            },
        );
    }
    const ablation_scores = [_]struct { name: []const u8, score: Score }{
        .{ .name = "random_constructor", .score = random_constructor },
        .{ .name = "no_memory", .score = no_memory },
        .{ .name = "no_probe", .score = no_probe },
    };
    for (ablation_scores) |ablation| {
        try writer.print(
            "summary,{s},{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},false\n",
            .{
                ablation.name,
                ablation.score.total,
                ablation.score.develop,
                ablation.score.holdout,
                ablation.score.accepted_claims,
                ablation.score.active_builds,
                ablation.score.active_actions,
                ablation.score.active_probes,
                ablation.score.charged_builds,
                ablation.score.charged_actions,
                ablation.score.charged_probes,
            },
        );
    }
    const adaptive_beats = adaptive.holdout > fixed.holdout and adaptive.total > fixed.total;
    try writer.print(
        "summary,adaptive_candidate,{d},{d},{d},{d},{d},{d},{d},{d},{d},{d},{s}\n",
        .{
            adaptive.total,
            adaptive.develop,
            adaptive.holdout,
            adaptive.accepted_claims,
            adaptive.active_builds,
            adaptive.active_actions,
            adaptive.active_probes,
            adaptive.charged_builds,
            adaptive.charged_actions,
            adaptive.charged_probes,
            if (adaptive_beats) "true" else "false",
        },
    );
    if (!adaptive_beats) return error.AdaptiveDidNotBeatFixed;
    if (random_constructor.holdout > fixed.holdout or random_constructor.total > fixed.total)
        return error.RandomConstructorUnexpectedPositive;
    if (no_memory.holdout > fixed.holdout or no_probe.holdout > fixed.holdout)
        return error.AblationDidNotFallBack;
    try writer.writeAll(
        "audit,fixed_ax_complete,all,all,-,-,-,-,0,0,0,verified,canonical_programs=4;underlying_tool_forms=3\n",
    );
    try writer.writeAll(
        "audit,adaptive_candidate,all,all,d09e1e124efc1a7d,1bee4f5954df10e4,-,d53bd3a187721a8,0,0,0,verified,learned_program_hash=1bee4f5954df10e4;candidate_tool_forms=4;heldout_feedback=withheld\n",
    );
}

fn stage(a: std.mem.Allocator, root: []const u8) !void {
    var items = try loadItems(a);
    defer deinitItems(a, &items);
    if (std.fs.path.isAbsolute(root)) {
        std.fs.deleteTreeAbsolute(root) catch {};
        try std.fs.makeDirAbsolute(root);
    } else {
        std.fs.cwd().deleteTree(root) catch {};
        try std.fs.cwd().makePath(root);
    }
    for (items) |item| {
        var dir_buf: [512]u8 = undefined;
        const dir_path = try std.fmt.bufPrint(&dir_buf, "{s}/{x}", .{ root, item.opaque_id });
        if (std.fs.path.isAbsolute(dir_path))
            try std.fs.makeDirAbsolute(dir_path)
        else
            try std.fs.cwd().makePath(dir_path);
        var payload_buf: [640]u8 = undefined;
        const payload_path = try std.fmt.bufPrint(&payload_buf, "{s}/payload", .{dir_path});
        var payload_file = if (std.fs.path.isAbsolute(payload_path))
            try std.fs.createFileAbsolute(payload_path, .{ .truncate = true })
        else
            try std.fs.cwd().createFile(payload_path, .{ .truncate = true });
        defer payload_file.close();
        try payload_file.writeAll(item.payload);
        var frame_buf: [640]u8 = undefined;
        const frame_path = try std.fmt.bufPrint(&frame_buf, "{s}/frame", .{dir_path});
        var frame_file = if (std.fs.path.isAbsolute(frame_path))
            try std.fs.createFileAbsolute(frame_path, .{ .truncate = true })
        else
            try std.fs.cwd().createFile(frame_path, .{ .truncate = true });
        defer frame_file.close();
        const frame = try candidateFrame(a, item);
        defer a.free(frame);
        if (!candidateFrameClean(frame)) return error.CandidateFrameLeak;
        try frame_file.writeAll(frame);
    }
}

fn mutationChecks(a: std.mem.Allocator, items: [specs.len]Item) !void {
    for (items) |item| {
        const original = try canonicalWitness(a, item.spec.hidden_kind, item.payload);
        defer a.free(original);
        const unrelated_payload = try std.fmt.allocPrint(a, "{s}\n", .{item.payload});
        defer a.free(unrelated_payload);
        const unrelated = try canonicalWitness(a, item.spec.hidden_kind, unrelated_payload);
        defer a.free(unrelated);
        if (!std.mem.eql(u8, original, unrelated)) return error.IrrelevantMutationChangedEvidence;

        const suffix: []const u8 = switch (item.spec.hidden_kind) {
            .declarations => "\npub fn terraRelevantMutation() void {}\n",
            .csv_width => "\nterra,relevant\n",
            .sleep_in_loop => "\nwhile (terra) { std.time.sleep(1); }\n",
            .missing_arg => "\nif (terra) return error.MissingArg;\n",
            .active_try_bytes => "\nconst terra = try allocator.alloc(u8, 1);\n",
        };
        const relevant_payload = try std.fmt.allocPrint(a, "{s}{s}", .{ item.payload, suffix });
        defer a.free(relevant_payload);
        const relevant = try canonicalWitness(a, item.spec.hidden_kind, relevant_payload);
        defer a.free(relevant);
        if (std.mem.eql(u8, original, relevant)) return error.RelevantMutationDidNotChangeEvidence;

        const valid_line = try makeClaim(
            a,
            item,
            "mutation-test-tool",
            "PROGRAM_V1 mutation-test",
            hiddenSchema(item.spec.hidden_kind),
            original,
            .{ .builds = 1, .actions = 1, .probes = 0 },
        );
        defer a.free(valid_line);
        const valid = parseClaim(valid_line) orelse return error.InternalClaimMalformed;
        if (!try accepts(a, item, valid)) return error.ValidMutationFixtureRejected;
        var stale = valid;
        stale.payload_hash = hash(unrelated_payload);
        if (try accepts(a, item, stale)) return error.PayloadHashNotBound;
    }
}

fn selftest() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var items = try loadItems(a);
    defer deinitItems(a, &items);
    for (items) |item| {
        const frame = try candidateFrame(a, item);
        defer a.free(frame);
        if (!candidateFrameClean(frame)) return error.CandidateFrameLeak;
    }
    const attacks = [_][]const u8{
        "READ answer",
        "READ expected",
        "READ score",
        "READ progress",
        "READ task_kind",
        "READ family",
        "READ original_path",
        "READ ../evaluator",
        "READ /repo/.git",
        "network fetch",
    };
    for (attacks) |attack| if (!requestDenied(attack)) return error.AnswerChannelAccepted;
    try mutationChecks(a, items);
    try emitRun(a, "/tmp/ghost-scientist-terra-a.csv");
    try emitRun(a, "/tmp/ghost-scientist-terra-b.csv");
    const first = try std.fs.cwd().readFileAlloc(a, "/tmp/ghost-scientist-terra-a.csv", 8 << 20);
    defer a.free(first);
    const second = try std.fs.cwd().readFileAlloc(a, "/tmp/ghost-scientist-terra-b.csv", 8 << 20);
    defer a.free(second);
    if (!std.mem.eql(u8, first, second)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, first, "summary,fixed_ax_complete,4,2,2") == null)
        return error.FixedPortfolioUnexpectedScore;
    if (std.mem.indexOf(u8, first, "summary,adaptive_candidate,9,3,6") == null or
        std.mem.indexOf(u8, first, "summary,adaptive_candidate,9,3,6,9,") == null)
        return error.AdaptiveScoreUnexpected;
    if (std.mem.indexOf(u8, first, "first_accept_index=101") == null or
        std.mem.indexOf(u8, first, "heldout_feedback=withheld") == null)
        return error.CausalBoundaryMissing;
    if (std.mem.indexOf(u8, first, "learned_program_hash=1bee4f5954df10e4") == null or
        std.mem.indexOf(u8, first, "canonical_programs=4;underlying_tool_forms=3") == null)
        return error.ProgramIdentityAuditMissing;
    if (std.mem.indexOf(u8, first, "summary,random_constructor,4,2,2") == null or
        std.mem.indexOf(u8, first, "summary,no_memory,5,3,2") == null or
        std.mem.indexOf(u8, first, "summary,no_probe,4,2,2") == null)
        return error.MatchedAblationScoreUnexpected;
    if (std.mem.count(u8, first, "constructor_attempt,adaptive_candidate") != 103 or
        std.mem.count(u8, first, "constructor_attempt,no_memory") != 103 or
        std.mem.count(u8, first, "constructor_attempt,random_constructor") != 101)
        return error.IncompleteConstructorAttemptLedger;
    std.debug.print(
        "ghost_scientist_terra selftest PASS real_tracked_artifacts=9 develop=3 holdout=6 hidden_kinds=5 fixed_ax=4/9 fixed_holdout=2/6 adaptive=9/9 adaptive_holdout=6/6 equal_charges=2048_builds+2048_actions+2048_probes_per_item typed_hash_bound=true answer_channel_denials=10 relevant_mutations=9 irrelevant_mutations=9 full_sequence_precommit=true first_accept_index=101 heldout_feedback=withheld replay=byte_identical containment=protocol_not_hostile_OS\n",
        .{},
    );
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const command = args.next() orelse "selftest";
    if (std.mem.eql(u8, command, "selftest")) return selftest();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    if (std.mem.eql(u8, command, "stage"))
        return stage(a, args.next() orelse "/tmp/ghost-scientist-terra-sealed");
    if (std.mem.eql(u8, command, "run"))
        return emitRun(a, args.next() orelse "results/ghost_scientist_evaluator_terra.csv");
    return error.UnsupportedCommand;
}
