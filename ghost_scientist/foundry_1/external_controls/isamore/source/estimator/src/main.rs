//! Example usage of the XLS estimators.

use env_logger::Env;
use estimator::{
  area_estimator::AreaEstimator,
  delay_estimator::{DelayEstimator, EstimableNode},
  model_loader::ModelLoader,
};
use std::{fmt::Display, path::Path};

// A simple node implementation for testing
#[derive(Debug)]
struct SimpleNode {
  op_type: String,
  width: i64,
  operands: Vec<SimpleNode>,
  is_lit: bool,
}

impl Display for SimpleNode {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    write!(f, "{}", self.op_type)
  }
}

impl SimpleNode {
  fn new(op: &str, width: i64) -> Self {
    SimpleNode {
      op_type: op.to_string(),
      width,
      operands: vec![],
      is_lit: false,
    }
  }

  fn with_operands(mut self, operands: Vec<SimpleNode>) -> Self {
    self.operands = operands;
    self
  }

  fn as_literal(mut self) -> Self {
    self.is_lit = true;
    self
  }
}

impl EstimableNode for SimpleNode {
  fn op(&self) -> &str {
    &self.op_type
  }

  fn bit_count(&self) -> i64 {
    self.width
  }

  fn operands(&self) -> Vec<&dyn EstimableNode> {
    self
      .operands
      .iter()
      .map(|op| op as &dyn EstimableNode)
      .collect()
  }

  fn is_literal(&self) -> bool {
    self.is_lit
  }

  fn operands_identical(&self) -> bool {
    if self.operands.len() < 2 {
      return false;
    }

    let first = &self.operands[0];
    self
      .operands
      .iter()
      .skip(1)
      .all(|op| op.op() == first.op() && op.bit_count() == first.bit_count())
  }
}

fn main() {
  env_logger::init_from_env(Env::new().filter_or("RUST_LOG", "info"));
  println!("XLS Estimator Example");

  // Load the models
  let delay_model_path = Path::new("models/delay_asap7.bin");
  let area_model_path = Path::new("models/area_asap7.bin");
  let delay_model = ModelLoader::load_model(&delay_model_path).unwrap();
  let area_model = ModelLoader::load_model(&area_model_path).unwrap();

  // Create the estimators
  let delay_estimator = DelayEstimator::new("asap7-delay", delay_model);
  let area_estimator = AreaEstimator::new("asap7-area", area_model);

  // Create some test nodes
  let param_a = SimpleNode::new("kParam", 32);
  let param_b = SimpleNode::new("kParam", 32);
  let add_node =
    SimpleNode::new("FPExt", 32).with_operands(vec![param_a, param_b]);

  println!("\nCreated test nodes:");
  println!("  add_node: {} ({})", add_node.op(), add_node.bit_count());

  // Estimate the delay and area of the add node
  let delay = delay_estimator
    .get_operation_delay_in_ps(&add_node)
    .unwrap();
  let area = area_estimator
    .get_operation_area_in_square_microns(&add_node)
    .unwrap();

  println!("\nEstimated delay and area:");
  println!("  delay: {} ps", delay);
  println!("  area: {} square microns", area);
}
