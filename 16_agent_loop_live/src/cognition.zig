const std = @import("std");
const prover = @import("native_prover");
const memory = @import("domain_concept_memory");

pub const CognitionEngine = struct {
    allocator: std.mem.Allocator,
    aig: prover.Aig,
    mem: memory.ConceptMemory,
    
    pub fn init(allocator: std.mem.Allocator) CognitionEngine {
        return .{
            .allocator = allocator,
            .aig = prover.Aig.init(allocator),
            .mem = memory.ConceptMemory.init(allocator),
        };
    }

    pub fn deinit(self: *CognitionEngine) void {
        self.aig.deinit();
        self.mem.deinit();
    }

    /// ProcessPercept fulfills the 'Recursive Cognition' directive.
    /// It reduces the perceptual bit-stream into a compressed AIG representation.
    pub fn processPercept(self: *CognitionEngine, r0: u64, r1: u64) !?[]const u8 {
        // 1. Ingest
        const b0 = try self.aig.createInput();
        const b1 = try self.aig.createInput();
        self.aig.setInputSimValue(b0, r0);
        self.aig.setInputSimValue(b1, r1);
        
        // 2. Synthesize
        const interaction = try self.aig.xorNodes(b0, b1);

        // 3. REFLECT: Sweep
        _ = try self.aig.sweep();

        // 4. CONCEPTUALIZE: Check memory
        if (try self.mem.nameStructure(self.aig, interaction)) |name| {
            return name;
        } else {
            // New discovery: Label it (simplified for PoC)
            const new_name = try std.fmt.allocPrint(self.allocator, "CONCEPT_{d}", .{self.aig.nodes.items.len});
            try self.mem.register(new_name, interaction, 1);
            return new_name;
        }
    }
};
