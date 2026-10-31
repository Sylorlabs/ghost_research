use super::*;
use std::panic;

fn expr<I>(operation: RdgEggOp, args: I, info: RdgEggInfo) -> RcRdgEggExpr
where
  I: IntoIterator<Item = RcRdgEggExpr>,
{
  // log::warn!("add an expr: {}", operation);
  let x = Rc::new(RdgEggExpr::new(operation.with(info), args));
  x
}

pub fn function(
  name: &str,
  body: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::Function(name.to_string().into()), [body], info)
}

pub fn tuple(
  elems: impl Iterator<Item = RcRdgEggExpr>,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::Tuple(Tuple {}), elems, info)
}

pub fn arg(info: RdgEggInfo) -> RcRdgEggExpr {
  expr(RdgEggOp::Arg(Arg { bbs: vec![] }), [], info)
}

pub fn get(e: RcRdgEggExpr, i: usize, info: RdgEggInfo) -> RcRdgEggExpr {
  // 需要从e中解析出具体的datasource
  let get_from_node = e.ast.operation().op.clone();
  let datasource = match get_from_node {
    RdgEggOp::Arg(_) => GetDataSource::Arg(i),
    RdgEggOp::Dummy(_) => GetDataSource::Dummy(i),
    RdgEggOp::Switch => GetDataSource::SwitchBranch(i),
    RdgEggOp::DoWhile => GetDataSource::DoWhileVar(i),
    RdgEggOp::VectorOp(_) => GetDataSource::VecElement(i),
    RdgEggOp::Bop(BinaryOp::Load)
    | RdgEggOp::Top(TernaryOp::Store)
    | RdgEggOp::IOBarrier => GetDataSource::MemState(i),
    _ => {
      todo!("get from node: {:?}", get_from_node);
    }
  };
  let ty = if info.result_tys.is_empty() {
    EggType::Unknown
  } else {
    if info.result_tys[0].is_vector() {
      EggType::Unknown
    } else {
      info.result_tys[0].clone()
    }
  };
  let info = RdgEggInfo {
    result_tys: vec![ty],
    ..info
  };
  expr(RdgEggOp::Get(GetOp::new(datasource)), [e], info)
}

pub fn switch(
  pred: RcRdgEggExpr,
  input: RcRdgEggExpr,
  branches: Vec<RcRdgEggExpr>,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(
    RdgEggOp::Switch,
    vec![pred, input].into_iter().chain(branches.into_iter()),
    info,
  )
}

pub fn dowhile(
  input: RcRdgEggExpr,
  pred_body: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::DoWhile, [input, pred_body], info)
}

pub fn int(i: i64, info: RdgEggInfo) -> RcRdgEggExpr {
  let ty = info.result_tys[0].clone();
  match ty {
    EggType::IntT(w) => {
      return expr(
        RdgEggOp::Const(RdgConst::Int(i, w.map(|w| w as u32))),
        [],
        info,
      );
    }
    _ => {
      panic!("int type mismatch: {} vs {:?}", i, ty);
    }
  }
}

pub fn tfalse(info: RdgEggInfo) -> RcRdgEggExpr {
  expr(RdgEggOp::Const(RdgConst::Int(0, Some(1))), [], info)
}

pub fn ttrue(info: RdgEggInfo) -> RcRdgEggExpr {
  expr(RdgEggOp::Const(RdgConst::Int(1, Some(1))), [], info)
}
pub fn float(f: f64, info: RdgEggInfo) -> RcRdgEggExpr {
  let ty = info.result_tys[0].clone();
  match ty {
    EggType::FloatT(w) => {
      return expr(
        RdgEggOp::Const(RdgConst::float(f, w.map(|w| w as u32))),
        [],
        info,
      );
    }
    _ => {
      panic!("float type mismatch: {} vs {:?}", f, ty);
    }
  }
}

macro_rules! op_egg_expr_constructer {
  ($op: ident, $fname:ident, $x: ident, $y:ident, $z: ident) => {
    pub fn $fname(
      $x: RcRdgEggExpr,
      $y: RcRdgEggExpr,
      $z: RcRdgEggExpr,
      info: RdgEggInfo,
    ) -> RcRdgEggExpr {
      expr(RdgEggOp::Top(TernaryOp::$op), [$x, $y, $z], info)
    }
  };
  ($op: ident, $fname:ident, $x: ident, $y:ident) => {
    pub fn $fname(
      $x: RcRdgEggExpr,
      $y: RcRdgEggExpr,
      info: RdgEggInfo,
    ) -> RcRdgEggExpr {
      expr(RdgEggOp::Bop(BinaryOp::$op), [$x, $y], info)
    }
  };
  ($op: ident, $fname:ident, $x: ident) => {
    pub fn $fname($x: RcRdgEggExpr, info: RdgEggInfo) -> RcRdgEggExpr {
      expr(RdgEggOp::Uop(UnaryOp::$op), [$x], info)
    }
  };
}

// pub fn add(x: RcRdgEggExpr, y: RcRdgEggExpr) -> RcRdgEggExpr {
//   expr(RdgEgg::Bop(BinaryOp::Add), [x, y])
// }

op_egg_expr_constructer!(Add, add, x, y);
op_egg_expr_constructer!(Sub, sub, x, y);
op_egg_expr_constructer!(Mul, mul, x, y);
op_egg_expr_constructer!(Div, div, x, y);
op_egg_expr_constructer!(Mod, modulo, x, y);
op_egg_expr_constructer!(Eq, eq, x, y);
op_egg_expr_constructer!(Ne, ne, x, y);
op_egg_expr_constructer!(LessEq, less_eq, x, y);
op_egg_expr_constructer!(LessThan, less_than, x, y);
op_egg_expr_constructer!(GreaterEq, greater_eq, x, y);
op_egg_expr_constructer!(GreaterThan, greater_than, x, y);
op_egg_expr_constructer!(Max, max, x, y);
op_egg_expr_constructer!(Min, min, x, y);
op_egg_expr_constructer!(Shl, shl, x, y);
op_egg_expr_constructer!(Shr, shr, x, y);
op_egg_expr_constructer!(And, and, x, y);
op_egg_expr_constructer!(Or, or, x, y);
op_egg_expr_constructer!(Xor, xor, x, y);
// op_egg_expr_constructer!(Load, load, e, state);
op_egg_expr_constructer!(Not, not, x);
op_egg_expr_constructer!(Abs, abs, x);
op_egg_expr_constructer!(Select, select, cond, thn, els);
op_egg_expr_constructer!(Store, store, addr, val, state);
op_egg_expr_constructer!(StateMerge, statemerge, a, b);

macro_rules! cast_egg_expr_constructer_range {
  ($op: ident, $fname:ident, $x: ident, $from: ident, $to: ident) => {
    pub fn $fname(
      $x: RcRdgEggExpr,
      $from: usize,
      $to: usize,
      info: RdgEggInfo,
    ) -> RcRdgEggExpr {
      expr(
        RdgEggOp::Uop(UnaryOp::Cast(CastOp::$op(CastRange::WithWidth(
          $from, $to,
        )))),
        [$x],
        RdgEggInfo {
          result_tys: vec![EggType::IntT(Some($to))],
          ..info
        },
      )
    }
  };
}

macro_rules! cast_egg_expr_constructer_no_range {
  ($op: ident, $fname:ident, $x: ident) => {
    pub fn $fname($x: RcRdgEggExpr, info: RdgEggInfo) -> RcRdgEggExpr {
      expr(RdgEggOp::Uop(UnaryOp::Cast(CastOp::$op)), [$x], info)
    }
  };
}

cast_egg_expr_constructer_range!(ZExt, zext, x, from, to);
cast_egg_expr_constructer_no_range!(FPTrunc, fptrunc, x);
cast_egg_expr_constructer_no_range!(FPExt, fpext, x);
cast_egg_expr_constructer_range!(Trunc, trunc, x, from, to);
cast_egg_expr_constructer_range!(SExt, sext, x, from, to);

pub fn iobarrier(
  ptr: RcRdgEggExpr,
  state: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::IOBarrier, [ptr, state], info)
}

pub fn dummy(
  name: String,
  args: Vec<RcRdgEggExpr>,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  Rc::new(RdgEggExpr::new(
    RdgEggOp::Dummy(Dummy { name }).with(info),
    args,
  ))
}

pub fn vec_add(
  a: RcRdgEggExpr,
  b: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::VecAdd), [a, b], info)
}

pub fn vec_mul(
  a: RcRdgEggExpr,
  b: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::VecMul), [a, b], info)
}

pub fn vec_sub(
  a: RcRdgEggExpr,
  b: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::VecSub), [a, b], info)
}

pub fn vec_div(
  a: RcRdgEggExpr,
  b: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::VecDiv), [a, b], info)
}

pub fn vec_neg(a: RcRdgEggExpr, info: RdgEggInfo) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::VecNeg), [a], info)
}

pub fn vec_const(
  operands: Vec<RcRdgEggExpr>,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  expr(RdgEggOp::VectorOp(VectorOp::Vec), operands, info)
}

pub fn load(
  x: RcRdgEggExpr,
  y: RcRdgEggExpr,
  info: RdgEggInfo,
) -> RcRdgEggExpr {
  // let ty = if info.result_tys.is_empty() {
  //   EggType::Unknown
  // } else {
  //   info.result_tys[0].clone()
  // };
  expr(RdgEggOp::Bop(BinaryOp::Load), [x, y], info)
}
