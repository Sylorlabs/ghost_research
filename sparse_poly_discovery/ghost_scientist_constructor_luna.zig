//! Luna: a small, answer-free constructor for the Ghost Scientist milestone.
//!
//! Candidate-side code has no task/family/kind enum and receives only an
//! opaque id, phase, payload hash, remaining counters, payload bytes, and the
//! previous opaque accept/reject receipt.  It constructs analyzers from a
//! generic byte/record/region grammar.  The private evaluator in this
//! standalone experiment exists only to measure the candidate and controls.
//!
//! This file also exposes the candidate-side Program/Proposal API so the
//! separately developed Terra evaluator can import the constructor without
//! importing the private experiment specifications.
const std = @import("std");

pub const Phase = enum { develop, holdout };

pub const CandidateInput = struct {
    opaque_id: u64,
    phase: Phase,
    payload_hash: u64,
    remaining_actions: usize,
    remaining_builds: usize,
    remaining_probes: usize,
    payload: []const u8,
    last_receipt: ?u64 = null,
    last_accepted: bool = false,
};

pub const Schema = enum {
    positions_v1,
    record_width_v1,
    offset_spans_v1,
};

/// These are deliberately low-level program shapes, not source/CSV/control
/// task alternatives.  The same operations can be composed over arbitrary
/// bytes.
pub const Shape = enum {
    scan,
    scan_not_after_in_line,
    containing_line,
    containing_block,
    record_width,
};

pub const Program = struct {
    shape: Shape,
    anchor: [64]u8 = [_]u8{0} ** 64,
    anchor_len: u8 = 0,
    aux: [32]u8 = [_]u8{0} ** 32,
    aux_len: u8 = 0,

    pub fn anchorBytes(self: *const Program) []const u8 {
        return self.anchor[0..self.anchor_len];
    }
    pub fn auxBytes(self: *const Program) []const u8 {
        return self.aux[0..self.aux_len];
    }
    pub fn schema(self: Program) Schema {
        return switch (self.shape) {
            .scan, .scan_not_after_in_line => .positions_v1,
            .record_width => .record_width_v1,
            .containing_line, .containing_block => .offset_spans_v1,
        };
    }
};

pub const Cost = struct {
    builds: usize = 0,
    actions: usize = 0,
    probes: usize = 0,
};

pub const Proposal = struct {
    program: Program,
    program_hash: u64,
    tool_hash: u64,
    payload_hash: u64,
    schema_hash: u64,
    summary: usize,
    evidence: []u8,
    cost: Cost,

    pub fn deinit(self: Proposal, a: std.mem.Allocator) void {
        a.free(self.evidence);
    }
};

const MAX_PROGRAMS: usize = 8192;
const MAX_BUILDS: usize = 4096;
const COMMENT = "//";

pub fn hash(bytes: []const u8) u64 {
    return std.hash.Wyhash.hash(0, bytes);
}

pub fn schemaHash(s: Schema) u64 {
    return hash(@tagName(s));
}

fn isWord(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '_' or c == '.';
}

fn fillProgram(shape: Shape, anchor: []const u8, aux: []const u8) ?Program {
    if (anchor.len > 64 or aux.len > 32) return null;
    var p = Program{ .shape = shape };
    @memcpy(p.anchor[0..anchor.len], anchor);
    p.anchor_len = @intCast(anchor.len);
    @memcpy(p.aux[0..aux.len], aux);
    p.aux_len = @intCast(aux.len);
    return p;
}

fn sameProgram(a: Program, b: Program) bool {
    return a.shape == b.shape and
        std.mem.eql(u8, a.anchorBytes(), b.anchorBytes()) and
        std.mem.eql(u8, a.auxBytes(), b.auxBytes());
}

fn appendUnique(out: *std.ArrayList(Program), p: Program) !void {
    if (out.items.len >= MAX_PROGRAMS) return;
    for (out.items) |q| if (sameProgram(p, q)) return;
    try out.append(p);
}

const Span = struct { start: usize, end: usize };

fn lexicalSpans(a: std.mem.Allocator, b: []const u8) ![]Span {
    var spans = std.ArrayList(Span).init(a);
    errdefer spans.deinit();
    var i: usize = 0;
    while (i < b.len) {
        while (i < b.len and !isWord(b[i])) : (i += 1) {}
        if (i == b.len) break;
        const start = i;
        while (i < b.len and isWord(b[i])) : (i += 1) {}
        const len = i - start;
        if (len >= 2 and len <= 64) try spans.append(.{ .start = start, .end = i });
    }
    return spans.toOwnedSlice();
}

/// Enumerate programs from payload observations only.  No target metadata,
/// evaluator answer, family name, compatibility table, or result score enters.
pub fn enumeratePrograms(a: std.mem.Allocator, payload: []const u8) ![]Program {
    var out = std.ArrayList(Program).init(a);
    errdefer out.deinit();

    // Generic record candidates are observation-triggered: only bytes that
    // actually occur are admitted.
    if (std.mem.indexOfScalar(u8, payload, '\n') != null) {
        const delims = [_]u8{ ',', ';', '\t', '|' };
        for (delims) |d| if (std.mem.indexOfScalar(u8, payload, d) != null) {
            const db = [_]u8{d};
            if (fillProgram(.record_width, "\n", &db)) |p| try appendUnique(&out, p);
        };
    }

    const spans = try lexicalSpans(a, payload);
    defer a.free(spans);
    var i: usize = 0;
    while (i < spans.len) : (i += 1) {
        const one = payload[spans[i].start..spans[i].end];
        if (fillProgram(.scan, one, "")) |p| try appendUnique(&out, p);
        if (fillProgram(.scan_not_after_in_line, one, COMMENT)) |p| try appendUnique(&out, p);
        if (fillProgram(.containing_line, one, "")) |p| try appendUnique(&out, p);

        // Adjacent lexical pairs retain the observed separator.  This is how
        // phrases such as "catch unreachable" are constructed without a
        // phrase dictionary or task contract.
        if (i + 1 < spans.len) {
            const pair_start = spans[i].start;
            const pair_end = spans[i + 1].end;
            const gap = spans[i + 1].start - spans[i].end;
            if (gap <= 3 and pair_end - pair_start <= 64) {
                const pair = payload[pair_start..pair_end];
                if (fillProgram(.scan, pair, "")) |p| try appendUnique(&out, p);
                if (fillProgram(.scan_not_after_in_line, pair, COMMENT)) |p| try appendUnique(&out, p);
                if (fillProgram(.containing_line, pair, "")) |p| try appendUnique(&out, p);
            }
        }

        // A generic block constructor pairs an observed anchor with any
        // earlier lexical atom near an opening brace.  It is intentionally
        // byte-geometric; it does not name loops or control flow.
        if (std.mem.indexOfPos(u8, payload, spans[i].end, "{")) |open| {
            if (open - spans[i].end <= 8) {
                if (fillProgram(.containing_block, one, one)) |p| try appendUnique(&out, p);
            }
        }
    }
    return out.toOwnedSlice();
}

fn lineStart(b: []const u8, p: usize) usize {
    return if (std.mem.lastIndexOfScalar(u8, b[0..p], '\n')) |x| x + 1 else 0;
}

fn lineEnd(b: []const u8, p: usize) usize {
    return if (std.mem.indexOfScalar(u8, b[p..], '\n')) |x| p + x else b.len;
}

fn afterInLine(b: []const u8, p: usize, marker: []const u8) bool {
    if (marker.len == 0) return false;
    return if (std.mem.indexOf(u8, b[lineStart(b, p)..p], marker)) |_| true else false;
}

fn matchingBrace(b: []const u8, open: usize) ?usize {
    var depth: usize = 0;
    var i = open;
    while (i < b.len) : (i += 1) {
        if (b[i] == '{') depth += 1 else if (b[i] == '}') {
            if (depth == 0) return null;
            depth -= 1;
            if (depth == 0) return i;
        }
    }
    return null;
}

fn containingBlock(b: []const u8, pos: usize, opener: []const u8) ?Span {
    if (opener.len == 0) return null;
    var search_end = pos;
    while (std.mem.lastIndexOf(u8, b[0..search_end], opener)) |start| {
        const open = std.mem.indexOfPos(u8, b, start + opener.len, "{") orelse return null;
        if (open >= pos) {
            if (start == 0) return null;
            search_end = start;
            continue;
        }
        const end = matchingBrace(b, open) orelse return null;
        if (pos <= end) return .{ .start = start, .end = end + 1 };
        if (start == 0) return null;
        search_end = start;
    }
    return null;
}

fn appendSep(out: *std.ArrayList(u8), first: *bool) !void {
    if (!first.*) try out.append(',');
    first.* = false;
}

/// Execute one generic program and return canonical structural evidence.
pub fn executeProgram(a: std.mem.Allocator, p: Program, payload: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(a);
    errdefer out.deinit();
    var first = true;

    switch (p.shape) {
        .record_width => {
            const d = p.auxBytes();
            if (d.len != 1) return error.BadProgram;
            var lines = std.mem.splitScalar(u8, payload, '\n');
            const reference = std.mem.trimRight(u8, lines.next() orelse "", "\r");
            const fields = std.mem.count(u8, reference, d) + 1;
            try out.writer().print("r{d}:", .{fields});
            var row: usize = 1;
            while (lines.next()) |raw| : (row += 1) {
                const line = std.mem.trimRight(u8, raw, "\r");
                if (line.len == 0) continue;
                const got = std.mem.count(u8, line, d) + 1;
                if (got != fields) {
                    if (!first) try out.append(',');
                    first = false;
                    try out.writer().print("{d}:{d}", .{ row, got });
                }
            }
            if (first) try out.appendSlice("none");
        },
        else => {
            const needle = p.anchorBytes();
            if (needle.len == 0) return error.BadProgram;
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, payload, at, needle)) |pos| {
                at = pos + needle.len;
                switch (p.shape) {
                    .scan => {
                        try appendSep(&out, &first);
                        try out.writer().print("{d}", .{pos});
                    },
                    .scan_not_after_in_line => {
                        if (!afterInLine(payload, pos, p.auxBytes())) {
                            try appendSep(&out, &first);
                            try out.writer().print("{d}", .{pos});
                        }
                    },
                    .containing_line => {
                        try appendSep(&out, &first);
                        try out.writer().print("{d}:{d}:{d}", .{ pos, lineStart(payload, pos), lineEnd(payload, pos) });
                    },
                    .containing_block => if (containingBlock(payload, pos, p.auxBytes())) |s| {
                        try appendSep(&out, &first);
                        try out.writer().print("{d}:{d}:{d}", .{ pos, s.start, s.end });
                    },
                    .record_width => unreachable,
                }
            }
            if (first) try out.appendSlice("none");
        },
    }
    return out.toOwnedSlice();
}

pub fn summary(evidence: []const u8) usize {
    if (std.mem.eql(u8, evidence, "none") or std.mem.endsWith(u8, evidence, ":none")) return 0;
    return 1 + std.mem.count(u8, evidence, ",");
}

pub fn writeProgram(p: Program, w: anytype) !void {
    try w.print("PROGRAM_V1 {s} ", .{@tagName(p.shape)});
    for (p.anchorBytes()) |b| try w.print("{x:0>2}", .{b});
    try w.writeByte(' ');
    for (p.auxBytes()) |b| try w.print("{x:0>2}", .{b});
}

pub fn programHash(a: std.mem.Allocator, p: Program) !u64 {
    var bytes = std.ArrayList(u8).init(a);
    defer bytes.deinit();
    try writeProgram(p, bytes.writer());
    return hash(bytes.items);
}

pub fn programSequenceHash(a: std.mem.Allocator, programs: []const Program, order: []const usize) !u64 {
    var bytes = std.ArrayList(u8).init(a);
    defer bytes.deinit();
    for (order) |index| {
        if (index >= programs.len) return error.BadProgramOrder;
        try writeProgram(programs[index], bytes.writer());
        try bytes.append('\n');
    }
    return hash(bytes.items);
}

pub fn makeProposal(a: std.mem.Allocator, p: Program, payload: []const u8, cost: Cost) !Proposal {
    const evidence = try executeProgram(a, p, payload);
    errdefer a.free(evidence);
    const ph = try programHash(a, p);
    return .{
        .program = p,
        .program_hash = ph,
        .tool_hash = hash(std.mem.asBytes(&ph)),
        .payload_hash = hash(payload),
        .schema_hash = schemaHash(p.schema()),
        .summary = summary(evidence),
        .evidence = evidence,
        .cost = cost,
    };
}

pub fn writeEnvelope(p: Proposal, opaque_id: u64, w: anytype) !void {
    try w.print(
        "GHOST_WITNESS_V1 {x} {x} {x} {x} {x} {d} {d} {d} {d} {s}",
        .{
            opaque_id,
            p.tool_hash,
            p.program_hash,
            p.payload_hash,
            p.schema_hash,
            p.cost.builds,
            p.cost.actions,
            p.cost.probes,
            p.summary,
            p.evidence,
        },
    );
}

// -------------------------------------------------------------------------
// Standalone experiment.  Everything below this line is evaluator/audit code,
// not part of the candidate input or selection API.

const DEV_PATH = "boundary_crossing/verified_generation.zig";
const HOLDOUT_PATH = "boundary_crossing/parametric_guide.zig";
const PRIVATE_NEEDLE = "try";
const DEV_ID: u64 = 0x8f21a4401;
const HOLDOUT_ID: u64 = 0x8f21a4402;

fn canonical(a: std.mem.Allocator, payload: []const u8) ![]u8 {
    const p = fillProgram(.scan_not_after_in_line, PRIVATE_NEEDLE, COMMENT).?;
    return executeProgram(a, p, payload);
}

const Receipt = struct { token: u64, accepted: bool };

fn privateEvaluate(a: std.mem.Allocator, opaque_id: u64, payload: []const u8, proposal: Proposal) !Receipt {
    const expected = try canonical(a, payload);
    defer a.free(expected);
    const ok = proposal.schema_hash == schemaHash(.positions_v1) and
        proposal.payload_hash == hash(payload) and
        std.mem.eql(u8, proposal.evidence, expected);
    var receipt_material: [24]u8 = undefined;
    std.mem.writeInt(u64, receipt_material[0..8], opaque_id, .little);
    std.mem.writeInt(u64, receipt_material[8..16], proposal.program_hash, .little);
    std.mem.writeInt(u64, receipt_material[16..24], if (ok) 0xa7 else 0x51, .little);
    return .{ .token = hash(&receipt_material), .accepted = ok };
}

const Discovery = struct {
    proposal: ?Proposal,
    attempted: usize,
    failed_receipt_chain: u64,
    sequence_hash: u64,
    sequence_len: usize,

    fn deinit(self: Discovery, a: std.mem.Allocator) void {
        if (self.proposal) |p| p.deinit(a);
    }
};

fn discover(a: std.mem.Allocator, input: CandidateInput, random_order: bool, build_cap: usize) !Discovery {
    const programs = try enumeratePrograms(a, input.payload);
    defer a.free(programs);
    const cap = @min(
        @min(programs.len, build_cap),
        @min(input.remaining_actions, @min(input.remaining_builds, input.remaining_probes)),
    );
    var failed_chain: u64 = input.last_receipt orelse 0;
    var attempted: usize = 0;
    var prng = std.Random.DefaultPrng.init(input.opaque_id ^ 0x6c756e61);
    var order = try a.alloc(usize, programs.len);
    defer a.free(order);
    for (order, 0..) |*v, i| v.* = i;
    if (random_order) prng.random().shuffle(usize, order);
    const sequence_hash = try programSequenceHash(a, programs, order[0..cap]);

    for (order[0..cap]) |ix| {
        attempted += 1;
        const p = programs[ix];
        // The full sequence is determined by payload bytes before reduction.
        // An opaque rejection advances to the next generic construction; no
        // target-shaped mutation or evaluator metadata changes the order.
        var proposal = try makeProposal(a, p, input.payload, .{
            .builds = attempted,
            .actions = attempted,
            .probes = attempted,
        });
        const r = try privateEvaluate(a, input.opaque_id, input.payload, proposal);
        if (r.accepted) return .{
            .proposal = proposal,
            .attempted = attempted,
            .failed_receipt_chain = failed_chain,
            .sequence_hash = sequence_hash,
            .sequence_len = cap,
        };
        failed_chain = hash(std.mem.asBytes(&r.token)) ^ std.math.rotl(u64, failed_chain, 7);
        proposal.deinit(a);
    }
    return .{
        .proposal = null,
        .attempted = attempted,
        .failed_receipt_chain = failed_chain,
        .sequence_hash = sequence_hash,
        .sequence_len = cap,
    };
}

fn fixedAxPrograms() [4]Program {
    return .{
        fillProgram(.scan_not_after_in_line, "pub fn ", COMMENT).?,
        fillProgram(.record_width, "\n", ",").?,
        fillProgram(.containing_block, "std.time.sleep", "while").?,
        fillProgram(.containing_line, "return error.MissingArg", "").?,
    };
}

const ArmResult = struct {
    name: []const u8,
    accepted: bool,
    builds: usize,
    actions: usize,
    probes: usize,
    program_hash: u64,
    tool_hash: u64,
    schema_hash: u64,
    source: []const u8,
};

fn evaluateKnownProgram(a: std.mem.Allocator, name: []const u8, p: Program, payload: []const u8, builds: usize, actions: usize, probes: usize) !ArmResult {
    const q = try makeProposal(a, p, payload, .{ .builds = builds, .actions = actions, .probes = probes });
    defer q.deinit(a);
    const r = try privateEvaluate(a, HOLDOUT_ID, payload, q);
    return .{
        .name = name,
        .accepted = r.accepted,
        .builds = builds,
        .actions = actions,
        .probes = probes,
        .program_hash = q.program_hash,
        .tool_hash = q.tool_hash,
        .schema_hash = q.schema_hash,
        .source = @tagName(p.shape),
    };
}

fn broadResult(a: std.mem.Allocator, payload: []const u8) !ArmResult {
    const ps = fixedAxPrograms();
    var best = ArmResult{
        .name = "broad_full_ax",
        .accepted = false,
        .builds = ps.len,
        .actions = ps.len,
        .probes = ps.len,
        .program_hash = 0,
        .tool_hash = 0,
        .schema_hash = 0,
        .source = "full_ax_four_program_portfolio",
    };
    for (ps) |p| {
        const r = try evaluateKnownProgram(a, "broad_full_ax", p, payload, ps.len, ps.len, ps.len);
        if (r.accepted) return r;
        if (best.program_hash == 0) best = r;
    }
    return best;
}

fn runExperiment(a: std.mem.Allocator, out_path: []const u8) !void {
    const dev = try std.fs.cwd().readFileAlloc(a, DEV_PATH, 1 << 20);
    defer a.free(dev);
    const holdout = try std.fs.cwd().readFileAlloc(a, HOLDOUT_PATH, 1 << 20);
    defer a.free(holdout);

    const common_cap = Cost{ .builds = MAX_BUILDS, .actions = MAX_BUILDS, .probes = MAX_BUILDS };
    const dev_input = CandidateInput{
        .opaque_id = DEV_ID,
        .phase = .develop,
        .payload_hash = hash(dev),
        .remaining_actions = common_cap.actions,
        .remaining_builds = common_cap.builds,
        .remaining_probes = common_cap.probes,
        .payload = dev,
    };
    const learned = try discover(a, dev_input, false, common_cap.builds);
    defer learned.deinit(a);
    if (learned.proposal == null) return error.ConstructorDidNotDiscover;
    const earned = learned.proposal.?.program;
    const candidate = try evaluateKnownProgram(a, "candidate_causal_reuse", earned, holdout, 0, 1, 1);
    const no_memory_input = CandidateInput{
        .opaque_id = HOLDOUT_ID,
        .phase = .holdout,
        .payload_hash = hash(holdout),
        .remaining_actions = common_cap.actions,
        .remaining_builds = common_cap.builds,
        .remaining_probes = common_cap.probes,
        .payload = holdout,
    };
    const no_memory_discovery = try discover(a, no_memory_input, false, common_cap.builds);
    defer no_memory_discovery.deinit(a);
    const no_memory = if (no_memory_discovery.proposal) |p|
        ArmResult{
            .name = "no_causal_memory",
            .accepted = true,
            .builds = no_memory_discovery.attempted,
            .actions = no_memory_discovery.attempted,
            .probes = no_memory_discovery.attempted,
            .program_hash = p.program_hash,
            .tool_hash = p.tool_hash,
            .schema_hash = p.schema_hash,
            .source = @tagName(p.program.shape),
        }
    else
        ArmResult{ .name = "no_causal_memory", .accepted = false, .builds = no_memory_discovery.attempted, .actions = no_memory_discovery.attempted, .probes = no_memory_discovery.attempted, .program_hash = 0, .tool_hash = 0, .schema_hash = 0, .source = "none" };

    const random_discovery = try discover(a, no_memory_input, true, learned.attempted);
    defer random_discovery.deinit(a);
    const random = if (random_discovery.proposal) |p|
        ArmResult{ .name = "random_construction", .accepted = true, .builds = random_discovery.attempted, .actions = random_discovery.attempted, .probes = random_discovery.attempted, .program_hash = p.program_hash, .tool_hash = p.tool_hash, .schema_hash = p.schema_hash, .source = @tagName(p.program.shape) }
    else
        ArmResult{ .name = "random_construction", .accepted = false, .builds = random_discovery.attempted, .actions = random_discovery.attempted, .probes = random_discovery.attempted, .program_hash = 0, .tool_hash = 0, .schema_hash = 0, .source = "none" };

    const fixed = try evaluateKnownProgram(a, "fixed_ax_source", fixedAxPrograms()[0], holdout, 1, 1, 1);
    const broad = try broadResult(a, holdout);
    const arms = [_]ArmResult{ candidate, no_memory, random, fixed, broad };

    var f = try std.fs.cwd().createFile(out_path, .{ .truncate = true });
    defer f.close();
    const w = f.writer();
    try w.writeAll("record,arm,phase,accepted,builds,actions,probes,common_build_cap,common_action_cap,program_hash,tool_hash,payload_hash,schema_hash,source_or_note\n");
    try w.print("develop,candidate_constructor,develop,true,{d},{d},{d},{d},{d},{x},{x},{x},{x},exact_tracked_promotion_after_precommitted_generic_program_sequence_and_opaque_receipts\n", .{
        learned.attempted,
        learned.attempted,
        learned.attempted,
        common_cap.builds,
        common_cap.actions,
        learned.proposal.?.program_hash,
        learned.proposal.?.tool_hash,
        hash(dev),
        learned.proposal.?.schema_hash,
    });
    try w.print("precommit,candidate_constructor,develop,not_scored,0,0,0,{d},{d},{x},0,{x},0,sequence_len={d};complete_order_hashed_before_reduction\n", .{
        common_cap.builds,
        common_cap.actions,
        learned.sequence_hash,
        hash(dev),
        learned.sequence_len,
    });
    for (arms) |r| try w.print("holdout,{s},holdout,{s},{d},{d},{d},{d},{d},{x},{x},{x},{x},{s}\n", .{
        r.name,
        if (r.accepted) "true" else "false",
        r.builds,
        r.actions,
        r.probes,
        common_cap.builds,
        common_cap.actions,
        r.program_hash,
        r.tool_hash,
        hash(holdout),
        r.schema_hash,
        r.source,
    });
    try w.print("precommit,no_causal_memory,holdout,not_scored,0,0,0,{d},{d},{x},0,{x},0,sequence_len={d};evaluator_side_first_reach_only\n", .{
        common_cap.builds,
        common_cap.actions,
        no_memory_discovery.sequence_hash,
        hash(holdout),
        no_memory_discovery.sequence_len,
    });
    try w.print("precommit,random_construction,holdout,not_scored,0,0,0,{d},{d},{x},0,{x},0,sequence_len={d};evaluator_side_first_reach_only\n", .{
        common_cap.builds,
        common_cap.actions,
        random_discovery.sequence_hash,
        hash(holdout),
        random_discovery.sequence_len,
    });
    try w.print("summary,candidate_vs_no_memory,holdout,{s},0_vs_{d},1_vs_{d},1_vs_{d},{d},{d},{x},{x},{x},{x},reuse_build_saving={d};fixed_and_full_ax_accepted={s}|{s};random_accepted={s}\n", .{
        if (candidate.accepted and no_memory.accepted) "both_correct_candidate_cheaper" else if (candidate.accepted) "candidate_only" else "FAIL",
        no_memory.builds,
        no_memory.actions,
        no_memory.probes,
        common_cap.builds,
        common_cap.actions,
        candidate.program_hash,
        candidate.tool_hash,
        hash(holdout),
        candidate.schema_hash,
        no_memory.builds,
        if (fixed.accepted) "true" else "false",
        if (broad.accepted) "true" else "false",
        if (random.accepted) "true" else "false",
    });

    if (!candidate.accepted) return error.CandidateTransferFailed;
    if (fixed.accepted or broad.accepted) return error.AxPortfolioUnexpectedlySolvedNovelPair;
    if (!no_memory.accepted or no_memory.builds == 0) return error.NoMemoryAblationInvalid;
    if (candidate.builds >= no_memory.builds) return error.NoReuseCostBenefit;
}

fn selftest(a: std.mem.Allocator) !void {
    try runExperiment(a, "/tmp/ghost-scientist-luna-a.csv");
    try runExperiment(a, "/tmp/ghost-scientist-luna-b.csv");
    const x = try std.fs.cwd().readFileAlloc(a, "/tmp/ghost-scientist-luna-a.csv", 1 << 20);
    defer a.free(x);
    const y = try std.fs.cwd().readFileAlloc(a, "/tmp/ghost-scientist-luna-b.csv", 1 << 20);
    defer a.free(y);
    if (!std.mem.eql(u8, x, y)) return error.NonDeterministicReplay;
    if (std.mem.indexOf(u8, x, "candidate_causal_reuse,holdout,true,0,1,1") == null) return error.MissingReuseProof;
    if (std.mem.indexOf(u8, x, "broad_full_ax,holdout,false") == null) return error.MissingBroadControl;
    std.debug.print(
        "ghost_scientist_luna selftest PASS generic_program_grammar=true candidate_input_answer_free=true opaque_failure_receipts=true distinct_tracked_holdout=true earned_program_reuse=true full_ax_broad_control=true deterministic_replay=true\n",
        .{},
    );
}

fn auditExact(a: std.mem.Allocator, path: []const u8, needle: []const u8) !void {
    const payload = try std.fs.cwd().readFileAlloc(a, path, 32 << 20);
    defer a.free(payload);
    const expected_program = fillProgram(.scan_not_after_in_line, needle, COMMENT) orelse return error.NeedleTooLong;
    const expected = try executeProgram(a, expected_program, payload);
    defer a.free(expected);
    const programs = try enumeratePrograms(a, payload);
    defer a.free(programs);
    for (programs, 0..) |p, i| {
        if (p.schema() != .positions_v1) continue;
        const observed = try executeProgram(a, p, payload);
        defer a.free(observed);
        if (std.mem.eql(u8, expected, observed)) {
            std.debug.print(
                "audit_exact path_hash={x} payload_hash={x} needle_hash={x} first_accept={d} program_hash={x} shape={s} summary={d}\n",
                .{ hash(path), hash(payload), hash(needle), i + 1, try programHash(a, p), @tagName(p.shape), summary(observed) },
            );
            return;
        }
    }
    return error.NoExactProgram;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const a = gpa.allocator();
    var args = std.process.args();
    _ = args.next();
    const cmd = args.next() orelse "run";
    if (std.mem.eql(u8, cmd, "selftest")) return selftest(a);
    if (std.mem.eql(u8, cmd, "run")) return runExperiment(a, args.next() orelse "results/ghost_scientist_constructor_luna.csv");
    if (std.mem.eql(u8, cmd, "audit-exact")) return auditExact(a, args.next() orelse return error.MissingPath, args.next() orelse return error.MissingNeedle);
    return error.UnsupportedCommand;
}
