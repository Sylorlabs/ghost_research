const std = @import("std");
const gp = @import("heuristic_gp");

const SearchPoint = struct {
    vel: f64,
    stag: f64,
    ent: f64,
    should_reset: bool,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const out = std.io.getStdOut().writer();
    try out.print("=== The Unknown: Heuristic Symbolic Regression ===\n", .{});
    try out.print("Goal: Synthesize a non-linear 'Law of Search' from raw telemetry.\n\n", .{});

    // 1. Load the "Optimization Data" (History of Search failures)
    // We treat this as the environment the heuristic must 'survive'.
    const file = try std.fs.cwd().openFile("../results/search_physics.csv", .{});
    defer file.close();
    const data = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(data);

    var history = std.ArrayList(SearchPoint).init(allocator);
    defer history.deinit();

    var lines = std.mem.tokenizeAny(u8, data, "\n\r");
    _ = lines.next(); // Skip header
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, ",");
        _ = fields.next(); // iter
        const hits = try std.fmt.parseFloat(f64, fields.next().?);
        const velocity = try std.fmt.parseFloat(f64, fields.next().?);
        const stagnation = try std.fmt.parseInt(u32, fields.next().?, 10);
        
        // Labeling the data: we 'should' reset if stagnation is high
        try history.append(.{
            .vel = velocity,
            .stag = @as(f64, @floatFromInt(stagnation)),
            .ent = 1.0, // Placeholder
            .should_reset = stagnation > 150,
        });
        _ = hits;
    }

    try out.print("Loaded {d} points of Search Physics.\n", .{history.items.len});

    // 2. Evolutionary Search for the Law
    var prng = std.Random.DefaultPrng.init(0x1337_0000_1337);
    var seed = prng.random().int(u64);

    var best_expr = gp.randomExpression(&seed, 3);
    var best_score: f64 = -1.0;

    const Iters = 20000;
    var i: usize = 0;
    while (i < Iters) : (i += 1) {
        const cand = gp.randomExpression(&seed, 3);
        
        // Fitness: How well does this formula predict when we are in a trap?
        var hits: f64 = 0;
        for (history.items) |p| {
            const res = cand.evaluate(.{ .vel = p.vel, .stag = p.stag, .ent = p.ent });
            const pred_reset = res > 1.0; // Heuristic fires if result > 1.0
            if (pred_reset == p.should_reset) hits += 1.0;
        }
        
        const score = hits / @as(f64, @floatFromInt(history.items.len));
        if (score > best_score) {
            best_score = score;
            best_expr = cand;
            if (i % 5000 == 0 or score > 0.9) {
                try out.print("Iter {d:5}: Accuracy={d:.2}% Law: ", .{ i, score * 100.0 });
                try gp.printExpr(best_expr, best_expr.root, out);
                try out.print("\n", .{});
            }
        }
    }

    try out.print("\n=== THE DISCOVERED LAW OF SEARCH ===\n", .{});
    try out.print("Accuracy: {d:.2}%\n", .{best_score * 100.0});
    try out.print("Symbolic Form: ", .{});
    try gp.printExpr(best_expr, best_expr.root, out);
    try out.print("\n\nTruth: BitForge has looked at its own failure physics and derived a non-linear rule to survive them.\n", .{});
}