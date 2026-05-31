const std = @import("std");

pub const MaxProgLen = 12;
pub const StackSize = 8;

pub const Op = enum(u4) {
    INC = 0,
    DEC = 1,
    DUP = 2,
    DROP = 3,
    SWAP = 4,
    ADD = 5,
    SUB = 6,
    SHL1 = 7, // Shift left by 1 (multiply by 2)
};

pub const State = struct {
    stack: [StackSize]u64,
    sp: usize,
    
    pub fn push(self: *State, val: u64) void {
        if (self.sp < StackSize) {
            self.stack[self.sp] = val;
            self.sp += 1;
        }
    }
    
    pub fn pop(self: *State) u64 {
        if (self.sp > 0) {
            self.sp -= 1;
            return self.stack[self.sp];
        }
        return 0; // Underflow = 0
    }
};

pub const Program = struct {
    instructions: [MaxProgLen]Op,
    used: u8,

    pub fn execute(self: Program, input: u64) u64 {
        var state = State{ .stack = undefined, .sp = 0 };
        state.push(input);
        
        var i: usize = 0;
        while (i < self.used) : (i += 1) {
            switch (self.instructions[i]) {
                .INC => { const a = state.pop(); state.push(a +% 1); },
                .DEC => { const a = state.pop(); state.push(a -% 1); },
                .DUP => { const a = state.pop(); state.push(a); state.push(a); },
                .DROP => { _ = state.pop(); },
                .SWAP => { const a = state.pop(); const b = state.pop(); state.push(a); state.push(b); },
                .ADD => { const a = state.pop(); const b = state.pop(); state.push(b +% a); },
                .SUB => { const a = state.pop(); const b = state.pop(); state.push(b -% a); },
                .SHL1 => { const a = state.pop(); state.push(a << 1); },
            }
        }
        return state.pop();
    }
};

// The "Execution Signature" is the program's output when fed inputs [1, 2, 3, 4]
pub const Signature = struct {
    out: [4]u64,

    pub fn compute(p: Program) Signature {
        return .{
            .out = .{ p.execute(1), p.execute(2), p.execute(3), p.execute(4) }
        };
    }

    // Mathematical distance between two signatures
    pub fn distance(self: Signature, other: Signature) f64 {
        var dist: f64 = 0;
        var i: usize = 0;
        while (i < 4) : (i += 1) {
            // Absolute difference handles magnitude. We cap it to prevent overflow in squares.
            const a = @as(f64, @floatFromInt(self.out[i]));
            const b = @as(f64, @floatFromInt(other.out[i]));
            const diff = @abs(a - b);
            dist += diff;
        }
        return dist;
    }
};

// Context setup for HashMap
const SignatureContext = struct {
    pub fn hash(self: @This(), s: Signature) u64 {
        _ = self;
        var h: u64 = 0xCBF29CE484222325;
        for (s.out) |v| {
            h ^= v;
            h *%= 0x100000001B3;
        }
        return h;
    }
    pub fn eql(self: @This(), a: Signature, b: Signature) bool {
        _ = self;
        return a.out[0] == b.out[0] and a.out[1] == b.out[1] and a.out[2] == b.out[2] and a.out[3] == b.out[3];
    }
};

fn smix(x: u64) u64 {
    var z = x +% 0x9E3779B97F4A7C15;
    z = (z ^ (z >> 30)) *% 0xBF58476D1CE4E5B9;
    z = (z ^ (z >> 27)) *% 0x94D049BB133111EB;
    return z ^ (z >> 31);
}

fn nextRand(rng: *u64) u64 {
    rng.* = smix(rng.*);
    return rng.*;
}

pub fn randomProgram(rng: *u64, max_len: u8) Program {
    const len: u8 = @intCast(1 + (nextRand(rng) % max_len));
    var p = Program{ .instructions = undefined, .used = len };
    var i: usize = 0;
    while (i < len) : (i += 1) {
        p.instructions[i] = @enumFromInt(nextRand(rng) % 8);
    }
    return p;
}

pub fn mutate(p: Program, rng: *u64) Program {
    var q = p;
    const draw = nextRand(rng) % 16;
    if (draw < 4 and q.used > 1) {
        q.used -= 1;
    } else if (draw < 8 and q.used < MaxProgLen) {
        const idx = nextRand(rng) % (q.used + 1);
        var i: usize = q.used;
        while (i > idx) : (i -= 1) q.instructions[i] = q.instructions[i - 1];
        q.instructions[idx] = @enumFromInt(nextRand(rng) % 8);
        q.used += 1;
    } else {
        const idx = nextRand(rng) % @max(1, q.used);
        q.instructions[idx] = @enumFromInt(nextRand(rng) % 8);
    }
    return q;
}

pub fn printProgram(p: Program, writer: anytype) !void {
    var i: usize = 0;
    while (i < p.used) : (i += 1) {
        try writer.print(" {s}", .{@tagName(p.instructions[i])});
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_ABCD_0005);
    var seed = prng.random().int(u64);

    const out = std.io.getStdOut().writer();
    try out.print("=== PURE TIER 4: Autonomous Fuzzing & Execution Signatures ===\n\n", .{});

    // 1. WAKE PHASE: Autonomous Exploration
    try out.print(">>> EXPLORATION PHASE: Fuzzing 100,000 random programs to build the Ontological Map...\n", .{});
    
    var library = std.HashMap(Signature, Program, SignatureContext, 80).init(allocator);
    defer library.deinit();

    var i: usize = 0;
    while (i < 100_000) : (i += 1) {
        const p = randomProgram(&seed, 6); // Keep generated programs short to act as clean foundational concepts
        const sig = Signature.compute(p);
        
        // If we found a new behavior, OR a shorter program for an existing behavior, save it!
        const entry = library.getOrPut(sig) catch unreachable;
        if (!entry.found_existing) {
            entry.value_ptr.* = p;
        } else if (p.used < entry.value_ptr.used) {
            entry.value_ptr.* = p; // MDL Compression: Keep the shortest AST that produces this exact signature
        }
    }

    try out.print("    Discovered {d} mathematically unique behaviors.\n\n", .{library.count()});

    // 2. TARGETED TASK: "Multiply by 13"
    // We want output: [13, 26, 39, 52]
    const target_sig = Signature{ .out = .{ 13, 26, 39, 52 } };
    try out.print(">>> TASK: Find a program with Signature [13, 26, 39, 52] (Multiply by 13)\n", .{});
    
    // Check if we accidentally fuzzed the exact answer already
    if (library.get(target_sig)) |exact_match| {
        try out.print("    EXACT MATCH FOUND IN LIBRARY!\n    AST:", .{});
        try printProgram(exact_match, out);
        try out.print("\n", .{});
        return;
    }

    // 3. SEMANTIC ROUTING (No ML, No Transfomers)
    try out.print("    Target not in library. Routing via Execution Signatures...\n", .{});
    var best_base_prog: Program = undefined;
    var best_dist: f64 = std.math.floatMax(f64);
    
    var it = library.iterator();
    while (it.next()) |entry| {
        const dist = target_sig.distance(entry.key_ptr.*);
        if (dist < best_dist) {
            best_dist = dist;
            best_base_prog = entry.value_ptr.*;
        }
    }

    try out.print("    Selected closest structural base program (Distance = {d}):\n    AST:", .{best_dist});
    try printProgram(best_base_prog, out);
    try out.print("\n    Base Signature: [{d}, {d}, {d}, {d}]\n\n", .{
        Signature.compute(best_base_prog).out[0],
        Signature.compute(best_base_prog).out[1],
        Signature.compute(best_base_prog).out[2],
        Signature.compute(best_base_prog).out[3],
    });

    // 4. FLUID TOPOLOGY MUTATION
    try out.print(">>> MUTATION PHASE: Mutating the unpacked base program to bridge the final gap...\n", .{});
    
    var current_best = best_base_prog;
    var current_best_dist = best_dist;
    
    var global_best = current_best;
    var global_best_dist = current_best_dist;
    
    var search_iters: usize = 0;
    while (global_best_dist > 0 and search_iters < 1000000) : (search_iters += 1) {
        const cand = mutate(current_best, &seed);
        const cand_sig = Signature.compute(cand);
        const dist = target_sig.distance(cand_sig);
        
        // Accept if better, or with small probability if slightly worse (SA)
        if (dist <= current_best_dist or (nextRand(&seed) % 100 < 5)) {
            current_best = cand;
            current_best_dist = dist;
            
            if (dist < global_best_dist or (dist == global_best_dist and cand.used < global_best.used)) {
                global_best = cand;
                global_best_dist = dist;
            }
        }
    }

    if (global_best_dist == 0) {
        try out.print("    [SOLVED in {d} mutations] Final Fluid AST:", .{search_iters});
        try printProgram(global_best, out);
        try out.print("\n", .{});
    } else {
        try out.print("    [FAILED] Could not bridge the gap. Distance remaining: {d}\n", .{global_best_dist});
    }
}