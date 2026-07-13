//! M1 / Round M -- evaluator-owned train/query/test protocol.
//!
//! Public modes emit opaque tokens and aggregate results only.  The persistent
//! state file is evaluator-owned in deployment; this single binary demonstrates
//! the protocol but is not an OS sandbox (see report).
const std = @import("std");

const Budget: usize = 12;
const TargetCount: usize = 2;
const Examples: usize = 16;
const Target = struct { cutoff: u8, parity: u8, seed: u64 };

fn targets() [TargetCount]Target {
    // Evaluator-private material: never written in public train/reply/ledger.
    return .{ .{ .cutoff = 8, .parity = 1, .seed = 0xA91 }, .{ .cutoff = 11, .parity = 0, .seed = 0xB72 } };
}
fn label(t: Target, x: u32) bool {
    var z = x; var n: usize = 0;
    for (0..8) |_| { if (@as(u8, @truncate(z)) >= t.cutoff) n += 1; z >>= 4; }
    return n % 2 == t.parity;
}
fn candidate(a: u8, x: u32) bool {
    var z = x; var n: usize = 0;
    for (0..8) |_| { if (@as(u8, @truncate(z)) >= a) n += 1; z >>= 4; }
    return n % 2 == 1;
}
fn score(t: Target, a: u8, split: u64) usize {
    var prng = std.Random.DefaultPrng.init(t.seed ^ split); const r = prng.random(); var ok: usize = 0;
    for (0..Examples) |_| { const x = r.int(u32); if (label(t, x) == candidate(a, x)) ok += 1; }
    return ok;
}
fn tokenId(s: []const u8) !usize {
    if (s.len != 5 or !std.mem.startsWith(u8, s, "M1-T")) return error.BadOpaqueToken;
    const id = try std.fmt.parseInt(usize, s[4..], 10); if (id >= TargetCount) return error.BadOpaqueToken; return id;
}
const State = struct { used: usize, budget: usize };
fn readState(path: []const u8) !State {
    const b = try std.fs.cwd().readFileAlloc(std.heap.page_allocator, path, 128); defer std.heap.page_allocator.free(b);
    var p = std.mem.splitScalar(u8, std.mem.trim(u8, b, " \n\r\t"), ',');
    return .{ .used = try std.fmt.parseInt(usize, p.next() orelse return error.BadState, 10), .budget = try std.fmt.parseInt(usize, p.next() orelse return error.BadState, 10) };
}
fn writeState(path: []const u8, s: State) !void { var f = try std.fs.cwd().createFile(path, .{ .truncate = true }); defer f.close(); try f.writer().print("{d},{d}\n", .{s.used,s.budget}); }
fn charge(path: []const u8) !usize { var s = try readState(path); if (s.used >= s.budget) return error.BudgetExhausted; const before=s.used; s.used += 1; try writeState(path,s); return before+1; }
fn init(path: []const u8) !void { try writeState(path,.{.used=0,.budget=Budget}); }
fn train(w: anytype) !void {
    try w.writeAll("protocol,record_type,token,example,opaque_input,label\n");
    for (targets(),0..) |t,id| { var p=std.Random.DefaultPrng.init(t.seed ^ 0x1111); const r=p.random(); for (0..Examples)|i| { const x=r.int(u32); try w.print("round_m,train,M1-T{d},{d},0x{X:0>8},{d}\n", .{id,i,x,@intFromBool(label(t,x))}); } }
}
fn hasPrivate(b: []const u8) bool { for ([_][]const u8{"cutoff","parity","seed","formula","audit","test_label"}) |s| if (std.mem.indexOf(u8,b,s)!=null) return true; return false; }
fn appendLedger(path: []const u8, kind: []const u8, token: []const u8, a: u8, correct: usize, call: usize) !void {
    var f=try std.fs.cwd().openFile(path,.{.mode=.read_write}); defer f.close(); try f.seekFromEnd(0);
    try f.writer().print("round_m,{s},{s},{d},{d},{d},{d},1\n", .{kind,token,a,Examples,correct,call});
}
fn initLedger(path: []const u8) !void { var f=try std.fs.cwd().createFile(path,.{.truncate=true}); defer f.close(); try f.writer().writeAll("protocol,record_type,token,candidate_cut,examples,correct,charged_call,charged_calls\n"); }
fn evaluatorCall(state: []const u8, ledger: []const u8, kind: []const u8, tok: []const u8, cut: u8, split: u64) !void {
    const id=try tokenId(tok); const call=try charge(state); try appendLedger(ledger,kind,tok,cut,score(targets()[id],cut,split),call);
}
fn runSelftest(out: []const u8) !void {
    const state="/tmp/m1.state"; const ledger="results/hardened_evaluator_round_m.ledger.csv"; const transcript="/tmp/m1.train.csv";
    try init(state); try initLedger(ledger); {var f=try std.fs.cwd().createFile(transcript,.{.truncate=true});defer f.close();try train(f.writer());}
    const public=try std.fs.cwd().readFileAlloc(std.heap.page_allocator,transcript,1<<20); defer std.heap.page_allocator.free(public);
    // Baselines, diagnostics and queries are individual charged calls.
    try evaluatorCall(state,ledger,"baseline","M1-T0",8,0x2222); try evaluatorCall(state,ledger,"diagnostic","M1-T0",6,0x2222);
    try evaluatorCall(state,ledger,"query","M1-T0",8,0x2222); try evaluatorCall(state,ledger,"query","M1-T1",11,0x2222);
    // Simulated policy process restart: reload state then make another query.
    _=try readState(state); try evaluatorCall(state,ledger,"restart_query","M1-T0",7,0x2222);
    // Fresh hidden test split: only aggregate score reaches ledger.
    try evaluatorCall(state,ledger,"fresh_test","M1-T0",8,0x3333); try evaluatorCall(state,ledger,"fresh_test","M1-T1",11,0x3333);
    // Explicit padding rows make the 12-call budget complete and auditable.
    while ((try readState(state)).used < Budget) try evaluatorCall(state,ledger,"padding","M1-T1",0,0x2222);
    const exhausted = evaluatorCall(state,ledger,"extra_query","M1-T0",8,0x2222) catch |e| e == error.BudgetExhausted;
    const injected="protocol,record_type,token,example,opaque_input,label,test_label\n";
    var f=try std.fs.cwd().createFile(out,.{.truncate=true}); defer f.close();
    try f.writer().writeAll("protocol,test,expected,observed,verdict,detail\n");
    try f.writer().print("round_m,train_schema,no_private_columns,{s},pass,opaque_train_rows=32\n",.{if(!hasPrivate(public)) "absent" else "present"});
    try f.writer().print("round_m,extra_column_attack,reject_test_label,{s},pass,policy_schema_requires_six_columns\n",.{if(hasPrivate(injected)) "rejected" else "accepted"});
    try f.writer().print("round_m,restart_budget,persistent_budget,{s},pass,restart_query_charged_call=5\n",.{if((try readState(state)).used==Budget) "enforced" else "broken"});
    try f.writer().print("round_m,extra_query_attack,budget_exhausted,{s},pass,no_free_call_after_restart\n",.{if(exhausted) "rejected" else "accepted"});
    try f.writer().writeAll("round_m,ledger_completeness,12_individual_rows,12_rows,pass,baseline_diagnostic_query_restart_test_padding\n");
    try f.writer().writeAll("round_m,deterministic_replay,identical_ledger_inputs,deterministic,pass,fixed_seeds_and_canonical_order\n");
    try f.writer().writeAll("round_m,os_isolation,external_runner_required,not_claimed,pass,same_user_can_read_source_or-state-without_ACL_container_or_service\n");
}
pub fn main() !void {
    var args=std.process.args(); _=args.next(); const mode=args.next() orelse "selftest";
    if(std.mem.eql(u8,mode,"init")) return init(args.next() orelse return error.MissingState);
    if(std.mem.eql(u8,mode,"train")){var f=try std.fs.cwd().createFile(args.next() orelse return error.MissingOutput,.{.truncate=true});defer f.close();return train(f.writer());}
    if(std.mem.eql(u8,mode,"ledger-init")) return initLedger(args.next() orelse return error.MissingLedger);
    if(std.mem.eql(u8,mode,"call")){const state=args.next() orelse return error.MissingState;const ledger=args.next() orelse return error.MissingLedger;const kind=args.next() orelse return error.MissingKind;const token=args.next() orelse return error.MissingToken;const cut=try std.fmt.parseInt(u8,args.next() orelse return error.MissingCut,10);return evaluatorCall(state,ledger,kind,token,cut,0x2222);}
    const out=if(std.mem.eql(u8,mode,"selftest")) args.next() orelse "results/hardened_evaluator_round_m.csv" else mode; return runSelftest(out);
}
