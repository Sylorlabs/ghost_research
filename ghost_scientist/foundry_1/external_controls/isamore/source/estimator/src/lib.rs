//! Rust implementation of XLS area and delay estimators.
//!
//! This crate provides functionality for estimating the delay and area
//! of XLS operations, similar to the C++ implementation in the XLS project.

pub mod area_estimator;
pub mod delay_estimator;
pub mod estimator_model;
pub mod model_loader;
pub mod regression;

// Include the generated protobuf code
pub mod proto {
  include!(concat!(env!("OUT_DIR"), "/xls.estimator_model.rs"));
}

pub use area_estimator::*;
pub use delay_estimator::*;
pub use estimator_model::*;
pub use model_loader::*;
pub use regression::*;
