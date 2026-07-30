const std = @import("std");

/// BitForge-Native Prover (PoC)
///
/// Goals: 
/// 1. Low-latency bit-vector to AIG (And-Inverter Graph) lowering.
/// 2. Structural hashing for "free" concept discovery.
/// 3. SAT-Sweeping for deep logical reduction.

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

    pub fn addAndGate(self: *SatSolver, x: u32, a: u32, b: u32, a_inv: bool, b_bit_inv: bool) !void {
        const alit: Lit = if (a_inv) -@as(i32, @intCast(a)) else @as(i32, @intCast(a));
        const blit: Lit = if (b_bit_inv) -@as(i32, @intCast(b)) else @as(i32, @intCast(b));
        const xlit: Lit = @intCast(x);

        try self.addClause(&[_]Lit{ -xlit, alit });
        try self.addClause(&[_]Lit{ -xlit, blit });
        try self.addClause(&[_]Lit{ xlit, -alit, -blit });
    }

    pub fn solve(self: *SatSolver) bool {
        return self.backtrack();
    }

    fn backtrack(self: *SatSolver) bool {
        if (self.assignments.count() == self.num_vars) {
            return self.checkSatisfaction();
        }

        const next_var = self.assignments.count() + 1;
        
        self.assignments.put(@intCast(next_var), false) catch unreachable;
        if (self.backtrack()) return true;
        
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
    strash: std.AutoHashMap(Node, NodeId),
    sim_values: std.ArrayList(SimVector),

    pub fn init(allocator: std.mem.Allocator) Aig {
        var self = Aig{
            .allocator = allocator,
            .nodes = std.ArrayList(Node).init(allocator),
            .strash = std.AutoHashMap(Node, NodeId).init(allocator),
            .sim_values = std.ArrayList(SimVector).init(allocator),
        };
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
        if (a == 0 or b == 0) return 0;
        if (a == 1) return b;
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

        const val_a = self.getSimValue(a);
        const val_b = self.getSimValue(b);
        try self.sim_values.append(val_a & val_b);
        return new_id;
    }

    pub fn getSimValue(self: *const Aig, id: NodeId) u64 {
        const idx = id >> 1;
        if (idx >= self.sim_values.items.len) return 0;
        const val = self.sim_values.items[idx];
        return if ((id & 1) != 0) ~val else val;
    }

    pub fn setInputSimValue(self: *Aig, id: NodeId, val: SimVector) void {
        self.sim_values.items[id >> 1] = val;
    }

    pub fn createInput(self: *Aig) !NodeId {
        const id: NodeId = @intCast(self.nodes.items.len * 2);
        try self.nodes.append(.{ .left = 0, .right = 0 });
        try self.sim_values.append(0);
        return id;
    }

    pub fn sweep(self: *Aig) !std.AutoHashMap(NodeId, NodeId) {
        var total_merged: usize = 0;
        var passes: usize = 0;
        
        // This map will track the cumulative remapping from the ORIGINAL IDs to the FINAL IDs
        var cumulative_map = std.AutoHashMap(NodeId, NodeId).init(self.allocator);
        errdefer cumulative_map.deinit();

        // Initialize cumulative map as identity
        for (0..self.nodes.items.len) |i| {
            const id = @as(NodeId, @intCast(i * 2));
            try cumulative_map.put(id, id);
        }

        while (passes < 10) : (passes += 1) {
            var pass_merged: usize = 0;
            var rep_map = std.AutoHashMap(NodeId, NodeId).init(self.allocator);
            defer rep_map.deinit();
            var sig_map = std.AutoHashMap(SimVector, NodeId).init(self.allocator);
            defer sig_map.deinit();

            for (0..self.nodes.items.len) |i| {
                const id = @as(NodeId, @intCast(i * 2));
                const sig = self.getSimValue(id);
                if (sig_map.get(sig)) |match_id| {
                    try rep_map.put(id, match_id);
                    pass_merged += 1;
                } else if (sig_map.get(~sig)) |match_id| {
                    try rep_map.put(id, match_id ^ 1);
                    pass_merged += 1;
                } else {
                    try sig_map.put(sig, id);
                    try rep_map.put(id, id);
                }
            }

            if (pass_merged == 0) break;

            var new_aig = Aig.init(self.allocator);
            var id_map = std.AutoHashMap(NodeId, NodeId).init(self.allocator);
            defer id_map.deinit();
            try id_map.put(0, 0);

            for (self.nodes.items, 0..) |node, i| {
                const old_id = @as(NodeId, @intCast(i * 2));
                const rep_id = rep_map.get(old_id).?;
                if (rep_id != old_id) continue;

                if (node.left == 0 and node.right == 0 and i > 0) {
                    const new_id = try new_aig.createInput();
                    new_aig.setInputSimValue(new_id, self.sim_values.items[i]);
                    try id_map.put(old_id, new_id);
                } else if (i > 0) {
                    const new_left = self.lookupNewId(node.left, &rep_map, &id_map);
                    const new_right = self.lookupNewId(node.right, &rep_map, &id_map);
                    const new_id = try new_aig.andNodes(new_left, new_right);
                    try id_map.put(old_id, new_id);
                }
            }

            // Update cumulative map: Original -> Intermediate -> New
            var it = cumulative_map.iterator();
            while (it.next()) |entry| {
                const intermediate_literal = entry.value_ptr.*;
                const intermediate_base = intermediate_literal & ~@as(u32, 1);
                const intermediate_inv = intermediate_literal & 1;
                
                const rep_literal = rep_map.get(intermediate_base).? ^ intermediate_inv;
                const rep_base = rep_literal & ~@as(u32, 1);
                const rep_inv = rep_literal & 1;
                
                entry.value_ptr.* = id_map.get(rep_base).? ^ rep_inv;
            }

            self.strash.deinit();
            self.nodes.deinit();
            self.sim_values.deinit();
            self.* = new_aig;
            total_merged += pass_merged;
        }
        return cumulative_map;
    }

    fn lookupNewId(self: Aig, old_literal: NodeId, rep_map: *std.AutoHashMap(NodeId, NodeId), id_map: *std.AutoHashMap(NodeId, NodeId)) NodeId {
        _ = self;
        const old_base = old_literal & ~@as(u32, 1);
        const old_inv = old_literal & 1;
        
        const rep_literal = rep_map.get(old_base).? ^ old_inv;
        const rep_base = rep_literal & ~@as(u32, 1);
        const rep_inv = rep_literal & 1;
        
        const new_base = id_map.get(rep_base).?;
        return new_base ^ rep_inv;
    }

    pub fn orNodes(self: *Aig, a: NodeId, b: NodeId) !NodeId {
        // x | y = ~(~x & ~y)
        return self.notNode(try self.andNodes(self.notNode(a), self.notNode(b)));
    }

    pub fn createBvMiter(self: *Aig, a: BitVector, b: BitVector) !NodeId {
        var diff_or = @as(NodeId, 0);
        for (0..64) |i| {
            const bit_xor = try self.xorNodes(a.bits[i], b.bits[i]);
            diff_or = try self.orNodes(diff_or, bit_xor);
        }
        return diff_or;
    }

    pub fn createMiter(self: *Aig, a: NodeId, b: NodeId) !NodeId {
        return try self.xorNodes(a, b);
    }

    pub fn toSat(self: Aig, allocator: std.mem.Allocator) !SatSolver {
        var solver = SatSolver.init(allocator);
        var i: usize = 0;
        while (i < self.nodes.items.len) : (i += 1) _ = solver.newVar();
        try solver.addClause(&[_]Lit{-1});
        i = 1;
        while (i < self.nodes.items.len) : (i += 1) {
            const node = self.nodes.items[i];
            // Primary inputs are {0,0} nodes (distinct from the constant-false node at index 0).
            if (node.left == 0 and node.right == 0) continue;
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

    pub fn initConstant(aig: *Aig, val: u64) BitVector {
        var bv: BitVector = undefined;
        for (&bv.bits, 0..) |*b, i| {
            const bit = (val >> @as(u6, @intCast(i))) & 1;
            b.* = if (bit != 0) @as(NodeId, 1) else @as(NodeId, 0);
        }
        _ = aig;
        return bv;
    }

    pub fn initInput(aig: *Aig) !BitVector {
        var bv: BitVector = undefined;
        for (&bv.bits) |*b| b.* = try aig.createInput();
        return bv;
    }

    pub fn xorBv(self: BitVector, aig: *Aig, other: BitVector) !BitVector {
        var res: BitVector = undefined;
        for (0..64) |i| res.bits[i] = try aig.xorNodes(self.bits[i], other.bits[i]);
        return res;
    }

    pub fn andBv(self: BitVector, aig: *Aig, other: BitVector) !BitVector {
        var res: BitVector = undefined;
        for (0..64) |i| res.bits[i] = try aig.andNodes(self.bits[i], other.bits[i]);
        return res;
    }

    pub fn addBv(self: BitVector, aig: *Aig, other: BitVector) !BitVector {
        var res: BitVector = undefined;
        var carry = @as(NodeId, 0);
        for (0..64) |i| {
            try aig.addBits(self.bits[i], other.bits[i], carry, &res.bits[i], &carry);
        }
        return res;
    }

    pub fn shrBv(self: BitVector, aig: *Aig, imm: u6) BitVector {
        var res: BitVector = undefined;
        for (0..64) |i| {
            if (i + imm < 64) {
                res.bits[i] = self.bits[i + imm];
            } else {
                res.bits[i] = 0;
            }
        }
        _ = aig;
        return res;
    }

    pub fn shlBv(self: BitVector, aig: *Aig, imm: u6) BitVector {
        var res: BitVector = undefined;
        for (0..64) |i| {
            if (i >= imm) {
                res.bits[i] = self.bits[i - imm];
            } else {
                res.bits[i] = 0;
            }
        }
        _ = aig;
        return res;
    }

    pub fn rotlBv(self: BitVector, aig: *Aig, imm: u6) BitVector {
        var res: BitVector = undefined;
        for (0..64) |i| {
            const src = (i + 64 - imm) % 64;
            res.bits[i] = self.bits[src];
        }
        _ = aig;
        return res;
    }
};
