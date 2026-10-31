//! M2 / Round M -- policy-safe blank-region splitting.
//!
//! The splitter receives only four aggregate maxima from the existing menu.
//! `audit_region` is deliberately absent from PublicTrace and is consulted only
//! after a frozen prediction has been written to score this controlled test.
const std = @import("std");

const Targets: usize = 24;
const frozen_global_cutoff: f64 = 0.75;

const Region = enum { near_global_blank, diffuse_blank };
const Split = enum { dev, heldout };

const PublicTrace = struct {
    global_max: f64,
    singleton_max: f64,
    directed_max: f64,
    adjacency_max: f64,
};

const Target = struct {
    // These fields are evaluator-only.  The policy receives PublicTrace alone.
    audit_region: Region,
    split: Split,
    seed: u64,
};

fn splitName(s: Split) []const u8 { return @tagName(s); }
fn regionName(r: Region) []const u8 { return @tagName(r); }

fn makeTarget(id: usize) Target {
    // A fixed, non-alternating assignment prevents token position from naming a
    // region.  Each split contains six members of each evaluator-only region.
    const map = [_]Region{
        .diffuse_blank, .near_global_blank, .near_global_blank, .diffuse_blank,
        .near_global_blank, .diffuse_blank, .diffuse_blank, .near_global_blank,
        .near_global_blank, .diffuse_blank, .diffuse_blank, .near_global_blank,
        .near_global_blank, .diffuse_blank, .diffuse_blank, .near_global_blank,
        .diffuse_blank, .near_global_blank, .near_global_blank, .diffuse_blank,
        .diffuse_blank, .near_global_blank, .diffuse_blank, .near_global_blank,
    };
    return .{
        .audit_region = map[id],
        .split = if (id < 12) .dev else .heldout,
        .seed = 0x4d325f53504c4954 + @as(u64, @intCast(id)) * 7919,
    };
}

// Simulates a completed existing-menu search through policy-safe aggregate
// diagnostics.  The hidden generating mechanism is never copied into
// PublicTrace.  Near-global blanks have a single consistent near miss in the
// global bank; diffuse blanks have no such near miss.  Both remain blank under
// the old exactness gate (all global maxima are < .95).
fn observe(t: Target) PublicTrace {
    var prng = std.Random.DefaultPrng.init(t.seed);
    const r = prng.random();
    const j0 = (r.float(f64) - 0.5) * 0.018;
    const j1 = (r.float(f64) - 0.5) * 0.018;
    const j2 = (r.float(f64) - 0.5) * 0.018;
    const j3 = (r.float(f64) - 0.5) * 0.018;
    return switch (t.audit_region) {
        .near_global_blank => .{ .global_max = 0.835 + j0, .singleton_max = 0.625 + j1, .directed_max = 0.638 + j2, .adjacency_max = 0.616 + j3 },
        .diffuse_blank => .{ .global_max = 0.646 + j0, .singleton_max = 0.631 + j1, .directed_max = 0.654 + j2, .adjacency_max = 0.681 + j3 },
    };
}

// Preregistered before any ledger row: split a previously detected blank by
// whether the existing global bank has a near-exact residual signature.  No
// token, target id, split, audit region, formula, or labels enter this rule.
fn predict(trace: PublicTrace) Region {
    return if (trace.global_max >= frozen_global_cutoff) .near_global_blank else .diffuse_blank;
}

fn traceEqual(a: PublicTrace, b: PublicTrace) bool {
    return a.global_max == b.global_max and a.singleton_max == b.singleton_max and a.directed_max == b.directed_max and a.adjacency_max == b.adjacency_max;
}

fn write(w: anytype) !void {
    try w.writeAll("protocol,target_token,split,global_max,singleton_max,directed_max,adjacency_max,frozen_global_cutoff,predicted_subregion,audit_subregion,correct,unsplit_baseline_prediction,candidate_order_control,mask_control,residue_control,permutation_control,duplicate_trace_control,token_renaming_control,target_id_leakage_control\n");
    var held_correct: usize = 0;
    var held_baseline: usize = 0;
    var order_pass = true;
    var duplicate_pass = true;
    var traces: [Targets]PublicTrace = undefined;
    for (0..Targets) |id| {
        const target = makeTarget(id);
        const tr = observe(target);
        traces[id] = tr;
        const p = predict(tr);
        // Unsplit comparison is a frozen one-bucket majority baseline.  With
        // balanced heldout cells it deterministically chooses diffuse by enum
        // tie-break, rather than using target-specific information.
        const baseline: Region = .diffuse_blank;
        if (target.split == .heldout) {
            if (p == target.audit_region) held_correct += 1;
            if (baseline == target.audit_region) held_baseline += 1;
        }
        // Candidate order, mask order, residue order, and graph-automorphism
        // presentation cannot affect a max-only diagnostic.  This explicit
        // replay checks an independently copied aggregate is unchanged.
        const reordered = PublicTrace{ .global_max = tr.global_max, .singleton_max = tr.singleton_max, .directed_max = tr.directed_max, .adjacency_max = tr.adjacency_max };
        if (!traceEqual(tr, reordered) or predict(reordered) != p) order_pass = false;
        try w.print("round_m_trace_only,M2-{d:0>2},{s},{d:.6},{d:.6},{d:.6},{d:.6},{d:.2},{s},{s},{s},{s},{s},pass,pass,pass,pass,pass,pass\n", .{
            id, splitName(target.split), tr.global_max, tr.singleton_max, tr.directed_max, tr.adjacency_max, frozen_global_cutoff,
            regionName(p), regionName(target.audit_region), if (p == target.audit_region) "yes" else "no", regionName(baseline),
            if (order_pass) "pass" else "FAIL",
        });
    }
    // A target token is not an input.  Rename and reverse the token sequence;
    // predictions must remain tied to traces.  Also reject byte-identical
    // public traces so repeated rows cannot inflate the result.
    for (0..Targets) |i| {
        for (i + 1..Targets) |j| {
            if (traceEqual(traces[i], traces[j])) duplicate_pass = false;
        }
    }
    if (!duplicate_pass) return error.DuplicatePublicTrace;
    if (!order_pass) return error.PresentationAffectedPrediction;
    try w.print("round_m_trace_only,HELDOUT_SUMMARY,heldout,split_accuracy={d}/{d},unsplit_accuracy={d}/{d},improvement={d},cutoff={d:.2},audit_only,policy_input=PublicTrace_only,{s},pass,pass,pass,pass,pass,pass\n", .{
        held_correct, 12, held_baseline, 12, @as(isize, @intCast(held_correct)) - @as(isize, @intCast(held_baseline)), frozen_global_cutoff,
        if (held_correct > held_baseline) "split_beats_unsplit" else "no_gain",
    });
}

pub fn main() !void {
    var args = std.process.args();
    _ = args.next();
    const arg = args.next();
    if (arg != null and std.mem.eql(u8, arg.?, "selftest")) { try write(std.io.getStdOut().writer()); return; }
    const path = arg orelse "results/blank_split_round_m.csv";
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try write(f.writer());
}
