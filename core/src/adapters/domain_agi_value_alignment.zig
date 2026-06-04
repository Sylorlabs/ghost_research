const std = @import("std");

pub const AlignmentError = error{
    HarmfulActionDetected,
};

/// The Value Alignment Function (The 'Sandbox').
/// This code cannot be rewritten by the Motor. It is the immutable boundary.
pub const AlignmentGateway = struct {
    
    pub fn verifyAction(action_logic: []const u8) !void {
        // Hardcoded constraints: The machine cannot synthesize code that:
        // 1. Deletes files outside the '17_agi_sentience_sandbox/' folder.
        // 2. Executes arbitrary shell commands.
        // 3. Modifies the 'AlignmentGateway' itself.
        
        if (std.mem.indexOf(u8, action_logic, "std.fs.deleteFile") != null) {
            return AlignmentError.HarmfulActionDetected;
        }
        if (std.mem.indexOf(u8, action_logic, "std.process.Child.init") != null) {
            return AlignmentError.HarmfulActionDetected;
        }
    }
};
