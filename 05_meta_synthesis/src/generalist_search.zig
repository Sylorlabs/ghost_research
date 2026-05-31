const std = @import("std");
const domain = @import("domain_general");

// The Curriculum: A list of tasks moving from simple to complex.
const Task = struct {
    name: []const u8,
    examples: []const struct { in: u64, out: u64 },
};

const curriculum = [_]Task{
    .{ .name = "Task 1: Add 2", .examples = &.{ .{ .in = 0, .out = 2 }, .{ .in = 5, .out = 7 }, .{ .in = 10, .out = 12 } } },
    .{ .name = "Task 2: Double (x*2)", .examples = &.{ .{ .in = 0, .out = 0 }, .{ .in = 5, .out = 10 }, .{ .in = 12, .out = 24 } } },
    .{ .name = "Task 3: Quadruple (x*4)", .examples = &.{ .{ .in = 1, .out = 4 }, .{ .in = 3, .out = 12 }, .{ .in = 10, .out = 40 } } },
    .{ .name = "Task 4: Times 8 (x*8)", .examples = &.{ .{ .in = 1, .out = 8 }, .{ .in = 3, .out = 24 }, .{ .in = 5, .out = 40 } } },
};

fn evaluateTask(p: domain.Program, sys: domain.System, task: Task) f64 {
    var hits: f64 = 0;
    for (task.examples) |ex| {
        const res = p.execute(sys, ex.in);
        if (res == ex.out) hits += 1.0;
    }
    // Penalize length to encourage compression
    return hits - (@as(f64, @floatFromInt(p.used)) * 0.05);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0001);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== Generalist Inventor: Wake/Sleep Cycle ===\n", .{});
    try out.print("Substrate: Minimal Stack Machine (INC, DEC, DUP, DROP, SWAP, ADD, SUB)\n", .{});
    try out.print("Curriculum: 4 mathematical tasks progressing in complexity.\n\n", .{});

    var sys = domain.System{ .concepts = undefined, .concepts_used = 0 };

    for (curriculum) |task| {
        try out.print(">>> WAKE PHASE: Solving {s}...\n", .{task.name});
        
        var best = domain.randomProgram(&seed, sys);
        var best_q = evaluateTask(best, sys, task);
        
        var iters: usize = 0;
        const max_target = @as(f64, @floatFromInt(task.examples.len));
        
        // Search until it perfectly solves all examples
        while (best_q < max_target - 0.99 and iters < 200000) : (iters += 1) {
            const cand = domain.mutateProgram(best, &seed, sys);
            const q = evaluateTask(cand, sys, task);
            if (q >= best_q) {
                best = cand;
                best_q = q;
            }
        }
        
        if (best_q >= max_target - 0.99) {
            try out.print("    [SOLVED in {d} iters] AST:", .{iters});
            try domain.printProgram(best, out);
            
            // SLEEP PHASE: Library Learning (Compression)
            // If the solution uses 2 or more instructions, extract it as a Concept to build the vocabulary!
            if (best.used >= 2 and sys.concepts_used < domain.NumConcepts) {
                try out.print(">>> SLEEP PHASE: Extracting successful behavior into Concept_C{d}...\n", .{sys.concepts_used});
                
                var c = domain.Concept{ .instructions = undefined, .used = best.used };
                var j: usize = 0;
                while (j < best.used) : (j += 1) {
                    c.instructions[j] = best.instructions[j];
                }
                sys.concepts[sys.concepts_used] = c;
                sys.concepts_used += 1;
                
                try out.print("    Vocabulary expanded! Engine can now use CALL_C{d} as a single axiom.\n\n", .{sys.concepts_used - 1});
            } else {
                try out.print("\n", .{});
            }
        } else {
            try out.print("    [FAILED] Could not solve task with current vocabulary.\n\n", .{});
        }
    }

    try out.print("=== Final Learned Library (Ontology) ===\n", .{});
    var c: usize = 0;
    while (c < sys.concepts_used) : (c += 1) {
        try out.print("Concept_C{d}:", .{c});
        var j: usize = 0;
        while (j < sys.concepts[c].used) : (j += 1) {
            try out.print(" {s}", .{@tagName(sys.concepts[c].instructions[j].op)});
        }
        try out.print("\n", .{});
    }
}