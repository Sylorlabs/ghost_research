use super::*;

/// Utility struct for building RDG
/// similar to eggcc::rvsdg:tests:RvsdgTest
#[derive(Debug, Default)]
pub struct RdgBuilder {
  functions: Vec<RdgFunction>,
  nodes: Vec<RdgBody>,
}

impl RdgBuilder {
  /// into a RdgProgram
  pub fn into_program(self) -> RdgProgram {
    assert!(self.nodes.is_empty(), "dangling nodes");
    RdgProgram {
      functions: self.functions,
    }
  }

  /// convert `nodes` into a new function at the end of `functions`
  pub fn push_function(
    &mut self,
    name: &str,
    results: Vec<Option<Operand>>,
    bb_info: BBInfo,
  ) {
    let nodes = self.nodes.drain(..).collect();
    self.functions.push(RdgFunction {
      name: name.to_string(),
      nodes,
      results,
      bb_info,
    });
  }

  /// Call a function with given arguments and number of return values.
  pub fn call(
    &mut self,
    func_name: String,
    args: Vec<Operand>,
    num_outputs: usize,
    result_tys: Vec<RdgType>,
  ) -> NodeOutput {
    // Use Dummy for function calls instead of Call
    let dummy_expr =
      BasicExpr::Dummy(format!("call-{}", func_name), args, num_outputs);

    // Add this dummy expression to the node list and return the resulting
    // NodeOutput.
    self.node(RdgBody::BasicOp {
      expr: dummy_expr,
      output_tys: result_tys,
    })
  }

  pub fn lit_int(&mut self, i: i64, ty: Option<RdgType>) -> Operand {
    self
      .node(RdgBody::BasicOp {
        expr: BasicExpr::Const(Literal::Int(i), ty.clone().unwrap()),
        output_tys: vec![ty.clone().unwrap()],
      })
      .get(0, ty.unwrap())
  }

  pub fn lit_bool(&mut self, b: bool) -> Operand {
    self
      .node(RdgBody::BasicOp {
        expr: BasicExpr::Const(Literal::Bool(b), RdgType::Bool),
        output_tys: vec![RdgType::Bool],
      })
      .get(0, RdgType::Bool)
  }

  pub fn lt(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Lt, &[l, r], Some(RdgType::Bool))
  }

  pub fn abs(&mut self, op: Operand, ty: Option<RdgType>) -> Operand {
    self.prim_op_one_output(PrimOp::Abs, &[op], ty)
  }

  pub fn add(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Add, &[l, r], ty)
  }

  pub fn ptradd(
    &mut self,
    base: Operand,
    offset: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::PtrAdd, &[base, offset], ty)
  }

  pub fn mul(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Mul, &[l, r], ty)
  }

  pub fn ge(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Ge, &[l, r], Some(RdgType::Bool))
  }

  pub fn sub(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Sub, &[l, r], ty)
  }

  pub fn div(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Div, &[l, r], ty)
  }

  pub fn eq(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Eq, &[l, r], Some(RdgType::Bool))
  }

  pub fn gt(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Gt, &[l, r], Some(RdgType::Bool))
  }

  pub fn le(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Le, &[l, r], Some(RdgType::Bool))
  }

  pub fn not(&mut self, op: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Not, &[op], Some(RdgType::Bool))
  }

  pub fn and(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::And, &[l, r], ty)
  }

  pub fn or(&mut self, l: Operand, r: Operand, ty: Option<RdgType>) -> Operand {
    self.prim_op_one_output(PrimOp::Or, &[l, r], ty)
  }

  pub fn select(
    &mut self,
    cond: Operand,
    true_val: Operand,
    false_val: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Select, &[cond, true_val, false_val], ty)
  }

  pub fn smax(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Smax, &[l, r], ty)
  }

  pub fn smin(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Smin, &[l, r], ty)
  }

  pub fn shl(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Shl, &[l, r], ty)
  }

  pub fn shr(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Shr, &[l, r], ty)
  }

  pub fn fadd(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fadd, &[l, r], ty)
  }

  pub fn fsub(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fsub, &[l, r], ty)
  }

  pub fn fmul(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fmul, &[l, r], ty)
  }

  pub fn fdiv(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fdiv, &[l, r], ty)
  }

  pub fn feq(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Feq, &[l, r], Some(RdgType::Bool))
  }

  pub fn flt(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Flt, &[l, r], Some(RdgType::Bool))
  }

  pub fn fgt(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Fgt, &[l, r], Some(RdgType::Bool))
  }

  pub fn fle(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Fle, &[l, r], Some(RdgType::Bool))
  }

  pub fn fge(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::Fge, &[l, r], Some(RdgType::Bool))
  }

  pub fn fmax(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fmax, &[l, r], ty)
  }

  pub fn fmin(
    &mut self,
    l: Operand,
    r: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::Fmin, &[l, r], ty)
  }

  pub fn store(
    &mut self,
    ptr: Operand,
    val: Operand,
    state: Operand,
  ) -> Operand {
    self.prim_op_one_output(
      PrimOp::Store,
      &[ptr, val, state],
      Some(RdgType::State),
    )
  }

  pub fn statemerge(&mut self, l: Operand, r: Operand) -> Operand {
    self.prim_op_one_output(PrimOp::StateMerge, &[l, r], Some(RdgType::State))
  }

  pub fn prim_op_one_output(
    &mut self,
    op: PrimOp,
    args: &[Operand],
    ty: Option<RdgType>,
  ) -> Operand {
    self
      .node(RdgBody::BasicOp {
        expr: BasicExpr::Op(op, args.to_vec()),
        output_tys: vec![ty.clone().unwrap()],
      })
      .get(0, ty.unwrap())
  }

  pub fn load(
    &mut self,
    ptr: Operand,
    state: Operand,
    ty: Option<RdgType>,
  ) -> NodeOutput {
    self.node(RdgBody::BasicOp {
      expr: BasicExpr::Op(PrimOp::Load, vec![ptr, state]),
      output_tys: vec![ty.clone().unwrap(), RdgType::State],
    })
  }

  pub fn alloc(&mut self, size: Operand, _ty: RdgType) -> NodeOutput {
    // Use Dummy for alloc operations
    let dummy_expr = BasicExpr::Dummy("alloc".to_string(), vec![size], 2);
    self.node(RdgBody::BasicOp {
      expr: dummy_expr,
      output_tys: vec![RdgType::Pointer, RdgType::State],
    })
  }

  pub fn iobarrier(
    &mut self,
    operand1: Operand,
    operand2: Operand,
    ty: Option<RdgType>,
  ) -> Operand {
    self.prim_op_one_output(PrimOp::IOBarrier, &[operand1, operand2], ty)
  }

  pub fn gamma(
    &mut self,
    pred: Operand,
    inputs: &[Operand],
    outputs: &[&[Operand]],
    bb_infos: Vec<BBInfo>,
    output_tys: Vec<RdgType>,
  ) -> NodeOutput {
    assert!(inputs.len() == outputs.len());
    assert!(inputs.len() == bb_infos.len());

    self.node(RdgBody::Gamma {
      pred,
      inputs: inputs.to_vec(),
      outputs: outputs.iter().map(|outs| outs.to_vec()).collect(),
      bb_infos,
      output_tys,
    })
  }

  pub fn theta(
    &mut self,
    pred: Operand,
    inputs: &[Operand],
    outputs: &[Operand],
    bb_info: BBInfo,
    output_tys: Vec<RdgType>,
  ) -> NodeOutput {
    assert!(inputs.len() == outputs.len());
    self.node(RdgBody::Theta {
      pred,
      inputs: inputs.to_vec(),
      outputs: outputs.to_vec(),
      bb_info,
      output_tys,
    })
  }

  pub fn node(&mut self, body: RdgBody) -> NodeOutput {
    let id = self.nodes.len();
    self.nodes.push(body);
    id.into()
  }

  pub fn arg(&mut self, index: usize, ty: RdgType) -> Operand {
    Operand::Arg { index, ty }
  }
}

#[derive(Debug, Clone, Copy)]
pub struct NodeOutput {
  id: Id,
}

impl NodeOutput {
  pub fn get(&self, k: usize, ty: RdgType) -> Operand {
    Operand::Project {
      index: k,
      node_id: self.id,
      ty,
    }
  }
}

impl From<Id> for NodeOutput {
  fn from(value: Id) -> Self {
    NodeOutput { id: value }
  }
}
