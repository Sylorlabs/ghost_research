//! Convert RDG to the egg encoding

use babble::bb_query::BBQuery;
use egg::RecExpr;
use enumo::HashSet;
use graphviz_rust::attributes::bb;
use indexmap::IndexMap;
use std::{default::Default, hash::Hash};

use super::*;
use crate::egg_lang::{
  EggType, RcRdgEggExpr, RdgEggInfo, RdgEggLang,
  ast::{self as east},
};

impl RdgProgram {
  pub fn to_rc_expr(&self) -> RcRdgEggExpr {
    let x = east::tuple(
      self.functions.iter().map(|f| f.to_rc_expr()),
      Default::default(),
    );
    log::debug!("finish convert the program");
    x
  }

  pub fn to_egg(&self) -> RecExpr<RdgEggLang> {
    RdgEggLang::build_recexpr_from_rc_expr(self.to_rc_expr())
  }

  pub fn delete_main_function(&mut self) {
    log::debug!("delete main function");
    // 删除所有以main开头的函数
    self.functions.retain(|f| !f.name.starts_with("main"));
    log::debug!("finish delete main function");
  }
  pub fn delete_functions_according_to_bbs_info(
    &mut self,
    bb_query: &BBQuery,
    chosen_funcs: &std::collections::BTreeSet<String>,
  ) {
    log::debug!("delete functions according to bbs info");
    // 把functions的name 和bb打印
    let mut new_functions = Vec::new();
    for f in self.functions.clone() {
      if !f.bb_info.is_empty() {
        let bb = f.bb_info.first().unwrap();
        // 如果bb以main开头，说明是main函数，不用加速，直接删掉
        if bb.starts_with("main") {
          log::debug!("function {} is main, delete it", f.name);
          continue;
        }
      }
      if f.name.starts_with("main") {
        log::debug!("function {} is main, delete it", f.name);
        continue;
      }
      // 如果函数名不在chosen_funcs中，直接删掉
      // if !chosen_funcs.contains(&f.name) {
      //   log::debug!("function {} is not in chosen_funcs, delete it", f.name);
      //   continue;
      // }
      let func_name = f.name.clone();
      let mut bb_func: Vec<String> = f
        .bb_info
        .iter()
        .map(|bb| bb.split('#').next().unwrap_or(bb).to_string())
        .collect();
      bb_func.push(func_name);
      // 如果bb_func中没有一个元素在chosen_funcs中，说明这个函数没有用到
      if !bb_func.iter().any(|func| chosen_funcs.contains(func)) {
        log::debug!("function {} has no bb in chosen_funcs, delete it", f.name);
        continue;
      }
      // if new_f.nodes.is_empty() {
      //   log::debug!("function {} has no body, delete it", f.name);
      //   continue;
      // }
      new_functions.push(f);
    }
    log::debug!("finish delete functions according to bbs info");
    self.functions = new_functions;
  }
}

impl RdgFunction {
  pub fn to_rc_expr(&self) -> RcRdgEggExpr {
    let mut translator = EggTranslator {
      stored_node: IndexMap::new(),
      nodes: &self.nodes,
      bb_info: vec![self.bb_info.clone()],
      // next_alloc_id: 0,
    };
    // let translated_results = self
    //   .results
    //   .iter()
    //   .map(|r| translator.translate_operand(r.clone()).as_single())
    //   .collect::<Vec<_>>();
    let translated_results = self
      .results
      .iter()
      .filter_map(|r| {
        if r.is_none() {
          None
        } else {
          Some(translator.translate_operand(r.clone().unwrap()).as_single())
        }
      })
      .collect::<Vec<_>>();
    let x = east::function(
      self.name.as_str(),
      east::tuple(translated_results.into_iter(), self.bb_info.clone().into()),
      self.bb_info.clone().into(),
    );
    log::debug!("finish translate function {}", self.name);
    x
  }

  // pub fn delete_body_according_to_bbs_info(
  //   &mut self,
  //   bb_query: &BBQuery,
  //   chosen_funcs: &std::collections::HashSet<String>,
  // ) {
  //   // delete those node that donnot have bb info in bb_query
  //   let exist_this_bb = |bbs: &Vec<Vec<String>>| {
  //     if bbs.is_empty() {
  //       return false;
  //     }
  //     let bb_info = bbs.first().unwrap();
  //     if bb_info.is_empty() {
  //       return false;
  //     }
  //     let bb_i = bb_info.first().unwrap();
  //     let func = bb_i.split('#').next().unwrap_or(bb_i);

  //     if !chosen_funcs.contains(func) {
  //       return false;
  //     }
  //     bb_query.get(&bb_i).is_some()
  //   };
  //   let mut bodys = self.nodes.clone();
  //   bodys.retain(|node| match node {
  //     RdgBody::BasicOp { .. } => exist_this_bb(&vec![self.bb_info.clone()]),
  //     RdgBody::Gamma { bb_infos, .. } => exist_this_bb(bb_infos),
  //     RdgBody::Theta { bb_info, .. } =>
  // exist_this_bb(&vec![bb_info.clone()]),   });
  //   self.nodes = bodys;
  // }
}

/// From eggcc::rvsdg::to_dag::DagTranslator
struct EggTranslator<'a> {
  stored_node: IndexMap<Id, StoredValue>,
  nodes: &'a [RdgBody],
  bb_info: Vec<BBInfo>,
}

impl EggTranslator<'_> {
  fn push_bb(&mut self, bb_info: BBInfo) {
    self.bb_info.push(bb_info);
  }
  fn get_bb(&self) -> &BBInfo {
    self.bb_info.last().as_ref().unwrap()
  }
  fn pop_bb(&mut self) {
    self.bb_info.pop();
  }
  fn cache_single(&mut self, expr: RcRdgEggExpr, id: Id) -> StoredValue {
    let res = StoredValue {
      is_tuple: false,
      expr: expr.clone(),
    };
    self.stored_node.insert(id, res.clone());
    if self.stored_node.len() % 10000 == 0 {
      log::debug!("store {} nodes", self.stored_node.len())
    }
    res
  }
  fn cache_tuple(&mut self, expr: RcRdgEggExpr, id: Id) -> StoredValue {
    let res = StoredValue {
      is_tuple: true,
      expr: expr.clone(),
    };
    self.stored_node.insert(id, res.clone());
    res
  }

  fn translate_subregion(
    &mut self,
    operands: impl Iterator<Item = Operand>,
    bb_info: BBInfo,
  ) -> RcRdgEggExpr {
    log::debug!("translate_region");
    self.push_bb(bb_info.clone());
    let x = east::tuple(
      operands.map(|operand| self.translate_operand(operand).as_single()),
      bb_info.into(),
    );
    log::debug!("finish translate_region");
    self.pop_bb();
    x
  }

  fn translate_operand(
    &mut self,
    operand: Operand,
    // assump: AssumpWithArgs,
  ) -> StoredValue {
    // log::warn!("translate_operand: {:?}", operand);
    match operand {
      Operand::Arg { index, ty } => StoredValue {
        is_tuple: false,
        expr: east::get(
          east::arg(RdgEggInfo::default().with_tys(vec![ty.clone().into()])),
          // east::arg(RdgEggInfo::default().with_tys(vec![ty.into()]), index),
          index,
          RdgEggInfo::default().with_tys(vec![ty.into()]),
        ),
      },
      Operand::Project { index, node_id, ty } => {
        self.translate_node(node_id).project(index, ty.into())
      }
    }
  }

  fn translate_node(&mut self, id: Id) -> StoredValue {
    let node = &self.nodes[id];

    // log::warn!("try get node {} from {} nodes", id, self.stored_node.len());
    if let Some(cached) = self.stored_node.get(&id) {
      return cached.clone();
    }
    // log::warn!("translate_node of id {}", id.to_string());

    let x = match node {
      RdgBody::BasicOp { expr, output_tys } => self.translate_basic_expr(
        expr.clone(),
        id,
        output_tys.iter().map(|ty| ty.clone().into()).collect(),
      ),
      RdgBody::Gamma {
        pred,
        inputs,
        outputs,
        output_tys,
        bb_infos,
      } => {
        let result_tys: Vec<EggType> =
          output_tys.iter().map(|ty| ty.clone().into()).collect();
        // log::warn!("translate gamma");
        let mut input_values = vec![];
        for input in inputs {
          input_values.push(self.translate_operand(input.clone()).as_single());
        }

        let mut branches = vec![];
        for (output_vec, bb_info) in outputs.iter().zip(bb_infos.iter()) {
          branches.push(self.translate_subregion(
            output_vec.clone().into_iter(),
            bb_info.clone(),
          ))
        }
        let pred = self.translate_operand(pred.clone()).as_single();
        let rdg_info: RdgEggInfo = self.get_bb().clone().into();
        self.cache_tuple(
          east::switch(
            pred,
            east::tuple(input_values.into_iter(), RdgEggInfo::default()),
            branches,
            rdg_info.with_tys(result_tys),
          ),
          id,
        )
      }
      RdgBody::Theta {
        pred,
        inputs,
        outputs,
        bb_info,
        output_tys,
      } => {
        let result_tys: Vec<EggType> =
          output_tys.iter().map(|ty| ty.clone().into()).collect();
        // log::warn!("translate theta");
        let mut input_values = vec![];
        for input in inputs {
          input_values.push(self.translate_operand(input.clone()).as_single());
        }

        let pred_body = self.translate_subregion(
          std::iter::once(pred).chain(outputs.iter()).cloned(),
          bb_info.clone(),
        );
        let rdg_info: RdgEggInfo = self.get_bb().clone().into();
        self.cache_tuple(
          east::dowhile(
            east::tuple(input_values.into_iter(), RdgEggInfo::default()),
            pred_body,
            rdg_info.with_tys(result_tys),
          ),
          id,
        )
      }
    };

    x
  }

  fn translate_basic_expr(
    &mut self,
    expr: BasicExpr<Operand>,
    id: Id,
    output_tys: Vec<EggType>,
  ) -> StoredValue {
    use super::super::egg_lang::ast::*;

    macro_rules! translate_op {
        // translate_op!(PrimOp::Add, add, [a, b]):
        // (PrimOp::Add, [a, b]) => add(a.clone(), b.clone(), self.get_bb().clone().into()),
        ($op:expr, [$($a:expr),*]) => {
         $op($($a.clone()),*, Into::<RdgEggInfo>::into(self.get_bb().clone()).with_tys(output_tys))
        };
            // 传四个参数：op, from, to, 参数数组
        ($op:expr, $from:expr, $to:expr, [$($a:expr),*]) => {
            $op($($a.clone()),*, $from, $to, Into::<RdgEggInfo>::into(self.get_bb().clone()).with_tys(output_tys))
        };
    }
    match expr {
      BasicExpr::Op(op, children) => {
        let children = children
          .iter()
          .map(|c| self.translate_operand(c.clone()).as_single())
          .collect::<Vec<_>>();
        use east::*;
        let expr = match (op.clone(), children.as_slice()) {
          (PrimOp::Add, [a, b]) => translate_op!(add, [a, b]),
          (PrimOp::Mul, [a, b]) => translate_op!(mul, [a, b]),
          (PrimOp::Sub, [a, b]) => translate_op!(sub, [a, b]),
          (PrimOp::Div, [a, b]) => translate_op!(div, [a, b]),
          (PrimOp::Mod, [a, b]) => translate_op!(modulo, [a, b]),

          (PrimOp::Smax, [a, b]) => translate_op!(max, [a, b]),
          (PrimOp::Smin, [a, b]) => translate_op!(min, [a, b]),
          (PrimOp::Shl, [a, b]) => translate_op!(shl, [a, b]),
          (PrimOp::Shr, [a, b]) => translate_op!(shr, [a, b]),

          (PrimOp::Fadd, [a, b]) => translate_op!(add, [a, b]),
          (PrimOp::Fmul, [a, b]) => translate_op!(mul, [a, b]),
          (PrimOp::Fsub, [a, b]) => translate_op!(sub, [a, b]),
          (PrimOp::Fdiv, [a, b]) => translate_op!(div, [a, b]),

          (PrimOp::Eq, [a, b]) => translate_op!(eq, [a, b]),
          (PrimOp::Gt, [a, b]) => translate_op!(greater_than, [a, b]),
          (PrimOp::Lt, [a, b]) => translate_op!(less_than, [a, b]),
          (PrimOp::Ge, [a, b]) => translate_op!(greater_eq, [a, b]),
          (PrimOp::Le, [a, b]) => translate_op!(less_eq, [a, b]),
          (PrimOp::Ne, [a, b]) => translate_op!(ne, [a, b]),

          (PrimOp::Feq, [a, b]) => translate_op!(eq, [a, b]),
          (PrimOp::Fgt, [a, b]) => translate_op!(greater_than, [a, b]),
          (PrimOp::Flt, [a, b]) => translate_op!(less_than, [a, b]),
          (PrimOp::Fge, [a, b]) => translate_op!(greater_eq, [a, b]),
          (PrimOp::Fle, [a, b]) => translate_op!(less_eq, [a, b]),
          (PrimOp::Fmax, [a, b]) => translate_op!(max, [a, b]),
          (PrimOp::Fmin, [a, b]) => translate_op!(min, [a, b]),

          (PrimOp::And, [a, b]) => translate_op!(and, [a, b]),
          (PrimOp::Or, [a, b]) => translate_op!(or, [a, b]),
          (PrimOp::Xor, [a, b]) => translate_op!(xor, [a, b]),
          (PrimOp::Not, [a]) => translate_op!(not, [a]),
          (PrimOp::Abs, [a]) => translate_op!(abs, [a]),

          (PrimOp::PtrAdd, [a, b]) => translate_op!(add, [a, b]),
          (PrimOp::Load, [a, b]) => translate_op!(load, [a, b]),
          (PrimOp::Select, [a, b, c]) => {
            translate_op!(select, [a, b, c])
          }
          (PrimOp::Store, [a, b, c]) => translate_op!(store, [a, b, c]),
          (PrimOp::StateMerge, [a, b]) => translate_op!(statemerge, [a, b]),
          (PrimOp::ZExt(from, to), [a]) => translate_op!(zext, from, to, [a]),
          (PrimOp::SExt(from, to), [a]) => {
            translate_op!(sext, from, to, [a])
          }
          (PrimOp::Trunc(from, to), [a]) => {
            translate_op!(trunc, from, to, [a])
          }
          (PrimOp::FPTrunc, [a]) => translate_op!(fptrunc, [a]),
          (PrimOp::FPExt, [a]) => translate_op!(fpext, [a]),
          (PrimOp::IOBarrier, [a, b]) => {
            translate_op!(iobarrier, [a, b])
          }
          (PrimOp::VECFPOPAdd, [a, b]) => translate_op!(vec_add, [a, b]),
          (PrimOp::VECFPOPMul, [a, b]) => translate_op!(vec_mul, [a, b]),
          (PrimOp::VECFPOPSub, [a, b]) => translate_op!(vec_sub, [a, b]),
          (PrimOp::VECFPOPDiv, [a, b]) => translate_op!(vec_div, [a, b]),
          (PrimOp::VECFNeg, [a]) => translate_op!(vec_neg, [a]),
          (PrimOp::VECConstant, operands) => {
            let vec_consts =
              operands.iter().map(|a| a.clone()).collect::<Vec<_>>();
            east::vec_const(
              vec_consts,
              Into::<RdgEggInfo>::into(self.get_bb().clone())
                .with_tys(output_tys),
            )
          }
          _ => todo!("handle {} op", op),
        };
        match op {
          PrimOp::Load => self.cache_tuple(expr, id),
          _ => self.cache_single(expr, id),
        }
      }
      BasicExpr::Dummy(name, inputs, num_outputs) => {
        let mut input_values = vec![];
        for input in inputs {
          input_values.push(self.translate_operand(input));
        }

        // Create a dummy operation with a generic name
        let expr = dummy(
          name,
          input_values
            .into_iter()
            .map(|val| val.as_single())
            .collect(),
          self.get_bb().clone().into(),
        );

        if num_outputs > 1 {
          self.cache_tuple(expr, id)
        } else {
          self.cache_single(expr, id)
        }
      }
      BasicExpr::Const(literal, ty) => {
        let lit_expr = match literal {
          Literal::Int(n) => {
            east::int(n, RdgEggInfo::default().with_tys(vec![ty.into()]))
          }
          Literal::Bool(b) => {
            if b {
              east::ttrue(RdgEggInfo::default().with_tys(vec![ty.into()]))
            } else {
              east::tfalse(RdgEggInfo::default().with_tys(vec![ty.into()]))
            }
          }
          Literal::Float(f) => east::float(
            f.into(),
            RdgEggInfo::default().with_tys(vec![ty.into()]),
          ),
        };
        self.cache_single(lit_expr, id)
      }
    }
  }
}

/// Similar to eggcc::rvsdg::to_dag::StoredValue
/// > We cache a stored value for each node in the RVSDG, representing the
/// > corresponding expression in the dag encoding.
/// > These can either be tuple typed or single typed, and we need to track this
/// > to properly translate projects.
/// Here, the stored expr should be RcRdgEggExpr, rather than RcExpr
#[derive(Clone, Debug)]
struct StoredValue {
  is_tuple: bool,
  expr: RcRdgEggExpr,
}

impl StoredValue {
  fn as_single(self) -> RcRdgEggExpr {
    assert_eq!(self.is_tuple, false);
    self.expr
  }
  fn project(&self, index: usize, ty: EggType) -> StoredValue {
    if self.is_tuple {
      StoredValue {
        is_tuple: false,
        expr: east::get(
          self.expr.clone(),
          index,
          RdgEggInfo::default().with_tys(vec![ty]),
        ),
      }
    } else {
      assert_eq!(
        index, 0,
        "Tried to access index {} of non-tuple value",
        index
      );
      self.clone()
    }
  }
}

impl Into<EggType> for RdgType {
  fn into(self) -> EggType {
    match self {
      Self::Void => panic!("Void type cannot be converted into egg"),
      Self::Int(x) => EggType::IntT(Some(x)),
      Self::Bool => EggType::IntT(Some(1)),
      Self::Float(x) => EggType::FloatT(Some(x)),
      Self::Pointer => EggType::IntT(Some(64)),
      Self::State => EggType::IntT(Some(0)),
      Self::CTL(_x) => EggType::IntT(Some(4)),
      Self::Vector(ty, size) => {
        EggType::VectorT(Box::new((*ty).into()), Some(size))
      }
    }
  }
}
