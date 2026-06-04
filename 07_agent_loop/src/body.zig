const std = @import("std");
const perception = @import("perception");
const cognition = @import("cognition");
const homeostasis = @import("homeostasis");
const motor = @import("motor");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== BITFORGE AGI: BODY REALIZATION ===\n", .{});
    try out.print("Status: ACTIVATING RECURSIVE LOOP\n\n", .{});

    // 1. Initialize Subsystems
    // DIRECTIVE: INGEST_SELF - Point eyes at the metabolism
    var eye = try perception.PerceptionEngine.init(allocator, "./src");
    defer eye.deinit();

    var brain = cognition.CognitionEngine.init(allocator);
    defer brain.deinit();

    var heart = homeostasis.HomeostasisEngine{};
    var hands = motor.MotorEngine.init(allocator);

    // 2. The Universal Cycle
    while (true) {
        // A. PERCEPTION
        const percept = try eye.nextPercept() orelse {
            try out.print(">>> Corpus exhausted. Persistent existence achieved.\n", .{});
            break;
        };

        // B. COGNITION
        const concept = try brain.processPercept(percept.r0, percept.r1);

        // C. HOMEOSTASIS
        heart.update(brain.aig.nodes.items.len);
        
        // D. MOTOR: Act on the environment by emitting synthesized logic
        if (concept) |c| {
            try out.print("\n>>> MOTOR ACT: Conceptual Discovery: {s}\n", .{c});
        }
        
        if (brain.aig.nodes.items.len > 10) {
            const root_id = @as(u32, @intCast((brain.aig.nodes.items.len - 1) * 2));
            const code = try hands.lift(brain.aig, root_id);
            defer allocator.free(code);
            
            try out.print(">>> MOTOR ACT: Synthesized Concept Discovery:\n{s}\n", .{code});
        }

        try out.print("Vitality: {d:.2} | Nodes: {d} | Velocity: {d:.4}\n", .{ 
            heart.velocity * 100.0, brain.aig.nodes.items.len, heart.velocity 
        });
        
        // Loop delay to simulate real-world compute budget
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}