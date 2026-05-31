const std = @import("std");

/// BitForge-Native Prover (PoC)
///
/// Goals: 
/// 1. Low-latency bit-vector to AIG (And-Inverter Graph) lowering.
/// 2. Structural hashing for "free" concept discovery.
///
/// Harshest Critic Review:
/// You are trying to rebuild Z3 in a weekend. Z3 has 20 years of heuristic
/// optimization (CDCL, VSIDS, Literal-Block Distance pruning) that you 
/// cannot replicate in a single Zig file. 
///
/// This PoC will likely be 1000x SLOWER than Z3 because while Z3 handles
/// 'everything', it is extremely good at the 'Bit-Vector' portion. 
/// This is 'Ass' territory until we implement a real SAT solver core.

pub const NodeId = u32;

pub const Node = struct {
    // Literal encoding: lsb is inverted bit, rest is node index
    left: NodeId,
    right: NodeId,
};

pub const SimVector = u64; // We run 64 simulations in parallel per pass

pub const Lit = i32; // Standard SAT encoding: positive = variable, negative = NOT variable

pub const Clause = struct {
    lits: std.ArrayList(Lit),
};

pub const SatSolver = struct {
    allocator: std.mem.Allocator,
    clauses: std.ArrayList(Clause),
    assignments: std.AutoHashMap(u32, bool),
    num_vars: u32,

    pub fn init(allocator: std.mem.Allocator) SatSolver {
        return .{
            .allocator = allocator,
            .clauses = std.ArrayList(Clause).init(allocator),
            .assignments = std.AutoHashMap(u32, bool).init(allocator),
            .num_vars = 0,
        };
    }

    pub fn deinit(self: *SatSolver) void {
        for (self.clauses.items) |*c| c.lits.deinit();
        self.clauses.deinit();
        self.assignments.deinit();
    }

    pub fn newVar(self: *SatSolver) u32 {
        self.num_vars += 1;
        return self.num_vars;
    }

    pub fn addClause(self: *SatSolver, lits: []const Lit) !void {
        var c = Clause{ .lits = std.ArrayList(Lit).init(self.allocator) };
        try c.lits.appendSlice(lits);
        try self.clauses.append(c);
    }

    // Tseitin Transformation for AND gate: x = a & b
    // Clauses: (~x | a), (~x | b), (x | ~a | ~b)
    pub fn addAndGate(self: *SatSolver, x: u32, a: u32, b: u32, a_inv: bool, b_bit_inv: bool) !void {
        const alit: Lit = if (a_inv) -@as(i32, @intCast(a)) else @as(i32, @intCast(a));
        const blit: Lit = if (b_bit_inv) -@as(i32, @intCast(b)) else @as(i32, @intCast(b));
        const xlit: Lit = @intCast(x);

        try self.addClause(&[_]Lit{ -xlit, alit });
        try self.addClause(&[_]Lit{ -xlit, blit });
        try self.addClause(&[_]Lit{ xlit, -alit, -blit });
    }

    // THE BUZZKILL: Basic Backtracking DPLL (No heuristics, very slow)
    pub fn solve(self: *SatSolver) bool {
        return self.backtrack();
    }

    fn backtrack(self: *SatSolver) bool {
        if (self.assignments.count() == self.num_vars) {
            return self.checkSatisfaction();
        }

        const next_var = self.assignments.count() + 1;
        
        // Try False
        self.assignments.put(@intCast(next_var), false) catch unreachable;
        if (self.backtrack()) return true;
        
        // Try True
        self.assignments.put(@intCast(next_var), true) catch unreachable;
        if (self.backtrack()) return true;
        
        _ = self.assignments.remove(@intCast(next_var));
        return false;
    }

    fn checkSatisfaction(self: SatSolver) bool {
        for (self.clauses.items) |c| {
            var satisfied = false;
            for (c.lits.items) |l| {
                const var_idx = @as(u32, @intCast(@abs(l)));
                const val = self.assignments.get(var_idx).?;
                if ((l > 0 and val) or (l < 0 and !val)) {
                    satisfied = true;
                    break;
                }
            }
            if (!satisfied) return false;
        }
        return true;
    }
};

pub const Aig = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(Node),
    // Map of (left, right) -> NodeId for structural hashing
    strash: std.AutoHashMap(Node, NodeId),
    // Simulation values for each node
    sim_values: std.ArrayList(SimVector),

    pub fn init(allocator: std.mem.Allocator) Aig {
        var self = Aig{
            .allocator = allocator,
            .nodes = std.ArrayList(Node).init(allocator),
            .strash = std.AutoHashMap(Node, NodeId).init(allocator),
            .sim_values = std.ArrayList(SimVector).init(allocator),
        };
        // Node 0 is the constant False/Zero
        self.nodes.append(.{ .left = 0, .right = 0 }) catch unreachable;
        self.sim_values.append(0) catch unreachable;
        return self;
    }

    pub fn deinit(self: *Aig) void {
        self.nodes.deinit();
        self.strash.deinit();
        self.sim_values.deinit();
    }

    pub fn andNodes(self: *Aig, a: NodeId, b: NodeId) !NodeId {
        // Trivial simplifications
        if (a == 0 or b == 0) return 0; // x & 0 = 0
        if (a == 1) return b;          // x & 1 = x
        if (b == 1) return a;
        if (a == b) return a;
        if ((a ^ 1) == b) return 0;

        const low = if (a < b) a else b;
        const high = if (a < b) b else a;
        const key = Node{ .left = low, .right = high };

        if (self.strash.get(key)) |id| return id;

        const new_id: NodeId = @intCast(self.nodes.items.len * 2);
        try self.nodes.append(key);
        try self.strash.put(key, new_id);
        
        // Simulation propagation
        const val_a = self.getSimValue(a);
        const val_b = self.getSimValue(b);
        try self.sim_values.append(val_a & val_b);
        
        return new_id;
    }

    pub fn getSimValue(self: Aig, id: NodeId) SimVector {
        const idx = id >> 1;
        const val = self.sim_values.items[idx];
        return if (id & 1 != 0) ~val else val;
    }

    pub fn setInputSimValue(self: *Aig, id: NodeId, val: SimVector) void {
        self.sim_values.items[id >> 1] = val;
    }

    pub fn createInput(self: *Aig) !NodeId {
        const id: NodeId = @intCast(self.nodes.items.len * 2);
        try self.nodes.append(.{ .left = 0, .right = 0 }); // Inputs have no children in AIG
        try self.sim_values.append(0); // Initialized to 0, will be set by simulator
        return id;
    }

    pub fn toSat(self: Aig, allocator: std.mem.Allocator) !SatSolver {
        var solver = SatSolver.init(allocator);
        
        // Map AIG node indices to SAT variable indices
        // Node 0 is mapped to Var 1
        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) {
            _ = solver.newVar();
        }

        // Node 0 is False. In SAT, Var 1 = False => Clause(-1)
        try solver.addClause(&[_]Lit{-1});

        // Add AND gates for all other nodes
        i = 1;
        while (i < self.nodes.items.len) : (i += 1) {
            const node = self.nodes.items[i];
            const x: u32 = @intCast(i + 1);
            
            const a_idx = node.left >> 1;
            const a_inv = (node.left & 1) != 0;
            const b_idx = node.right >> 1;
            const b_inv = (node.right & 1) != 0;
            
            try solver.addAndGate(x, @intCast(a_idx + 1), @intCast(b_idx + 1), a_inv, b_inv);
        }
        return solver;
    }

    pub fn notNode(self: *Aig, a: NodeId) NodeId {
        _ = self;
        return a ^ 1;
    }

    pub fn xorNodes(self: *Aig, a: NodeId, b: NodeId) !NodeId {
        const left = try self.andNodes(a, self.notNode(b));
        const right = try self.andNodes(self.notNode(a), b);
        return self.notNode(try self.andNodes(self.notNode(left), self.notNode(right)));
    }
    
    pub fn addBits(self: *Aig, a: NodeId, b: NodeId, cin: NodeId, sum: *NodeId, cout: *NodeId) !void {
        const xab = try self.xorNodes(a, b);
        sum.* = try self.xorNodes(xab, cin);
        
        const and_ab = try self.andNodes(a, b);
        const and_xab_cin = try self.andNodes(xab, cin);
        cout.* = self.notNode(try self.andNodes(self.notNode(and_ab), self.notNode(and_xab_cin)));
    }
};

pub const BitVector = struct {
    bits: [64]NodeId,

    pub fn initIdentity(aig: *Aig) BitVector {
        _ = aig;
        const bv: BitVector = undefined;
        return bv;
    }
};
