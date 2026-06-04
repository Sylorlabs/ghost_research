const std = @import("std");
const domain = @import("domain_agi_creative_divergence");
const memory = @import("domain_concept_memory");
const prover = @import("native_prover");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var prng = std.Random.DefaultPrng.init(0x1337_F00D_0035);
    const random = prng.random();

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE CREATIVE DIVERGENCE ENGINE ===\n", .{});
    try out.print("Directive: 'Maximize distance from known concepts.'\n\n", .{});

    // 1. Initialize Concept Library
    var mem = memory.ConceptMemory.init(allocator);
    defer mem.deinit();
    
    // Seed the memory with basics (XOR)
    // In a real run, this would be auto-populated.
    try mem.register("BASIC_XOR", 0x1, 1);

    // 2. Initialize Divergence Engine
    var div = domain.DivergenceObjective.init(&mem);
    
    // Simulate evolution loop
    var aig = prover.Aig.init(allocator);
    defer aig.deinit();

    try out.print(">>> Divergence Loop Active. Seeking the unknown...\n", .{});

    var i: usize = 0;
    while (i < 500) : (i += 1) {
        // Machine synthesizes a random logic gate
        // Use the random number generator to create 'inputs' for the AIG
        const node = try aig.createInput();
        aig.setInputSimValue(node, random.int(u64));
        const q = div.calculateFitness(aig, node);
        
        if (q > 0.8) {
            try out.print(">>> CREATIVE BREAKTHROUGH: Novel Logic Pattern (Divergence: {d:.2})\n", .{q});
            try mem.register("NOVEL_CONCEPT", node, 2);
        }
    }
    try out.print("\nTruth: Machine is exploring structural novelty.\n", .{});
}