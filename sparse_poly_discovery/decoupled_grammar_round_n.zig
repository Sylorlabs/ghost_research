//! Round N N4 -- decoupled grammar expansion.
//!
//! The evaluator owns the target implementation.  The policy only sees opaque
//! tokens, a duplicated public diagnostic, frozen old outcome rows, and scores
//! returned for public candidate symbols.  This is a reproducible protocol
//! test, not an OS isolation claim.
const std = @import("std");

const N: usize = 16;
const Train: usize = 8;
const Samples: usize = 64;
const QuerySamples: usize = 16;
const TrainBudget: usize = 9; // three equal-cost arms x (two queries + test)
const HeldoutBudget: usize = 3; // three evaluator-owned fresh scores; no queries allowed
const Kind = enum { join_gt, join_bit };
const Candidate = enum { atom_gt, atom_bit, compose_gt_pair, compose_bit_pair };
const Target = struct { kind: Kind, cut: u8, mask: u8, seed: u64 };
const Trace = struct { a: u8, b: u8, r: u8, n: u8 };

// Every public trace has one target of each hidden kind in each split.  Thus a
// deterministic trace-only family router is exactly 4/8 on the fresh split.
const kinds = [_]Kind{
    .join_gt,.join_bit,.join_bit,.join_gt,.join_gt,.join_bit,.join_bit,.join_gt,
    .join_bit,.join_gt,.join_gt,.join_bit,.join_bit,.join_gt,.join_gt,.join_bit,
};
fn target(id: usize) Target {
    const cuts=[_]u8{3,5,7,9,11,13,4,6,8,10,12,14,2,15,1,16};
    const masks=[_]u8{0x95,0x2d,0x73,0xc1,0x4e,0xb2,0x1f,0xa6,0x59,0xe3,0x36,0x8c,0x55,0xaa,0xf0,0x0f};
    return .{.kind=kinds[id],.cut=cuts[id],.mask=masks[id],.seed=0x4e345f4445434f55+@as(u64,@intCast(id))*104729};
}
fn tr(id: usize) Trace { // ids 0..3 and 8..11 repeat; 4..7 and 12..15 repeat
    const q: u8=@intCast((id%4)+1); return .{.a=7+q,.b=9-q,.r=3+q,.n=2+(q%2)};
}
fn token(id:usize, buf:[]u8)![]const u8 { return std.fmt.bufPrint(buf,"N4-Q{d:0>2}",.{id}); }
fn cname(c:Candidate)[]const u8 { return switch(c){.atom_gt=>"atom_gt",.atom_bit=>"atom_bit",.compose_gt_pair=>"compose_gt_pair",.compose_bit_pair=>"compose_bit_pair"}; }
fn pop(x:u8)u8{return @intCast(@popCount(x));}
fn truth(t:Target,x:u32)bool { const a:u8=@truncate(x); const b:u8=@truncate(x>>8); return switch(t.kind){.join_gt=>((@as(u8,@intFromBool(a>=t.cut))+@as(u8,@intFromBool(b>=t.cut)))%2)==1,.join_bit=>((pop(a&t.mask)+pop(b&t.mask))%2)==1}; }
fn eval(t:Target,c:Candidate,x:u32)bool { const a:u8=@truncate(x); const b:u8=@truncate(x>>8); return switch(c){
    .atom_gt => a>=t.cut,
    .atom_bit => (pop(a&t.mask)%2)==1,
    .compose_gt_pair => ((@as(u8,@intFromBool(a>=t.cut))+@as(u8,@intFromBool(b>=t.cut)))%2)==1,
    .compose_bit_pair => ((pop(a&t.mask)+pop(b&t.mask))%2)==1,
}; }
fn score(t:Target,c:Candidate, seed:u64, count:usize)usize {
    var p = std.Random.DefaultPrng.init(t.seed ^ seed); const r = p.random();
    var ok: usize = 0;
    for (0..count) |_| { const x = r.int(u32); ok += @intFromBool(truth(t, x) == eval(t, c, x)); }
    return ok;
}

const State=struct{used:usize};
fn initState(path:[]const u8)!void{var f=try std.fs.cwd().createFile(path,.{.truncate=true});defer f.close();try f.writer().print("0\n",.{});}
fn charge(path:[]const u8, limit:usize)!usize{const b=try std.fs.cwd().readFileAlloc(std.heap.page_allocator,path,32);defer std.heap.page_allocator.free(b);var s=State{.used=try std.fmt.parseInt(usize,std.mem.trim(u8,b," \n\r\t"),10)};if(s.used>=limit)return error.BudgetExhausted;s.used+=1;var f=try std.fs.cwd().createFile(path,.{.truncate=true});defer f.close();try f.writer().print("{d}\n",.{s.used});return s.used;}

// Frozen public old outcomes.  Each composition is supported twice and is
// strictly better than its underlying atom; no row maps a new trace to a tool.
const History=struct{candidate:Candidate,score:u8};
const history=[_]History{.{.candidate=.atom_gt,.score=33},.{.candidate=.atom_bit,.score=31},.{.candidate=.compose_gt_pair,.score=64},.{.candidate=.compose_bit_pair,.score=64},.{.candidate=.atom_gt,.score=32},.{.candidate=.atom_bit,.score=30},.{.candidate=.compose_gt_pair,.score=64},.{.candidate=.compose_bit_pair,.score=64}};
fn deriveGrammar() [2]Candidate {
    var gt: usize = 0; var bit: usize = 0;
    for (history) |h| switch (h.candidate) {
        .compose_gt_pair => { if (h.score == Samples) gt += 1; },
        .compose_bit_pair => { if (h.score == Samples) bit += 1; },
        else => {},
    };
    if (gt < 2 or bit < 2) @panic("frozen history lacks composition support");
    return .{ .compose_gt_pair, .compose_bit_pair };
}
fn chosenByQueries(t:Target, grammar:[2]Candidate, reverse:bool)Candidate { const a=if(reverse)grammar[1]else grammar[0];const b=if(reverse)grammar[0]else grammar[1];const sa=score(t,a,0x7175657279,QuerySamples);const sb=score(t,b,0x7175657279,QuerySamples);return if(sb>sa)b else a; }
fn fixedChoice(t:Target, reverse:bool)Candidate { const a=if(reverse)Candidate.atom_bit else Candidate.atom_gt;const b=if(reverse)Candidate.atom_gt else Candidate.atom_bit;const sa=score(t,a,0x7175657279,QuerySamples);const sb=score(t,b,0x7175657279,QuerySamples);return if(sb>sa)b else a; }
fn blindChoice(id:usize, reverse:bool)Candidate { const g=deriveGrammar(); return g[(id+@intFromBool(reverse))%2]; }
fn privateLeak(b:[]const u8)bool {for([_][]const u8{"hidden_kind","formula","family_label","mask","cut","seed","test_label","audit"})|n|if(std.mem.indexOf(u8,b,n)!=null)return true;return false;}

fn run(a:std.mem.Allocator,out:[]const u8,reverse:bool)!void {
    _=a; const state="/tmp/n4_decoupled_grammar.state";const g=deriveGrammar();var f=try std.fs.cwd().createFile(out,.{.truncate=true});defer f.close();
    try f.writer().writeAll("protocol,stage,opaque_token,split,trace_a,trace_b,trace_r,trace_n,arm,candidate,returned_score,charged_call,detail\n");
    // The frozen history is recorded, but is not charged against new target budgets.
    for(history,0..)|h,i|try f.writer().print("round_n_n4,frozen_history,history-{d},prior,-,-,-,-,memory,{s},{d},0,raw_public_old_outcome\n",.{i,cname(h.candidate),h.score});
    var grammar_total:usize=0;var fixed_total:usize=0;var blind_total:usize=0;var grammar_a:usize=0;var grammar_b:usize=0;var trace_router:usize=0;
    for(0..N)|loop| { const id=if(reverse)N-1-loop else loop; const t=target(id);const x=tr(id);var buf:[16]u8=undefined;const tok=try token(id,&buf);try initState(state);
        // All arms receive two query calls and one fresh evaluator test call.
        const train = id < Train;
        const arms=[_]struct{name:[]const u8, q0:Candidate,q1:Candidate, chosen:Candidate}{
            .{.name="derived_grammar",.q0=g[0],.q1=g[1],.chosen=if(train) chosenByQueries(t,g,reverse) else g[0]},
            .{.name="frozen_menu",.q0=.atom_gt,.q1=.atom_bit,.chosen=if(train) fixedChoice(t,reverse) else .atom_gt},
            .{.name="blind_composition",.q0=g[0],.q1=g[1],.chosen=blindChoice(id,reverse)},
        };
        for(arms)|arm| {
            if (train) {
                const q0=score(t,arm.q0,0x7175657279,QuerySamples);const c0=try charge(state,TrainBudget);try f.writer().print("round_n_n4,query,{s},train,{d},{d},{d},{d},{s},{s},{d},{d},permitted_train_query\n",.{tok,x.a,x.b,x.r,x.n,arm.name,cname(arm.q0),q0,c0});
                const q1=score(t,arm.q1,0x7175657279,QuerySamples);const c1=try charge(state,TrainBudget);try f.writer().print("round_n_n4,query,{s},train,{d},{d},{d},{d},{s},{s},{d},{d},permitted_train_query\n",.{tok,x.a,x.b,x.r,x.n,arm.name,cname(arm.q1),q1,c1});
            }
            const fresh=score(t,arm.chosen,0x6672657368,Samples);const c2=try charge(state,if(train)TrainBudget else HeldoutBudget);try f.writer().print("round_n_n4,fresh_test,{s},{s},{d},{d},{d},{d},{s},{s},{d},{d},evaluator_owned_fresh_split\n",.{tok,if(train)"train" else "heldout",x.a,x.b,x.r,x.n,arm.name,cname(arm.chosen),fresh,c2});
            if(id>=Train){if(std.mem.eql(u8,arm.name,"derived_grammar")){grammar_total+=@intFromBool(fresh==Samples);if(t.kind==.join_gt)grammar_a+=@intFromBool(fresh==Samples)else grammar_b+=@intFromBool(fresh==Samples);}else if(std.mem.eql(u8,arm.name,"frozen_menu"))fixed_total+=@intFromBool(fresh==Samples)else blind_total+=@intFromBool(fresh==Samples);}
        }
        if(id>=Train)trace_router+=@intFromBool((if(x.a%2==0)Candidate.compose_gt_pair else Candidate.compose_bit_pair)==(if(t.kind==.join_gt)Candidate.compose_gt_pair else Candidate.compose_bit_pair));
        _=charge(state,if(train)TrainBudget else HeldoutBudget) catch |e| { if(e!=error.BudgetExhausted)return e; }; // restart boundary refused
    }
    const positive=grammar_total>fixed_total and grammar_total>blind_total and grammar_a>0 and grammar_b>0 and trace_router==4;
    try f.writer().print("round_n_n4,VERDICT,all,heldout,-,-,-,-,summary,derived_grammar,{d},0,{s}:grammar={d}/8;fixed={d}/8;blind={d}/8;kind_a={d}/4;kind_b={d}/4;trace_router={d}/8\n",.{@intFromBool(positive),if(positive)"CONTROLLED_LIMITED_POSITIVE" else "VALID_NEGATIVE",grammar_total,fixed_total,blind_total,grammar_a,grammar_b,trace_router});
}
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator(); var args = std.process.args(); _ = args.next();
    const arg = args.next() orelse "results/decoupled_grammar_round_n.csv";
    if (std.mem.eql(u8, arg, "selftest")) {
        const x = "/tmp/n4_a.csv"; const y = "/tmp/n4_b.csv";
        try run(a, x, false); try run(a, y, true);
        const bx = try std.fs.cwd().readFileAlloc(a, x, 1 << 20); defer a.free(bx);
        const by = try std.fs.cwd().readFileAlloc(a, y, 1 << 20); defer a.free(by);
        if (privateLeak(bx) or privateLeak(by)) return error.PrivateFieldLeak;
        const expected = "VALID_NEGATIVE:grammar=4/8;fixed=0/8;blind=4/8;kind_a=4/4;kind_b=0/4;trace_router=4/8";
        if (std.mem.indexOf(u8, bx, expected) == null or std.mem.indexOf(u8, by, expected) == null) return error.ResultMismatch;
        std.debug.print("SELFTEST PASS: fresh heldout targets reject queries; trace router=4/8; derived grammar=4/8 ties blind=4/8; persistent split budgets enforced\n", .{});
        return;
    }
    try run(a, arg, false);
}
