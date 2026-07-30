//! L5 / Round L -- independent audit of revised public API and L4.
const std = @import("std");
const L1 = "results/failure_atlas_round_l.csv";
const L2 = "results/blank_region_round_l.csv";
const L3 = "results/sealed_evaluator_round_l.csv";
const API = "results/sealed_evaluator_api_round_l.csv";
const QUERY = "results/sealed_evaluator_api_query_round_l.csv";
const L4 = "results/family_expedition_round_l.csv";
const L2S = "sparse_poly_discovery/blank_region_round_l.zig";
const L3S = "sparse_poly_discovery/sealed_evaluator_round_l.zig";
const L4S = "sparse_poly_discovery/family_expedition_round_l.zig";
fn read(a: std.mem.Allocator, p: []const u8) ![]u8 { return std.fs.cwd().readFileAlloc(a, p, 1 << 20); }
fn has(b: []const u8, s: []const u8) bool { return std.mem.indexOf(u8, b, s) != null; }
fn need(ok: bool) !void { if (!ok) return error.AuditExpectationFailed; }
const Stats = struct { q0: usize = 0, q1: usize = 0, seen0: [80]bool = [_]bool{false} ** 80, seen1: [80]bool = [_]bool{false} ** 80, s0: bool = false, s1: bool = false, represented: bool = false };
fn stats(b: []const u8) !Stats {
    var out = Stats{}; var ls = std.mem.splitScalar(u8, b, '\n'); _ = ls.next() orelse return error.EmptyL4;
    while (ls.next()) |line| { if (line.len == 0) continue; var fs = std.mem.splitScalar(u8, line, ','); var v: [13][]const u8 = undefined; var n: usize = 0; while (fs.next()) |f| { if (n == v.len) return error.BadL4; v[n] = f; n += 1; } if (n != v.len) return error.BadL4;
        if (std.mem.eql(u8, v[1], "extension_query")) { const ix = try std.fmt.parseInt(usize, std.mem.trimLeft(u8, v[12], "canonical="), 10); if (ix >= 80 or !std.mem.eql(u8, v[3], "threshold") or !std.mem.eql(u8, v[10], "1")) return error.BadQuery; if (std.mem.eql(u8, v[2], "L3-00")) { out.q0 += 1; out.seen0[ix] = true; } else if (std.mem.eql(u8, v[2], "L3-01")) { out.q1 += 1; out.seen1[ix] = true; } }
        if (std.mem.eql(u8, v[1], "target_summary") and std.mem.eql(u8, v[2], "L3-00")) out.s0 = std.mem.eql(u8, v[8], "10") and std.mem.eql(u8, v[9], "11") and std.mem.eql(u8, v[10], "412") and std.mem.eql(u8, v[11], "no_strict_win");
        if (std.mem.eql(u8, v[1], "target_summary") and std.mem.eql(u8, v[2], "L3-01")) out.s1 = std.mem.eql(u8, v[8], "12") and std.mem.eql(u8, v[9], "10") and std.mem.eql(u8, v[10], "412") and std.mem.eql(u8, v[11], "strict_win");
        if (std.mem.eql(u8, v[1], "blank_decision") and std.mem.eql(u8, v[2], "L3-02")) out.represented = std.mem.eql(u8, v[8], "12") and std.mem.eql(u8, v[11], "represented");
    } return out;
}
fn full(a: [80]bool) bool { for (a) |x| if (!x) return false; return true; }
fn write(w: anytype, l1: []const u8, l2: []const u8, l3: []const u8, api: []const u8, query: []const u8, l4: []const u8, l2s: []const u8, l3s: []const u8, l4s: []const u8) !void {
    const s = try stats(l4);
    try need(has(l1, "SUMMARY") and has(l2s, "fn detect(t: Trace) bool") and has(l2s, "const k = kinds[id % kinds.len];") and has(l2, "audit_actual_unmapped,audit_kind"));
    try need(has(l3, "public_columns=6") and has(l3s, "not_OS_isolated") and has(api, "policy_token,bank,examples,best_correct,accuracy_milli,charged_calls") and has(query, "policy_token,candidate_kind,a,b,c,examples,correct,accuracy_milli,charged_calls"));
    try need(!has(api, "formula") and !has(api, "mask") and !has(api, "audit") and !has(query, "formula") and !has(query, "mask") and !has(query, "audit"));
    try need(has(l3s, "var p = std.Random.DefaultPrng.init(t.seed);") and has(l3s, "writeTranscript") and has(l4s, "while (charged < BaselineCalls)") and !has(l4, ",padding_query,"));
    try need(s.q0 == 80 and s.q1 == 80 and full(s.seen0) and full(s.seen1) and s.s0 and s.s1 and s.represented);
    try w.writeAll("protocol,component,claim,observed,verdict,detail\n");
    try w.writeAll("round_l_l5,L1,atlas_generalization,controlled_corpus_only,LIMITED,No independent unknown-family claim\n");
    try w.writeAll("round_l_l5,L2,blank_rule_input,four_trace_maxima_only,pass,Detector function is trace-only\n");
    try w.writeAll("round_l_l5,L2,corpus_boundary,audit_columns_and_id_cycled_kinds,LIMITED,Published CSV is not policy-safe and corpus is controlled\n");
    try w.writeAll("round_l_l5,L3,public_API_fields,aggregate_scores_counts_calls_only,pass,Replies contain no formula mask or audit fields\n");
    try w.writeAll("round_l_l5,L3,protocol_sealing,same_user_source_access,NOT_OS_SEALED,Protocol boundary only\n");
    try w.writeAll("round_l_l5,L3,evaluation_independence,transcript_and_query_share_12_seeded_examples,LIMITED,No fresh holdout evaluates an extension\n");
    try w.writeAll("round_l_l5,L4,blank_eligibility,L3_00_and_L3_01_blank_L3_02_represented,pass,Eligibility follows diagnostics\n");
    try w.writeAll("round_l_l5,L4,canonical_coverage,80_unique_candidates_per_blank,pass,Every canonical identity 0_through_79 occurs once per blank token\n");
    try w.writeAll("round_l_l5,L4,outcomes,L3_00_10_of_12_vs_11_of_12_L3_01_12_of_12_vs_10_of_12,pass,One strict exact win only\n");
    try w.writeAll("round_l_l5,L4,cost_accounting,source_pads_80_to_412_CSV_omits_332_padding_queries,LIMITED,Source replay supports total but raw ledger is not per-call complete\n");
    try w.writeAll("round_l_l5,L4,verdict,one_of_two_required_wins,VALID_NEGATIVE,Defined trial; neither positive nor blocked\n");
    try w.writeAll("round_l_l5,VERDICT,revised_API_and_expedition,L4_VALID_NEGATIVE_AUDITED,AUDIT_COMPLETE,Future positive requires fresh sealed split and complete call ledger\n");
}
pub fn main() !void { var g = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = g.deinit(); const a = g.allocator(); var args = std.process.args(); _ = args.next(); const arg = args.next() orelse "results/cartography_audit_round_l.csv"; const out: []const u8 = if (std.mem.eql(u8, arg, "selftest")) "/dev/stdout" else arg;
    const l1 = try read(a, L1); defer a.free(l1); const l2 = try read(a, L2); defer a.free(l2); const l3 = try read(a, L3); defer a.free(l3); const api = try read(a, API); defer a.free(api); const query = try read(a, QUERY); defer a.free(query); const l4 = try read(a, L4); defer a.free(l4); const l2s = try read(a, L2S); defer a.free(l2s); const l3s = try read(a, L3S); defer a.free(l3s); const l4s = try read(a, L4S); defer a.free(l4s);
    const f = if (std.mem.eql(u8, out, "/dev/stdout")) std.io.getStdOut() else try std.fs.cwd().createFile(out, .{ .truncate = true }); defer if (!std.mem.eql(u8, out, "/dev/stdout")) f.close(); try write(f.writer(), l1, l2, l3, api, query, l4, l2s, l3s, l4s); }
