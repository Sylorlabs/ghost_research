//! Round G / G1: gate-v6 decision-layer audit.
//!
//! Frozen protocol: candidate is a remix iff a greedy, excluded-family,
//! multi-feature classifier reaches COVER on held-out labels.  The decision
//! deliberately consumes the already-measured F3 COVER witnesses; it does
//! not retune feature pools, K, split, or threshold after observing them.
//! This small standalone program makes the proposed rule executable and emits
//! the G1 decision table.  See docs/research/gate_v6_round_g.md for scope.
const std = @import("std");

const COVER: f64 = 0.90;
const R2_GATE: f64 = 0.40;

const Kind = enum { novel, remix };
const Row = struct {
    name: []const u8,
    truth: Kind,
    cover: f64,
    r2: f64,
    k: u8,
    seed: []const u8,
};

// Frozen F3 witnesses, copied verbatim from results/run1_gate_audit_2026_07_11.csv
// `roc` / `roc_r2` rows.  RUN1's `cover` is its *minimum* of the three
// replicated `gate_repro` COVER witnesses (0.9011, 0.8817, 0.8789).  The
// frozen replication rule is deliberately conservative for rejection: a
// replicated target is called a remix only if every replication reaches COVER;
// a one-seed control has its one observed witness.  The remaining controls
// were explicitly secondary one-seed rows in F3.
const rows = [_]Row{
    .{ .name = "RUN1", .truth = .novel, .cover = 0.8789, .r2 = 0.7347, .k = 12, .seed = "3seed_min" },
    .{ .name = "RUN-var2", .truth = .novel, .cover = 0.8686, .r2 = 0.7222, .k = 8, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "RUN-var3", .truth = .remix, .cover = 1.0000, .r2 = 0.5004, .k = 8, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "RUN-var4", .truth = .novel, .cover = 0.6954, .r2 = 0.2778, .k = 8, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "C09", .truth = .novel, .cover = 0.4869, .r2 = -0.0167, .k = 8, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "RATIO1", .truth = .novel, .cover = 0.5069, .r2 = -0.0166, .k = 6, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "MIXMOD1", .truth = .novel, .cover = 0.6560, .r2 = 0.0321, .k = 6, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "REMIX-A", .truth = .remix, .cover = 1.0000, .r2 = 0.7539, .k = 4, .seed = "0xF0235A11CE0FF1CE" },
    .{ .name = "REMIX-B", .truth = .remix, .cover = 0.9983, .r2 = 0.9621, .k = 7, .seed = "0xF0235A11CE0FF1CE" },
};

fn v5Reject(r: Row) bool { return r.r2 >= R2_GATE; }
/// Gate v6: a label is redundant only when the existing, candidate-excluded
/// engine basis can reconstruct the held-out target label to its existing
/// COVER bar. Equality rejects, matching the escape rule (< COVER <= after).
fn v6Reject(r: Row) bool { return r.cover >= COVER; }
fn verdict(reject: bool) []const u8 { return if (reject) "reject_remix" else "admit_novel"; }

pub fn main() !void {
    var v5_correct: usize = 0;
    var v6_correct: usize = 0;
    var v5_false_reject: usize = 0;
    var v6_false_reject: usize = 0;
    var truth_novel: usize = 0;
    var v5_false_admit: usize = 0;
    var v6_false_admit: usize = 0;
    var all_valid = true;
    for (rows) |r| {
        if (!(r.cover >= 0 and r.cover <= 1 and r.k > 0)) all_valid = false;
        const old_reject = v5Reject(r);
        const new_reject = v6Reject(r);
        const want_reject = r.truth == .remix;
        if (old_reject == want_reject) v5_correct += 1;
        if (new_reject == want_reject) v6_correct += 1;
        if (r.truth == .novel) {
            truth_novel += 1;
            if (old_reject) v5_false_reject += 1;
            if (new_reject) v6_false_reject += 1;
        } else {
            if (!old_reject) v5_false_admit += 1;
            if (!new_reject) v6_false_admit += 1;
        }
    }
    if (!all_valid or rows.len != 9 or truth_novel != 6) return error.InvalidFrozenProtocol;

    const path = "../results/gate_v6_round_g.csv";
    const f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    var out = f.writer();
    try out.writeAll("section,seed,target,truth,k,cover_before,r2_old,v5_verdict,v6_verdict,delta,validity\n");
    for (rows) |r| {
        const old_reject = v5Reject(r);
        const new_reject = v6Reject(r);
        try out.print("case,{s},{s},{s},{d},{d:.4},{d:.4},{s},{s},{s},pass\n", .{
            r.seed, r.name, @tagName(r.truth), r.k, r.cover, r.r2,
            verdict(old_reject), verdict(new_reject), if (old_reject == new_reject) "unchanged" else "flip",
        });
    }
    try out.print("summary,-,battery,-,-,-,-,v5_correct={d}/9,v6_correct={d}/9,delta_correct=+{d},protocol=pass\n", .{ v5_correct, v6_correct, v6_correct - v5_correct });
    try out.print("summary,-,novel_false_rejects,-,-,-,-,v5={d}/6,v6={d}/6,delta=-{d},protocol=pass\n", .{ v5_false_reject, v6_false_reject, v5_false_reject - v6_false_reject });
    try out.print("summary,-,remix_false_admits,-,-,-,-,v5={d}/3,v6={d}/3,delta={d},protocol=pass\n", .{ v5_false_admit, v6_false_admit, v6_false_admit - v5_false_admit });
    try std.io.getStdOut().writer().print("gate-v6: {d}/9 correct; v5: {d}/9; false-reject novel: {d}/6 -> {d}/6; CSV {s}\n", .{ v6_correct, v5_correct, v5_false_reject, v6_false_reject, path });
}
