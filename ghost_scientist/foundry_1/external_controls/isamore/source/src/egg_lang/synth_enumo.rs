use super::*;
use crate::egg_lang::{BinaryOp, RdgConst, RdgEggOp, TernaryOp, UnaryOp};
use egg::{ENodeOrVar, Pattern, RecExpr};
use enumo::{
  IndexMap, Limits, SynthLanguage, ValidationResult,
  enumo::{Filter, Metric, Ruleset, Scheduler, Workload},
  recipe_utils::{Lang, recursive_rules, run_workload_extend},
  self_product,
};
use log::warn;
use rand::{rng, seq::SliceRandom};
use schedule::get_delay;
use std::ops::Not;
use std::panic;
use z3::ast::{Ast, BV};

macro_rules! eval_map {
  ($args:expr; $get:ident; $a:ident => $body:expr) => {
    match $args {
      [$a] => $get($a)
        .iter()
        .map(|a| match a {
          Some($a) => $body,
          _ => None,
        })
        .collect::<Vec<_>>(),
      args @ _ => panic!("wrong args {:?}, expected 1", args),
    }
  };
  ($args:expr; $get:ident; $a:ident, $b:ident => $body:expr) => {
    match $args {
      [$a, $b] => $get($a)
        .iter()
        .zip($get($b).iter())
        .map(|tup| match tup {
          (Some($a), Some($b)) => $body,
          _ => None,
        })
        .collect::<Vec<_>>(),
      args @ _ => panic!("wrong args {:?}, expected 2", args),
    }
  };
  ($args:expr; $get:ident; $a:ident, $b:ident, $c:ident => $body:expr) => {
    match $args {
      [$a, $b, $c] => $get($a)
        .iter()
        .zip($get($b).iter())
        .zip($get($c).iter())
        .map(|tup| match tup {
          ((Some($a), Some($b)), Some($c)) => $body,
          _ => None,
        })
        .collect::<Vec<_>>(),
      args @ _ => panic!("wrong args {:?}, expected 3", args),
    }
  };
}

impl SynthLanguage for RdgEggLang {
  type Constant = RdgConst;

  fn eval<'a, F>(&'a self, cvec_len: usize, mut get: F) -> enumo::CVec<Self>
  where
    F: FnMut(&'a enumo::Id) -> &'a enumo::CVec<Self>,
  {
    let x = match &self.op().op {
      RdgEggOp::Top(top) => match top {
        TernaryOp::Store => todo!(),
        TernaryOp::Select => {
          eval_map!(self.args(); get; cond, thn, els => RdgConst::select(cond, thn, els))
        }
      },
      RdgEggOp::Bop(bop) => {
        eval_map!(self.args(); get; lhs, rhs => RdgConst::bop(bop.clone(), lhs, rhs))
      }
      RdgEggOp::Uop(uop) => {
        eval_map!(self.args(); get; x => RdgConst::uop(uop.clone(), x))
      }
      RdgEggOp::Const(constant) => {
        vec![Some(constant.clone()); cvec_len]
      }
      RdgEggOp::RulerVar(_sym) => {
        vec![]
      }
      RdgEggOp::VectorOp(vecop) => match vecop {
        // 二元按元素
        VectorOp::VecAdd => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_add(lhs, rhs))
        }
        VectorOp::VecSub => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_sub(lhs, rhs))
        }
        VectorOp::VecMul => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_mul(lhs, rhs))
        }
        VectorOp::VecDiv => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_div(lhs, rhs))
        }
        VectorOp::VecRem => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_rem(lhs, rhs))
        }
        VectorOp::VecAnd => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_and(lhs, rhs))
        }
        VectorOp::VecOr => {
          eval_map!(self.args(); get; lhs, rhs => RdgConst::vec_or(lhs, rhs))
        }
        // 三元按元素
        VectorOp::VecMac => {
          eval_map!(self.args(); get; acc, a, b => RdgConst::vec_mac(acc, a, b))
        }

        // 一元按元素
        VectorOp::VecNeg => {
          eval_map!(self.args(); get; x => RdgConst::vec_neg(x))
        }

        VectorOp::VecNot => {
          eval_map!(self.args(); get; x => RdgConst::vec_not(x))
        }
        VectorOp::VecAbs => {
          eval_map!(self.args(); get; x => RdgConst::vec_abs(x))
        }
        VectorOp::VecSext => {
          eval_map!(self.args(); get; x => RdgConst::vec_sext(x))
        }

        // 下面这几种如果暂时还没想好语义，可以先 todo!()
        VectorOp::VecLoad => todo!("VecLoad eval"),
        VectorOp::VecStore => todo!("VecStore eval"),
        VectorOp::Gather(_) => todo!("Gather eval"),
        VectorOp::Shuffle(_) => todo!("Shuffle eval"),

        // 所有分支列完后，不可达
        _ => todo!("VecOp eval"),
      },

      _ => todo!(),
    };
    x
  }

  fn initialize_vars(
    egraph: &mut enumo::EGraph<Self, enumo::SynthAnalysis>,
    vars: &[String],
  ) {
    let consts = vec![
      Some(RdgConst::int(-5, Some(64))),
      Some(RdgConst::int(-2, Some(64))),
      Some(RdgConst::int(-1, Some(64))),
      Some(RdgConst::int(0, Some(64))),
      Some(RdgConst::int(1, Some(64))),
      Some(RdgConst::int(2, Some(64))),
      Some(RdgConst::int(5, Some(64))),
      Some(RdgConst::int(11, Some(64))),
      Some(RdgConst::int(1000, Some(64))),
      Some(RdgConst::int(1, Some(1))),
      Some(RdgConst::int(0, Some(1))),
      // 新增向量常量
      Some(RdgConst::vec_int(vec![-5, -5], 64)),
      Some(RdgConst::vec_int(vec![-2, -2], 64)),
      Some(RdgConst::vec_int(vec![-1, -1], 64)),
      Some(RdgConst::vec_int(vec![0, 0], 64)),
      Some(RdgConst::vec_int(vec![1, 1], 64)),
      Some(RdgConst::vec_int(vec![2, 2], 64)),
      Some(RdgConst::vec_int(vec![5, 5], 64)),
      Some(RdgConst::vec_int(vec![11, 11], 64)),
      Some(RdgConst::vec_int(vec![1000, 1000], 64)),
      Some(RdgConst::vec_int(vec![1, 1], 1)),
      Some(RdgConst::vec_int(vec![0, 0], 1)),
      Some(RdgConst::vec_int(vec![0, 1], 64)),
      Some(RdgConst::vec_int(vec![1, 0], 64)),
    ];

    let cvecs = self_product(&consts, vars.len());

    egraph.analysis.cvec_len = cvecs[0].len();
    for (i, v) in vars.iter().enumerate() {
      let id = egraph.add(RdgEggLang::new(
        RdgEggOp::RulerVar(v.clone().into()).into(),
        [],
      ));
      let cvec = cvecs[i].clone();
      egraph[id].data.cvec = cvec;
    }
  }

  fn to_var(&self) -> Option<enumo::Symbol> {
    if let RdgEggOp::RulerVar(sym) = &self.op().op {
      Some(*sym)
    } else {
      None
    }
  }

  fn mk_var(sym: enumo::Symbol) -> Self {
    Self::new(RdgEggOp::RulerVar(sym).into(), [])
  }

  fn is_constant(&self) -> bool {
    matches!(self.op().op, RdgEggOp::Const(_))
  }

  fn mk_constant(
    c: Self::Constant,
    // _egraph: &mut enumo::EGraph<Self, enumo::SynthAnalysis>,
  ) -> Self {
    RdgEggLang::new(RdgEggOp::Const(c).into(), [])
  }

  fn validate(lhs: &Pattern<Self>, rhs: &Pattern<Self>) -> ValidationResult {
    println!("validating: {} ==> {}", lhs, rhs);
    let mut cfg = z3::Config::new();
    cfg.set_timeout_msec(1000);
    let ctx = z3::Context::new(&cfg);
    let solver = z3::Solver::new(&ctx);
    // let mut params = Params::new(&ctx);
    // params.set_u32("timeout", 60_000);
    // solver.set_params(&params);
    let lhs_expr = Self::instantiate(lhs);
    let mut lhs_nodes: Vec<RdgEggLang> = lhs_expr.clone().into();
    let lhs_has_unknown = type_check(&mut lhs_nodes);
    let rhs_expr = Self::instantiate(rhs);
    let mut rhs_nodes: Vec<RdgEggLang> = rhs_expr.clone().into();
    let rhs_has_unknown = type_check(&mut rhs_nodes);
    let mut lhs_expr = RecExpr::from(lhs_nodes);
    let mut rhs_expr = RecExpr::from(rhs_nodes);
    if lhs_has_unknown || rhs_has_unknown {
      match_unknown_vars(&mut lhs_expr, &mut rhs_expr);
    }
    // 检查lhs_expr和rhs_expr中是否存在Int1出现在除了and/or之外的二元操作符中
    for node in lhs_expr.as_ref() {
      if let RdgEggOp::Bop(bop) = node.ast.operation().op.clone() {
        if matches!(bop, BinaryOp::And | BinaryOp::Or) {
          continue;
        }
        if node.ast.operation().info.result_tys.len() > 0
          && node.ast.operation().info.result_tys[0] == EggType::IntT(Some(1))
        {
          return ValidationResult::Invalid;
        }
      }
    }
    for node in rhs_expr.as_ref() {
      if let RdgEggOp::Bop(bop) = node.ast.operation().op.clone() {
        if matches!(bop, BinaryOp::And | BinaryOp::Or) {
          continue;
        }
        if node.ast.operation().info.result_tys.len() > 0
          && node.ast.operation().info.result_tys[0] == EggType::IntT(Some(1))
        {
          return ValidationResult::Invalid;
        }
      }
    }
    // println!("lhs:");
    // for node in lhs_expr.as_ref() {
    //   println!("{:?}", node);
    // }
    // println!("rhs:");
    // for node in rhs_expr.as_ref() {
    //   println!("{:?}", node);
    // }
    let lexpr = egg_to_z3(&ctx, lhs_expr.as_ref());
    let rexpr = egg_to_z3(&ctx, rhs_expr.as_ref());
    solver.assert(&lexpr._eq(&rexpr).not());
    match solver.check() {
      z3::SatResult::Unsat => ValidationResult::Valid,
      z3::SatResult::Unknown => {
        let _reason = solver.get_reason_unknown().unwrap();
        // println!("z3 unknown: {:?}", reason);
        ValidationResult::Unknown
      }
      z3::SatResult::Sat => ValidationResult::Invalid,
    }
    // ValidationResult::Valid
  }
}

fn type_check(expr: &mut Vec<RdgEggLang>) -> bool {
  // 本函数的目的是，为RuleVar尽可能地添加类型，也就是说，
  // 当发现有一个操作数是RuleVar类型时，去检查其他操作
  for i in 0..expr.len() {
    let node = expr[i].clone();
    let args = node.ast.args();
    let op = node.ast.operation().op.clone();
    // 如果当前的op是select类型并且arg[0]是RuleVar类型,那么直接赋给它bool类型
    if matches!(op, RdgEggOp::Top(TernaryOp::Select))
      && matches!(
        expr[usize::from(args[0])].ast.operation().op,
        RdgEggOp::RulerVar(_)
      )
    {
      let op_id = usize::from(args[0]);
      let info = expr[op_id]
        .ast
        .operation()
        .clone()
        .info
        .with_tys(vec![EggType::IntT(Some(1))]);
      expr[op_id].ast.operation_mut().info = info;
    }
    // 如果存在没有类型的操作数
    let mut unknown_vars = Vec::new();
    let mut consts = Vec::new();
    let mut bool_ops = Vec::new();
    let mut ty = Vec::new();
    for op in args.iter() {
      let op_id = usize::from(*op);
      let op = expr[op_id].ast.operation().op.clone();
      if expr[op_id].ast.operation().info.result_tys.len() == 0 {
        unknown_vars.push(op_id);
      }
      if matches!(op, RdgEggOp::Const(_)) {
        consts.push(op_id);
      }
      if matches!(
        op,
        RdgEggOp::Bop(BinaryOp::Eq)
          | RdgEggOp::Bop(BinaryOp::Ne)
          | RdgEggOp::Bop(BinaryOp::GreaterEq)
          | RdgEggOp::Bop(BinaryOp::GreaterThan)
          | RdgEggOp::Bop(BinaryOp::LessEq)
          | RdgEggOp::Bop(BinaryOp::LessThan)
      ) {
        bool_ops.push(op_id);
      }
      // // 如果当前的操作数非三元操作符，且args中有类型不为空
      if expr[op_id].ast.operation().info.result_tys.len() > 0
        && !matches!(op, RdgEggOp::Top(TernaryOp::Select))
      {
        ty = expr[op_id].ast.operation().info.result_tys.clone();
      }
    }
    // 如果当前操作符是select类型的三元操作符，其第二个和第三个参数不为空，
    // 那么就直接将类型赋给ty直接跳出
    if matches!(op, RdgEggOp::Top(TernaryOp::Select))
      && (expr[usize::from(args[1])]
        .ast
        .operation()
        .info
        .result_tys
        .len()
        > 0
        || expr[usize::from(args[2])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          > 0)
    {
      ty = if expr[usize::from(args[1])]
        .ast
        .operation()
        .info
        .result_tys
        .len()
        > 0
      {
        expr[usize::from(args[1])]
          .ast
          .operation()
          .info
          .result_tys
          .clone()
      } else {
        expr[usize::from(args[2])]
          .ast
          .operation()
          .info
          .result_tys
          .clone()
      };
    }
    let is_unknown_var = unknown_vars.len() > 0;
    if is_unknown_var {
      // 如果ty不为空,那么就将ty赋给当前操作数
      if ty.len() > 0 {
        for op in unknown_vars.iter() {
          let info =
            expr[*op].ast.operation().clone().info.with_tys(ty.clone());
          expr[*op].ast.operation_mut().info = info;
        }
      }

      // 如果存在Eq,Ne,GreaterEq,GreaterThan,LessEq,LessThan类型的操作数,
      // 则将类型设置为bool
      if bool_ops.len() > 0 {
        for op in unknown_vars.iter() {
          let op_id = usize::from(*op);
          let info = expr[op_id]
            .ast
            .operation()
            .clone()
            .info
            .with_tys(vec![EggType::IntT(Some(1))]);
          expr[op_id].ast.operation_mut().info = info;
        }
      } else if consts.len() > 0 {
        // 如果存在Const类型的操作数，则将类型设为和Const相同
        for op in unknown_vars.iter() {
          let op_id = usize::from(*op);
          let ty = expr[consts[0]].ast.operation().info.result_tys.clone();
          let info = expr[op_id].ast.operation().clone().info.with_tys(ty);
          expr[op_id].ast.operation_mut().info = info;
        }
      }
    }
    // 更新当前操作符的类型
    let op_id = i;
    let op = node.ast.operation().op.clone();

    match op {
      RdgEggOp::Top(top) => {
        match top {
          TernaryOp::Select => {
            // 如果args[1]和args[2]已经有类型，就赋给当前操作符
            if expr[usize::from(args[1])]
              .ast
              .operation()
              .info
              .result_tys
              .len()
              > 0
              && expr[usize::from(args[2])]
                .ast
                .operation()
                .info
                .result_tys
                .len()
                > 0
            {
              let ty = expr[usize::from(args[1])]
                .ast
                .operation()
                .info
                .result_tys
                .clone();
              let info = node.ast.operation().clone().info.with_tys(ty);
              expr[op_id].ast.operation_mut().info = info;
            }
          }
          _ => {}
        }
      }
      RdgEggOp::Bop(_) => {
        // 如果当前操作符是Eq,Ne,GreaterEq,GreaterThan,LessEq,
        // LessThan类型的操作数,则将类型设置为bool
        if matches!(
          op,
          RdgEggOp::Bop(BinaryOp::Eq)
            | RdgEggOp::Bop(BinaryOp::Ne)
            | RdgEggOp::Bop(BinaryOp::GreaterEq)
            | RdgEggOp::Bop(BinaryOp::GreaterThan)
            | RdgEggOp::Bop(BinaryOp::LessEq)
            | RdgEggOp::Bop(BinaryOp::LessThan)
        ) {
          let info = node
            .ast
            .operation()
            .clone()
            .info
            .with_tys(vec![EggType::IntT(Some(1))]);
          expr[op_id].ast.operation_mut().info = info;
        }
        // 如果当前操作符是Add,Sub,Div,Mul,Shl,Shl类型的操作数,
        // 并且两个操作数有类型，那么就将类型设置为和操作数相同
        else if matches!(
          op,
          RdgEggOp::Bop(BinaryOp::Add)
            | RdgEggOp::Bop(BinaryOp::Sub)
            | RdgEggOp::Bop(BinaryOp::Div)
            | RdgEggOp::Bop(BinaryOp::Mul)
            | RdgEggOp::Bop(BinaryOp::Shl)
            | RdgEggOp::Bop(BinaryOp::Shr)
            | RdgEggOp::Bop(BinaryOp::And)
            | RdgEggOp::Bop(BinaryOp::Or)
        ) {
          if expr[usize::from(args[0])]
            .ast
            .operation()
            .info
            .result_tys
            .len()
            > 0
            && expr[usize::from(args[1])]
              .ast
              .operation()
              .info
              .result_tys
              .len()
              > 0
          {
            let ty = expr[usize::from(args[0])]
              .ast
              .operation()
              .info
              .result_tys
              .clone();
            let info = node.ast.operation().clone().info.with_tys(ty);
            expr[op_id].ast.operation_mut().info = info;
          }
        }
      }
      RdgEggOp::Uop(_) => {
        // 如果当前操作符是Abs或not类型的操作数,则将类型设置为和操作数相同
        if expr[usize::from(args[0])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          > 0
        {
          let ty = expr[usize::from(args[0])]
            .ast
            .operation()
            .info
            .result_tys
            .clone();
          let info = node.ast.operation().clone().info.with_tys(ty);
          expr[op_id].ast.operation_mut().info = info;
        }
      }
      _ => {}
    }
  }
  // 重新遍历，如果有一元操作符，其类型不是unknown，且其操作数是unknown类型，
  // 则将其类型设置为和操作数相同
  for i in 0..expr.len() {
    let node = expr[i].clone();
    let args = node.ast.args();
    let op = node.ast.operation().op.clone();
    if matches!(op, RdgEggOp::Uop(_)) {
      if expr[i].ast.operation().info.result_tys.len() > 0
        && expr[usize::from(args[0])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          == 0
      {
        let ty = expr[usize::from(i)].ast.operation().info.result_tys.clone();
        let info = node.ast.operation().clone().info.with_tys(ty);
        expr[usize::from(args[0])].ast.operation_mut().info = info;
      }
    }
    // 如果是二元操作符，并且类型不为空，且操作数是unknown类型，并且不是eq,ne,
    // greaterEq,greaterThan,lessEq,lessThan类型的操作数,
    // 那么就将类型设置为和操作数相同
    if matches!(op, RdgEggOp::Bop(_)) {
      if expr[i].ast.operation().info.result_tys.len() > 0
        && expr[usize::from(args[0])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          == 0
        && expr[usize::from(args[1])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          == 0
        && !matches!(
          op,
          RdgEggOp::Bop(BinaryOp::Eq)
            | RdgEggOp::Bop(BinaryOp::Ne)
            | RdgEggOp::Bop(BinaryOp::GreaterEq)
            | RdgEggOp::Bop(BinaryOp::GreaterThan)
            | RdgEggOp::Bop(BinaryOp::LessEq)
            | RdgEggOp::Bop(BinaryOp::LessThan)
        )
      {
        let ty = expr[usize::from(i)].ast.operation().info.result_tys.clone();
        let info = node.ast.operation().clone().info.with_tys(ty);
        expr[usize::from(args[0])].ast.operation_mut().info = info.clone();
        expr[usize::from(args[1])].ast.operation_mut().info = info;
      }
    }
    // 如果是select类型的操作符，并且类型不为空，且arg1和arg2是unknown类型，
    // 那么就将类型设置为和操作数相同
    if matches!(op, RdgEggOp::Top(TernaryOp::Select)) {
      if expr[i].ast.operation().info.result_tys.len() > 0
        && expr[usize::from(args[1])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          == 0
        && expr[usize::from(args[2])]
          .ast
          .operation()
          .info
          .result_tys
          .len()
          == 0
      {
        let ty = expr[usize::from(i)].ast.operation().info.result_tys.clone();
        let info = node.ast.operation().clone().info.with_tys(ty);
        expr[usize::from(args[1])].ast.operation_mut().info = info.clone();
        expr[usize::from(args[2])].ast.operation_mut().info = info;
      }
    }
  }
  let mut has_unknown_type = false;
  for node in expr {
    let op = node.ast.operation().op.clone();
    if matches!(op, RdgEggOp::RulerVar(_)) {
      let ty = node.ast.operation().info.result_tys.clone();
      if ty.len() == 0 {
        has_unknown_type = true;
      }
    }
  }
  has_unknown_type
}

fn match_unknown_vars(
  lhs: &mut RecExpr<RdgEggLang>,
  rhs: &mut RecExpr<RdgEggLang>,
) {
  // 首先建立一个HashMap，用来存储lhs和rhs中的(var_name,var_id,ty）对
  let mut lhs_vars = HashMap::new();
  let mut rhs_vars = HashMap::new();
  for i in 0..lhs.as_ref().len() {
    let node = lhs.as_ref()[i].clone();
    if let RdgEggOp::RulerVar(var) = node.ast.operation().op.clone() {
      let var_name = var.to_string();
      let ty = node.ast.operation().info.result_tys.clone();
      lhs_vars.insert(var_name, (i, ty));
    }
  }
  for i in 0..rhs.as_ref().len() {
    let node = rhs.as_ref()[i].clone();
    if let RdgEggOp::RulerVar(var) = node.ast.operation().op.clone() {
      let var_name = var.to_string();
      let ty = node.ast.operation().info.result_tys.clone();
      rhs_vars.insert(var_name, (i, ty));
    }
  }
  // 遍历lhs_vars和rhs_vars,如果发现有类型是unknown的变量,
  // 那么就去另外一个HashMap中寻找 如果有相同的变量名,那么就将类型设置为相同
  for (var_name, (lhs_id, lhs_ty)) in lhs_vars.iter() {
    if let Some((rhs_id, rhs_ty)) = rhs_vars.get(var_name) {
      if lhs_ty.len() == 0 && rhs_ty.len() > 0 {
        let info = lhs.as_mut()[*lhs_id]
          .ast
          .operation()
          .clone()
          .info
          .with_tys(rhs_ty.clone());
        lhs.as_mut()[*lhs_id].ast.operation_mut().info = info;
      } else if rhs_ty.len() == 0 && lhs_ty.len() > 0 {
        let info = rhs.as_mut()[*rhs_id]
          .ast
          .operation()
          .clone()
          .info
          .with_tys(lhs_ty.clone());
        rhs.as_mut()[*rhs_id].ast.operation_mut().info = info;
      }
    }
  }
}

fn egg_to_z3<'a>(ctx: &'a z3::Context, expr: &[RdgEggLang]) -> BV<'a> {
  let mut buf: Vec<BV<'a>> = vec![];
  let zero_64 = BV::from_i64(ctx, 0, 64);
  let zero_1 = BV::from_i64(ctx, 0, 1);
  let one_1 = BV::from_i64(ctx, 1, 1);
  let _select = z3::ast::Bool::ite(
    &z3::ast::Bool::not(&zero_64._eq(&zero_64)),
    &zero_1,
    &one_1,
  );
  for node in expr.as_ref().iter() {
    // 目前对于vecop而言，检查非常简单，因为其行为全部是沿lane的，
    // 所以只将其降级为对应的标量操作来做验证
    let op = if matches!(node.ast.operation().op, RdgEggOp::VectorOp(_)) {
      let new_op = match node.ast.operation().op.clone() {
        RdgEggOp::VectorOp(vecop) => match vecop {
          VectorOp::VecAdd => RdgEggOp::Bop(BinaryOp::Add),
          VectorOp::VecSub => RdgEggOp::Bop(BinaryOp::Sub),
          VectorOp::VecMul => RdgEggOp::Bop(BinaryOp::Mul),
          VectorOp::VecDiv => RdgEggOp::Bop(BinaryOp::Div),
          VectorOp::VecRem => RdgEggOp::Bop(BinaryOp::Mod),
          VectorOp::VecAnd => RdgEggOp::Bop(BinaryOp::And),
          VectorOp::VecOr => RdgEggOp::Bop(BinaryOp::Or),
          VectorOp::VecMac => RdgEggOp::VectorOp(VectorOp::VecMac), /* 这个操作在标量中没有，单独拿出来实现即可 */
          VectorOp::VecNeg => RdgEggOp::Uop(UnaryOp::Neg),
          VectorOp::VecNot => RdgEggOp::Uop(UnaryOp::Not),
          VectorOp::VecAbs => RdgEggOp::Uop(UnaryOp::Abs),
          _ => panic!("unsupported vecop: {:?}", vecop),
        },
        _ => panic!("something wrong"),
      };
      new_op
    } else {
      node.ast.operation().op.clone()
    };
    let args = node.ast.args();
    match op {
      RdgEggOp::Const(c) => match c {
        RdgConst::Int(i, w) => buf.push(BV::from_i64(ctx, i, w.unwrap())),
        RdgConst::Float(_, _) => panic!("float not supported"),
        RdgConst::VecInt(_, _) => panic!("vecint not supported"),
        RdgConst::VecFloat(_, _) => panic!("vecfloat not supported"),
      },
      RdgEggOp::Top(top) => {
        assert!(args.len() == 3);
        match top {
          TernaryOp::Select => {
            // 如果&buf[usize::from(args[0])]位宽为1,那么就将其转换为64位
            let cond = if buf[usize::from(args[0])].get_size() == 1 {
              z3::ast::Bool::not(&buf[usize::from(args[0])]._eq(&zero_1))
            } else {
              z3::ast::Bool::not(&buf[usize::from(args[0])]._eq(&zero_64))
            };
            buf.push(z3::ast::Bool::ite(
              &cond,
              &buf[usize::from(args[1])],
              &buf[usize::from(args[2])],
            ))
          }
          TernaryOp::Store => todo!(),
        }
      }
      RdgEggOp::Bop(bop) => {
        assert!(args.len() == 2);
        let x = &buf[usize::from(args[0])];
        let y = &buf[usize::from(args[1])];
        match bop {
          BinaryOp::Add => buf.push(BV::bvadd(x, y)),
          BinaryOp::Sub => buf.push(BV::bvsub(x, y)),
          BinaryOp::Mul => buf.push(BV::bvmul(x, y)),
          BinaryOp::Div => buf.push(z3::ast::Bool::ite(
            &y._eq(&zero_64),
            &zero_64,
            &BV::bvsdiv(x, y),
          )),
          BinaryOp::Mod => buf.push(z3::ast::Bool::ite(
            &y._eq(&zero_64),
            &zero_64,
            &BV::bvsmod(x, y),
          )),
          BinaryOp::Shl => buf.push(BV::bvshl(x, y)),
          BinaryOp::Shr => buf.push(BV::bvashr(x, y)),
          BinaryOp::Eq => {
            buf.push(z3::ast::Bool::ite(&BV::_eq(x, y), &one_1, &zero_1))
          }
          BinaryOp::Ne => {
            buf.push(z3::ast::Bool::ite(&BV::_eq(x, y), &zero_1, &one_1))
          }
          BinaryOp::GreaterEq => {
            buf.push(z3::ast::Bool::ite(&BV::bvsge(x, y), &one_1, &zero_1))
          }
          BinaryOp::GreaterThan => {
            buf.push(z3::ast::Bool::ite(&BV::bvsgt(x, y), &one_1, &zero_1))
          }
          BinaryOp::LessEq => {
            buf.push(z3::ast::Bool::ite(&BV::bvsle(x, y), &one_1, &zero_1))
          }
          BinaryOp::LessThan => {
            buf.push(z3::ast::Bool::ite(&BV::bvslt(x, y), &one_1, &zero_1))
          }
          BinaryOp::Max => buf.push(z3::ast::Bool::ite(&BV::bvsge(x, y), x, y)),
          BinaryOp::Min => buf.push(z3::ast::Bool::ite(&BV::bvsle(x, y), x, y)),
          BinaryOp::And => buf.push(BV::bvand(x, y)),
          BinaryOp::Or => buf.push(BV::bvor(x, y)),
          BinaryOp::Xor => buf.push(BV::bvxor(x, y)),
          BinaryOp::Load => todo!(),
          BinaryOp::StateMerge => todo!(),
        }
      }
      RdgEggOp::Uop(uop) => {
        assert!(args.len() == 1);
        let x = &buf[usize::from(args[0])];
        match uop {
          UnaryOp::Abs => buf.push(z3::ast::Bool::ite(
            &BV::bvslt(x, &zero_64),
            &BV::bvneg(x),
            x,
          )),
          UnaryOp::Not => buf.push(BV::not((*x).clone())),
          UnaryOp::Neg => buf.push(BV::bvneg(x)),
          UnaryOp::Cast(_) => todo!(),
        }
      }
      // 单独处理VecMac操作, 还是将其当做是普通的标量乘加操作
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::VecMac => {
          assert!(args.len() == 3);
          let x = &buf[usize::from(args[0])];
          let y = &buf[usize::from(args[1])];
          let z = &buf[usize::from(args[2])];
          let mul = BV::bvmul(x, y);
          let add = BV::bvadd(z, &mul);
          buf.push(add);
        }
        _ => panic!("Transform vecop to scalar op failed"),
      },
      RdgEggOp::RulerVar(var) => {
        let ty = node.ast.operation().info.result_tys.clone();
        if ty.len() != 0 {
          match ty[0] {
            EggType::IntT(w) => {
              buf.push(BV::new_const(ctx, var.to_string(), w.unwrap() as u32))
            }
            _ => panic!("unsupported type: {:?}", ty),
          }
        } else {
          buf.push(BV::new_const(ctx, var.to_string(), 64));
        }
      }

      _ => panic!("unsupported op: {:?}", op),
    }
  }
  buf.pop().unwrap()
}

pub fn rdgegg_rules() -> Ruleset<RdgEggLang> {
  let mut rules: Ruleset<RdgEggLang> = Ruleset::default();
  // let mut rules = recursive_rules(
  //   Metric::Atoms,
  //   5,
  //   Lang::new(&["0i1", "1i1"], &["a", "b", "c"], &[
  //     &["not"],
  //     &["and", "or", "xor"],
  //     &["select"],
  //   ]),
  //   rules.clone(),
  // );

  // println!("+ bool rewrites:  {}", rules.len());
  // // 加入condition
  // for rule in rules.iter_mut() {
  //   rule.condition = Some("(all: bool)".to_string());
  // }

  // let arith_only = recursive_rules(
  //   Metric::Atoms,
  //   5,
  //   Lang::new(&["1i64", "0i64", "2i64"], &["a", "b", "c"], &[&[], &[
  //     "add", "sub", "mul", "div", "shl", "shr", "mod",
  //   ]]),
  //   rules.clone(),
  // );

  // let mut rules = arith_only.clone();
  // println!("+ arith rewrites: {}", rules.len());

  // for rule in rules.iter_mut() {
  //   if rule.condition.is_none() {
  //     rule.condition = Some("(all: int)".to_string());
  //   }
  // }

  // let mut rules = recursive_rules(
  //   Metric::Atoms,
  //   3,
  //   Lang::new(&["-1i64", "0i64", "1i64"], &["a", "b", "c"], &[
  //     &[],
  //     &["eq", "le", "lt", "ge", "gt"],
  //     &["select"],
  //   ]),
  //   rules.clone(),
  // );

  // println!("+ pred rewrites: {}", rules.len());
  // warn!("pred rewrites: {:?}", rules);
  // for rule in rules.iter_mut() {
  //   if rule.condition.is_none() {
  //     rule.condition = Some("(all: int)".to_string());
  //   }
  // }

  // let nested_bops_arith = Workload::new(&["(bop e e)", "v"])
  //   .plug("e", &Workload::new(&["(bop v v)", "(uop v)", "v"]))
  //   .plug(
  //     "bop",
  //     &Workload::new(&[
  //       "and", "or", "xor", "add", "sub", "mul", "div", "shl", "shr", "mod",
  //     ]),
  //   )
  //   .plug("uop", &Workload::new(&["abs", "not", "neg"]))
  //   .plug("v", &Workload::new(&["a", "b", "c"]))
  //   .filter(Filter::Canon(vec![
  //     "a".to_string(),
  //     "b".to_string(),
  //     "c".to_string(),
  //   ]));

  // let mut rules = run_workload_extend(
  //   nested_bops_arith,
  //   rules,
  //   Limits::synthesis(),
  //   Limits::minimize(),
  //   true,
  // );

  // for rule in rules.iter_mut() {
  //   if rule.condition.is_none() {
  //     rule.condition = Some("(all: int)".to_string());
  //   }
  // }

  // println!("running arith select");
  // let arith_select_wl = Workload::new([
  //   "(select V V V)",
  //   "(select V (OP V V) V)",
  //   "(select V V (OP V V))",
  //   "(select V (OP V V) (OP V V))",
  //   "(OP V (select V V V))",
  // ])
  // .plug("V", &Workload::new(["a", "b", "c", "d"]))
  // .plug("OP", &Workload::new(["add", "sub", "mul"]));

  // let mut rules = run_workload_extend(
  //   arith_select_wl,
  //   rules.clone(),
  //   Limits::synthesis(),
  //   Limits::minimize(),
  //   true,
  // );

  // // 一个闭包，用来在给定的Pattern<RdgEggLang>中寻找select语句的条件变量
  // let find_select_condition = |pattern: Pattern<RdgEggLang>| ->
  // Option<String> {   for node in pattern.ast.clone() {
  //     match node {
  //       ENodeOrVar::ENode(enode) => {
  //         if let RdgEggOp::Top(TernaryOp::Select) = enode.op().op {
  //           if let ENodeOrVar::Var(var) =
  // pattern.ast[enode.args()[0]].clone() {             return
  // Some(var.to_string());           }
  //         }
  //       }
  //       _ => {}
  //     }
  //   }
  //   None
  // };

  // for rule in rules.iter_mut() {
  //   if rule.condition.is_none() {
  //     let lhs = rule.lhs.clone();
  //     let rhs = rule.rhs.clone();
  //     let lhs_condition = find_select_condition(lhs);
  //     let rhs_condition = find_select_condition(rhs);
  //     if lhs_condition.is_some() || rhs_condition.is_some() {
  //       if lhs_condition.is_some()
  //         && rhs_condition.is_some()
  //         && lhs_condition != rhs_condition
  //       {
  //         panic!("I can't handle different conditions on lhs and rhs");
  //       } else {
  //         let condition = lhs_condition.unwrap_or(rhs_condition.unwrap());
  //         rule.condition = Some(format!("({}: bool)", condition));
  //       }
  //     }
  //   }
  // }
  // println!("+ arith select rewrites: {}", rules.len());

  // 添加向量运算规则生成
  println!("running vec ops");
  // 1. 首先定义「向量语言」里的常量、变量和操作符
  //    这里我们用一个空向量常量作为示例
  let vec_consts: &[&str] = &[];
  let vec_vars = &["v1", "v2", "v3"];

  let vec_unops = &["vec_neg", "vec_abs", "vec_not"];
  let vec_binops = &[
    "vec_add", "vec_sub", "vec_mul", "vec_div", "vec_rem", "vec_and", "vec_or",
  ];
  let vec_ternops = &["vec_mac"]; // MAC 是三元

  // 2. 调用 recursive_rules 生成这些算子的重写规则
  let mut vec_rules = recursive_rules(
    Metric::Atoms,
    5,
    Lang::new(vec_consts, vec_vars, &[vec_unops, vec_binops, vec_ternops]),
    Ruleset::default(), // 或者你已有的规则集.clone()
  );
  // 加入类型条件
  for rule in vec_rules.iter_mut() {
    if rule.condition.is_none() {
      rule.condition = Some("(all: vector<int>)".to_string());
    }
  }

  println!("+ vector rewrites: {}", vec_rules.len());
  rules.extend(vec_rules.clone());
  rules
}

pub type RdgRuleset = Ruleset<RdgEggLang>;

#[test]
fn report_rules() {
  let rules = rdgegg_rules();
  rules.to_file("resources/vec_int.rules");
  // unsafe {
  //   std::env::set_var("RUST_LOG", "WARN");
  // }
  // env_logger::init();
  // // let start = Instant::now();
  // let rules = rdgegg_rules();
  // // let duration = start.elapsed();
  // println!("+++++++++\nSummary:");
  // rules.pretty_print();
  // rules.to_file("resources/all.rules");
  // logger::write_baseline(
  //   &rules,
  //   "rdg_enumo",
  //   &Ruleset::default(),
  //   "empty",
  //   duration,
  // );
}

// 用于将Pattern<RdgEggLang>转换为RecExpr<RdgEggLang>
pub fn pattern_to_recexpr(
  pattern: Pattern<RdgEggLang>,
) -> RecExpr<AstNode<RdgEgg>> {
  let pattern_ast = pattern.ast;
  let mut result = Vec::new();
  for node in pattern_ast {
    match node {
      ENodeOrVar::ENode(enode) => {
        // 直接将enode加入result
        result.push(enode.ast.clone());
      }
      ENodeOrVar::Var(_) => {
        // 由于只需要计算延迟，所以可以将Var全部用Default替换
        result.push(AstNode::leaf(RdgEgg::default()));
      }
    }
  }
  let recexpr = RecExpr::from(result);
  recexpr
}

// 用于将enumo_manual.rules中删除会导致delay增加的rule
pub fn remove_rules(filename_in: &str, filename_out: &str) {
  let ruleset: RdgRuleset = Ruleset::from_file(filename_in);
  let mut rules = ruleset.0.into_iter().collect::<Vec<_>>();
  rules.retain(|(_name, rule)| {
    let lhs = rule.lhs.clone();
    let rhs = rule.rhs.clone();
    let lhs_expr = pattern_to_recexpr(lhs.clone());
    let rhs_expr = pattern_to_recexpr(rhs.clone());
    let lhs_delay = get_delay(&lhs_expr);
    let rhs_delay = get_delay(&rhs_expr);
    if rhs_delay <= lhs_delay {
      return true;
    }
    false
  });
  // 将delay减小的rule和文件resources/satuating.rules中的rule合并,
  // 并写入文件filename_out
  let mut ruleset = Ruleset::default();
  for (name, rule) in rules {
    ruleset.0.insert(name, rule);
  }
  // let saturating_rules: RdgRuleset =
  // Ruleset::from_file("resources/satuating.rules");
  // ruleset.extend(saturating_rules.clone());
  println!("{} rewrites left", ruleset.len());
  ruleset.to_file(filename_out);
}

#[test]
fn parse_synthesized_rules() {
  let mut rewrites: RdgRuleset =
    Ruleset::from_file("resources/origin_rewrites/int.rules");
  rewrites.extend(Ruleset::from_file("resources/origin_rewrites/float.rules"));
  // let mut decreasing_rules = Ruleset::default();
  // let mut decrease_satuating = Ruleset::default();
  // let mut decrease_no_satuating = Ruleset::default();
  // let mut increase_satuating = Ruleset::default();
  // let mut saturating_rules: RdgRuleset = Ruleset::default();
  // rewrites.0.retain(|_, rule| {
  //   if rule.is_saturating() {
  //     saturating_rules.add(rule.clone());
  //   }
  //   let lhs = rule.lhs.clone();
  //   let rhs = rule.rhs.clone();
  //   let lhs_size = lhs.ast.len();
  //   let rhs_size = rhs.ast.len();
  //   if rhs_size == lhs_size {
  //     decreasing_rules.add(rule.clone());
  //   }
  //   if rhs_size == lhs_size && rule.is_saturating() {
  //     decrease_satuating.add(rule.clone());
  //     return false;
  //   } else if rhs_size != lhs_size && rule.is_saturating() {
  //     increase_satuating.add(rule.clone());
  //     return false;
  //   } else if rhs_size == lhs_size && !rule.is_saturating() {
  //     decrease_no_satuating.add(rule.clone());
  //     return false;
  //   }
  //   true
  // });
  rewrites.0.retain(|_, rule| {
    // 只保留非saturating的规则
    if rule.is_saturating() {
      return false;
    }
    true
  });
  // let mut invalid_rewrites = RdgRuleset::default();
  // let mut unknown_rewrites = RdgRuleset::default();
  // let mut cnt = 0;
  // let mut valid_cnt = 0;
  // rewrites.0.retain(|_, rule| {
  //   cnt += 1;
  //   println!("{} / 1594  valid: {}", cnt, valid_cnt);
  //   let lhs = rule.lhs.clone();
  //   let rhs = rule.rhs.clone();
  //   match RdgEggLang::validate(&lhs, &rhs) {
  //     ValidationResult::Valid => {
  //       valid_cnt += 1;
  //       true
  //     }
  //     ValidationResult::Invalid => {
  //       println!("Invalid validation rewrite: {}", rule.name);
  //       invalid_rewrites.0.insert(rule.name.clone(), rule.clone());
  //       false
  //     }
  //     ValidationResult::Unknown => {
  //       unknown_rewrites.0.insert(rule.name.clone(), rule.clone());
  //       println!("Unknown validation result");
  //       valid_cnt += 1;
  //       false
  //     }
  //   }
  // });
  println!("{} rewrites left", rewrites.len());
  // 将chosen写入all_test.rules
  // decrease_satuating.to_file("resources/size_decrease_saturating.rules");
  // decrease_no_satuating.to_file("resources/size_decrease_no_saturating.rules"
  // ); increase_satuating.to_file("resources/size_increase_saturating.rules"
  // ); decreasing_rules.to_file("resources/size_decreasing.rules");
  // 将rewrites写入valid.rules
  rewrites.to_file("resources/libsel_rewrites/no_saturating.rules");
  // saturating_rules.to_file("resources/transform_vec_saturating.rules");
  // // 将invalid_rewrites写入invalid.rules
  // invalid_rewrites.to_file("resources/invalid.rules");
  // 将unknown_rewrites写入unknown.rules
  // unknown_rewrites.to_file("resources/unknown.rules");
}

// 用于打乱IndexMap的顺序
fn shuffle_indexmap<K: Clone + std::hash::Hash + Eq, V: Clone>(
  map: &IndexMap<K, V>,
) -> IndexMap<K, V> {
  let mut entries: Vec<_> = map.iter().collect();
  entries.shuffle(&mut rng());

  let mut shuffled = IndexMap::default();
  for (k, v) in entries {
    shuffled.insert(k.clone(), v.clone());
  }
  shuffled
}

#[test]
pub fn minimize_rules() {
  let mut rules: RdgRuleset = Ruleset::from_file("resources/all_test.rules");
  let mut rules_len = rules.len();
  let mut iter = 0;
  let limits = Limits::minimize();
  while rules.len() < rules_len || iter < 10 {
    println!("there are {} rules, iter: {}", rules.len(), iter);
    // 首先打乱rules顺序
    let index_map = rules.0.clone();
    rules.0 = shuffle_indexmap(&index_map);
    rules_len = rules.len();
    let scheduler = match iter % 3 {
      0 => Scheduler::Simple(limits),
      1 => Scheduler::Saturating(limits),
      _ => Scheduler::Compress(limits),
    };
    let past = Ruleset::default();
    rules = rules.minimize(past, scheduler).0;
    iter += 1;
  }
  println!("Minimized rules: {}", rules.len());
  rules.to_file("resources/minimized_great.rules");
}

#[test]
pub fn test_add_condition() {
  let mut rules: RdgRuleset =
    Ruleset::from_file("resources/transform_vec.rules");
  for rule in rules.iter_mut() {
    if rule.condition.is_none() {
      rule.condition = Some("(all: vector<int>)".to_string());
    }
  }
  rules.to_file("resources/transform_vec.rules");
}
