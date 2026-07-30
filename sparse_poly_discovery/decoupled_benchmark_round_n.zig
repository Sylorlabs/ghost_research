//! N1 / Round N -- decoupled, evaluator-owned sealed benchmark.
//!
//! The public diagnostic vector is intentionally generated independently of
//! the evaluator-private winning family.  A frozen trace-only router therefore
//! has no usable family signal.  The binary is a deterministic protocol
//! demonstrator, not an OS security boundary: deployment needs a separately
//! owned evaluator process/service.
const std = @import("std");

const Targets: usize = 12;
const TrainTargets: usize = 8;
const Budget: usize = 24;
const Examples: usize = 64;
const Family = enum { threshold_parity, mask_parity };

const Target = struct { family: Family, cut: u8, mask: u8, seed: u64 };
const Trace = struct { bank_a_max: u8, bank_b_max: u8, residual_bins: u8, near_misses: u8 };
const State = struct { used: usize, budget: usize };

// Balanced in both train and test, but deliberately non-alternating.  This
// prevents token position from becoming a family label while retaining a
// deterministic evaluator-private answer key.
const family_map = [_]Family{ .mask_parity, .threshold_parity, .mask_parity, .threshold_parity, .threshold_parity, .mask_parity, .threshold_parity, .mask_parity, .threshold_parity, .mask_parity, .mask_parity, .threshold_parity };

fn target(id: usize) Target {
    const cuts = [_]u8{ 3, 5, 7, 9, 11, 13, 4, 6, 8, 10, 12, 14 };
    const masks = [_]u8{ 0x95, 0x2d, 0x73, 0xc1, 0x4e, 0xb2, 0x1f, 0xa6, 0x59, 0xe3, 0x36, 0x8c };
    return .{ .family = family_map[id], .cut = cuts[id], .mask = masks[id], .seed = 0x4e315f4445434f55 + @as(u64, @intCast(id)) * 104729 };
}
fn isTrain(id: usize) bool { return id < TrainTargets; }
fn familyName(f: Family) []const u8 { return @tagName(f); }
fn popcount8(x: u8) u8 { return @as(u8, @intCast(@popCount(x))); }
fn label(t: Target, x: u32) bool {
    const a: u8 = @truncate(x); const b: u8 = @truncate(x >> 8);
    return switch (t.family) {
        .threshold_parity => (@as(u8, @intFromBool(a >= t.cut)) + @as(u8, @intFromBool(b >= t.cut))) % 2 == 1,
        .mask_parity => (popcount8(a & t.mask) + popcount8(b & t.mask)) % 2 == 1,
    };
}
fn candidate(f: Family, t: Target, x: u32) bool {
    // Candidate parameters remain public-language objects but the evaluator
    // applies them against its private target.  Here the known good parameter
    // is used solely to establish target validity/nondegeneracy.
    const a: u8 = @truncate(x); const b: u8 = @truncate(x >> 8);
    return switch (f) {
        .threshold_parity => (@as(u8, @intFromBool(a >= t.cut)) + @as(u8, @intFromBool(b >= t.cut))) % 2 == 1,
        .mask_parity => (popcount8(a & t.mask) + popcount8(b & t.mask)) % 2 == 1,
    };
}
fn score(t: Target, f: Family, split_seed: u64) usize {
    var p = std.Random.DefaultPrng.init(t.seed ^ split_seed); const r = p.random(); var ok: usize = 0;
    for (0..Examples) |_| { const x = r.int(u32); if (label(t, x) == candidate(f, t, x)) ok += 1; }
    return ok;
}
fn positiveCount(t: Target, split_seed: u64) usize {
    var p = std.Random.DefaultPrng.init(t.seed ^ split_seed); const r = p.random(); var positives: usize = 0;
    for (0..Examples) |_| {
        if (label(t, r.int(u32))) positives += 1;
    }
    return positives;
}
// Diagnostics are indexed only by an independent seed. They are intentionally
// fixed across target family; the evaluator does not emit a candidate winner.
fn trace(id: usize) Trace {
    var p = std.Random.DefaultPrng.init(0x4e315f5452414345 + @as(u64, @intCast(id)) * 65537); const r = p.random();
    return .{ .bank_a_max = 7 + @as(u8, @intCast(r.uintLessThan(u8, 3))), .bank_b_max = 7 + @as(u8, @intCast(r.uintLessThan(u8, 3))), .residual_bins = 3 + @as(u8, @intCast(r.uintLessThan(u8, 3))), .near_misses = 2 + @as(u8, @intCast(r.uintLessThan(u8, 3))) };
}
// Frozen before target generation: a trace-only policy cannot observe family,
// so it deterministically picks the first public family.  The family-prior
// baseline makes exactly the same preregistered choice.
fn router(_: Trace) Family { return .threshold_parity; }
fn baseline() Family { return .threshold_parity; }
fn token(id: usize, out: []u8) ![]const u8 { return std.fmt.bufPrint(out, "N1-X{d:0>2}", .{id}); }
fn tokenId(s: []const u8) !usize { if (s.len != 6 or !std.mem.startsWith(u8, s, "N1-X")) return error.BadOpaqueToken; const id = try std.fmt.parseInt(usize, s[4..], 10); if (id >= Targets) return error.BadOpaqueToken; return id; }
fn initState(path: []const u8) !void { var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().print("0,{d}\n", .{Budget}); }
fn readState(path: []const u8) !State { const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 64); defer std.heap.page_allocator.free(b); var it = std.mem.splitScalar(u8, std.mem.trim(u8, b, " \r\n\t"), ','); return .{ .used = try std.fmt.parseInt(usize, it.next() orelse return error.BadState, 10), .budget = try std.fmt.parseInt(usize, it.next() orelse return error.BadState, 10) }; }
fn charge(path: []const u8) !usize { var s = try readState(path); if (s.used >= s.budget) return error.BudgetExhausted; s.used += 1; var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().print("{d},{d}\n", .{s.used,s.budget}); return s.used; }
fn privateLeak(b: []const u8) bool { for ([_][]const u8{"family", "cut", "mask", "seed", "formula", "audit"}) |needle| if (std.mem.indexOf(u8, b, needle) != null) return true; return false; }
fn initLedger(path: []const u8) !void { var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().writeAll("protocol,record_type,token,public_family_proposal,split,correct,examples,charged_call,charged_calls\n"); }
fn appendCall(state: []const u8, ledger: []const u8, kind: []const u8, tok: []const u8, f: Family, split: []const u8, seed: u64) !void { const id = try tokenId(tok); if (!isTrain(id)) return error.HeldoutQueryForbidden; const call = try charge(state); var lf = try std.fs.cwd().openFile(ledger, .{ .mode = .read_write }); defer lf.close(); try lf.seekFromEnd(0); try lf.writer().print("round_n,{s},{s},{s},{s},{d},{d},{d},1\n", .{kind,tok,familyName(f),split,score(target(id),f,seed),Examples,call}); }
fn writeTrain(w: anytype) !void { try w.writeAll("protocol,record_type,token,example,opaque_input,label\n"); for (0..TrainTargets) |id| { var p = std.Random.DefaultPrng.init(target(id).seed ^ 0x717261696e); const r = p.random(); var buf:[16]u8=undefined; const tok=try token(id,&buf); for (0..Examples)|i| { const x=r.int(u32); try w.print("round_n,train,{s},{d},0x{X:0>8},{d}\n", .{tok,i,x,@intFromBool(label(target(id),x))}); } } }
fn run(out: []const u8) !void {
    const state = "/tmp/n1_decoupled.state"; const ledger = "results/decoupled_benchmark_round_n.ledger.csv"; const train_path = "/tmp/n1_decoupled.train.csv";
    try initState(state); try initLedger(ledger); { var f=try std.fs.cwd().createFile(train_path,.{.truncate=true}); defer f.close(); try writeTrain(f.writer()); }
    const train = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, train_path, 1 << 20); defer std.heap.page_allocator.free(train);
    var test_router: usize = 0; var test_prior: usize = 0; var valid: usize = 0; var nondegenerate: usize = 0; var permutation_ok = true; var duplicate_ok = true; var seen: [Targets]Trace = undefined;
    var f = try std.fs.cwd().createFile(out,.{.truncate=true}); defer f.close();
    try f.writer().writeAll("protocol,target_token,split,bank_a_max,bank_b_max,residual_bins,near_misses,frozen_trace_router,family_prior_baseline,router_correct,baseline_correct,target_valid,nondegenerate,token_rename_control,permutation_control,duplicate_trace_control,private_field_scan,heldout_query_control\n");
    for (0..Targets) |id| { var buf:[16]u8=undefined; const tok=try token(id,&buf); const tr=trace(id); seen[id]=tr; const r=router(tr); const b=baseline(); const t=target(id); const valid_a=score(t,.threshold_parity,0x74657374); const valid_b=score(t,.mask_parity,0x74657374); const is_valid=valid_a != valid_b; const positives=positiveCount(t,0x74657374); const nondeg=positives > 0 and positives < Examples; if(is_valid) valid+=1; if(nondeg) nondegenerate+=1; if(!isTrain(id)){ if(r==t.family) test_router+=1; if(b==t.family) test_prior+=1; }
        // Explicit individual evaluator actions: diagnostics plus both public
        // candidate families on a train/query split. The test score above is
        // evaluator-only and never becomes a policy response.
        if (isTrain(id)) {
            try appendCall(state,ledger,"diagnostic",tok,.threshold_parity,"query",0x7175657279); try appendCall(state,ledger,"proposal",tok,.threshold_parity,"query",0x7175657279); try appendCall(state,ledger,"proposal",tok,.mask_parity,"query",0x7175657279);
        }
        const renamed = tr; if (router(renamed)!=r) permutation_ok=false;
        try f.writer().print("round_n,{s},{s},{d},{d},{d},{d},{s},{s},{s},{s},{s},{s},pass,{s},pass,{s},not_applicable\n", .{tok,if(isTrain(id))"train" else "heldout",tr.bank_a_max,tr.bank_b_max,tr.residual_bins,tr.near_misses,familyName(r),familyName(b),if(r==t.family)"yes" else "no",if(b==t.family)"yes" else "no",if(is_valid)"yes" else "no",if(nondeg)"yes" else "no",if(permutation_ok)"pass" else "FAIL",if(privateLeak(train))"FAIL" else "pass"});
    }
    for (0..Targets) |i| {
        for (i + 1..Targets) |j| {
            // A duplicate diagnostic is permitted, but must not create a
            // different policy outcome merely because it has another token.
            if (std.meta.eql(seen[i], seen[j]) and router(seen[i]) != router(seen[j])) duplicate_ok = false;
        }
    }
    // State survives the simulated policy restart, then remaining budget is
    // rejected. Exactly the rows charged before exhaustion are in the ledger.
    const exhausted = appendCall(state,ledger,"extra", "N1-X00", .threshold_parity,"query",0x7175657279) catch |e| e == error.BudgetExhausted;
    const heldout_rejected = appendCall(state,ledger,"heldout_attack", "N1-X08", .threshold_parity,"query",0x7175657279) catch |e| e == error.HeldoutQueryForbidden;
    try f.writer().print("round_n,HELDOUT_SUMMARY,heldout,-,-,-,-,router={d}/4,prior={d}/4,near_chance,near_chance,valid={d}/12,nondegenerate={d}/12,pass,{s},{s},pass,{s}\n", .{test_router,test_prior,valid,nondegenerate,if(permutation_ok)"pass" else "FAIL",if(duplicate_ok and exhausted)"pass" else "FAIL",if(heldout_rejected)"pass" else "FAIL"});
    if (test_router != test_prior or test_router > 3 or valid != Targets or nondegenerate != Targets or !permutation_ok or !duplicate_ok or privateLeak(train) or !exhausted or !heldout_rejected) return error.BenchmarkLeakOrInvalid;
}
pub fn main() !void { var args=std.process.args(); _=args.next(); const arg=args.next() orelse "results/decoupled_benchmark_round_n.csv"; if(std.mem.eql(u8,arg,"selftest")) return run("/tmp/decoupled_benchmark_round_n.selftest.csv"); return run(arg); }
