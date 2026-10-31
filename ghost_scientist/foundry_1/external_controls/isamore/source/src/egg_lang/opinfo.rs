use core::panic;
use std::f32::consts::E;

use babble::{LibId, bb_query::BBInfo};
use egg::Symbol;

use super::*;
impl TypeInfo<EggType> for AstNode<RdgEgg> {
  fn get_rtype(&self, child_types: &Vec<EggType>) -> EggType {
    // 如果op已经有了类型，则直接返回
    if self.operation().info.result_tys.len() > 0 {
      return self.operation().info.result_tys[0].clone();
    }
    let op = self.operation().op.clone();

    let ty = self.operation().info.result_tys.clone();
    match op {
      RdgEggOp::Const(RdgConst::Int(_, w)) => {
        EggType::IntT(w.map(|w| w as usize))
      }
      RdgEggOp::Const(RdgConst::Float(_, w)) => {
        EggType::FloatT(w.map(|w| w as usize))
      }
      RdgEggOp::Arg(_) => ty[0].clone(),
      RdgEggOp::Get(_) => {
        let ty = ty[0].clone();
        // 补丁，parse错误时会出现vec
        if ty.is_vector() { EggType::Unknown } else { ty }
      }
      RdgEggOp::Top(top) => {
        assert!(child_types.len() == 3);
        match top {
          TernaryOp::Store => EggType::Unknown,
          TernaryOp::Select => {
            assert!(
              child_types[0] == EggType::IntT(Some(1))
                || child_types[0] == EggType::Unknown
            );
            child_types[1].clone()
          }
        }
      }
      RdgEggOp::Bop(bop) => {
        assert!(child_types.len() == 2);
        match bop {
          BinaryOp::Add | BinaryOp::Sub | BinaryOp::Mul | BinaryOp::Div => {
            match (child_types[0].clone(), child_types[1].clone()) {
              (EggType::IntT(a), EggType::IntT(b)) => {
                let max = std::cmp::max(a, b);
                EggType::IntT(max)
              }
              (EggType::FloatT(a), EggType::FloatT(b)) => {
                let max = std::cmp::max(a, b);
                EggType::FloatT(max)
              }
              (EggType::IntT(a), EggType::FloatT(b))
              | (EggType::FloatT(b), EggType::IntT(a)) => {
                let max = std::cmp::max(a, b);
                EggType::FloatT(max)
              }
              (ty, EggType::Unknown) | (EggType::Unknown, ty) => ty,
              _ => panic!(
                "Unsupported type for binary operation: {:?} vs {:?}",
                child_types[0], child_types[1]
              ),
            }
          }
          BinaryOp::Mod => {
            match (child_types[0].clone(), child_types[1].clone()) {
              (EggType::IntT(a), EggType::IntT(b)) => {
                let max = std::cmp::max(a, b);
                EggType::IntT(max)
              }
              (EggType::IntT(a), EggType::Unknown)
              | (EggType::Unknown, EggType::IntT(a)) => EggType::IntT(a),
              (EggType::Unknown, EggType::Unknown) => EggType::Unknown,
              (_, EggType::FloatT(_)) | (EggType::FloatT(_), _) => {
                panic!("Mod operation not supported for float types");
              }
              _ => panic!("Unsupported type for binary operation"),
            }
          }
          BinaryOp::Eq
          | BinaryOp::Ne
          | BinaryOp::LessThan
          | BinaryOp::GreaterThan
          | BinaryOp::LessEq
          | BinaryOp::GreaterEq => EggType::IntT(Some(1)),
          BinaryOp::Shl | BinaryOp::Shr => {
            match (child_types[0].clone(), child_types[1].clone()) {
              (EggType::IntT(a), EggType::IntT(_b)) => EggType::IntT(a),
              (EggType::IntT(a), EggType::Unknown)
              | (EggType::Unknown, EggType::IntT(a)) => EggType::IntT(a),
              (EggType::Unknown, EggType::Unknown) => EggType::Unknown,
              _ => panic!("Shift operation not supported for float types"),
            }
          }
          BinaryOp::And | BinaryOp::Or | BinaryOp::Xor => {
            match (child_types[0].clone(), child_types[1].clone()) {
              (EggType::IntT(a), EggType::IntT(b)) => {
                EggType::IntT(std::cmp::max(a, b))
              }
              (EggType::IntT(a), EggType::Unknown)
              | (EggType::Unknown, EggType::IntT(a)) => EggType::IntT(a),
              (EggType::Unknown, EggType::Unknown) => EggType::Unknown,
              _ => EggType::Unknown,
            }
          }
          BinaryOp::Max | BinaryOp::Min => {
            match (child_types[0].clone(), child_types[1].clone()) {
              (EggType::IntT(a), EggType::IntT(b)) => {
                let max = std::cmp::max(a, b);
                EggType::IntT(max)
              }
              (EggType::FloatT(a), EggType::FloatT(b)) => {
                let max = std::cmp::max(a, b);
                EggType::FloatT(max)
              }
              (EggType::IntT(a), EggType::FloatT(b))
              | (EggType::FloatT(b), EggType::IntT(a)) => {
                let max = std::cmp::max(a, b);
                EggType::FloatT(max)
              }
              (ty, EggType::Unknown) | (EggType::Unknown, ty) => ty,
              _ => panic!("Unsupported type for binary operation"),
            }
          }
          BinaryOp::Load => {
            // Load直接返回Unknown
            EggType::Unknown
          }
          BinaryOp::StateMerge => EggType::IntT(Some(0)),
        }
      }
      RdgEggOp::Uop(uop) => {
        assert!(child_types.len() == 1);
        match uop {
          UnaryOp::Abs => child_types[0].clone(),
          UnaryOp::Not => child_types[0].clone(),
          UnaryOp::Neg => child_types[0].clone(),
          // TODO: 后面需要处理类型问题
          UnaryOp::Cast(castop) => match castop {
            CastOp::FPExt | CastOp::FPTrunc => EggType::FloatT(None),
            CastOp::SExt(cr) | CastOp::ZExt(cr) | CastOp::Trunc(cr) => match cr
            {
              CastRange::WithWidth(_, to) => EggType::IntT(Some(to)),
              _ => EggType::IntT(None),
            },
          },
        }
      }
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::Vec => {
          let ty = child_types[0].clone();
          EggType::VectorT(Box::new(ty), Some(child_types.len()))
        }
        VectorOp::VecAdd
        | VectorOp::VecSub
        | VectorOp::VecMul
        | VectorOp::VecDiv
        | VectorOp::VecCmp => {
          assert!(child_types.len() == 2);
          child_types[0].clone()
        }
        VectorOp::VecMac => {
          assert!(child_types.len() == 3);
          child_types[0].clone()
        }
        VectorOp::VecNeg | VectorOp::VecAbs | VectorOp::VecNot => {
          assert!(child_types.len() == 1);
          child_types[0].clone()
        }
        VectorOp::VecSext => {
          assert!(child_types.len() == 1);
          // FIXME:目前先按照child_types[0]的类型来处理
          // 后面需要处理成tys[0]的类型
          child_types[0].clone()
        }
        VectorOp::Concat => {
          assert!(child_types.len() == 2);
          let ty1 = child_types[0].clone();
          let ty2 = child_types[1].clone();
          match (ty1, ty2) {
            (EggType::VectorT(ty1, len1), EggType::VectorT(ty2, len2)) => {
              let ty1 = ty1.as_ref().clone();
              let ty2 = ty2.as_ref().clone();
              EggType::VectorT(
                Box::new(Self::merge_types(&ty1, &ty2)),
                Some(len1.unwrap() + len2.unwrap()),
              )
            }
            _ => panic!("Invalid type for concat"),
          }
        }
        VectorOp::Gather(gather) => {
          assert!(child_types.len() == 1);
          let indices = &gather.indices;
          // 按照index来拿取
          let len = indices.len();
          match child_types[0].clone() {
            EggType::VectorT(ty, _) => {
              let ty = ty.as_ref().clone();
              EggType::VectorT(Box::new(ty), Some(len))
            }
            EggType::Unknown => {
              EggType::VectorT(Box::new(EggType::Unknown), Some(len))
            }
            _ => panic!("Invalid type for gather"),
          }
        }
        VectorOp::Shuffle(shuffle) => {
          assert!(child_types.len() == 2);
          let indices = &shuffle.indices;
          // 按照index来拿取
          let len = indices.len();
          match child_types[0].clone() {
            EggType::VectorT(ty, _) => {
              let ty = ty.as_ref().clone();
              EggType::VectorT(Box::new(ty), Some(len))
            }
            EggType::Unknown => {
              EggType::VectorT(Box::new(EggType::Unknown), Some(len))
            }
            _ => panic!("Invalid type for shuffle"),
          }
        }
        _ => EggType::Unknown,
      },
      _ => {
        // 其他操作符暂时不处理
        EggType::Unknown
      }
    }
  }

  fn merge_types(a: &EggType, b: &EggType) -> EggType {
    match (a, b) {
      (EggType::IntT(a_ty), EggType::IntT(b_ty)) => {
        if a_ty.is_none() && b_ty.is_none() {
          return EggType::IntT(None);
        } else if a_ty.is_none() {
          return b.clone();
        } else if b_ty.is_none() {
          return a.clone();
        }
        if a_ty.unwrap() == 1 && b_ty.unwrap() == 1 {
          EggType::IntT(Some(1))
        } else {
          let max_width = std::cmp::max(*a_ty, *b_ty);
          EggType::IntT(max_width)
        }
      }
      (EggType::FloatT(a_ty), EggType::FloatT(b_ty)) => {
        if a_ty.is_none() && b_ty.is_none() {
          return EggType::FloatT(None);
        } else if a_ty.is_none() {
          return b.clone();
        } else if b_ty.is_none() {
          return a.clone();
        }
        EggType::FloatT(std::cmp::max(*a_ty, *b_ty))
      }
      // FIXME: 这里将Int改为Float会有一些问题，不知道应该怎么解决
      (EggType::IntT(int_width), EggType::FloatT(_))
      | (EggType::FloatT(_), EggType::IntT(int_width)) => {
        EggType::IntT(*int_width)
      }
      // 处理VectorT的所有情况
      (EggType::VectorT(ty1, len1), EggType::VectorT(ty2, len2)) => {
        let ty1 = ty1.as_ref().clone();
        let ty2 = ty2.as_ref().clone();
        if len1 == len2 {
          EggType::VectorT(Box::new(Self::merge_types(&ty1, &ty2)), *len1)
        } else {
          EggType::VectorT(Box::new(Self::merge_types(&ty1, &ty2)), None)
        }
      }
      (EggType::VectorT(ty, len), other)
      | (other, EggType::VectorT(ty, len)) => {
        if !matches!(other, EggType::Unknown) {
          panic!("VectorT type mismatch: {:?} vs {:?}", a, b);
          return EggType::Unknown;
        }
        EggType::VectorT(ty.clone(), *len)
      }
      // 如果存在unkown类型，而另外一个类型不是unkown，则返回另外一个类型
      (EggType::Unknown, _) => b.clone(),
      (_, EggType::Unknown) => a.clone(),
    }
  }

  fn merge_types_neglecting_width(a: &EggType, b: &EggType) -> EggType {
    match (a, b) {
      (EggType::IntT(Some(1)), EggType::IntT(Some(1))) => {
        EggType::IntT(Some(1))
      }
      (EggType::IntT(_), EggType::IntT(_)) => {
        EggType::IntT(None) // 忽略宽度
      }
      (EggType::FloatT(_), EggType::FloatT(_)) => EggType::FloatT(None),
      (EggType::IntT(_), EggType::FloatT(_))
      | (EggType::FloatT(_), EggType::IntT(_)) => EggType::FloatT(None),
      (EggType::VectorT(ty1, _), EggType::VectorT(ty2, _)) => {
        let ty1 = ty1.as_ref().clone();
        let ty2 = ty2.as_ref().clone();
        EggType::VectorT(
          Box::new(Self::merge_types_neglecting_width(&ty1, &ty2)),
          None,
        )
      }
      (EggType::VectorT(ty, _), other) | (other, EggType::VectorT(ty, _)) => {
        if !matches!(other, EggType::Unknown) {
          return EggType::Unknown;
        }
        EggType::VectorT(ty.clone(), None)
      }
      (EggType::Unknown, _) => b.clone(),
      (_, EggType::Unknown) => a.clone(),
    }
  }
  fn can_merge_types(a: &EggType, b: &EggType) -> bool {
    // 从硬件意义上观察能否合并，也就是说，合并之后的硬件能够在两个类型上都能用
    match (a, b) {
      // 如果都是Int(0)或者都是其他位宽的Int，那么可以合并
      (EggType::IntT(Some(0)), EggType::IntT(Some(0))) => true,
      (EggType::IntT(Some(a_width)), EggType::IntT(Some(b_width))) => {
        *a_width != 0 && *b_width != 0
      }
      // Int(None)可以和非0的Int(Some)合并
      (EggType::IntT(None), EggType::IntT(Some(_)))
      | (EggType::IntT(Some(_)), EggType::IntT(None)) => true,
      // 都是Float
      (EggType::FloatT(Some(_)), EggType::FloatT(Some(_))) => true,
      // Float(None)可以和非0的Float(Some)合并
      (EggType::FloatT(None), EggType::FloatT(Some(_)))
      | (EggType::FloatT(Some(_)), EggType::FloatT(None)) => true,
      // 都是VectorT
      (EggType::VectorT(ty1, _), EggType::VectorT(ty2, _)) => {
        let ty1 = ty1.as_ref();
        let ty2 = ty2.as_ref();
        Self::can_merge_types(ty1, ty2)
      }
      // Unknown可以和任何类型合并
      (EggType::Unknown, _) | (_, EggType::Unknown) => true,
      // 其余情况不支持合并
      _ => false,
    }
  }
}

// 为RdgEgg实现OprerationInfo trait
impl OperationInfo for RdgEgg {
  fn get_full_info(&self) -> String {
    // 拿到ty，bbs，进行排序，和operation一起，组成完整信息
    let mut tys = self.info.result_tys.clone();
    tys.sort_by(|a, b| a.to_string().cmp(&b.to_string()));
    let mut bbs = self.info.bbs.clone();
    bbs.sort();
    let info = format!(
      "op: {}, tys: {:?}, bbs: {:?}",
      self.op,
      tys.iter().map(|ty| ty.to_string()).collect::<Vec<String>>(),
      bbs
    );
    info
  }
  fn is_commutative(&self) -> bool {
    match self.op {
      RdgEggOp::List => true,
      RdgEggOp::Bop(BinaryOp::Add)
      | RdgEggOp::Bop(BinaryOp::And)
      | RdgEggOp::Bop(BinaryOp::Or)
      | RdgEggOp::Bop(BinaryOp::Xor)
      | RdgEggOp::Bop(BinaryOp::Mul)
      | RdgEggOp::Bop(BinaryOp::Ne)
      | RdgEggOp::Bop(BinaryOp::Eq)
      | RdgEggOp::Bop(BinaryOp::Max)
      | RdgEggOp::Bop(BinaryOp::Min)
      | RdgEggOp::Bop(BinaryOp::StateMerge) => true,
      RdgEggOp::VectorOp(VectorOp::VecAdd)
      | RdgEggOp::VectorOp(VectorOp::VecMul)
      | RdgEggOp::VectorOp(VectorOp::VecAnd)
      | RdgEggOp::VectorOp(VectorOp::VecOr)
      | RdgEggOp::VectorOp(VectorOp::VecXor)
      | RdgEggOp::VectorOp(VectorOp::Concat) => true,
      _ => false,
    }
  }
  fn is_dowhile(&self) -> bool {
    match self.op {
      RdgEggOp::DoWhile => true,
      _ => false,
    }
  }
  fn is_liblearn_banned_op(&self) -> bool {
    // dummy, lib ， libvar, var, rulevar, apply, lambda
    match self.op {
      RdgEggOp::Dummy(_) => true,
      RdgEggOp::Lib(_, _, _, _) => true,
      RdgEggOp::LibVar(_) => true,
      RdgEggOp::Var(_) => true,
      RdgEggOp::RulerVar(_) => true,
      RdgEggOp::Apply => true,
      RdgEggOp::Lambda => true,
      RdgEggOp::Get(_) => true, /* get操作不允许学习， */
      RdgEggOp::VectorOp(VectorOp::Vec) => true, /* vec操作不允许学习， */
      // 因为会引起反常的
      // 多次匹配
      RdgEggOp::List => true, /* list操作不允许学习， */
      RdgEggOp::Tuple(_) => true, /* tuple操作不允许学习， */
      _ => false,
    }
  }
  fn is_lib(&self) -> bool {
    match self.op {
      RdgEggOp::Lib(_, _, _, _) => true,
      _ => false,
    }
  }
  fn is_lib_op(&self) -> bool {
    match self.op {
      RdgEggOp::LibVar(_) => true,
      RdgEggOp::Lib(_, _, _, _) => true,
      RdgEggOp::Apply => true,
      RdgEggOp::Lambda => true,
      _ => false,
    }
  }
  fn is_list_op(&self) -> bool {
    match self.op {
      RdgEggOp::List => true,
      _ => false,
    }
  }
  fn get_libid(&self) -> usize {
    match self.op {
      RdgEggOp::Lib(libid, _, _, _) => {
        let id = libid.0;
        id
      }
      _ => panic!("Not a lib"),
    }
  }
  fn make_lib(
    id: LibId,
    latency_cpu: f64,
    latency_acc: f64,
    cost: usize,
  ) -> Self {
    RdgEgg {
      op: RdgEggOp::Lib(
        id,
        OrderedFloat(latency_cpu),
        OrderedFloat(latency_acc),
        cost,
      ),
      info: RdgEggInfo::default(),
    }
  }
  fn make_vec(result_tys: Vec<String>, bbs_info: Vec<String>) -> Self {
    let ty = EggType::VectorT(
      Box::new(result_tys[0].parse::<EggType>().unwrap()),
      Some(result_tys.len()),
    );
    RdgEggOp::VectorOp(VectorOp::Vec).with(RdgEggInfo {
      result_tys: vec![ty],
      bbs: bbs_info,
    })
  }
  fn make_get_from_vec(
    id: usize,
    result_tys: Vec<String>,
    bbs_info: Vec<String>,
  ) -> Self {
    let ty = if result_tys.is_empty() {
      EggType::Unknown
    } else {
      result_tys[0].parse::<EggType>().unwrap()
    };
    RdgEggOp::Get(GetOp::new(GetDataSource::VecElement(id))).with(RdgEggInfo {
      result_tys: result_tys
        .iter()
        .map(|ty| ty.parse::<EggType>().unwrap())
        .collect(),
      bbs: bbs_info,
    })
  }
  fn get_const(&self) -> Option<(i64, u32)> {
    match self.op {
      RdgEggOp::Const(RdgConst::Int(i, w)) => match w {
        Some(width) => Some((i, width)),
        None => None,
      },
      // RdgEggOp::Const(RdgConst::Float(f, w)) => Some((, w.unwrap())),
      _ => None,
    }
  }
  fn make_const(const_value: (i64, u32)) -> Self {
    RdgEggOp::Const(RdgConst::Int(const_value.0, Some(const_value.1))).into()
  }
  fn is_dummy(&self) -> bool {
    matches!(self.op, RdgEggOp::Dummy(_))
  }
  fn is_vector_op(&self) -> bool {
    matches!(self.op, RdgEggOp::VectorOp(_))
  }
  fn get_simple_cost(&self) -> f64 {
    match self.op.clone() {
      RdgEggOp::VectorOp(vecop) => match vecop {
        VectorOp::VecAnd
        | VectorOp::VecOr
        | VectorOp::VecXor
        | VectorOp::VecCmp => 5.0,
        VectorOp::VecShl | VectorOp::VecShr => 0.5,
        VectorOp::VecAdd | VectorOp::VecSub => 1.0,
        VectorOp::VecMul | VectorOp::VecDiv | VectorOp::VecRem => 2.0,
        VectorOp::VecMac => 2.5,
        VectorOp::VecNeg | VectorOp::VecAbs | VectorOp::VecNot => 1.0,
        VectorOp::VecLoad => 2.0,
        VectorOp::VecStore => 3.0,
        VectorOp::Vec => 0.0, /* 必须严格遵守！！！，否则永远解决不了vec->get->vec链 */
        VectorOp::VecSext
        | VectorOp::VecZext
        | VectorOp::VecFPExt
        | VectorOp::VecFPTrunc
        | VectorOp::VecTrunc => 1.0,
        VectorOp::Concat => 0.2,
        VectorOp::Gather(_) => 0.0,
        VectorOp::Shuffle(_) => 0.0,
      },
      RdgEggOp::Const(_) => 1.0,
      RdgEggOp::Get(_) => 0.0, // 必须严格遵守！！！
      // // 鼓励选择lib
      // RdgEggOp::Lib(_, _, _) => 0.0,
      // RdgEggOp::Apply => 0.0,
      // RdgEggOp::LibVar(_) => 0.0,
      // RdgEggOp::Lambda => 0.0,
      _ => 1000.0,
    }
  }
  fn is_vec(&self) -> bool {
    match self.op {
      RdgEggOp::VectorOp(VectorOp::Vec) => true,
      _ => false,
    }
  }
  fn make_gather(indices: &Vec<usize>, bbs_info: Vec<String>) -> Self {
    RdgEggOp::VectorOp(VectorOp::Gather(Gather {
      indices: indices.clone(),
    }))
    .with(RdgEggInfo {
      result_tys: vec![],
      bbs: bbs_info,
    })
  }
  fn make_shuffle(indices: &Vec<usize>, bbs_info: Vec<String>) -> Self {
    RdgEggOp::VectorOp(VectorOp::Shuffle(Shuffle {
      indices: indices.clone(),
    }))
    .with(RdgEggInfo {
      result_tys: vec![],
      bbs: bbs_info,
    })
  }
  fn get_bbs_info(&self) -> Vec<String> {
    self.info.bbs.clone()
  }
  fn get_result_type(&self) -> Vec<String> {
    self
      .info
      .result_tys
      .iter()
      .map(|ty| ty.to_string())
      .collect::<Vec<String>>()
  }
  fn set_result_type(&mut self, result_ty: Vec<String>) {
    self.info.result_tys = result_ty
      .iter()
      .map(|ty| ty.parse::<EggType>().unwrap())
      .collect();
  }
  fn get_vec_len(&self) -> usize {
    if self.is_vector_op() {
      if self.info.result_tys.len() == 0 {
        return 1;
      }
      let ty = self.info.result_tys[0].clone();
      match ty {
        EggType::VectorT(_, len) => {
          if let Some(len) = len {
            len
          } else {
            1
          }
        }
        EggType::Unknown => 1, // 如果是unknown类型，默认长度为1
        _ => {
          panic!("Not a vector type")
        }
      }
    } else {
      1
    }
  }
  fn make_op_pack(ops: Vec<String>, bbs: Vec<String>) -> Self {
    RdgEggOp::OpPack(OpPack { config: ops })
      .with(RdgEggInfo {
        result_tys: vec![EggType::Unknown],
        bbs: bbs,
      })
      .into()
  }
  fn make_op_select() -> Self {
    RdgEggOp::OpSelect
      .with(RdgEggInfo {
        result_tys: vec![EggType::Unknown],
        ..Default::default()
      })
      .into()
  }
  fn make_rule_var(name: String) -> Self {
    RdgEggOp::RulerVar(Symbol::from(name))
      .with(RdgEggInfo {
        result_tys: vec![EggType::Unknown],
        ..Default::default()
      })
      .into()
  }
  fn make_opmask() -> Self {
    RdgEggOp::OpMask
      .with(RdgEggInfo {
        result_tys: vec![EggType::Unknown],
        ..Default::default()
      })
      .into()
  }
  fn is_opmask(&self) -> bool {
    matches!(self.op, RdgEggOp::OpMask)
  }
  fn is_rule_var(&self) -> bool {
    matches!(self.op, RdgEggOp::RulerVar(_))
  }
  fn get_bitwidth(&self) -> usize {
    if self.info.result_tys.len() > 0 {
      match self.info.result_tys[0] {
        EggType::IntT(Some(width)) => width,
        EggType::FloatT(Some(width)) => width,
        _ => 32,
      }
    } else {
      32
    }
  }
  fn make_bitwidth(&mut self, width: usize) {
    if self.info.result_tys.len() > 0 {
      match &mut self.info.result_tys[0] {
        EggType::IntT(w) => *w = Some(width),
        EggType::FloatT(w) => *w = Some(width),
        _ => {}
      }
    }
  }
  fn is_var(&self) -> bool {
    matches!(self.op, RdgEggOp::Var(_))
  }
  fn set_bbs_info(&mut self, bbs: Vec<String>) {
    self.info.bbs = bbs;
  }
  fn is_op(&self) -> bool {
    match &self.op {
      RdgEggOp::Bop(bop) => match bop {
        BinaryOp::StateMerge => false,
        _ => true,
      },
      RdgEggOp::Top(_) => true,
      RdgEggOp::Uop(_) => true,
      RdgEggOp::OpPack(_) => true,
      RdgEggOp::VectorOp(vec_op) => match vec_op {
        VectorOp::Vec => false,
        _ => true,
      },
      _ => false,
    }
  }
  fn is_tuple(&self) -> bool {
    matches!(self.op, RdgEggOp::Tuple(_))
  }
  fn is_get_from_arg(&self) -> bool {
    // 判断是否是从arg中获取的
    if let RdgEggOp::Get(get) = &self.op {
      matches!(get.source, GetDataSource::Arg(_))
    } else {
      false
    }
  }
  fn is_get_from_vec(&self) -> bool {
    // 判断是否是从vec中获取的
    if let RdgEggOp::Get(get) = &self.op {
      matches!(get.source, GetDataSource::VecElement(_))
    } else {
      false
    }
  }
  fn is_external_arg(&self) -> bool {
    // 根据arg的bbs信息来判断是否是外部arg
    if let RdgEggOp::Arg(arg) = &self.op {
      let bbs = &arg.bbs;
      //取出每一个bb，每一个String使用"#"切分，第二部分，如果有一个entry，
      // 说明是外部参数
      bbs.iter().any(|bb| {
        let parts: Vec<&str> = bb.split('#').collect();
        if parts.len() > 1 {
          parts[1].contains("entry")
        } else {
          false
        }
      })
    } else {
      false
    }
  }
  fn is_useful_expr(&self, children_ops: &[Self]) -> bool
  where
    Self: Sized,
  {
    // 主要是判读这个表达式能不能进行化简，如果可以进行化简，就是无用的
    // 首先检查children_ops里面有没有0和1
    let has_zero_or_one = if children_ops.iter().any(|op| {
      matches!(
        op.op,
        RdgEggOp::Const(RdgConst::Int(0, _))
          | RdgEggOp::Const(RdgConst::Int(1, _))
          | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
          | RdgEggOp::Const(RdgConst::Float(OrderedFloat(1.0), _))
      )
    }) {
      true
    } else {
      false
    };
    // 接下来检查子节点是不是相同
    let all_children_equal = if children_ops.len() > 1
      && children_ops.iter().all(|op| op.op == children_ops[0].op)
    {
      true
    } else {
      false
    };
    // 通过op的类型来判断是否是无用的，
    // 目前子节点中必然存在0或者1，所以大部分都不需要额外判断
    match self.op.clone() {
      RdgEggOp::Bop(bop) => match bop {
        BinaryOp::Add => {
          // 如果有一个子节点是0，则可以化简
          if children_ops.iter().any(|op| {
            matches!(
              op.op,
              RdgEggOp::Const(RdgConst::Int(0, _))
                | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
            )
          }) {
            return false;
          }
          // 第二个节点是Neg，则可以化简
          if matches!(children_ops[1].op, RdgEggOp::Uop(UnaryOp::Neg)) {
            return false;
          }
          true
        }
        BinaryOp::Sub => {
          // 第二个子节点是0，则可以化简
          if matches!(
            children_ops[1].op,
            RdgEggOp::Const(RdgConst::Int(0, _))
              | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
          ) || all_children_equal
          {
            return false;
          }
          // 第二个节点是Neg，则可以化简
          if matches!(children_ops[1].op, RdgEggOp::Uop(UnaryOp::Neg)) {
            return false;
          }
          true
        }
        BinaryOp::Mul => {
          // 因为有一个子节点是0或者1，所以总可以化简
          if has_zero_or_one {
            return false;
          }
          true
        }
        BinaryOp::Div | BinaryOp::Mod => {
          // 如果第二个节点为1或者第一个节点为0，则可以化简
          if matches!(
            children_ops[1].op,
            RdgEggOp::Const(RdgConst::Int(1, _))
              | RdgEggOp::Const(RdgConst::Float(OrderedFloat(1.0), _))
          ) || all_children_equal
          {
            return false;
          }
          if matches!(
            children_ops[0].op,
            RdgEggOp::Const(RdgConst::Int(0, _))
              | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
          ) {
            return false;
          }
          true
        }

        BinaryOp::Eq
        | BinaryOp::Ne
        | BinaryOp::LessThan
        | BinaryOp::GreaterThan
        | BinaryOp::LessEq
        | BinaryOp::GreaterEq => {
          if all_children_equal {
            return false; // 如果子节点相同，则可以化简
          }
          true
        }
        BinaryOp::Shl | BinaryOp::Shr => {
          // 如果子节点中任意一个是0，则可以化简
          if children_ops.iter().any(|op| {
            matches!(
              op.op,
              RdgEggOp::Const(RdgConst::Int(0, _))
                | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
            )
          }) || all_children_equal
          {
            return false;
          }
          true
        }
        BinaryOp::And | BinaryOp::Or => {
          if has_zero_or_one || all_children_equal {
            return false; // 如果子节点相同或者有0或1，则可以化简
          }
          true
        }
        BinaryOp::Xor => {
          // 如果子节点相同，则可以化简
          if all_children_equal {
            return false;
          }
          // 如果有一个子节点是0，则可以化简
          if children_ops.iter().any(|op| {
            matches!(
              op.op,
              RdgEggOp::Const(RdgConst::Int(0, _))
                | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
            )
          }) {
            return false;
          }
          true
        }
        BinaryOp::Max | BinaryOp::Min => {
          // 如果子节点相同，则可以化简
          if all_children_equal {
            return false;
          }
          true
        }
        _ => true, // 其他操作符都认为是有用的
      },
      RdgEggOp::Top(top) => match top {
        TernaryOp::Select => {
          // 如果第一个节点是0或者1，则可以化简
          if matches!(
            children_ops[0].op,
            RdgEggOp::Const(RdgConst::Int(0, _))
              | RdgEggOp::Const(RdgConst::Int(1, _))
              | RdgEggOp::Const(RdgConst::Float(OrderedFloat(0.0), _))
              | RdgEggOp::Const(RdgConst::Float(OrderedFloat(1.0), _))
          ) || all_children_equal
          {
            return false;
          }
          // 如果第二个节点和第三个节点相同，则可以化简
          if children_ops[1].op == children_ops[2].op {
            return false;
          }
          true
        }
        _ => true,
      },
      _ => true,
    }
  }

  fn is_mem(&self) -> bool {
    match self.op {
      RdgEggOp::Bop(BinaryOp::Load)
      | RdgEggOp::Top(TernaryOp::Store)
      | RdgEggOp::VectorOp(VectorOp::VecLoad)
      | RdgEggOp::VectorOp(VectorOp::VecStore) => true,
      _ => false,
    }
  }

  fn is_arithmetic(&self) -> bool {
    match &self.op {
      RdgEggOp::Bop(bop) => match bop {
        BinaryOp::StateMerge => false,
        BinaryOp::Load => false,
        _ => true,
      },

      RdgEggOp::Top(top) => match top {
        TernaryOp::Store => false,
        TernaryOp::Select => true,
      },
      RdgEggOp::Uop(_) => true,
      RdgEggOp::OpPack(_) => true,
      RdgEggOp::VectorOp(vec_op) => match vec_op {
        VectorOp::Vec | VectorOp::VecLoad | VectorOp::VecStore => false,
        _ => true,
      },
      _ => false,
    }
  }

  fn op_execution_count(&self, bb_query: &babble::bb_query::BBQuery) -> f64 {
    let factor = bb_query.get_factor();
    if self.info.bbs.is_empty() {
      return factor;
    }
    match bb_query.get(&self.info.bbs[0]) {
      Some(bb_entry) => bb_entry.execution_count_normalized,
      None => factor,
    }
  }

  fn genericize(&mut self) {
    // 目前只有Arg和Get需要genericize
    if let RdgEggOp::Arg(arg) = &mut self.op {
      arg.genericize();
    } else {
      // 其他操作符不需要genericize
      return;
    }
  }
}

impl BBInfo for RdgEgg {
  fn get_mut_bbs_info(&mut self) -> &mut Vec<String> {
    self.info.bbs.as_mut()
  }
}
