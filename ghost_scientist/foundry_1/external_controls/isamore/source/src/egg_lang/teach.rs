use super::*;

macro_rules! vec_op_to_shielding {
  ($vec_op:ident) => {
    ShieldingOp::VectorOp(babble::teachable::VectorOp::$vec_op)
  };
}

impl babble::Teachable for RdgEgg {
  fn from_binding_expr<T>(
    binding_expr: babble::BindingExpr<T>,
  ) -> babble::AstNode<Self, T> {
    use babble::BindingExpr;
    match binding_expr {
      BindingExpr::Var(idx) => babble::AstNode::leaf(RdgEggOp::Var(idx).into()),
      BindingExpr::LibVar(lib_id) => {
        babble::AstNode::leaf(RdgEggOp::LibVar(lib_id).into())
      }
      BindingExpr::Lambda(body) => {
        babble::AstNode::new(RdgEggOp::Lambda.into(), [body])
      }
      BindingExpr::Apply(fun, arg) => {
        babble::AstNode::new(RdgEggOp::Apply.into(), [fun, arg])
      }
      BindingExpr::Lib(lib_id, bound_value, body, lat_cpu, lat_acc, cost) => {
        babble::AstNode::new(
          RdgEggOp::Lib(lib_id, lat_cpu, lat_acc, cost).into(),
          [bound_value, body],
        )
      }
    }
  }

  fn as_binding_expr<T>(
    node: &babble::AstNode<Self, T>,
  ) -> Option<babble::BindingExpr<&T>> {
    use babble::BindingExpr;
    let (op, args) = node.as_parts();
    match (&op.op, args) {
      (RdgEggOp::Var(idx), []) => Some(BindingExpr::Var(*idx)),
      (RdgEggOp::LibVar(lib_id), []) => Some(BindingExpr::LibVar(*lib_id)),
      (RdgEggOp::Lambda, [body]) => Some(BindingExpr::Lambda(body)),
      (RdgEggOp::Apply, [fun, arg]) => Some(BindingExpr::Apply(fun, arg)),
      (RdgEggOp::Lib(lib_id, lat_cpu, lat_acc, cost), [bound_value, body]) => {
        Some(BindingExpr::Lib(
          *lib_id,
          bound_value,
          body,
          *lat_cpu,
          *lat_acc,
          *cost,
        ))
      }
      _ => None,
    }
  }

  fn list() -> Self {
    RdgEggOp::List.into()
  }

  fn to_shielding_op(&self) -> ShieldingOp {
    match self.op.clone() {
      RdgEggOp::List => ShieldingOp::List,
      RdgEggOp::Lambda => ShieldingOp::Lambda,
      RdgEggOp::Apply => ShieldingOp::Apply,
      RdgEggOp::Var(_) => ShieldingOp::Var,
      RdgEggOp::Lib(id, _, _, _) => ShieldingOp::Lib(id),
      RdgEggOp::LibVar(id) => ShieldingOp::LibVar(id),
      RdgEggOp::Const(c) => match c {
        RdgConst::Int(_, w) => ShieldingOp::Const(ShieldingConst::Int(w)),
        RdgConst::Float(_, w) => ShieldingOp::Const(ShieldingConst::Float(w)),
        RdgConst::VecInt(vec, w) => {
          ShieldingOp::Const(ShieldingConst::VecInt(vec.len() as u32, w))
        }
        RdgConst::VecFloat(vec, w) => {
          ShieldingOp::Const(ShieldingConst::VecFloat(vec.len() as u32, w))
        }
      },
      RdgEggOp::Top(top) => match top {
        TernaryOp::Store => ShieldingOp::Top(ShieldingTop::Store),
        TernaryOp::Select => ShieldingOp::Top(ShieldingTop::Select),
      },
      RdgEggOp::Bop(bop) => match bop {
        BinaryOp::Add => ShieldingOp::Bop(ShieldingBop::Add),
        BinaryOp::Sub => ShieldingOp::Bop(ShieldingBop::Sub),
        BinaryOp::Mul => ShieldingOp::Bop(ShieldingBop::Mul),
        BinaryOp::Div => ShieldingOp::Bop(ShieldingBop::Div),
        BinaryOp::Mod => ShieldingOp::Bop(ShieldingBop::Mod),
        BinaryOp::Eq => ShieldingOp::Bop(ShieldingBop::Eq),
        BinaryOp::Ne => ShieldingOp::Bop(ShieldingBop::Ne),
        BinaryOp::LessThan => ShieldingOp::Bop(ShieldingBop::LessThan),
        BinaryOp::GreaterThan => ShieldingOp::Bop(ShieldingBop::GreaterThan),
        BinaryOp::LessEq => ShieldingOp::Bop(ShieldingBop::LessEq),
        BinaryOp::GreaterEq => ShieldingOp::Bop(ShieldingBop::GreaterEq),
        BinaryOp::Max => ShieldingOp::Bop(ShieldingBop::Max),
        BinaryOp::Min => ShieldingOp::Bop(ShieldingBop::Min),
        BinaryOp::Shl => ShieldingOp::Bop(ShieldingBop::Shl),
        BinaryOp::Shr => ShieldingOp::Bop(ShieldingBop::Shr),
        BinaryOp::And => ShieldingOp::Bop(ShieldingBop::And),
        BinaryOp::Or => ShieldingOp::Bop(ShieldingBop::Or),
        BinaryOp::Xor => ShieldingOp::Bop(ShieldingBop::Xor),
        BinaryOp::Load => ShieldingOp::Bop(ShieldingBop::Load),
        BinaryOp::StateMerge => ShieldingOp::Bop(ShieldingBop::StateMerge),
      },
      RdgEggOp::Uop(uop) => match uop {
        UnaryOp::Abs => ShieldingOp::Uop(ShieldingUop::Abs),
        UnaryOp::Not => ShieldingOp::Uop(ShieldingUop::Not),
        UnaryOp::Neg => ShieldingOp::Uop(ShieldingUop::Neg),
        UnaryOp::Cast(cas) => match cas {
          CastOp::ZExt(_) => ShieldingOp::Uop(ShieldingUop::Cast(
            babble::teachable::CastOp::ZExt,
          )),
          CastOp::FPTrunc => ShieldingOp::Uop(ShieldingUop::Cast(
            babble::teachable::CastOp::FPTrunc,
          )),
          CastOp::FPExt => ShieldingOp::Uop(ShieldingUop::Cast(
            babble::teachable::CastOp::FPExt,
          )),
          CastOp::Trunc(_) => ShieldingOp::Uop(ShieldingUop::Cast(
            babble::teachable::CastOp::Trunc,
          )),
          CastOp::SExt(_) => ShieldingOp::Uop(ShieldingUop::Cast(
            babble::teachable::CastOp::SExt,
          )),
        },
      },
      RdgEggOp::Get(_) => ShieldingOp::Get,
      RdgEggOp::Dummy(dummy) => ShieldingOp::Dummy(dummy.name),
      RdgEggOp::Tuple(_) => ShieldingOp::Tuple,
      RdgEggOp::Switch => ShieldingOp::Switch,
      RdgEggOp::DoWhile => ShieldingOp::DoWhile,
      RdgEggOp::Arg(_) => ShieldingOp::Arg,
      RdgEggOp::Function(func) => ShieldingOp::Function(func.name),
      RdgEggOp::RulerVar(_) => ShieldingOp::RulerVar,
      RdgEggOp::IOBarrier => ShieldingOp::IOBarrier,
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::Vec => vec_op_to_shielding!(Vec),
        VectorOp::VecCmp => vec_op_to_shielding!(VecCmp),
        VectorOp::VecAdd => vec_op_to_shielding!(VecAdd),
        VectorOp::VecSub => vec_op_to_shielding!(VecSub),
        VectorOp::VecMul => vec_op_to_shielding!(VecMul),
        VectorOp::VecDiv => vec_op_to_shielding!(VecDiv),
        VectorOp::VecMac => vec_op_to_shielding!(VecMac),
        VectorOp::VecRem => vec_op_to_shielding!(VecRem),
        VectorOp::VecNeg => vec_op_to_shielding!(VecNeg),
        VectorOp::VecNot => vec_op_to_shielding!(VecNot),
        VectorOp::VecAbs => vec_op_to_shielding!(VecAbs),
        VectorOp::VecSext => vec_op_to_shielding!(VecSext),
        VectorOp::VecZext => vec_op_to_shielding!(VecZext),
        VectorOp::VecTrunc => vec_op_to_shielding!(VecTrunc),
        VectorOp::VecFPTrunc => vec_op_to_shielding!(VecFPTrunc),
        VectorOp::VecFPExt => vec_op_to_shielding!(VecFPExt),
        VectorOp::VecLoad => vec_op_to_shielding!(VecLoad),
        VectorOp::VecStore => vec_op_to_shielding!(VecStore),
        VectorOp::Concat => vec_op_to_shielding!(Concat),
        VectorOp::VecAnd => vec_op_to_shielding!(VecAnd),
        VectorOp::VecOr => vec_op_to_shielding!(VecOr),
        VectorOp::VecXor => vec_op_to_shielding!(VecXor),
        VectorOp::VecShr => vec_op_to_shielding!(VecShr),
        VectorOp::VecShl => vec_op_to_shielding!(VecShl),
        VectorOp::Gather(_) => vec_op_to_shielding!(Gather),
        VectorOp::Shuffle(_) => vec_op_to_shielding!(Shuffle),
      },
      RdgEggOp::OpPack(_) => ShieldingOp::OpPack,
      RdgEggOp::OpSelect => ShieldingOp::OpSelect,
      RdgEggOp::OpMask => ShieldingOp::OpMask,
    }
  }
}

impl babble::Arity for RdgEgg {
  fn min_arity(&self) -> usize {
    match self.op.clone() {
      RdgEggOp::List => 0,
      RdgEggOp::Lambda => 1,
      RdgEggOp::Apply => 2,
      RdgEggOp::Var(_) => 0,
      RdgEggOp::Lib(_, _, _, _) => 2,
      RdgEggOp::LibVar(_) => 0,
      RdgEggOp::Const(_) => 0,
      RdgEggOp::Top(_) => 3,
      RdgEggOp::Bop(_) => 2,
      RdgEggOp::Uop(_) => 1,
      RdgEggOp::Get(_) => 1,
      RdgEggOp::Dummy(_) => 0,
      RdgEggOp::Tuple(_) => 0,
      RdgEggOp::Switch => 2,
      RdgEggOp::DoWhile => 2,
      RdgEggOp::Arg(_) => 0,
      RdgEggOp::Function(_) => 1,
      RdgEggOp::RulerVar(_) => 0,
      RdgEggOp::IOBarrier => 2,
      RdgEggOp::OpPack(_) => 0,
      RdgEggOp::OpSelect => 1,
      RdgEggOp::OpMask => 0,
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::Vec => 0,
        VectorOp::VecAdd => 2,
        VectorOp::VecCmp => 2,
        VectorOp::VecSub => 2,
        VectorOp::VecMul => 2,
        VectorOp::VecDiv => 2,
        VectorOp::VecMac => 3,
        VectorOp::VecRem => 2,
        VectorOp::VecAnd => 2,
        VectorOp::VecOr => 2,
        VectorOp::VecXor => 2,
        VectorOp::VecAbs => 1,
        VectorOp::VecNeg => 1,
        VectorOp::VecNot => 1,
        VectorOp::VecSext => 1,
        VectorOp::VecZext => 1,
        VectorOp::VecTrunc => 1,
        VectorOp::VecFPTrunc => 1,
        VectorOp::VecFPExt => 1,
        VectorOp::VecLoad => 2,
        VectorOp::VecStore => 3,
        VectorOp::VecShl => 2,
        VectorOp::VecShr => 2,
        VectorOp::Concat => 2,
        VectorOp::Gather(_) => 1,
        VectorOp::Shuffle(_) => 2,
      },
    }
  }
  fn max_arity(&self) -> Option<usize> {
    match self.op.clone() {
      RdgEggOp::List => None,
      RdgEggOp::Switch => None,
      RdgEggOp::Tuple(_) => None,
      RdgEggOp::Dummy(_) => None,
      RdgEggOp::OpSelect => None,
      RdgEggOp::OpMask => None, /* 由于该节点可以匹配任意的操作符， */
      // 所以参数数目没有上下界
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::Vec => None,
        _ => Some(self.min_arity()),
      },
      _ => Some(self.min_arity()),
    }
  }
}
