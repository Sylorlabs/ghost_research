//! Data structures for representing operation models, factors, and expressions.

use crate::proto;

/// Enum describing the metric that the estimator is estimating.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Metric {
  Unspecified,
  Delay,
  Area,
}

impl From<proto::Metric> for Metric {
  fn from(metric: proto::Metric) -> Self {
    match metric {
      proto::Metric::DelayMetric => Metric::Delay,
      proto::Metric::AreaMetric => Metric::Area,
      _ => Metric::Unspecified,
    }
  }
}

/// Enum describing a specialization of the estimator model of an operation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SpecializationKind {
  NoSpecialization,
  OperandsIdentical,
  HasLiteralOperand,
}

impl From<proto::SpecializationKind> for SpecializationKind {
  fn from(kind: proto::SpecializationKind) -> Self {
    match kind {
      proto::SpecializationKind::OperandsIdentical => {
        SpecializationKind::OperandsIdentical
      }
      proto::SpecializationKind::HasLiteralOperand => {
        SpecializationKind::HasLiteralOperand
      }
      _ => SpecializationKind::NoSpecialization,
    }
  }
}

/// Source of factors used in estimator expressions
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FactorSource {
  Invalid,
  ResultBitCount,
  OperandBitCount,
  OperandCount,
  OperandElementCount,
  OperandElementBitCount,
}

impl From<proto::estimator_factor::Source> for FactorSource {
  fn from(source: proto::estimator_factor::Source) -> Self {
    match source {
      proto::estimator_factor::Source::ResultBitCount => {
        FactorSource::ResultBitCount
      }
      proto::estimator_factor::Source::OperandBitCount => {
        FactorSource::OperandBitCount
      }
      proto::estimator_factor::Source::OperandCount => {
        FactorSource::OperandCount
      }
      proto::estimator_factor::Source::OperandElementCount => {
        FactorSource::OperandElementCount
      }
      proto::estimator_factor::Source::OperandElementBitCount => {
        FactorSource::OperandElementBitCount
      }
      _ => FactorSource::Invalid,
    }
  }
}

/// A factor used in estimator expressions
#[derive(Debug, Clone)]
pub struct EstimatorFactor {
  pub source: FactorSource,
  pub operand_number: Option<usize>,
}

impl From<&proto::EstimatorFactor> for EstimatorFactor {
  fn from(factor: &proto::EstimatorFactor) -> Self {
    EstimatorFactor {
      source: proto::estimator_factor::Source::from_i32(factor.source)
        .unwrap_or(proto::estimator_factor::Source::InvalidVariableSource)
        .into(),
      operand_number: if factor.operand_number > 0 {
        Some(factor.operand_number as usize)
      } else {
        None
      },
    }
  }
}

/// Binary operations for combining expressions
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BinaryOperation {
  Invalid,
  Add,
  Divide,
  Max,
  Min,
  Multiply,
  Power,
  Sub,
}

impl From<proto::estimator_expression::BinaryOperation> for BinaryOperation {
  fn from(op: proto::estimator_expression::BinaryOperation) -> Self {
    match op {
      proto::estimator_expression::BinaryOperation::Add => BinaryOperation::Add,
      proto::estimator_expression::BinaryOperation::Divide => {
        BinaryOperation::Divide
      }
      proto::estimator_expression::BinaryOperation::Max => BinaryOperation::Max,
      proto::estimator_expression::BinaryOperation::Min => BinaryOperation::Min,
      proto::estimator_expression::BinaryOperation::Multiply => {
        BinaryOperation::Multiply
      }
      proto::estimator_expression::BinaryOperation::Power => {
        BinaryOperation::Power
      }
      proto::estimator_expression::BinaryOperation::Sub => BinaryOperation::Sub,
      _ => BinaryOperation::Invalid,
    }
  }
}

/// A nested mathematical expression for estimator models
#[derive(Debug, Clone)]
pub enum EstimatorExpression {
  BinaryOp {
    op: BinaryOperation,
    lhs: Box<EstimatorExpression>,
    rhs: Box<EstimatorExpression>,
  },
  Factor(EstimatorFactor),
  Constant(i64),
}

impl From<&proto::EstimatorExpression> for EstimatorExpression {
  fn from(expr: &proto::EstimatorExpression) -> Self {
    match &expr.expression_type {
      Some(proto::estimator_expression::ExpressionType::BinOp(bin_op)) => {
        let lhs = if let Some(lhs_expr) = &expr.lhs_expression {
          Box::new(EstimatorExpression::from(lhs_expr.as_ref()))
        } else {
          Box::new(EstimatorExpression::Constant(0))
        };

        let rhs = if let Some(rhs_expr) = &expr.rhs_expression {
          Box::new(EstimatorExpression::from(rhs_expr.as_ref()))
        } else {
          Box::new(EstimatorExpression::Constant(0))
        };

        EstimatorExpression::BinaryOp {
          op: proto::estimator_expression::BinaryOperation::from_i32(*bin_op)
            .unwrap_or(proto::estimator_expression::BinaryOperation::Invalid)
            .into(),
          lhs,
          rhs,
        }
      }
      Some(proto::estimator_expression::ExpressionType::Factor(factor)) => {
        EstimatorExpression::Factor(EstimatorFactor::from(factor))
      }
      Some(proto::estimator_expression::ExpressionType::Constant(value)) => {
        EstimatorExpression::Constant(*value)
      }
      None => EstimatorExpression::Constant(0),
    }
  }
}

/// Details about literal operands for specializations
#[derive(Debug, Clone)]
pub struct LiteralOperandDetails {
  pub allowed_nonliteral_operands: Vec<usize>,
  pub required_literal_operands: Vec<usize>,
}

impl From<&proto::LiteralOperandDetails> for LiteralOperandDetails {
  fn from(details: &proto::LiteralOperandDetails) -> Self {
    LiteralOperandDetails {
      allowed_nonliteral_operands: details
        .allowed_nonliteral_operand
        .iter()
        .map(|&x| x as usize)
        .collect(),
      required_literal_operands: details
        .required_literal_operand
        .iter()
        .map(|&x| x as usize)
        .collect(),
    }
  }
}

/// Estimator types
#[derive(Debug, Clone)]
pub enum Estimator {
  Fixed(i64),
  AliasOp(String),
  Regression {
    expressions: Vec<EstimatorExpression>,
  },
  AreaRegression {
    expressions: Vec<EstimatorExpression>,
  },
  BoundingBox {
    factors: Vec<EstimatorFactor>,
  },
  LogicalEffort {
    tau_in_ps: i64,
  },
}

impl From<&proto::Estimator> for Estimator {
  fn from(estimator: &proto::Estimator) -> Self {
    match &estimator.estimator {
      Some(proto::estimator::Estimator::Fixed(value)) => {
        Estimator::Fixed(*value)
      }
      Some(proto::estimator::Estimator::AliasOp(op)) => {
        Estimator::AliasOp(op.clone())
      }
      Some(proto::estimator::Estimator::Regression(reg)) => {
        Estimator::Regression {
          expressions: reg
            .expressions
            .iter()
            .map(EstimatorExpression::from)
            .collect(),
        }
      }
      Some(proto::estimator::Estimator::AreaRegression(reg)) => {
        Estimator::AreaRegression {
          expressions: reg
            .expressions
            .iter()
            .map(EstimatorExpression::from)
            .collect(),
        }
      }
      Some(proto::estimator::Estimator::BoundingBox(bb)) => {
        Estimator::BoundingBox {
          factors: bb.factors.iter().map(EstimatorFactor::from).collect(),
        }
      }
      Some(proto::estimator::Estimator::LogicalEffort(le)) => {
        Estimator::LogicalEffort {
          tau_in_ps: le.tau_in_ps,
        }
      }
      None => Estimator::Fixed(0),
    }
  }
}

/// Specialization of an operation model
#[derive(Debug, Clone)]
pub struct Specialization {
  pub kind: SpecializationKind,
  pub estimator: Estimator,
  pub literal_operand_details: Option<LiteralOperandDetails>,
}

impl From<&proto::op_model::Specialization> for Specialization {
  fn from(spec: &proto::op_model::Specialization) -> Self {
    let literal_operand_details = if let Some(details) = &spec.details {
      if let Some(details_variant) = &details.specialization_details {
        match details_variant {
          proto::op_model::specialization::details::SpecializationDetails::LiteralOperandDetails(lit_details) => {
            Some(LiteralOperandDetails::from(lit_details))
          }
        }
      } else {
        None
      }
    } else {
      None
    };

    Specialization {
      kind: proto::SpecializationKind::from_i32(spec.kind)
        .unwrap_or(proto::SpecializationKind::NoSpecialization)
        .into(),
      estimator: if let Some(est) = &spec.estimator {
        Estimator::from(est)
      } else {
        Estimator::Fixed(0)
      },
      literal_operand_details,
    }
  }
}

/// Model for a single operation
#[derive(Debug, Clone)]
pub struct OpModel {
  pub op: String,
  pub estimator: Estimator,
  pub specializations: Vec<Specialization>,
}

impl From<&proto::OpModel> for OpModel {
  fn from(model: &proto::OpModel) -> Self {
    OpModel {
      op: model.op.clone(),
      estimator: if let Some(est) = &model.estimator {
        Estimator::from(est)
      } else {
        Estimator::Fixed(0)
      },
      specializations: model
        .specializations
        .iter()
        .map(Specialization::from)
        .collect(),
    }
  }
}

/// Operand description for data points
#[derive(Debug, Clone)]
pub struct Operand {
  pub bit_count: i64,
  pub element_count: Option<i64>,
}

impl From<&proto::operation::Operand> for Operand {
  fn from(operand: &proto::operation::Operand) -> Self {
    Operand {
      bit_count: operand.bit_count,
      element_count: if operand.element_count > 0 {
        Some(operand.element_count)
      } else {
        None
      },
    }
  }
}

/// Operation description for data points
#[derive(Debug, Clone)]
pub struct Operation {
  pub op: String,
  pub bit_count: i64,
  pub operands: Vec<Operand>,
  pub specialization: Option<SpecializationKind>,
  pub literal_operands: Vec<usize>,
  pub nonliteral_operands: Vec<usize>,
}

impl From<&proto::Operation> for Operation {
  fn from(operation: &proto::Operation) -> Self {
    let mut literal_operands = Vec::new();
    let mut nonliteral_operands = Vec::new();

    if let Some(details) = &operation.literal_operand_details {
      literal_operands = details
        .literal_operand
        .iter()
        .map(|&x| x as usize)
        .collect();
      nonliteral_operands = details
        .nonliteral_operand
        .iter()
        .map(|&x| x as usize)
        .collect();
    }

    Operation {
      op: operation.op.clone(),
      bit_count: operation.bit_count,
      operands: operation.operands.iter().map(Operand::from).collect(),
      specialization: if operation.specialization
        == proto::SpecializationKind::NoSpecialization as i32
      {
        None
      } else {
        Some(
          proto::SpecializationKind::from_i32(operation.specialization)
            .unwrap_or(proto::SpecializationKind::NoSpecialization)
            .into(),
        )
      },
      literal_operands,
      nonliteral_operands,
    }
  }
}

/// Measured data point
#[derive(Debug, Clone)]
pub struct DataPoint {
  pub operation: Operation,
  pub delay: i64,
  pub delay_offset: i64,
  pub total_area: f64,
  pub sequential_area: f64,
}

impl From<&proto::DataPoint> for DataPoint {
  fn from(data_point: &proto::DataPoint) -> Self {
    DataPoint {
      operation: if let Some(op) = &data_point.operation {
        Operation::from(op)
      } else {
        Operation {
          op: String::new(),
          bit_count: 0,
          operands: Vec::new(),
          specialization: None,
          literal_operands: Vec::new(),
          nonliteral_operands: Vec::new(),
        }
      },
      delay: data_point.delay,
      delay_offset: data_point.delay_offset,
      total_area: data_point.total_area,
      sequential_area: data_point.sequential_area,
    }
  }
}

/// Complete estimator model
#[derive(Debug, Clone)]
pub struct EstimatorModel {
  pub op_models: Vec<OpModel>,
  pub data_points: Vec<DataPoint>,
  pub metric: Metric,
}

impl From<&proto::EstimatorModel> for EstimatorModel {
  fn from(model: &proto::EstimatorModel) -> Self {
    EstimatorModel {
      op_models: model.op_models.iter().map(OpModel::from).collect(),
      data_points: model.data_points.iter().map(DataPoint::from).collect(),
      metric: proto::Metric::from_i32(model.metric)
        .unwrap_or(proto::Metric::UnspecifiedMetric)
        .into(),
    }
  }
}
