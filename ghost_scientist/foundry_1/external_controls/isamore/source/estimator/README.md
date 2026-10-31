# XLS Estimators

A Rust implementation of the XLS area and delay estimators. This crate provides functionality for estimating the delay and area of XLS operations, similar to the C++ implementation in the XLS project.

## Overview

The XLS Estimators crate provides tools for:

- Estimating the delay of operations in picoseconds
- Estimating the area of operations in square microns
- Analyzing critical paths in a graph of operations
- Loading estimator models from textproto files

## Features

- **Protobuf-based Model Loading**: Uses the prost crate to parse textproto files containing model definitions
- **Flexible Estimator Interface**: The `EstimableNode` trait allows any node type to be estimated
- **Caching**: Both delay and area estimators cache results for better performance
- **Specialization Support**: Handles specialized estimators for identical operands and literal operands
- **Critical Path Analysis**: Analyzes critical paths in a graph of nodes

## Build the Protobuf Models

```
cd proto
protoc -I . --encode xls.estimator_model.EstimatorModel estimator_model.proto < ../models/area_asap7.textproto > ../models/area_asap7.bin
protoc -I . --encode xls.estimator_model.EstimatorModel estimator_model.proto < ../models/delay_asap7.textproto > ../models/delay_asap7.bin
```

## Usage

To use the estimators, you need to implement the `EstimableNode` trait for your node type:

```rust
use estimator::delay_estimator::EstimableNode;

// Implement the EstimableNode trait for your node type

use estimator::delay_estimator::EstimableNode;
impl EstimableNode for YourNodeType {
  fn op(&self) -> &str {
    // Return the operation type (e.g., "kAdd", "kMul")
    self.get_op_name()
  }
  fn bit_count(&self) -> i64 {
    // Return the bit width of the result
    self.get_bit_width()
  }
  fn operands(&self) -> Vec<&dyn EstimableNode> {
    // Return a vector of references to the operands
    self
      .get_operands()
      .iter()
      .map(|op| op as &dyn EstimableNode)
      .collect()
  }
  fn is_literal(&self) -> bool {
    // Return true if this node is a literal
    self.is_literal_node()
  }
  fn operands_identical(&self) -> bool {
    // Return true if all operands are identical
    if self.operands().len() < 2 {
      return false;
    }
    let first = self.operands()[0];
    self
      .operands()
      .iter()
      .skip(1)
      .all(|&op| op.op() == first.op() && op.bit_count() == first.bit_count())
  }
}
```

### Loading Models

Load the model files using the `ModelLoader`:
```rust
use std::path::Path;
use estimator::model_loader::ModelLoader;
let delay_model = ModelLoader::load_model(Path::new("path/to/delay_model.textproto"))?;
let area_model = ModelLoader::load_model(Path::new("path/to/area_model.textproto"))?;
```

### Creating Estimators

Create the delay and area estimators:

```rust
use estimator::delay_estimator::DelayEstimator;
use estimator::area_estimator::AreaEstimator;

let delay_estimator = DelayEstimator::new("asap7", delay_model);
let area_estimator = AreaEstimator::new("asap7", area_model);
```


### Estimating Delay and Area

Estimate the delay and area of a node:

```rust
let delay = delay_estimator.get_operation_delay_in_ps(&your_node)?;
let area = area_estimator.get_operation_area_in_square_microns(&your_node)?;

println!("Delay: {} ps", delay);
println!("Area: {} µm²", area);
```

### Analyzing Critical Paths

Analyze the critical path in a graph of nodes:

```rust
use estimator::critical_path::CriticalPathAnalyzer;

// Create a critical path analyzer with a clock period of 1000 ps
let analyzer = CriticalPathAnalyzer::new(&delay_estimator, Some(1000));

// Analyze the critical path
// - nodes: A slice of references to EstimableNode objects
// - source_filter: A function that returns true for source nodes
// - sink_filter: A function that returns true for sink nodes
let critical_path = analyzer.analyze_critical_path(
    &nodes,
    |node| node.op() == "kParam",  // Source filter
    |node| node.op() == "kOutput"  // Sink filter
)?;

// Convert the critical path to a string
let path_string = analyzer.critical_path_to_string(&critical_path, None);
println!("Critical path:\n{}", path_string);
```

## Model Format

The estimator models are defined in textproto format according to the schema in `proto/estimator_model.proto`. The models include:

- Operation models for each XLS operation type
- Specializations for certain operation patterns
- Measured data points for calibration

## Example

Here's a complete example of using the estimators:

```rust
use estimator::{
  area_estimator::AreaEstimator,
  critical_path::CriticalPathAnalyzer,
  delay_estimator::{DelayEstimator, EstimableNode},
  model_loader::ModelLoader,
};
use std::path::Path;
// Implement EstimableNode for your node type
// ...
fn main() -> Result<(), Box<dyn std::error::Error>> {
  // Load models
  let delay_model =
    ModelLoader::load_model(Path::new("models/asap7.textproto"))?;
  let area_model =
    ModelLoader::load_model(Path::new("models/asap7.textproto"))?;
  // Create estimators
  let delay_estimator = DelayEstimator::new("asap7", delay_model);
  let area_estimator = AreaEstimator::new("asap7", area_model);
  // Estimate delay and area
  let delay = delay_estimator.get_operation_delay_in_ps(&your_node)?;
  let area = area_estimator.get_operation_area_in_square_microns(&your_node)?;
  println!("Delay: {} ps", delay);
  println!("Area: {} µm²", area);
  // Analyze critical path
  let analyzer = CriticalPathAnalyzer::new(&delay_estimator, Some(1000));
  let critical_path =
    analyzer.analyze_critical_path(&nodes, || true, || true)?;
  let path_string = analyzer.critical_path_to_string(&critical_path, None);
  println!("Critical path:\n{}", path_string);
  Ok(())
}

```


## Advanced Usage

### Register Area Estimation

In addition to estimating the area of operations, you can also estimate the area of registers:

```rust
// Estimate the area of a 32-bit register
let register_area = area_estimator.get_register_area_in_square_microns(32)?;
println!("32-bit register area: {} µm²", register_area);
```

### Custom Critical Path Analysis

You can customize the critical path analysis by providing filters for source and sink nodes:

```rust
// Only consider paths from parameters to outputs
let critical_path = analyzer.analyze_critical_path(
    &nodes,
    |node| node.op() == "kParam",  // Source filter - only parameters
    |node| node.op() == "kOutput"  // Sink filter - only outputs
)?;
```

You can also provide additional information to display for each node in the critical path:

```rust
// Display additional information for each node
let path_string = analyzer.critical_path_to_string(
    &critical_path,
    Some(|node| format!("  - Additional info: {}", node.bit_count()))
);
```

### Handling Specializations

The estimators automatically handle specializations for:

1. **Identical Operands**: When all operands of an operation are identical (e.g., squaring)
2. **Literal Operands**: When one or more operands are literals (e.g., constant shifts)

These specializations can significantly affect the estimated delay and area.

## Model Structure

The estimator models consist of:

### Operation Models

Each operation type (e.g., `kAdd`, `kMul`) has a model that defines how to estimate its delay or area. Models can be:

- **Fixed**: A constant value
- **Regression**: A curve-fitting model based on factors like bit width
- **Area Regression**: A specialized regression model for area estimation
- **Logical Effort**: A model based on logical effort calculations
- **Alias**: A reference to another operation's model

### Specializations

Operations can have specializations for specific cases:
```
op_models {
  op: "kUMul"
  estimator {
    regression {
      expressions {
        factor { source: OPERAND_BIT_COUNT }
      }
    }
  }
}
specializations {
  kind: OPERANDS_IDENTICAL
  estimator {
    regression {
      expressions {
        factor { source: OPERAND_BIT_COUNT }
        constant: -10 // Faster when squaring
      }
    }
  }
}
```


### Data Points

The models include measured data points used for calibration:

```
data_points {
  operation {
    op: "kAdd"
    bit_count: 32
    operands {
      bit_count: 32
    }
    operands {
      bit_count: 32
    }
  }
  delay: 250
  delay_offset: 94
  total_area: 120.5
  sequential_area: 0.0
}
```

## Acknowledgments

This crate is a Rust implementation of the delay and area estimators from the [XLS project](https://github.com/google/xls). The original C++ implementation and model data were created by the XLS team.
