//! Delay estimator for XLS operations.

use log::warn;
use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use thiserror::Error;

use crate::estimator_model::{
  BinaryOperation, Estimator, EstimatorExpression, EstimatorModel,
  FactorSource, OpModel, SpecializationKind,
};
use crate::hash_node;
use crate::regression::EstimatorFitProblem;

#[derive(Error, Debug)]
pub enum DelayEstimatorError {
  #[error("Operation not supported: {0}")]
  OperationNotSupported(String),

  #[error("Model not found: {0}")]
  ModelNotFound(String),

  #[error("Evaluation error: {0}")]
  EvaluationError(String),
}

/// Trait for nodes that can be estimated
pub trait EstimableNode {
  fn op(&self) -> &str;
  fn bit_count(&self) -> i64;
  fn operands(&self) -> Vec<&dyn EstimableNode>;
  fn is_literal(&self) -> bool;
  fn operands_identical(&self) -> bool;
}

/// Delay estimator for XLS operations
#[derive(Clone)]
pub struct DelayEstimator {
  name: String,
  model: EstimatorModel,
  pub op_model_map: HashMap<String, OpModel>,
  cache: Arc<RwLock<HashMap<u64, i64>>>,
}

impl DelayEstimator {
  pub fn new(name: &str, model: EstimatorModel) -> Self {
    let mut op_model_map = HashMap::new();
    for op_model in &model.op_models {
      op_model_map.insert(op_model.op.clone(), op_model.clone());
    }

    DelayEstimator {
      name: name.to_string(),
      model: model,
      op_model_map,
      cache: Arc::new(RwLock::new(HashMap::new())),
    }
  }

  pub fn name(&self) -> &str {
    &self.name
  }

  pub fn get_operation_delay_in_ps(
    &self,
    node: &dyn EstimableNode,
  ) -> Result<i64, DelayEstimatorError> {
    // Check cache first
    // println!("Checking cache for delay estimation");
    let cache_key = hash_node(node);

    {
      let cache = self.cache.read().unwrap();
      if let Some(delay) = cache.get(&cache_key) {
        return Ok(*delay);
      }
    }

    // Find the appropriate model
    // println!("Finding appropriate model for delay estimation");
    let op_model = self.op_model_map.get(node.op()).ok_or_else(|| {
      warn!("supported operations: {:?}", self.op_model_map.keys());
      DelayEstimatorError::OperationNotSupported(node.op().to_string())
    });

    if let Err(_) = op_model {
      return Ok(0);
    }
    let op_model = op_model.unwrap();

    // Check for specializations
    // println!("Checking for specializations");
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
    // println!("Evaluating the estimator");
    let delay = self.evaluate_estimator(estimator, node)?;

    // Cache the result
    // println!("Caching the result");
    {
      let mut cache = self.cache.write().unwrap();
      cache.insert(cache_key, delay);
    }

    Ok(delay)
  }

  fn evaluate_estimator(
    &self,
    estimator: &Estimator,
    node: &dyn EstimableNode,
  ) -> Result<i64, DelayEstimatorError> {
    match estimator {
      Estimator::Fixed(value) => Ok(*value),

      Estimator::AliasOp(alias_op) => {
        let alias_model = self.op_model_map.get(alias_op).ok_or_else(|| {
          DelayEstimatorError::ModelNotFound(alias_op.clone())
        })?;
        self.evaluate_estimator(&alias_model.estimator, node)
      }

      Estimator::Regression { expressions } => {
        let mut result = 0;
        let expr = &expressions[0];
        result += self.evaluate_expression(expr, node)?;
        Ok(result)
      }

      Estimator::LogicalEffort { tau_in_ps } => {
        self.get_logical_effort_delay(node, *tau_in_ps)
      }

      _ => Err(DelayEstimatorError::EvaluationError(format!(
        "Unsupported estimator type for delay estimation"
      ))),
    }
  }

  fn evaluate_expression(
    &self,
    expr: &EstimatorExpression,
    node: &dyn EstimableNode,
  ) -> Result<i64, DelayEstimatorError> {
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
              return Err(DelayEstimatorError::EvaluationError(
                "Division by zero".to_string(),
              ));
            }
            Ok(lhs_value / rhs_value)
          }
          BinaryOperation::Max => Ok(std::cmp::max(lhs_value, rhs_value)),
          BinaryOperation::Min => Ok(std::cmp::min(lhs_value, rhs_value)),
          BinaryOperation::Power => {
            if rhs_value < 0 {
              return Err(DelayEstimatorError::EvaluationError(
                "Negative exponent not supported".to_string(),
              ));
            }
            Ok(lhs_value.pow(rhs_value as u32))
          }
          _ => Err(DelayEstimatorError::EvaluationError(format!(
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
  ) -> Result<i64, DelayEstimatorError> {
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
        let y: Vec<f64> =
          dps.map(|dp| (dp.delay - dp.delay_offset) as f64).collect();
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
        let y: Vec<f64> =
          dps.map(|dp| (dp.delay - dp.delay_offset) as f64).collect();
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
        let y: Vec<f64> =
          dps.map(|dp| (dp.delay - dp.delay_offset) as f64).collect();
        let problem = EstimatorFitProblem::new(vec![x], y);
        let param = problem.fit(100);
        let curve = problem.get_curve(param);
        Ok(curve(factors).round() as i64)
      }

      _ => Err(DelayEstimatorError::EvaluationError(format!(
        "Unsupported factor source: {:?}",
        factor.source
      ))),
    }
  }

  fn get_logical_effort_delay(
    &self,
    node: &dyn EstimableNode,
    tau_in_ps: i64,
  ) -> Result<i64, DelayEstimatorError> {
    // This is a simplified implementation - you would need to expand this
    // based on the C++ implementation for different operations
    match node.op() {
      "kAnd" | "kNand" | "kOr" | "kNor" | "kXor" => {
        // Simple logical effort calculation for basic gates
        let operand_count = node.operands().len() as i64;
        let base_effort = if operand_count <= 1 { 1 } else { operand_count };
        Ok(base_effort * tau_in_ps)
      }

      "kAndReduce" | "kOrReduce" | "kXorReduce" => {
        // For reductions, effort is proportional to bit count
        let bit_count = if let Some(op) = node.operands().get(0) {
          op.bit_count()
        } else {
          return Err(DelayEstimatorError::EvaluationError(
            "Reduction operation has no operands".to_string(),
          ));
        };

        let base_effort = if bit_count < 2 { 0 } else { bit_count };
        Ok(base_effort * tau_in_ps)
      }

      _ => Err(DelayEstimatorError::EvaluationError(format!(
        "Logical effort not implemented for operation: {}",
        node.op()
      ))),
    }
  }
}
