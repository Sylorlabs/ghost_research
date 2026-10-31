//! Module for loading estimator models from textproto files.

use prost::Message;
use std::fs::File;
use std::io::{BufReader, Read};
use std::path::Path;
use thiserror::Error;

use crate::estimator_model::EstimatorModel;
use crate::proto;

#[derive(Error, Debug)]
pub enum ModelLoaderError {
  #[error("IO error: {0}")]
  IoError(#[from] std::io::Error),

  #[error("Protobuf decode error: {0}")]
  DecodeError(#[from] prost::DecodeError),

  #[error("Model not found: {0}")]
  ModelNotFound(String),

  #[error("Parse error: {0}")]
  ParseError(String),
}

pub struct ModelLoader;

impl ModelLoader {
  /// Load an estimator model from a textproto file
  pub fn load_model(path: &Path) -> Result<EstimatorModel, ModelLoaderError> {
    // Read the file
    let file = File::open(path)?;
    let mut reader = BufReader::new(file);

    // Read the file into a Vec<u8>
    let mut buffer = Vec::new();
    reader.read_to_end(&mut buffer)?;

    // Parse from protobuf binary format
    let model = proto::EstimatorModel::decode(&buffer[..])?;

    // Convert to our model
    Ok(EstimatorModel::from(&model))
  }
}
