use std::{fmt::Debug, path::Path, vec};

use crate::egg_lang::RdgEggOp;
use crate::{RdgEgg, egg_lang::CastOp};
use babble::{
  AstNode, bb_query::BBQuery, runner::OperationInfo, schedule::Schedulable,
};
use egg::RecExpr;
use estimator::{
  EstimableNode, ModelLoader, area_estimator::AreaEstimator,
  delay_estimator::DelayEstimator,
};

use super::{BinaryOp, EggType, TernaryOp, UnaryOp};

impl RdgEgg {
  fn op_map(&self) -> &str {
    match &self.op {
      RdgEggOp::Apply => "apply",
      RdgEggOp::Arg(_) => "arg",
      RdgEggOp::Const(_) => "const",
      RdgEggOp::DoWhile => "do_while",
      RdgEggOp::Dummy(_) => "dummy",
      RdgEggOp::Function(_) => "function",
      RdgEggOp::Get(_) => "get",
      RdgEggOp::IOBarrier => "io_barrier",
      RdgEggOp::Lambda => "lambda",
      RdgEggOp::Lib(_, _, _, _) => "lib",
      RdgEggOp::LibVar(_) => "lib_var",
      RdgEggOp::List => "list",
      RdgEggOp::RulerVar(_) => "ruler_var",
      RdgEggOp::Switch => "switch",
      RdgEggOp::Tuple(_) => "tuple",
      RdgEggOp::Var(_) => "var",
      RdgEggOp::Bop(op) => match op {
        BinaryOp::Add => match self.info.result_tys.len() {
          0 => "kAdd",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kAdd",
            EggType::FloatT(_) => "FPAdd",
            _ => "kAdd",
          },
          _ => "kAdd",
        },
        BinaryOp::Sub => match self.info.result_tys.len() {
          0 => "kSub",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSub",
            EggType::FloatT(_) => "FPAdd",
            _ => "kSub",
          },
          _ => "kSub",
        },
        BinaryOp::Mul => match self.info.result_tys.len() {
          0 => "kUMul",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kUMul",
            EggType::FloatT(_) => "FPMul",
            _ => "kUMul",
          },
          _ => "kUMul",
        },
        BinaryOp::Div => "kUDiv",
        BinaryOp::Mod => "kUDiv",
        BinaryOp::Eq => match self.info.result_tys.len() {
          0 => "kEq",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kEq",
            EggType::FloatT(_) => "FPEq",
            _ => "kEq",
          },
          _ => "kEq",
        },
        BinaryOp::Ne => match self.info.result_tys.len() {
          0 => "kEq",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kEq",
            EggType::FloatT(_) => "FPEq",
            _ => "kEq",
          },
          _ => "kEq",
        },
        BinaryOp::LessThan => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::GreaterThan => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::LessEq => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::GreaterEq => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::Max => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::Min => match self.info.result_tys.len() {
          0 => "kSGt",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSGt",
            EggType::FloatT(_) => "FPGt",
            _ => "kSGt",
          },
          _ => "kSGt",
        },
        BinaryOp::Shl => "kShll",
        BinaryOp::Shr => "kShll",
        BinaryOp::And => "kAnd",
        BinaryOp::Or => "kOr",
        BinaryOp::Xor => "kXor",
        BinaryOp::Load => "load",
        BinaryOp::StateMerge => "state_merge",
      },
      RdgEggOp::Uop(op) => match op {
        UnaryOp::Abs => "kNot",
        UnaryOp::Not => "kNot",
        UnaryOp::Neg => "kNeg",
        UnaryOp::Cast(cast_op) => match cast_op {
          CastOp::SExt(_) => "kSignExt",
          CastOp::ZExt(_) => "kZeroExt",
          CastOp::Trunc(_) => "kTrunc",
          CastOp::FPTrunc => "FPTrunc",
          CastOp::FPExt => "FPExt",
        },
      },
      RdgEggOp::Top(op) => match op {
        TernaryOp::Select => "kSel",
        TernaryOp::Store => "store",
      },
      RdgEggOp::VectorOp(vector_op) => match vector_op {
        super::VectorOp::Vec => "vec",
        super::VectorOp::VecAdd => match self.info.result_tys.len() {
          0 => "kAdd",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kAdd",
            EggType::FloatT(_) => "FPAdd",
            _ => "kAdd",
          },
          _ => "kAdd",
        },
        super::VectorOp::VecSub => match self.info.result_tys.len() {
          0 => "kSub",
          1 => match self.info.result_tys[0] {
            EggType::IntT(_) => "kSub",
            EggType::FloatT(_) => "FPAdd",
            _ => "kSub",
          },
          _ => "kSub",
        },
        super::VectorOp::VecMul | super::VectorOp::VecMac => {
          match self.info.result_tys.len() {
            0 => "kUMul",
            1 => match self.info.result_tys[0] {
              EggType::IntT(_) => "kUMul",
              EggType::FloatT(_) => "FPMul",
              _ => "kUMul",
            },
            _ => "kUMul",
          }
        }
        &super::VectorOp::VecShl => "kShll",
        super::VectorOp::VecShr => "kShll",
        super::VectorOp::VecDiv => "kUDiv",
        super::VectorOp::VecNeg => "kNeg",
        super::VectorOp::VecNot => "kNot",
        super::VectorOp::VecAbs => "kNot",
        super::VectorOp::VecRem => "kUDiv",
        super::VectorOp::VecAnd => "kAnd",
        super::VectorOp::VecOr | super::VectorOp::VecCmp => "kOr",
        super::VectorOp::VecXor => "kXor",
        super::VectorOp::VecSext => "kSignExt",
        super::VectorOp::VecZext => "kZeroExt",
        super::VectorOp::VecTrunc => "kTrunc",
        super::VectorOp::VecFPTrunc => "FPTrunc",
        super::VectorOp::VecFPExt => "FPExt",
        super::VectorOp::VecLoad => "load",
        super::VectorOp::VecStore => "store",
        super::VectorOp::Concat => "concat",
        super::VectorOp::Gather(_) => "gather",
        super::VectorOp::Shuffle(_) => "shuffle",
      },
      RdgEggOp::OpSelect => "kSel",
      RdgEggOp::OpPack(_) => "op_pack",
      RdgEggOp::OpMask => "op_mask",
    }
  }
}

#[derive(Clone)]
pub struct LangArea {
  pub estimator: AreaEstimator,
}

impl Default for LangArea {
  fn default() -> Self {
    let area_model_path = Path::new("estimator/models/area_asap7.bin");
    let area_model = ModelLoader::load_model(&area_model_path).unwrap();
    let area_estimator = AreaEstimator::new("asap7-area", area_model);
    Self {
      estimator: area_estimator,
    }
  }
}

impl Debug for LangArea {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    write!(f, "LangArea {{ estimator: {:?} }}", self.estimator.name())
  }
}

#[derive(Clone)]
pub struct LangDelay {
  pub estimator: DelayEstimator,
}

impl Default for LangDelay {
  fn default() -> Self {
    let delay_model_path = Path::new("estimator/models/delay_asap7.bin");
    let delay_model = ModelLoader::load_model(&delay_model_path).unwrap();
    let delay_estimator = DelayEstimator::new("asap7-delay", delay_model);
    Self {
      estimator: delay_estimator,
    }
  }
}

impl Debug for LangDelay {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    write!(f, "LangDelay {{ estimator: {:?} }}", self.estimator.name())
  }
}

#[derive(Clone, Debug)]
struct EstimableAstNode {
  node: AstNode<RdgEgg>,
  args: Vec<EstimableAstNode>,
}

impl EstimableAstNode {
  fn new(node: AstNode<RdgEgg>, args: Vec<AstNode<RdgEgg>>) -> Self {
    let args = args
      .iter()
      .map(|n| EstimableAstNode {
        node: n.clone(),
        args: vec![],
      })
      .collect();
    EstimableAstNode { node, args }
  }
}

impl EstimableNode for EstimableAstNode {
  fn op(&self) -> &str {
    self.node.operation().op_map()
  }

  fn bit_count(&self) -> i64 {
    let info = self.node.operation().info.clone();
    if info.result_tys.len() > 0 {
      match info.result_tys[0] {
        EggType::IntT(w) => w.unwrap_or(32) as i64,
        EggType::FloatT(w) => w.unwrap_or(32) as i64,
        _ => 32,
      }
    } else {
      32
    }
  }

  fn operands(&self) -> Vec<&dyn EstimableNode> {
    let nodes = self.args.iter().map(|n| n as &dyn EstimableNode).collect();
    nodes
  }

  fn is_literal(&self) -> bool {
    self.node.operation().info.result_tys.len() == 0
  }

  fn operands_identical(&self) -> bool {
    if self.args.len() < 2 {
      return false;
    }
    let first = &self.args[0];
    self.args.iter().skip(1).all(|op| {
      op.node.operation().op_map() == first.node.operation().op_map()
        && op.bit_count() == first.bit_count()
    })
  }
}

impl Schedulable<LangArea, LangDelay> for AstNode<RdgEgg> {
  fn op_delay(&self, ld: &LangDelay, args: Vec<Self>) -> usize {
    // println!("Estimating delay for node: {:?}", self);
    let mut estimable_node = EstimableAstNode::new(self.clone(), args);
    if let RdgEggOp::OpPack(op_pack) = &self.operation().op {
      let mut total_delay = usize::MAX;
      for op in op_pack.config.iter() {
        estimable_node.node.operation_mut().op = match op.as_str() {
          "add" => RdgEggOp::Bop(BinaryOp::Add),
          "sub" => RdgEggOp::Bop(BinaryOp::Sub),
          "mul" => RdgEggOp::Bop(BinaryOp::Mul),
          "div" => RdgEggOp::Bop(BinaryOp::Div),
          "mod" => RdgEggOp::Bop(BinaryOp::Mod),
          "eq" => RdgEggOp::Bop(BinaryOp::Eq),
          "ne" => RdgEggOp::Bop(BinaryOp::Ne),
          "lt" => RdgEggOp::Bop(BinaryOp::LessThan),
          "gt" => RdgEggOp::Bop(BinaryOp::GreaterThan),
          "le" => RdgEggOp::Bop(BinaryOp::LessEq),
          "ge" => RdgEggOp::Bop(BinaryOp::GreaterEq),
          "max" => RdgEggOp::Bop(BinaryOp::Max),
          "min" => RdgEggOp::Bop(BinaryOp::Min),
          "shl" => RdgEggOp::Bop(BinaryOp::Shl),
          "shr" => RdgEggOp::Bop(BinaryOp::Shr),
          "and" => RdgEggOp::Bop(BinaryOp::And),
          "or" => RdgEggOp::Bop(BinaryOp::Or),
          "xor" => RdgEggOp::Bop(BinaryOp::Xor),
          "not" => RdgEggOp::Uop(UnaryOp::Not),
          "abs" => RdgEggOp::Uop(UnaryOp::Abs),
          &_ => RdgEggOp::List,
        };
        let op_delay = ld.estimator.get_operation_delay_in_ps(&estimable_node);
        total_delay = total_delay.min(match op_delay {
          Ok(d) => d as usize,
          Err(_) => usize::MAX,
        });
      }
      total_delay as usize
    } else if self.operation().op == RdgEggOp::OpSelect {
      0
    } else {
      // For non-op_pack operations, just estimate the delay directly
      let delay = ld.estimator.get_operation_delay_in_ps(&estimable_node);
      match delay {
        Ok(d) => d as usize,
        Err(_) => 0,
      }
    }
  }

  fn op_area(&self, la: &LangArea, args: Vec<Self>) -> usize {
    let vec_len = self.operation().get_vec_len();
    let k = 0.7; // Scaling factor for vector operations area estimation
    // 闭包，用于获取操作符的delay
    let get_op_area = |node: &EstimableAstNode| -> usize {
      let area = la.estimator.get_operation_area_in_square_microns(node);
      let mut raw_area = match area {
        Ok(d) => d as usize,
        Err(_) => 0,
      };
      if self.operation().op == RdgEggOp::OpSelect {
        raw_area = 0;
      }
      if vec_len > 1 {
        // If the operation is a vector operation, scale the delay
        ((raw_area * vec_len) as f32 * k) as usize
      } else {
        raw_area
      }
    };
    let mut estimable_node = EstimableAstNode::new(self.clone(), args);
    if let RdgEggOp::OpPack(op_pack) = &self.operation().op {
      let mut total_area = 0;
      for op in op_pack.config.iter() {
        estimable_node.node.operation_mut().op = match op.as_str() {
          "add" => RdgEggOp::Bop(BinaryOp::Add),
          "sub" => RdgEggOp::Bop(BinaryOp::Sub),
          "mul" => RdgEggOp::Bop(BinaryOp::Mul),
          "div" => RdgEggOp::Bop(BinaryOp::Div),
          "mod" => RdgEggOp::Bop(BinaryOp::Mod),
          "eq" => RdgEggOp::Bop(BinaryOp::Eq),
          "ne" => RdgEggOp::Bop(BinaryOp::Ne),
          "lt" => RdgEggOp::Bop(BinaryOp::LessThan),
          "gt" => RdgEggOp::Bop(BinaryOp::GreaterThan),
          "le" => RdgEggOp::Bop(BinaryOp::LessEq),
          "ge" => RdgEggOp::Bop(BinaryOp::GreaterEq),
          "max" => RdgEggOp::Bop(BinaryOp::Max),
          "min" => RdgEggOp::Bop(BinaryOp::Min),
          "shl" => RdgEggOp::Bop(BinaryOp::Shl),
          "shr" => RdgEggOp::Bop(BinaryOp::Shr),
          "and" => RdgEggOp::Bop(BinaryOp::And),
          "or" => RdgEggOp::Bop(BinaryOp::Or),
          "xor" => RdgEggOp::Bop(BinaryOp::Xor),
          "not" => RdgEggOp::Uop(UnaryOp::Not),
          "abs" => RdgEggOp::Uop(UnaryOp::Abs),
          &_ => RdgEggOp::List,
        };
        let op_area = get_op_area(&estimable_node);
        total_area += op_area;
      }
      total_area
    } else {
      // For non-op_pack operations, just estimate the delay directly
      get_op_area(&estimable_node)
    }
  }

  fn op_latency(&self) -> usize {
    0
  }

  fn op_latency_cpu(&self, bb_query: &BBQuery) -> f64 {
    let vec_len = self.operation().get_vec_len();

    if self.operation().get_bbs_info().is_empty() && !self.operation().is_var()
    {
      println!(
        "Warning: op_latency_cpu called on node with no BB info: {:?}",
        self
      );
    }
    if self.operation().info.bbs.len() <= 0 {
      return 1.0 * vec_len as f64;
    }
    match bb_query.get(&self.operation().info.bbs[0]) {
      Some(bb_entry) => bb_entry.cpo * vec_len as f64,
      None => 1.0 * vec_len as f64,
    }
  }
}

/// Roughly estimate the delay of an expression, used in e.g. for pruning
/// rewrite rules
pub(super) fn get_delay(expr: &RecExpr<AstNode<RdgEgg>>) -> usize {
  let mut node_delay: Vec<usize> = Vec::new();
  for node in expr {
    let op_delay = 1;
    let args_max_delay = node
      .args()
      .iter()
      .map(|id| {
        let idx: usize = (*id).into();
        node_delay[idx]
      })
      .max()
      .unwrap_or(0);
    node_delay.push(op_delay + args_max_delay);
  }
  *node_delay.last().unwrap_or(&0)
}
