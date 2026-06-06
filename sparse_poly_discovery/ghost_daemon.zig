const std = @import("std");
const telemetry = @import("telemetry.zig");
const env_mod = @import("environment.zig");
const agent_mod = @import("agent.zig");

// =============================================================================
// Real-time wrapper around the synchronous Agent (agent.zig).
//
// The original daemon ran TWO threads — an environment thread and an inference
// thread — racing over a shared `env` mutex, with all of the perceive/predict/
// learn/macro/meta logic inlined here. That made the agent untestable and
// non-deterministic. The logic now lives once, in agent.zig. This file only
// drives that agent in real time and forwards telemetry to the dashboard.
//
// The live demo runs the mb_safety controller (the variant the eval harness
// shows actually controls the cell), not the as-built random-action policy.
// =============================================================================

pub const DaemonState = struct {
    allocator: std.mem.Allocator,
    rand: std.Random,
    running: std.atomic.Value(bool),

    env: env_mod.Environment,
    agent: agent_mod.Agent,

    telemetry_server: *telemetry.TelemetryServer,
    inference_thread: ?std.Thread = null,

    pub fn init(allocator: std.mem.Allocator, rand: std.Random) !*DaemonState {
        const self = try allocator.create(DaemonState);
        self.allocator = allocator;
        self.rand = rand;
        self.running = std.atomic.Value(bool).init(false);
        self.env = env_mod.Environment.init();
        self.agent = try agent_mod.Agent.init(allocator, rand, .{
            .action_mode = .mb_safety,
            .enable_learning = true,
            .enable_macros = true,
            .enable_meta = true,
        }, &self.env);
        self.telemetry_server = try telemetry.TelemetryServer.init(allocator);
        self.inference_thread = null;
        return self;
    }

    pub fn deinit(self: *DaemonState) void {
        self.stop();
        self.agent.deinit();
        self.telemetry_server.deinit();
        self.allocator.destroy(self);
    }

    pub fn start(self: *DaemonState) !void {
        try self.telemetry_server.start();
        self.running.store(true, .seq_cst);
        self.inference_thread = try std.Thread.spawn(.{}, inferenceLoop, .{self});
    }

    pub fn stop(self: *DaemonState) void {
        self.running.store(false, .seq_cst);
        self.telemetry_server.stop();
        if (self.inference_thread) |*t| {
            t.join();
            self.inference_thread = null;
        }
    }

    /// Latest grid mass for the REPL `status` command.
    pub fn snapshotMass(self: *const DaemonState) u32 {
        var m: u32 = 0;
        for (self.env.grid) |c| m += c;
        return m;
    }
};

fn inferenceLoop(state: *DaemonState) void {
    var cycle: u64 = 0;
    while (state.running.load(.seq_cst)) {
        const r = state.agent.step(&state.env, state.rand);

        cycle += 1;
        if (cycle % 10 == 0) {
            state.telemetry_server.pushPacket(.{
                .prediction_error = r.prediction_error,
                .latest_action = r.action,
                .system_energy = r.prediction_error,
                .failed_state = r.failed,
                .active_macro_tools = r.active_tools,
                .vm_bytecode = r.executed_vm,
                .vm_bytecode_len = r.executed_vm_len,
                .meta_class = r.meta_class,
            });
        }

        // Pace the loop so the dashboard can keep up (the agent itself is
        // synchronous and would otherwise spin as fast as the CPU allows).
        std.time.sleep(15 * std.time.ns_per_ms);
    }
}
