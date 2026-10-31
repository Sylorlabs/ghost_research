//! Most code came from [egraphs-good/eggcc](https://github.com/egraphs-good/eggcc)
//! RVSDGs support intra-function control flow in the form of switch statements
//! and do-while loops (gamma and theta nodes, respectively).
//!
//! RDG extends RVSDG.
//!
//! # References
//!
//! * ["RVSDG: An Intermediate Representation for Optimizing Compilers"](https://arxiv.org/abs/1912.05036)
//! by Reissmann, Meyer, Bahmann, and Själander
//! * ["Perfect Reconstructability of Control Flow from Demand Dependence Graphs"](https://dl.acm.org/doi/10.1145/2693261)
//! by Bahmann, Reissmann,  Jahre, and Meyer
//! * [optir](https://github.com/jameysharp/optir) project is a major
//!   inspiration.

use ordered_float::OrderedFloat;
use std::{fmt, vec};
use strum::Display;

pub mod contruct;
pub mod from_jlm_rvsdg;
mod to_egg;

#[cfg(test)]
pub mod tests;

pub type Id = usize;

#[derive(Debug, PartialEq, Clone)]
pub enum BasicExpr<Op> {
  /// A primitive operation.
  /// Also includes effect operations. These are a lot like an `Op`, but they
  /// only produce a "state edge" as output.
  /// The state edge for these operators is the last input and last output.
  Op(PrimOp, Vec<Op>),
  /// Any operation of no interest
  Dummy(String, Vec<Op>, usize),
  /// A literal constant.
  Const(Literal, RdgType),
}

impl<Op> BasicExpr<Op> {
  pub fn num_outputs(&self) -> usize {
    match self {
      BasicExpr::Op(PrimOp::Load, _) => 2,
      BasicExpr::Op(_, _) => 1,
      BasicExpr::Dummy(_, _, n_outputs) => *n_outputs,
      BasicExpr::Const(_, _) => 1,
      // BasicExpr::Match(_, _, _, _) => 1,
    }
  }

  #[allow(dead_code)]
  pub fn push_operand(&mut self, op: Op) {
    match self {
      BasicExpr::Op(_, operands) => operands.push(op),
      BasicExpr::Dummy(_, operands, _) => operands.push(op),
      BasicExpr::Const(_, _) => panic!("Cannot push operand to const"),
      // BasicExpr::Match(_, _, _, _) => panic!("Cannot push operand to match"),
    }
  }
}

#[derive(Clone, PartialEq, Eq, Debug, Hash)]
pub enum Operand {
  /// A reference to an argument in the enclosing region.
  Arg { index: usize, ty: RdgType },
  /// Project a single output from a region in the RVSDG.
  Project {
    index: usize,
    node_id: Id,
    ty: RdgType,
  },
}

pub type BBInfo = Vec<String>;

impl From<BBInfo> for crate::egg_lang::RdgEggInfo {
  fn from(bb_info: BBInfo) -> Self {
    crate::egg_lang::RdgEggInfo {
      bbs: bb_info,
      result_tys: vec![],
    }
  }
}

#[derive(Debug, PartialEq, Clone)]
pub enum RdgBody {
  BasicOp {
    expr: BasicExpr<Operand>,
    output_tys: Vec<RdgType>,
  },

  /// Conditional branch, where the outputs chosen depend on the predicate.
  Gamma {
    pred: Operand,
    inputs: Vec<Operand>,
    /// invariant: all of the vecs in output have
    /// the same length.
    outputs: Vec<Vec<Operand>>,
    bb_infos: Vec<BBInfo>,
    output_tys: Vec<RdgType>,
  },

  /// A tail-controlled loop.
  Theta {
    pred: Operand,
    inputs: Vec<Operand>,
    outputs: Vec<Operand>,
    bb_info: BBInfo,
    output_tys: Vec<RdgType>,
  },
}

#[derive(Debug, Clone, PartialEq, Eq, Hash, Display)]
pub enum RdgType {
  Void,
  Int(usize),
  Bool,
  Float(usize),
  Pointer,
  State,
  Vector(Box<RdgType>, usize),
  CTL(i32),
}

/// Represents a single function as an RDG.
/// The function has arguments, a result, and nodes.
/// The nodes are stored in a vector, and variants of RdgBody refer
/// to nodes by their index in the vector.
#[derive(Clone)]
pub struct RdgFunction {
  /// The name of this function.
  pub name: String,

  /// The backing heap for Rdg node ids within this function.
  /// Invariant: nodes refer only to nodes with a lower index.
  pub nodes: Vec<RdgBody>,

  /// A list of results pointing into this function.
  pub results: Vec<Option<Operand>>,

  /// The basic block information for this function.
  pub bb_info: BBInfo,
}

impl fmt::Debug for RdgFunction {
  fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
    f.debug_struct("RdgFunction")
      // .field("args", &self.args)
      .field("result", &self.results)
      .field("bb_info", &self.bb_info);
    let mut map = f.debug_map();
    for (i, node) in self.nodes.iter().enumerate() {
      map.entry(&i, node);
    }
    map.finish()?;
    write!(f, "}}")
  }
}

/// An Rdg program.
/// For now, it's simply a vector of [RdgFunction]s.
#[derive(Debug)]
pub struct RdgProgram {
  /// A list of functions in this program.
  /// The last function is the entry point (main function).
  pub functions: Vec<RdgFunction>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display)]
pub enum PrimOp {
  /// Absolute Values
  Abs,
  Add,
  Sub,
  Mul,
  Div,
  Mod,
  Eq,
  Ne,
  Lt,
  Gt,
  Le,
  Ge,
  Not,
  And,
  Or,
  Xor,
  Call,
  /// Select
  Select,
  /// Signed max
  Smax,
  /// Signed min
  Smin,
  /// Shift left
  Shl,
  /// Shift right
  Shr,
  Phi,
  Fadd,
  Fsub,
  Fmul,
  Fdiv,
  Feq,
  Flt,
  Fgt,
  Fle,
  Fge,
  /// Float max
  Fmax,
  /// Float min
  Fmin,
  Load,
  PtrAdd,
  Store,
  StateMerge,
  /// Cast operations
  ZExt(usize, usize), // from, to
  SExt(usize, usize),  // from, to
  Trunc(usize, usize), // from, to
  FPTrunc,
  FPExt,
  // Alloc(RdgType),
  // Nop,
  VECFPOPAdd,
  VECFPOPMul,
  VECFPOPSub,
  VECFPOPDiv,
  VECFNeg,
  VECFPCMP,
  VECConstant,
  IOBarrier,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Display)]
pub enum Literal {
  /// Integers
  Int(i64),
  /// Bool,
  Bool(bool),
  /// Floating Points
  Float(OrderedFloat<f64>),
}
