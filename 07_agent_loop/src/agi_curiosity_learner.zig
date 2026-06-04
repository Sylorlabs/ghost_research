const std = @import("std");
const domain = @import("domain_agi_curiosity");
const perception = @import("perception");
const cognition = @import("cognition");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE CURIOSITY-DRIVEN LEARNER ===\n", .{});
    try out.print("Status: Machine actively seeking 'Surprise'.\n\n", .{});

    var eye = try perception.PerceptionEngine.init(allocator, "./src");
    defer eye.deinit();

    var brain = cognition.CognitionEngine.init(allocator);
    defer brain.deinit();

    var curiosity = domain.CuriosityObjective.init(allocator);
    defer curiosity.deinit();

    var total_surprise: f64 = 0;
    
    // The machine now 'wanders' through its own source code
    while (true) {
        const percept = try eye.nextPercept() orelse break;
        _ = try brain.processPercept(percept.r0, percept.r1);
        
        // Hash the current AIG model state
        var hasher = std.hash.XxHash64.init(0);
        hasher.update(std.mem.sliceAsBytes(brain.aig.nodes.items));
        const hash = hasher.final();
        
        const reward = curiosity.calculateReward(hash);
        total_surprise += reward;
        
        if (reward > 0) {
            try out.print(">>> SURPRISE DETECTED: New structural concept discovered (Score: {d})\n", .{total_surprise});
        }
    }

    try out.print("\nTruth: Machine is now autonomously exploring its own structural possibilities.\n", .{});
}