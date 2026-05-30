const std = @import("std");
const vsa = @import("vsa");
const Sandbox = @import("sandbox").Sandbox;
const SandboxResult = @import("sandbox").SandboxResult;
const topology = @import("ghost_topology");
const AstEmitter = @import("ghost_ast_emitter").AstEmitter;
const void_eng = @import("state");
const grounding = @import("ghost_grounding");
const codebook = @import("ghost_codebook");

// ============================================================================
// THE REALITY FEEDBACK LOOP
//
// This is the closed-loop core of the Ghost Sovereign engine.
// Each iteration:
//   1. Ask the Void Engine for a mathematical invention (ChildKnot)
//   2. Project the FULL 512-chamber state → 1024-bit HV
//   3. Extract a ConceptGraph using VSA algebra (resonance + bind edges)
//   4. Dynamically assemble an AST from the graph
//   5. Render to Zig source code
//   6. Compile + run in the Sandbox
//   7. On failure: pipe stderr back as geometric heat → loop
//   8. On success: return the verified result
//
// The engine "dreams" a solution, the compiler checks reality,
// and the error messages become mathematical pressure that forces
// the engine to dream differently.
// ============================================================================

pub const CompilerLoop = struct {
    allocator: std.mem.Allocator,
    sandbox: Sandbox,
    emitter: AstEmitter,
    engine: *void_eng.VoidEngine,

    // Diagnostic counters
    total_attempts: u32 = 0,
    compile_failures: u32 = 0,
    empty_graphs: u32 = 0,
    render_failures: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, engine: *void_eng.VoidEngine) !CompilerLoop {
        return .{
            .allocator = allocator,
            .sandbox = try Sandbox.init(allocator),
            .emitter = AstEmitter.init(allocator),
            .engine = engine,
        };
    }

    pub fn deinit(self: *CompilerLoop) void {
        self.sandbox.deinit();
    }

    pub const SuccessResult = struct {
        sandbox_res: SandboxResult,
        generated_code: []const u8,
    };

    pub fn solveAndVerify(self: *CompilerLoop, intent_text: []const u8, max_iterations: usize) !?SuccessResult {
        // Semantic Injection: Ground the Void Engine state to the requested concepts
        const intent_concepts = grounding.Grounding.scanAndExtract(self.allocator, intent_text) catch &[_]codebook.Concept{};
        if (intent_concepts.len > 0) {
            std.debug.print("[System] Semantic Grounding: Pre-loading {d} concepts into the Void matrix...\n", .{intent_concepts.len});
            grounding.Grounding.injectTension(&self.engine.state, intent_concepts);
        }

        var generation: u32 = 0;

        while (generation < max_iterations) : (generation += 1) {
            self.total_attempts += 1;

            // 1. Ask the Void Engine for a mathematical invention
            const candidate_opt = self.engine.maybeInventText(intent_text, generation);
            if (candidate_opt == null) {
                // Engine is balanced or exhausted — inject chaos to destabilize
                self.engine.shapeTextPressure(generation, "INJECT_CHAOS_DESTABILIZE");
                continue;
            }
            const candidate = candidate_opt.?;

            // 2 + 3. Extract ConceptGraph from the FULL 512-chamber state
            // Uses the entire chamber_snapshot as a single geometric vector.
            // NO chambers are discarded.
            const graph = topology.extractGraph(&candidate.chamber_snapshot);

            if (graph.node_count == 0) {
                self.empty_graphs += 1;
                self.engine.shapeTextPressure(candidate.child_mark, "Error: Empty ConceptGraph — no concepts resonated above threshold");
                continue;
            }

            // [DEBUG] Print the raw topology before AST interference
            graph.printTopology(std.io.getStdErr().writer()) catch {};

            // 4. Dynamically assemble AST from the ConceptGraph
            const ast_tree = self.emitter.assembleFromGraph(&graph) catch {
                self.render_failures += 1;
                self.engine.shapeTextPressure(candidate.child_mark, "Error: AST Assembly Failure — graph topology incompatible");
                continue;
            };

            // 5. Render AST to Zig source code
            var buffer = std.ArrayList(u8).init(self.allocator);
            defer buffer.deinit();
            self.emitter.render(buffer.writer(), ast_tree, 0) catch {
                self.render_failures += 1;
                self.engine.shapeTextPressure(candidate.child_mark, "Error: AST Render Failure — recursive tree walk produced invalid output");
                continue;
            };
            const generated_code = buffer.items;

            if (generated_code.len == 0) {
                self.render_failures += 1;
                self.engine.shapeTextPressure(candidate.child_mark, "Error: Empty code output — renderer produced zero bytes");
                continue;
            }

            // 6. Compile + run in the Sandbox
            const result = try self.sandbox.verifyCode(generated_code);

            // 7. The Reality Feedback Loop
            if (result.success) {
                // Mathematical invention compiles and runs!
                return SuccessResult{
                    .sandbox_res = result,
                    .generated_code = try self.allocator.dupe(u8, generated_code),
                };
            } else {
                // Map the compiler's exact error message back into geometric tension.
                // Different error strings hash to different chamber perturbations,
                // which shift the projected HV, which changes concept resonance,
                // which changes the graph topology, which changes the generated code.
                self.compile_failures += 1;

                // Feed the full stderr as heat — each unique error shifts chambers differently
                if (result.stderr.len > 0) {
                    var triage_applied = false;
                    const stderr = result.stderr;
                    const std_mem = std.mem;
                    
                    var injection_concepts = std.ArrayList(codebook.Concept).init(self.allocator);
                    defer injection_concepts.deinit();

                    // String Triage: Dynamic pattern matching
                    if (std_mem.indexOf(u8, stderr, "expected type") != null) {
                        if (std_mem.indexOf(u8, stderr, "[3]u8") != null) {
                            injection_concepts.append(.Type_u8_Array) catch {};
                            triage_applied = true;
                        }
                    }
                    if (std_mem.indexOf(u8, stderr, "found") != null) {
                        if (std_mem.indexOf(u8, stderr, "'u32'") != null or std_mem.indexOf(u8, stderr, " u32 ") != null) {
                            // If we need a [3]u8 and we have a u32, we probably need a cast/conversion
                            injection_concepts.append(.Cast_u32_to_u8) catch {};
                            triage_applied = true;
                        }
                    }

                    if (triage_applied and injection_concepts.items.len > 0) {
                        std.debug.print("[Targeted Error Heat] Applying directional gradient & pinning missing types: {d} concepts\n", .{injection_concepts.items.len});
                        grounding.Grounding.injectTargetedHeat(&self.engine.state, injection_concepts.items);
                        grounding.Grounding.pinConcepts(&self.engine.state, injection_concepts.items);
                        // Also inject a slight text pressure to ensure the seed advances
                        const max_err_len = @min(result.stderr.len, 64);
                        self.engine.shapeTextPressure(candidate.child_mark, result.stderr[0..max_err_len]);
                    } else {
                        // Fallback to chaotic destabilization
                        const max_err_len = @min(result.stderr.len, 256);
                        self.engine.shapeTextPressure(candidate.child_mark, result.stderr[0..max_err_len]);
                    }
                } else {
                    self.engine.shapeTextPressure(candidate.child_mark, "Error: Sandbox returned failure with no stderr");
                }
            }
        }

        // Exhausted iterations without success
        return null;
    }
};
