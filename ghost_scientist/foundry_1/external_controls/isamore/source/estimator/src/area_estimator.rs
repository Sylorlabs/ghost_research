//! Area estimator for XLS operations.

use std::collections::HashMap;
use std::hash::{DefaultHasher, Hash, Hasher};
use std::sync::{Arc, RwLock};
use thiserror::Error;

use crate::EstimatorFitProblem;
use crate::delay_estimator::EstimableNode;
use crate::estimator_model::{
  BinaryOperation, Estimator, EstimatorExpression, EstimatorModel,
  FactorSource, OpModel, SpecializationKind,
};

#[derive(Error, Debug)]
pub enum AreaEstimatorError {
  #[error("Operation not supported: {0}")]
  OperationNotSupported(String),

  #[error("Model not found: {0}")]
  ModelNotFound(String),

  #[error("Evaluation error: {0}")]
  EvaluationError(String),
}

/// Area estimator for XLS operations
#[derive(Clone)]
pub struct AreaEstimator {
  name: String,
  model: EstimatorModel,
  op_model_map: HashMap<String, OpModel>,
  cache: Arc<RwLock<HashMap<u64, f64>>>,
}

pub fn hash_node(node: &dyn EstimableNode) -> u64 {
  let mut hasher = DefaultHasher::new();
  node.op().hash(&mut hasher);
  node.bit_count().hash(&mut hasher);
  node.is_literal().hash(&mut hasher);
  node.operands_identical().hash(&mut hasher);

  for operand in node.operands() {
    let sub_hash = hash_node(operand);
    sub_hash.hash(&mut hasher);
  }

  hasher.finish()
}

impl AreaEstimator {
  pub fn new(name: &str, model: EstimatorModel) -> Self {
    let mut op_model_map = HashMap::new();
    for op_model in &model.op_models {
      op_model_map.insert(op_model.op.clone(), op_model.clone());
    }

    AreaEstimator {
      name: name.to_string(),
      model,
      op_model_map,
      cache: Arc::new(RwLock::new(HashMap::new())),
    }
  }

  pub fn name(&self) -> &str {
    &self.name
  }

  pub fn get_operation_area_in_square_microns(
    &self,
    node: &dyn EstimableNode,
  ) -> Result<f64, AreaEstimatorError> {
    // Check cache first
    let cache_key = hash_node(node);
    {
      let cache = self.cache.read().unwrap();
      if let Some(area) = cache.get(&cache_key) {
        return Ok(*area);
      }
    }

    // Find the appropriate model
    let op_model = self.op_model_map.get(node.op()).ok_or_else(|| {
      AreaEstimatorError::OperationNotSupported(node.op().to_string())
    });

    if let Err(_) = op_model {
      return Ok(0.0);
    }
    let op_model = op_model.unwrap();

    // Check for specializations
    let estimator = if node.operands_identical() {
      // Check for OPERANDS_IDENTICAL specialization
      op_model
        .specializations
        .iter()
        .find(|s| s.kind == SpecializationKind::OperandsIdentical)
        .map(|s| &s.estimator)
        .unwrap_or(&op_model.estimator)
    } else if node.is_literal() {
      // Check for HAS_LITERAL_OPERAND specialization
      op_model
        .specializations
        .iter()
        .find(|s| s.kind == SpecializationKind::HasLiteralOperand)
        .map(|s| &s.estimator)
        .unwrap_or(&op_model.estimator)
    } else {
      &op_model.estimator
    };

    // Evaluate the estimator
    let area = self.evaluate_estimator(estimator, node)?;

    // Cache the result
    {
      let mut cache = self.cache.write().unwrap();
      cache.insert(cache_key, area);
    }
    Ok(area)
  }

  pub fn get_register_area_in_square_microns(
    &self,
    register_width: u64,
  ) -> Result<f64, AreaEstimatorError> {
    let one_bit_area = self.get_one_bit_register_area_in_square_microns()?;
    Ok(one_bit_area * (register_width as f64))
  }

  fn get_one_bit_register_area_in_square_microns(
    &self,
  ) -> Result<f64, AreaEstimatorError> {
    // Find a kIdentity data point to extract sequential area
    for data_point in &self.model.data_points {
      if data_point.operation.op == "kIdentity"
        && data_point.operation.bit_count == 1
      {
        // Sequential area of kIdentity with 1-bit is the area of a 1-bit
        // register
        return Ok(data_point.sequential_area / 2.0); // Divide by 2 because kIdentity has two registers
      }
    }

    Err(AreaEstimatorError::EvaluationError(
      "Could not find kIdentity data point to determine register area"
        .to_string(),
    ))
  }

  fn evaluate_estimator(
    &self,
    estimator: &Estimator,
    node: &dyn EstimableNode,
  ) -> Result<f64, AreaEstimatorError> {
    match estimator {
      Estimator::Fixed(value) => Ok(*value as f64),

      Estimator::AliasOp(alias_op) => {
        let alias_model = self
          .op_model_map
          .get(alias_op)
          .ok_or_else(|| AreaEstimatorError::ModelNotFound(alias_op.clone()))?;
        self.evaluate_estimator(&alias_model.estimator, node)
      }

      Estimator::AreaRegression { expressions } => {
        let mut result = 0.0;
        let expr = &expressions[0];
        result += self.evaluate_expression(expr, node)? as f64;
        Ok(result)
      }

      _ => Err(AreaEstimatorError::EvaluationError(format!(
        "Unsupported estimator type for area estimation"
      ))),
    }
  }

  fn evaluate_expression(
    &self,
    expr: &EstimatorExpression,
    node: &dyn EstimableNode,
  ) -> Result<i64, AreaEstimatorError> {
    match expr {
      EstimatorExpression::Constant(value) => Ok(*value),

      EstimatorExpression::Factor(factor) => self.evaluate_factor(factor, node),

      EstimatorExpression::BinaryOp { op, lhs, rhs } => {
        let lhs_value = self.evaluate_expression(lhs, node)?;
        let rhs_value = self.evaluate_expression(rhs, node)?;

        match op {
          BinaryOperation::Add => Ok(lhs_value + rhs_value),
          BinaryOperation::Sub => Ok(lhs_value - rhs_value),
          BinaryOperation::Multiply => Ok(lhs_value * rhs_value),
          BinaryOperation::Divide => {
            if rhs_value == 0 {
              return Err(AreaEstimatorError::EvaluationError(
                "Division by zero".to_string(),
              ));
            }
            Ok(lhs_value / rhs_value)
          }
          BinaryOperation::Max => Ok(std::cmp::max(lhs_value, rhs_value)),
          BinaryOperation::Min => Ok(std::cmp::min(lhs_value, rhs_value)),
          BinaryOperation::Power => {
            if rhs_value < 0 {
              return Err(AreaEstimatorError::EvaluationError(
                "Negative exponent not supported".to_string(),
              ));
            }
            Ok(lhs_value.pow(rhs_value as u32))
          }
          _ => Err(AreaEstimatorError::EvaluationError(format!(
            "Unsupported binary operation"
          ))),
        }
      }
    }
  }

  fn evaluate_factor(
    &self,
    factor: &crate::estimator_model::EstimatorFactor,
    node: &dyn EstimableNode,
  ) -> Result<i64, AreaEstimatorError> {
    match factor.source {
      FactorSource::ResultBitCount => {
        let factors = vec![node.bit_count() as f64];
        // get the data points from the model
        let dps = self
          .model
          .data_points
          .iter()
          .filter(|dp| dp.operation.op == node.op().to_string());
        let x: Vec<f64> = dps
          .clone()
          .map(|dp| dp.operation.bit_count as f64)
          .collect();
        let y: Vec<f64> = dps.map(|dp| dp.total_area).collect();
        let problem = EstimatorFitProblem::new(vec![x], y);
        let param = problem.fit(100);
        let curve = problem.get_curve(param);
        Ok(curve(factors).round() as i64)
      }

      FactorSource::OperandBitCount => {
        let operand_number =
          factor.operand_number.unwrap_or(node.operands().len());
        let operands = node.operands();
        let bit_count =
          operands.iter().map(|op| op.bit_count()).max().unwrap_or(0);
        let factors = vec![operand_number as f64, bit_count as f64];
        // get the data points from the model
        let dps = self
          .model
          .data_points
          .iter()
          .filter(|dp| dp.operation.op == node.op().to_string());
        let x0: Vec<f64> = dps
          .clone()
          .map(|dp| dp.operation.operands.len() as f64)
          .collect();
        let x1: Vec<f64> = dps
          .clone()
          .map(|dp| dp.operation.bit_count as f64)
          .collect();
        let y: Vec<f64> = dps.map(|dp| dp.total_area).collect();
        let problem = EstimatorFitProblem::new(vec![x0, x1], y);
        let param = problem.fit(100);
        let curve = problem.get_curve(param);
        Ok(curve(factors).round() as i64)
      }

      FactorSource::OperandCount => {
        let factors = vec![node.operands().len() as f64];
        // get the data points from the model
        let dps = self
          .model
          .data_points
          .iter()
          .filter(|dp| dp.operation.op == node.op().to_string());
        let x: Vec<f64> = dps
          .clone()
          .map(|dp| dp.operation.operands.len() as f64)
          .collect();
        let y: Vec<f64> = dps.map(|dp| dp.total_area).collect();
        let problem = EstimatorFitProblem::new(vec![x], y);
        let param = problem.fit(100);
        let curve = problem.get_curve(param);
        Ok(curve(factors).round() as i64)
      }

      _ => Err(AreaEstimatorError::EvaluationError(format!(
        "Unsupported factor source: {:?}",
        factor.source
      ))),
    }
  }
}
