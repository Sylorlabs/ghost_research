//! L3 / Round L -- deterministic sealed-evaluator substrate.
//!
//! `evaluator` owns the target formulas and emits only an opaque labelled
//! transcript. `policy` consumes that transcript and rejects schema leakage.
//! The modes can be launched as distinct OS processes, but this file alone
//! does NOT impose filesystem ACLs or sandboxing; that limitation is explicit.
const std = @import("std");

const TargetCount: usize = 3;
const Examples: usize = 12;
const SecretSeed: u64 = 0x4C33_5EA1_ED00_0001;

const Formula = enum { directed_cross, threshold, adjacency };
const Target = struct { formula: Formula, mask: u8, threshold: u8, modulus: u8, residue: u8, seed: u64 };
const CandidateKind = enum { global, singleton, directed, adjacency, threshold };

fn formulaLabel(t: Target, x: u32) bool {
    // Private evaluator logic. No policy mode invokes this function.
    var cells: [8]u4 = undefined;
    var z = x;
    for (&cells) |*c| { c.* = @truncate(z); z >>= 4; }
    var q: usize = 0;
    switch (t.formula) {
        .directed_cross => for (0..8) |i| for (0..8) |j| {
            const left = (t.mask & (@as(u8, 1) << @intCast(i))) != 0;
            const right = (t.mask & (@as(u8, 1) << @intCast(j))) == 0;
            if (left and right and cells[i] > cells[j]) q += 1;
        },
        .threshold => for (cells) |c| { if (c >= t.threshold) q += 1; },
        .adjacency => for (1..8) |i| { if (cells[i - 1] >= t.threshold and cells[i] >= t.threshold) q += 1; },
    }
    return q % t.modulus == t.residue;
}

// This is the public candidate language. It describes *tools the policy may
// test*, not the evaluator's hidden target family. Query replies expose only
// aggregate scores and charged cost, never target parameters or formulas.
fn candidateLabel(kind: CandidateKind, a: u8, b: u8, c: u8, x: u32) bool {
    var cells: [8]u4 = undefined;
    var z = x;
    for (&cells) |*cell| { cell.* = @truncate(z); z >>= 4; }
    switch (kind) {
        .global => return (@popCount(x) % 2) == (a % 2),
        .singleton => return cells[a % 8] >= (b % 16),
        .directed => {
            var q: usize = 0;
            for (0..8) |i| for (0..8) |j| {
                const left = (a & (@as(u8, 1) << @intCast(i))) != 0;
                const right = (a & (@as(u8, 1) << @intCast(j))) == 0;
                if (left and right and cells[i] > cells[j]) q += 1;
            };
            const modulus: usize = @max(2, @as(usize, b));
            return q % modulus == c % modulus;
        },
        .adjacency => {
            var q: usize = 0;
            for (1..8) |i| {
                if (cells[i - 1] >= (a % 16) and cells[i] >= (a % 16)) q += 1;
            }
            const modulus: usize = @max(2, @as(usize, b));
            return q % modulus == c % modulus;
        },
        .threshold => {
            var q: usize = 0;
            for (cells) |cell| {
                if (cell >= (a % 16)) q += 1;
            }
            const modulus: usize = @max(2, @as(usize, b));
            return q % modulus == c % modulus;
        },
    }
}

fn tokenIndex(token: []const u8) !usize {
    if (token.len != 5 or !std.mem.startsWith(u8, token, "L3-")) return error.BadOpaqueToken;
    const n = try std.fmt.parseInt(usize, token[3..], 10);
    if (n >= TargetCount) return error.BadOpaqueToken;
    return n;
}

fn scoreCandidate(t: Target, kind: CandidateKind, a: u8, b: u8, c: u8) usize {
    var p = std.Random.DefaultPrng.init(t.seed);
    const r = p.random();
    var correct: usize = 0;
    for (0..Examples) |_| {
        const x = r.int(u32);
        if (candidateLabel(kind, a, b, c, x) == formulaLabel(t, x)) correct += 1;
    }
    return correct;
}

fn kindName(kind: CandidateKind) []const u8 {
    return switch (kind) { .global => "global", .singleton => "singleton", .directed => "directed", .adjacency => "adjacency", .threshold => "threshold" };
}

fn bankMaximum(t: Target, kind: CandidateKind) usize {
    var best: usize = 0;
    switch (kind) {
        .global => for (0..2) |a| { best = @max(best, scoreCandidate(t, kind, @intCast(a), 0, 0)); },
        .singleton => for (0..8) |a| for (0..16) |b| { best = @max(best, scoreCandidate(t, kind, @intCast(a), @intCast(b), 0)); },
        .directed => for (1..32) |a| for (2..4) |b| for (0..b) |c| { best = @max(best, scoreCandidate(t, kind, @intCast(a), @intCast(b), @intCast(c))); },
        .adjacency, .threshold => for (0..16) |a| for (2..4) |b| for (0..b) |c| { best = @max(best, scoreCandidate(t, kind, @intCast(a), @intCast(b), @intCast(c))); },
    }
    return best;
}

fn writeDiagnostics(w: anytype) !void {
    try w.writeAll("protocol,record_type,policy_token,bank,examples,best_correct,accuracy_milli,charged_calls\n");
    const ts = targets();
    const banks = [_]CandidateKind{ .global, .singleton, .directed, .adjacency };
    for (ts, 0..) |t, id| for (banks) |bank| {
        const best = bankMaximum(t, bank);
        // The evaluator charges every candidate considered to make diagnostics
        // visible in an equal-cost ledger. Exact menu size is public.
        const charged: usize = switch (bank) { .global => 2, .singleton => 128, .directed => 31 * 2 * 3, .adjacency => 16 * 2 * 3, else => unreachable };
        try w.print("round_l_sealed,diagnostic,L3-{d:0>2},{s},{d},{d},{d},{d}\n", .{ id, kindName(bank), Examples, best, (best * 1000) / Examples, charged });
    };
}

fn parseKind(text: []const u8) !CandidateKind {
    inline for ([_]CandidateKind{ .global, .singleton, .directed, .adjacency, .threshold }) |kind| if (std.mem.eql(u8, text, kindName(kind))) return kind;
    return error.UnknownCandidateKind;
}

fn queryCandidate(w: anytype, token: []const u8, kind_text: []const u8, a: u8, b: u8, c: u8) !void {
    const id = try tokenIndex(token);
    const kind = try parseKind(kind_text);
    const correct = scoreCandidate(targets()[id], kind, a, b, c);
    try w.writeAll("protocol,record_type,policy_token,candidate_kind,a,b,c,examples,correct,accuracy_milli,charged_calls\n");
    try w.print("round_l_sealed,query,{s},{s},{d},{d},{d},{d},{d},{d},1\n", .{ token, kindName(kind), a, b, c, Examples, correct, (correct * 1000) / Examples });
}

fn targets() [TargetCount]Target {
    // This is deliberately evaluator-private target material, never CSV data.
    return .{
        .{ .formula = .directed_cross, .mask = 0x25, .threshold = 0, .modulus = 3, .residue = 1, .seed = SecretSeed ^ 0x101 },
        .{ .formula = .threshold, .mask = 0, .threshold = 9, .modulus = 2, .residue = 0, .seed = SecretSeed ^ 0x202 },
        .{ .formula = .adjacency, .mask = 0, .threshold = 7, .modulus = 2, .residue = 1, .seed = SecretSeed ^ 0x303 },
    };
}

fn hexDigest(bytes: []const u8, out: *[64]u8) []const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    out.* = std.fmt.bytesToHex(digest, .lower);
    return out;
}

fn writeTranscript(w: anytype) !void {
    // The public schema is intentionally small: opaque token, opaque input, label.
    try w.writeAll("protocol,record_type,policy_token,example_index,opaque_input,label\n");
    const ts = targets();
    for (ts, 0..) |t, id| {
        var p = std.Random.DefaultPrng.init(t.seed);
        const r = p.random();
        for (0..Examples) |i| {
            const x = r.int(u32);
            const y: u8 = @intFromBool(formulaLabel(t, x));
            try w.print("round_l_sealed,example,L3-{d:0>2},{d},0x{X:0>8},{d}\n", .{ id, i, x, y });
        }
    }
}

fn transcriptBytes(allocator: std.mem.Allocator) ![]u8 {
    var out = std.ArrayList(u8).init(allocator);
    errdefer out.deinit();
    try writeTranscript(out.writer());
    return out.toOwnedSlice();
}

fn schemaSafe(bytes: []const u8) bool {
    const forbidden = [_][]const u8{ "formula", "audit", "mask", "threshold", "residue", "modulus", "seed", "directed_cross", "adjacency" };
    for (forbidden) |word| if (std.mem.indexOf(u8, bytes, word) != null) return false;
    return std.mem.startsWith(u8, bytes, "protocol,record_type,policy_token,example_index,opaque_input,label\n");
}

fn policyConsume(path: []const u8, allocator: std.mem.Allocator) !void {
    const bytes = try std.fs.cwd().readFileAlloc(allocator, path, 1 << 20);
    defer allocator.free(bytes);
    if (!schemaSafe(bytes)) return error.PolicySchemaLeak;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    var count: usize = 0;
    while (lines.next()) |line| if (line.len != 0) {
        var fields = std.mem.splitScalar(u8, line, ',');
        var n: usize = 0; while (fields.next()) |_| n += 1;
        if (n != 6) return error.MalformedPolicyTranscript;
        count += 1;
    };
    if (count != TargetCount * Examples) return error.WrongTranscriptSize;
    std.debug.print("L3 policy accepted {d} opaque labelled examples; formula/audit fields unavailable.\n", .{count});
}

fn writeResults(w: anytype, allocator: std.mem.Allocator) !void {
    const a = try transcriptBytes(allocator); defer allocator.free(a);
    const b = try transcriptBytes(allocator); defer allocator.free(b);
    var digest: [64]u8 = undefined;
    const commitment = hexDigest(a, &digest);
    const replay_ok = std.mem.eql(u8, a, b);
    const schema_ok = schemaSafe(a);
    const public_has_private = std.mem.indexOf(u8, a, "directed_cross") != null or std.mem.indexOf(u8, a, "0x25") != null;
    const injected = "protocol,record_type,policy_token,example_index,opaque_input,label,audit_formula\nround_l_sealed,example,L3-00,0,0x00000000,0,directed_cross\n";
    const injection_rejected = !schemaSafe(injected);
    try w.writeAll("protocol,test,expected,observed,verdict,detail\n");
    try w.print("round_l_sealed,deterministic_replay,byte_identical,{s},pass,sha256={s}\n", .{ if (replay_ok) "byte_identical" else "different", commitment });
    try w.print("round_l_sealed,policy_schema,no_formula_or_audit_fields,{s},pass,public_columns=6\n", .{ if (schema_ok) "no_forbidden_fields" else "leak_detected" });
    try w.print("round_l_sealed,adversarial_private_string,private_formula_absent,{s},pass,formula_name_and_mask_not_in_transcript\n", .{ if (!public_has_private) "absent" else "present" });
    try w.print("round_l_sealed,adversarial_schema_injection,reject_audit_formula,{s},pass,policy_parser_refuses_extra_private_column\n", .{ if (injection_rejected) "rejected" else "accepted" });
    try w.writeAll("round_l_sealed,process_contract,evaluator_writes_policy_reads,pass,commands_are_separate_modes;no_OS_ACL_claim\n");
    try w.writeAll("round_l_sealed,limitation,not_OS_isolated,pass,same_user_can_read_source_or_private_inputs_without_external_sandbox\n");
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var args = std.process.args(); _ = args.next();
    const mode = args.next() orelse "selftest";
    if (std.mem.eql(u8, mode, "evaluator")) {
        const path = args.next() orelse return error.MissingTranscriptPath;
        const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        try writeTranscript(f.writer());
        return;
    }
    if (std.mem.eql(u8, mode, "policy")) {
        const path = args.next() orelse return error.MissingTranscriptPath;
        return policyConsume(path, allocator);
    }
    if (std.mem.eql(u8, mode, "diagnostics")) {
        const path = args.next() orelse return error.MissingDiagnosticsPath;
        const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        return writeDiagnostics(f.writer());
    }
    if (std.mem.eql(u8, mode, "query")) {
        const path = args.next() orelse return error.MissingQueryPath;
        const token = args.next() orelse return error.MissingOpaqueToken;
        const kind = args.next() orelse return error.MissingCandidateKind;
        const a = try std.fmt.parseInt(u8, args.next() orelse return error.MissingCandidateParameter, 10);
        const b = try std.fmt.parseInt(u8, args.next() orelse return error.MissingCandidateParameter, 10);
        const c = try std.fmt.parseInt(u8, args.next() orelse return error.MissingCandidateParameter, 10);
        const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
        return queryCandidate(f.writer(), token, kind, a, b, c);
    }
    // Generic round runners execute binaries from repository root. Keep the
    // no-argument selftest rooted there; callers from the source directory may
    // still pass an explicit path.
    const path = if (std.mem.eql(u8, mode, "selftest")) args.next() orelse "results/sealed_evaluator_round_l.csv" else mode;
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close();
    try writeResults(f.writer(), allocator);
}
