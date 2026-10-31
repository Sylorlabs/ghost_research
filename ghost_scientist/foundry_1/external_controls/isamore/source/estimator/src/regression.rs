use argmin::core::{CostFunction, Error, Executor, Gradient};
use argmin::solver::gradientdescent::SteepestDescent;
use argmin::solver::linesearch::MoreThuenteLineSearch;

#[derive(Clone)]
pub struct EstimatorFitProblem {
  x: Vec<Vec<f64>>,
  y: Vec<f64>,
}

impl CostFunction for EstimatorFitProblem {
  type Param = Vec<f64>;
  type Output = f64;

  fn cost(&self, p: &Self::Param) -> Result<Self::Output, Error> {
    assert_eq!(self.x.len() * 2 + 1, p.len());
    let mut sum = 0.0;
    for i in 0..self.y.len() {
      let mut residual = p[0];
      for j in 0..self.x.len() {
        residual +=
          p[2 * j + 1] * self.x[j][i] + p[2 * j + 2] * self.x[j][i].ln();
      }
      residual -= self.y[i];
      sum += residual * residual;
    }
    Ok(sum)
  }
}

impl Gradient for EstimatorFitProblem {
  /// Type of the parameter vector
  type Param = Vec<f64>;
  /// Type of the gradient
  type Gradient = Vec<f64>;

  /// Compute the gradient at parameter `p`.
  fn gradient(&self, p: &Self::Param) -> Result<Self::Gradient, Error> {
    let mut grad = vec![0.0; p.len()];
    for i in 0..self.y.len() {
      let mut residual = p[0];
      for j in 0..self.x.len() {
        residual +=
          p[2 * j + 1] * self.x[j][i] + p[2 * j + 2] * self.x[j][i].ln();
      }
      residual -= self.y[i];
      grad[0] += 2.0 * residual;
      for j in 0..self.x.len() {
        grad[2 * j + 1] += 2.0 * residual * self.x[j][i];
        grad[2 * j + 2] += 2.0 * residual * self.x[j][i].ln();
      }
    }
    Ok(grad)
  }
}

impl EstimatorFitProblem {
  /// Create a new `EstimatorFitProblem` instance.
  pub fn new(x: Vec<Vec<f64>>, y: Vec<f64>) -> Self {
    EstimatorFitProblem { x, y }
  }

  pub fn fit(&self, max_iters: u64) -> Vec<f64> {
    let init_param = vec![1.0; self.x.len() * 2 + 1];
    let linesearch = MoreThuenteLineSearch::new();
    let solver = SteepestDescent::new(linesearch);

    // Create an `Executor` object
    let res = Executor::new(self.clone(), solver)
      .configure(|state| {
        state
          .param(init_param)
          .max_iters(max_iters)
          .target_cost(0.0)
      })
      .run()
      .expect("Failed to run the optimization");

    res.state().best_param.clone().unwrap_or_default()
  }

  pub fn get_curve(&self, param: Vec<f64>) -> impl Fn(Vec<f64>) -> f64 {
    assert_eq!(self.x.len() * 2 + 1, param.len());
    move |x: Vec<f64>| {
      let mut result = param[0];
      for j in 0..self.x.len() {
        result += param[2 * j + 1] * x[j] + param[2 * j + 2] * x[j].ln();
      }
      result
    }
  }
}

#[test]
fn test_regression() {
  let x_data =
    vec![vec![1.0, 2.0, 3.0, 4.0, 5.0], vec![1.0, 2.0, 3.0, 4.0, 5.0]];
  let y_data = vec![2.0, 4.0, 6.0, 8.0, 10.0];

  let problem = EstimatorFitProblem::new(x_data, y_data);
  let best_param = problem.fit(1000);

  println!("Best parameters: {:?}", best_param);

  let curve = problem.get_curve(best_param);
  let x_test = vec![6.0, 7.0, 8.0];
  let y_test: Vec<f64> = x_test.iter().map(|&x| curve(vec![x, x])).collect();
  println!("Predicted values: {:?}", y_test);
}
