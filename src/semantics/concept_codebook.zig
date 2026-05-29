const std = @import("std");
const vsa = @import("vsa");

// ============================================================================
// MVD CONCEPT CODEBOOK (PURE GEOMETRIC SYNTAX)
// ============================================================================

pub const Concept = enum(u8) {
    FnDecl = 0, // Function declaration shell
    Parameter = 1, // Named typed parameter
    ReturnStmt = 2, // Return expression
    Type_u32 = 3, // The u32 type literal
    Type_u8_Array = 4, // The [3]u8 type literal
    Op_Add = 5, // Binary + (wrapping)
    Op_Sub = 6, // Binary - (wrapping)
    Op_Mul = 7, // Binary * (wrapping)
    VarAssign = 8, // const x = expr;
    Cast_u32_to_u8 = 9, // @truncate(expr)
};

pub const ConceptCount: usize = 10;

// 1. Orthogonal Port Vectors (Breaks commutativity: A->B != B->A)
pub const Port_Parent = vsa.Hypervector.initRandom(0x8B7D2F1A);
pub const Port_Child  = vsa.Hypervector.initRandom(0x4C9E6A3B);

// 2. Structural Role Vectors (Chemical Valence classes)
pub const Role_Statement  = vsa.Hypervector.initRandom(0x11111111);
pub const Role_Expression = vsa.Hypervector.initRandom(0x22222222);
pub const Role_Type       = vsa.Hypervector.initRandom(0x33333333);
pub const Role_Parameter  = vsa.Hypervector.initRandom(0x44444444);

pub fn superpose(vecs: []const vsa.Hypervector) vsa.Hypervector {
    var res = vsa.Hypervector.initEmpty();
    if (vecs.len == 0) return res;
    if (vecs.len == 1) return vecs[0];
    
    for (0..vsa.WordCount) |w| {
        for (0..64) |b| {
            var count: u32 = 0;
            for (vecs) |v| {
                if (((v.data[w] >> @intCast(b)) & 1) == 1) count += 1;
            }
            if (count > vecs.len / 2 or (count == vecs.len / 2 and ((vecs[0].data[w] >> @intCast(b)) & 1) == 1)) {
                res.data[w] |= (@as(u64, 1) << @intCast(b));
            }
        }
    }
    return res;
}

pub const ConceptGeometry = struct {
    identity: vsa.Hypervector,    // The raw base seed
    definition: vsa.Hypervector,  // What this node IS (Outward to parent)
    expectation: vsa.Hypervector, // What this node WANTS (Inward to child)
};

pub const Codebook = struct {
    const base_seed: u64 = 0xA7C3_E9F1_2B4D_6850;

    pub fn getConceptGeometry(concept: Concept) ConceptGeometry {
        const identity = vsa.Hypervector.initRandom(base_seed ^ @as(u64, @intFromEnum(concept)));
        var def = vsa.Hypervector.initEmpty();
        var exp = vsa.Hypervector.initEmpty();

        switch (concept) {
            .FnDecl => {
                def = superpose(&.{Role_Statement.bind(Port_Parent)});
                exp = superpose(&.{
                    Role_Parameter.bind(Port_Child),
                    Role_Type.bind(Port_Child),
                    Role_Statement.bind(Port_Child)
                });
            },
            .ReturnStmt => {
                def = superpose(&.{Role_Statement.bind(Port_Parent)});
                exp = superpose(&.{Role_Expression.bind(Port_Child)});
            },
            .VarAssign => {
                def = superpose(&.{Role_Statement.bind(Port_Parent)});
                exp = superpose(&.{
                    Role_Type.bind(Port_Child),
                    Role_Expression.bind(Port_Child)
                });
            },
            .Op_Add, .Op_Sub, .Op_Mul => {
                def = superpose(&.{Role_Expression.bind(Port_Parent)});
                exp = superpose(&.{Role_Expression.bind(Port_Child)});
            },
            .Cast_u32_to_u8 => {
                def = superpose(&.{Role_Expression.bind(Port_Parent)});
                exp = superpose(&.{Role_Expression.bind(Port_Child)});
            },
            .Type_u32, .Type_u8_Array => {
                def = superpose(&.{Role_Type.bind(Port_Parent)});
            },
            .Parameter => {
                def = superpose(&.{Role_Parameter.bind(Port_Parent)});
                exp = superpose(&.{Role_Type.bind(Port_Child)});
            },
        }
        return .{ .identity = identity, .definition = def, .expectation = exp };
    }

    // Compute resonance scores for ALL 10 concepts against a projected state HV.
    pub fn computeResonance(state_hv: vsa.Hypervector) [ConceptCount]u32 {
        var scores: [ConceptCount]u32 = undefined;
        inline for (0..ConceptCount) |i| {
            const concept: Concept = @enumFromInt(i);
            const geom = getConceptGeometry(concept);
            scores[i] = state_hv.similarity(geom.identity);
        }
        return scores;
    }
};

test "Concept Codebook: Identity mutually orthogonal" {
    for (0..ConceptCount) |i| {
        const geom_i = Codebook.getConceptGeometry(@enumFromInt(i));
        for (i + 1..ConceptCount) |j| {
            const geom_j = Codebook.getConceptGeometry(@enumFromInt(j));
            const sim = geom_i.identity.similarity(geom_j.identity);
            try std.testing.expect(sim > 450 and sim < 550);
        }
    }
}
