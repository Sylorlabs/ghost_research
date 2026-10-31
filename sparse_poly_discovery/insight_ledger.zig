// insight_ledger.zig — F6 of Round 2026-07-11b: the residual human-insight bit.
//
// This is a BOOKKEEPING harness, not a search: it does not run any engine, it
// counts and sums ingredients already measured and published in this repo's
// own docs (D5 = wcore/docs/research/auto_curriculum.md, E1 =
// docs/research/repr_expansion.md, E3 = wcore/docs/research/smart_gen.md,
// round-c = wcore/docs/research/conjunction_wall.md). Every ingredient's
// ORIGIN tag (human / machine / unresolved) is grounded in an exact quote or
// number from those docs (see the `.doc_ref` field on each ingredient below;
// the source quotes are reproduced in the .md write-up). The only thing this
// program actually COMPUTES (rather than states) is the arithmetic: summing
// weighted units per method into human/machine/unresolved fractions, and the
// secondary bit-narrowing cross-check from smart_gen.md's own pool-size
// numbers (L2=22345, L3 base cap=1000, len3 pool=3604, winners=2).
//
// Two independent ledgers are computed:
//   (1) MECHANISM ledger (9 units) — the generation/auto-discovery side,
//       applied to the SAME target (the distinct-count wall / noveltyflag
//       stone) across 4 methods: round-c hand-curriculum (pre-arc reference),
//       D5 blind bulk, E3 smart-gen (COVER-fair), F1 prior-selector (pending,
//       not yet landed — reported as such, no numbers fabricated).
//   (2) REPRESENTABILITY ledger (6 units, equal-weight, + a depth-weighted
//       variant) — the family-growth side, applied to E1's mixr -> MIXMOD1
//       solve (the most fully-documented certified new-family solve in E1).
//
// Reproduce: `zig build-exe -O ReleaseFast sparse_poly_discovery/insight_ledger.zig`
// then `./insight_ledger` (no args; deterministic; <1s; writes the CSV).

const std = @import("std");

const Origin = enum {
    human,
    machine,
    unresolved, // required but supplied by neither party (method failed)
    pending, // method not yet landed in this round; nothing measured yet

    fn tag(self: Origin) []const u8 {
        return switch (self) {
            .human => "human",
            .machine => "machine",
            .unresolved => "unresolved",
            .pending => "pending",
        };
    }
};

const Ingredient = struct {
    unit_id: []const u8,
    label: []const u8,
    origin: Origin,
    weight: f64 = 1.0,
    doc_ref: []const u8,
};

// ─────────────────────────────────────────────────────────────────────────
// (1) MECHANISM LEDGER — 9 fixed units decomposing the noveltyflag stone:
//   setup: r?=1;  step: r3=mem[r0];  mem[r0]=r?;  r3=xor(r?,r3);
// Units: {I0 setup opcode, I0 setup operand/register}
//        {I1 load opcode-class, I1 load operand/register-allocation}
//        {I2 store opcode-class, I2 store operand/register-allocation}
//        {same-address relational constraint linking I1/I2}
//        {I3 completing-op opcode, I3 completing-op operand-order+OUT_R-wiring}
// Held IDENTICAL across all 4 methods below so fractions are comparable.
// ─────────────────────────────────────────────────────────────────────────

fn mechUnitsAllHuman() [9]Ingredient {
    // round-c hand-curriculum: the FINISHED S1(membership)->S2(noveltyflag)
    // programs were authored end-to-end by a human and handed to the forge.
    // conjunction_wall.md: "the curriculum's stones were hand-designed from
    // the known distinct-count mechanism." smart_gen.md's structural-diff
    // note pins the hand version's exact registers: flag in r6, xor(r3,r6).
    return .{
        .{ .unit_id = "I0_opcode", .label = "setup instr opcode (load-immediate)", .origin = .human, .doc_ref = "conjunction_wall.md: stones hand-designed" },
        .{ .unit_id = "I0_operand", .label = "setup operand+register (r6, value=1)", .origin = .human, .doc_ref = "smart_gen.md: hand noveltyFlagProg uses r6" },
        .{ .unit_id = "I1_opcode", .label = "load instr opcode-class (read-from-memory)", .origin = .human, .doc_ref = "conjunction_wall.md: S1 membership designed" },
        .{ .unit_id = "I1_operand", .label = "load operand+register alloc (dest r3, addr r0)", .origin = .human, .doc_ref = "conjunction_wall.md: S1 hand-designed" },
        .{ .unit_id = "I2_opcode", .label = "store instr opcode-class (write-to-memory)", .origin = .human, .doc_ref = "conjunction_wall.md: S1 hand-designed" },
        .{ .unit_id = "I2_operand", .label = "store operand+register alloc (value-src r6)", .origin = .human, .doc_ref = "smart_gen.md: hand version register alloc" },
        .{ .unit_id = "same_addr_rel", .label = "load/store SAME-ADDRESS relational constraint", .origin = .human, .doc_ref = "conjunction_wall.md: S1 is the RMW sub-conjunction" },
        .{ .unit_id = "I3_opcode", .label = "completing instr opcode (xor)", .origin = .human, .doc_ref = "conjunction_wall.md: S2 noveltyflag = S1 + one instr" },
        .{ .unit_id = "I3_operand", .label = "completing operand order + OUT_R wiring (xor(r3,r6))", .origin = .human, .doc_ref = "smart_gen.md: hand xor(r3,r6)" },
    };
}

fn mechUnitsD5() [9]Ingredient {
    // D5: 0 candidates ever showed nonzero payoff across 54,432 evaluated
    // behaviours (both pure-random and archive-prefix sources), 8 runs, both
    // seeds. auto_curriculum.md: "no load/store bias, no hint that memory
    // ops matter" (deliberately withheld) AND "n_payoff_pos = 0" every round
    // of every run -> the machine never resolved a single unit either.
    // Every unit is UNRESOLVED: supplied by neither human nor machine.
    var u = mechUnitsAllHuman();
    for (&u) |*i| {
        i.origin = .unresolved;
        i.doc_ref = "auto_curriculum.md: n_payoff_pos=0 all 8 runs, 54,432 behaviours, 0 stones";
    }
    return u;
}

fn mechUnitsE3() [9]Ingredient {
    // E3 COVER-fair: human supplies ONLY the RMW-shape predicate as a
    // coverage-INCLUSION criterion (smart_gen.md: "the read-then-write-
    // same-address signature... applied as a coverage inclusion") -- this
    // pins the load/store OPCODE-CLASSES and the same-address RELATION, and
    // nothing else. The exhaustive enumerator then discovers, by construction
    // (not injection): the setup instruction entirely, both instructions'
    // register allocations, and the completing xor's opcode+operands+OUT_R
    // wiring -- verified "structurally distinct" (flag in r2 not r6,
    // xor(r2,r3) not xor(r3,r6)), genuinely NOT the hand program.
    return .{
        .{ .unit_id = "I0_opcode", .label = "setup instr opcode (r2=1)", .origin = .machine, .doc_ref = "smart_gen.md: discovered stone, not in shape predicate" },
        .{ .unit_id = "I0_operand", .label = "setup operand+register (r2, not hand's r6)", .origin = .machine, .doc_ref = "smart_gen.md: structurally distinct, flag in r2 not r6" },
        .{ .unit_id = "I1_opcode", .label = "load instr opcode-class (read-from-memory)", .origin = .human, .doc_ref = "smart_gen.md: RMW-shape predicate names 'read'" },
        .{ .unit_id = "I1_operand", .label = "load operand+register alloc (r3<-mem[r0])", .origin = .machine, .doc_ref = "smart_gen.md: COVER enumerates registers, not handed" },
        .{ .unit_id = "I2_opcode", .label = "store instr opcode-class (write-to-memory)", .origin = .human, .doc_ref = "smart_gen.md: RMW-shape predicate names 'write'" },
        .{ .unit_id = "I2_operand", .label = "store operand+register alloc (value-src r2)", .origin = .machine, .doc_ref = "smart_gen.md: structurally distinct register choice" },
        .{ .unit_id = "same_addr_rel", .label = "load/store SAME-ADDRESS relational constraint", .origin = .human, .doc_ref = "smart_gen.md: hasRMWShape = read-then-write-SAME-address" },
        .{ .unit_id = "I3_opcode", .label = "completing instr opcode (xor)", .origin = .machine, .doc_ref = "smart_gen.md: 'the needle... discovered', not in the predicate" },
        .{ .unit_id = "I3_operand", .label = "completing operand order+OUT_R wiring (xor(r2,r3))", .origin = .machine, .doc_ref = "smart_gen.md: exhaustively enumerated, 2 OUT_R-equiv progs found" },
    };
}

fn mechUnitsF1() [9]Ingredient {
    // F1 (prior_selector) has NOT landed as of this run (checked: no
    // wcore/docs/research/prior_selector.md exists, research_round_2026_07_11b.md
    // lists F1 as "pending" 0/6). No numbers are fabricated; every unit is
    // marked .pending and excluded from the fraction computation below.
    var u = mechUnitsAllHuman();
    for (&u) |*i| {
        i.origin = .pending;
        i.doc_ref = "research_round_2026_07_11b.md: F1 status=pending, not yet landed";
    }
    return u;
}

// ─────────────────────────────────────────────────────────────────────────
// (2) REPRESENTABILITY LEDGER — E1's mixr -> MIXMOD1 solve (6 units,
// equal-weight, plus a depth-weighted variant that up-weights the family's
// mathematical FORM since it is qualitatively deeper than a grid-cell pick).
// ─────────────────────────────────────────────────────────────────────────

fn reprUnitsE1() [6]Ingredient {
    return .{
        .{ .unit_id = "family_form", .label = "mixed-radix joint-residue FORM: (A mod a)*b+(B mod b)", .origin = .human, .weight = 1.0, .doc_ref = "repr_expansion.md sec.1: mixr definition" },
        .{ .unit_id = "stat_pair_grid", .label = "candidate stat-pair grid {(sum,count3),(sum,inv),(count3,inv)}", .origin = .human, .weight = 1.0, .doc_ref = "repr_expansion.md sec.1: mixr stat-pairs" },
        .{ .unit_id = "radius_grid", .label = "candidate radius grid {2x2, 3x3}", .origin = .human, .weight = 1.0, .doc_ref = "repr_expansion.md sec.1: mixr radii" },
        .{ .unit_id = "family_selection", .label = "WHICH family certifies (mixr, not thresh/ratio/run)", .origin = .machine, .weight = 1.0, .doc_ref = "repr_expansion.md sec.3: thresh=0, mixr=+1, ratio=+1, run=0 certified" },
        .{ .unit_id = "member_selection", .label = "WHICH stat-pair+radius certifies (sum,count3,3x3)", .origin = .machine, .weight = 1.0, .doc_ref = "repr_expansion.md sec.3: exact certified member table" },
        .{ .unit_id = "lens_selection", .label = "WHICH lens certifies (mod4, of the 7-lens set)", .origin = .machine, .weight = 1.0, .doc_ref = "repr_expansion.md sec.3: mixr(sum,count3,3x3,mod4)" },
    };
}

// depth-weighted variant: family_form's weight raised to 3.0 (it is a novel
// algebraic construction, not a parameter pick) -- conservative in the OTHER
// direction (shrinks the machine fraction), reported alongside the
// equal-weight number as an honest bracket, not a single point estimate.
fn reprUnitsE1DepthWeighted() [6]Ingredient {
    var u = reprUnitsE1();
    u[0].weight = 3.0;
    return u;
}

// ─────────────────────────────────────────────────────────────────────────
// Aggregation
// ─────────────────────────────────────────────────────────────────────────

const Tally = struct {
    human: f64 = 0,
    machine: f64 = 0,
    unresolved: f64 = 0,
    pending: f64 = 0,
    total: f64 = 0,

    fn fractionMachine(self: Tally) ?f64 {
        const resolved = self.human + self.machine;
        if (resolved <= 0) return null; // nothing resolved -> undefined, not zero
        return self.machine / resolved;
    }
};

fn tally(units: []const Ingredient) Tally {
    var t = Tally{};
    for (units) |u| {
        t.total += u.weight;
        switch (u.origin) {
            .human => t.human += u.weight,
            .machine => t.machine += u.weight,
            .unresolved => t.unresolved += u.weight,
            .pending => t.pending += u.weight,
        }
    }
    return t;
}

const MethodRow = struct {
    method: []const u8,
    round_tag: []const u8,
    target: []const u8,
    reach: []const u8,
    solved: bool,
    units: []const Ingredient,
    doc: []const u8,
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const out = std.io.getStdOut().writer();

    const mech_curr = mechUnitsAllHuman();
    const mech_d5 = mechUnitsD5();
    const mech_e3 = mechUnitsE3();
    const mech_f1 = mechUnitsF1();
    const repr_e1 = reprUnitsE1();
    const repr_e1_dw = reprUnitsE1DepthWeighted();

    const mech_methods = [_]MethodRow{
        .{ .method = "hand_curriculum", .round_tag = "round-c (pre-arc reference)", .target = "distinct-count WALL (9 targets)", .reach = "6/9", .solved = true, .units = &mech_curr, .doc = "wcore/docs/research/conjunction_wall.md" },
        .{ .method = "D5_blind_bulk", .round_tag = "round-2026-07-10d exp5", .target = "distinct-count WALL (9 targets)", .reach = "0/9", .solved = false, .units = &mech_d5, .doc = "wcore/docs/research/auto_curriculum.md" },
        .{ .method = "E3_smart_gen_cover_fair", .round_tag = "round-E exp3", .target = "distinct-count WALL (9 targets)", .reach = "6/9", .solved = true, .units = &mech_e3, .doc = "wcore/docs/research/smart_gen.md" },
        .{ .method = "F1_prior_selector", .round_tag = "round-F exp1 (PENDING)", .target = "distinct-count WALL (9 targets)", .reach = "pending", .solved = false, .units = &mech_f1, .doc = "docs/research/research_round_2026_07_11b.md" },
    };

    try out.print("════════ F6 insight ledger — MECHANISM side (generation/auto-discovery) ════════\n", .{});
    for (mech_methods) |m| {
        const t = tally(m.units);
        try out.print("{s: <24} reach={s: <8} human={d:.0} machine={d:.0} unresolved={d:.0} pending={d:.0}", .{ m.method, m.reach, t.human, t.machine, t.unresolved, t.pending });
        if (t.fractionMachine()) |f| {
            try out.print("  machine_fraction={d:.4}\n", .{f});
        } else {
            try out.print("  machine_fraction=N/A (nothing resolved)\n", .{});
        }
    }

    try out.print("\n════════ F6 insight ledger — REPRESENTABILITY side (E1 mixr->MIXMOD1) ════════\n", .{});
    {
        const t = tally(&repr_e1);
        try out.print("E1_equal_weight          human={d:.0} machine={d:.0}  machine_fraction={d:.4}\n", .{ t.human, t.machine, t.fractionMachine().? });
        const tdw = tally(&repr_e1_dw);
        try out.print("E1_depth_weighted        human={d:.1} machine={d:.1}  machine_fraction={d:.4}\n", .{ tdw.human, tdw.machine, tdw.fractionMachine().? });
    }

    // ── Cross-check: search-space-narrowing bit estimate from smart_gen.md's
    // own numbers (L2 pool=22345, L3 base cap=1000 [SAME size for fair AND
    // uniform], len3 tested pool=3604, winners=2). This deliberately checks
    // whether an entropy/bit framing is even a faithful model here.
    const l2_pool: f64 = 22345;
    const l3_cap: f64 = 1000;
    const len3_pool: f64 = 3604;
    const winners: f64 = 2;
    const bits_l2_to_cap = std.math.log2(l2_pool / l3_cap);
    const bits_within_pool = std.math.log2(len3_pool / winners);
    try out.print("\n════════ Cross-check: bit-narrowing estimate (smart_gen.md pool sizes) ════════\n", .{});
    try out.print("log2(L2_pool/L3_cap) = log2({d:.0}/{d:.0}) = {d:.2} bits  <- SAME for cover-fair AND cover-uniform (both sample 1000)\n", .{ l2_pool, l3_cap, bits_l2_to_cap });
    try out.print("log2(len3_pool/winners) = log2({d:.0}/{d:.0}) = {d:.2} bits  <- machine's exhaustive within-pool resolving work\n", .{ len3_pool, winners, bits_within_pool });
    try out.print("HONEST FINDING: cover-fair and cover-uniform sample the SAME SIZE subset (1000 of 22345,\n", .{});
    try out.print("identical {d:.2}-bit narrowing) yet only cover-fair succeeds (6/9) and cover-uniform fails (0/9).\n", .{bits_l2_to_cap});
    try out.print("The prior's value is NOT bits-eliminated (quantity); it is WHICH region is sampled (targeting/aim).\n", .{});
    try out.print("A smooth entropy model under-describes this; the choice-count ledger above is the primary metric.\n", .{});

    // ── Write CSV ──
    const csv_path = "/home/micah/Desktop/Sylorlabs/ghost_research/results/insight_ledger_2026_07_11.csv";
    if (std.fs.path.dirname(csv_path)) |dir| std.fs.cwd().makePath(dir) catch {};
    const cf = try std.fs.cwd().createFile(csv_path, .{ .truncate = true });
    defer cf.close();
    const cw = cf.writer();
    try cw.print("row_type,method,round_tag,target,reach,solved,unit_id,label,origin,weight,doc_ref\n", .{});

    for (mech_methods) |m| {
        for (m.units) |u| {
            try cw.print("ingredient,{s},{s},\"{s}\",{s},{},{s},\"{s}\",{s},{d:.2},\"{s}\"\n", .{ m.method, m.round_tag, m.target, m.reach, m.solved, u.unit_id, u.label, u.origin.tag(), u.weight, u.doc_ref });
        }
        const t = tally(m.units);
        var frac_buf: [32]u8 = undefined;
        const frac_str: []const u8 = if (t.fractionMachine()) |f|
            try std.fmt.bufPrint(&frac_buf, "{d:.4}", .{f})
        else
            "NA";
        try cw.print("method_summary,{s},{s},\"{s}\",{s},{},SUMMARY,\"human={d:.0} machine={d:.0} unresolved={d:.0} pending={d:.0}\",machine_fraction,{s},\"{s}\"\n", .{ m.method, m.round_tag, m.target, m.reach, m.solved, t.human, t.machine, t.unresolved, t.pending, frac_str, m.doc });
    }

    // repr side
    {
        const t = tally(&repr_e1);
        for (repr_e1) |u| {
            try cw.print("ingredient,E1_repr_equal_weight,round-E exp1,\"mixr->MIXMOD1 (family growth)\",1/1,true,{s},\"{s}\",{s},{d:.2},\"{s}\"\n", .{ u.unit_id, u.label, u.origin.tag(), u.weight, u.doc_ref });
        }
        try cw.print("method_summary,E1_repr_equal_weight,round-E exp1,\"mixr->MIXMOD1\",1/1,true,SUMMARY,\"human={d:.0} machine={d:.0}\",machine_fraction,{d:.4},\"docs/research/repr_expansion.md\"\n", .{ t.human, t.machine, t.fractionMachine().? });
        const tdw = tally(&repr_e1_dw);
        try cw.print("method_summary,E1_repr_depth_weighted,round-E exp1,\"mixr->MIXMOD1\",1/1,true,SUMMARY,\"human={d:.1} machine={d:.1}\",machine_fraction,{d:.4},\"docs/research/repr_expansion.md (family_form weight=3)\"\n", .{ tdw.human, tdw.machine, tdw.fractionMachine().? });
    }

    // crosscheck rows
    try cw.print("crosscheck,cover_l2_to_cap_bits,-,-,-,-,-,\"log2(22345/1000)\",computed,{d:.4},\"smart_gen.md: L2=22345, L3 base cap=1000 (both fair+uniform)\"\n", .{bits_l2_to_cap});
    try cw.print("crosscheck,cover_within_pool_bits,-,-,-,-,-,\"log2(3604/2)\",computed,{d:.4},\"smart_gen.md: len3 pool=3604, 2 OUT_R-equiv winners\"\n", .{bits_within_pool});
    try cw.print("crosscheck,entropy_model_verdict,-,-,-,-,-,\"same-size-sample--different-outcome\",qualitative,0,\"fair and uniform both sample 1000/22345 (identical bits); only fair hits -- prior is targeting/aim not quantity\"\n", .{});

    // floor rows (always-human infrastructure, never varied/machine-selected
    // in D5/E3/E1/hand-curriculum)
    const floor_items = [_][2][]const u8{
        .{ "alphabet", "the instruction-set alphabet itself (which opcodes/registers/immediates exist as primitives; E3 additionally shrinks it 12reg/13imm->4reg/2imm for tractability, itself a human choice, smart_gen.md 'Honest limitations')" },
        .{ "certifier", "the certifier/detector definition: depth-3/4 irreducibility check, COVER 0.90 threshold, R^2<0.40 novelty gate, real payoff/reachability test -- never machine-authored in this arc" },
        .{ "target_battery", "the target/battery definition: which 9 WALL members count as solved, what MIXMOD1/RATIO1/ORDER2 mean as targets -- always human-designed witnesses (repr_expansion.md sec.8: 'fresh targets are a design choice')" },
        .{ "protocol", "the comparability protocol: seeds, depth caps, budget caps, equal-budget requirement, leakage guards -- fixed by the researcher across every method for apples-to-apples comparison" },
    };
    for (floor_items) |fi| {
        try cw.print("floor,ALL_METHODS,-,-,-,-,{s},\"{s}\",human_always,1.00,\"see docs/research/insight_ledger.md floor section\"\n", .{ fi[0], fi[1] });
    }

    try out.print("\nWrote {s}\n", .{csv_path});
}
