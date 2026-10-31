use egg::{define_language, Id, RecExpr};
use ruler::{
    enumo::{Filter, Metric, Ruleset, Workload},
    recipe_utils::{base_lang, iter_metric, run_workload},
    self_product, CVec, EGraph, Interval, Limits, Pattern, SynthAnalysis,
    SynthLanguage, Symbol, ValidationResult,
};
use serde::Serialize;
use std::{
    collections::{BTreeMap, BTreeSet},
    fmt::{Display, Formatter},
    str::FromStr,
};

#[derive(Clone, Copy, Debug, Eq, Hash, Ord, PartialEq, PartialOrd)]
struct V4([i32; 4]);

impl Display for V4 {
    fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
        write!(
            f,
            "[{},{},{},{}]",
            self.0[0], self.0[1], self.0[2], self.0[3]
        )
    }
}

impl FromStr for V4 {
    type Err = String;

    fn from_str(raw: &str) -> Result<Self, Self::Err> {
        if !raw.starts_with('[') || !raw.ends_with(']') {
            return Err("not a vector literal".into());
        }
        let values: Result<Vec<i32>, _> = raw[1..raw.len() - 1]
            .split(',')
            .map(str::parse)
            .collect();
        let values = values.map_err(|_| "invalid vector element")?;
        let array: [i32; 4] = values
            .try_into()
            .map_err(|_| "vector literal must have width four")?;
        Ok(V4(array))
    }
}

impl V4 {
    fn zip_checked(self, other: Self, op: &str) -> Option<Self> {
        let mut out = [0; 4];
        for (index, (left, right)) in self.0.into_iter().zip(other.0).enumerate() {
            out[index] = match op {
                "add" => left.checked_add(right)?,
                "mul" => left.checked_mul(right)?,
                _ => unreachable!(),
            };
        }
        Some(V4(out))
    }

    fn relu(self) -> Self {
        V4(self.0.map(|value| value.max(0)))
    }
}

define_language! {
    enum Tensor4 {
        "+" = Add([Id; 2]),
        "*" = Mul([Id; 2]),
        "relu" = Relu(Id),
        Lit(V4),
        Var(Symbol),
    }
}

fn samples() -> Vec<V4> {
    vec![
        V4([-2, -1, 0, 1]),
        V4([-1, 0, 1, 2]),
        V4([0, 1, -2, 2]),
        V4([1, -1, 2, -2]),
        V4([2, 2, -1, 0]),
    ]
}

fn eval_expr(expr: &RecExpr<Tensor4>, values: &BTreeMap<Symbol, V4>) -> Option<V4> {
    let mut environment: Vec<Option<V4>> = Vec::new();
    for node in expr.as_ref() {
        let value = match node {
            Tensor4::Add([left, right]) => match (
                environment[usize::from(*left)],
                environment[usize::from(*right)],
            ) {
                (Some(left), Some(right)) => left.zip_checked(right, "add"),
                _ => None,
            },
            Tensor4::Mul([left, right]) => match (
                environment[usize::from(*left)],
                environment[usize::from(*right)],
            ) {
                (Some(left), Some(right)) => left.zip_checked(right, "mul"),
                _ => None,
            },
            Tensor4::Relu(value) => {
                environment[usize::from(*value)].map(V4::relu)
            }
            Tensor4::Lit(value) => Some(*value),
            Tensor4::Var(symbol) => values.get(symbol).copied(),
        };
        environment.push(value);
    }
    environment.last().copied().flatten()
}

fn validate_patterns(lhs: &Pattern<Tensor4>, rhs: &Pattern<Tensor4>) -> bool {
    let left = Tensor4::instantiate(lhs);
    let right = Tensor4::instantiate(rhs);
    let variables: Vec<Symbol> = left
        .as_ref()
        .iter()
        .chain(right.as_ref())
        .filter_map(|node| match node {
            Tensor4::Var(symbol) => Some(*symbol),
            _ => None,
        })
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect();
    let choices: Vec<Option<V4>> = samples().into_iter().map(Some).collect();
    let assignments = self_product(&choices, variables.len());
    let mut defined = 0usize;
    for assignment in assignments {
        let values: BTreeMap<Symbol, V4> = variables
            .iter()
            .copied()
            .zip(assignment.into_iter().map(Option::unwrap))
            .collect();
        match (eval_expr(&left, &values), eval_expr(&right, &values)) {
            (Some(a), Some(b)) if a == b => defined += 1,
            (None, None) => {}
            _ => return false,
        }
    }
    defined > 0
}

impl SynthLanguage for Tensor4 {
    type Constant = V4;

    fn eval<'a, F>(&'a self, cvec_len: usize, mut get_cvec: F) -> CVec<Self>
    where
        F: FnMut(&'a Id) -> &'a CVec<Self>,
    {
        match self {
            Tensor4::Add([left, right]) => get_cvec(left)
                .iter()
                .zip(get_cvec(right))
                .map(|(a, b)| match (a, b) {
                    (Some(a), Some(b)) => a.zip_checked(*b, "add"),
                    _ => None,
                })
                .collect(),
            Tensor4::Mul([left, right]) => get_cvec(left)
                .iter()
                .zip(get_cvec(right))
                .map(|(a, b)| match (a, b) {
                    (Some(a), Some(b)) => a.zip_checked(*b, "mul"),
                    _ => None,
                })
                .collect(),
            Tensor4::Relu(value) => get_cvec(value)
                .iter()
                .map(|value| value.map(V4::relu))
                .collect(),
            Tensor4::Lit(value) => vec![Some(*value); cvec_len],
            Tensor4::Var(_) => vec![],
        }
    }

    fn mk_interval<'a, F>(&'a self, _get_interval: F) -> Interval<Self::Constant>
    where
        F: FnMut(&'a Id) -> &'a Interval<Self::Constant>,
    {
        Interval::default()
    }

    fn initialize_vars(
        egraph: &mut EGraph<Self, SynthAnalysis>,
        variables: &[String],
    ) {
        let choices: Vec<Option<V4>> = samples().into_iter().map(Some).collect();
        let vectors = self_product(&choices, variables.len());
        egraph.analysis.cvec_len = vectors[0].len();
        for (index, variable) in variables.iter().enumerate() {
            let id = egraph.add(Tensor4::Var(Symbol::from(variable.clone())));
            egraph[id].data.cvec = vectors[index].clone();
        }
    }

    fn to_var(&self) -> Option<Symbol> {
        match self {
            Tensor4::Var(symbol) => Some(*symbol),
            _ => None,
        }
    }

    fn mk_var(symbol: Symbol) -> Self {
        Tensor4::Var(symbol)
    }

    fn is_constant(&self) -> bool {
        matches!(self, Tensor4::Lit(_))
    }

    fn mk_constant(
        value: Self::Constant,
        _egraph: &mut EGraph<Self, SynthAnalysis>,
    ) -> Self {
        Tensor4::Lit(value)
    }

    fn validate(
        lhs: &Pattern<Self>,
        rhs: &Pattern<Self>,
    ) -> ValidationResult {
        if validate_patterns(lhs, rhs) {
            ValidationResult::Valid
        } else {
            ValidationResult::Invalid
        }
    }
}

fn tensor_workload(atoms: usize) -> Workload {
    iter_metric(base_lang(2), "EXPR", Metric::Atoms, atoms)
        .filter(Filter::Contains("VAR".parse().unwrap()))
        .plug(
            "VAL",
            &Workload::new([
                "[0,0,0,0]",
                "[1,1,1,1]",
                "[-1,-1,-1,-1]",
            ]),
        )
        .plug("VAR", &Workload::new(["a", "b"]))
        .plug("OP1", &Workload::new(["relu"]))
        .plug("OP2", &Workload::new(["+", "*"]))
}

#[derive(Serialize)]
struct Output {
    experiment_name: &'static str,
    evaluator_authored_domain: bool,
    is_frozen_boolean_a7: bool,
    workload_atom_limits: Vec<usize>,
    workload_counts: Vec<usize>,
    stage_rule_counts: Vec<usize>,
    learned_rules: Vec<String>,
    all_rules_primary_valid: bool,
    primary_vector_samples: usize,
    validation_v6_accessed: bool,
}

fn main() {
    let mut rules: Ruleset<Tensor4> = Ruleset::default();
    let mut workload_counts = Vec::new();
    let mut stage_rule_counts = Vec::new();
    for atoms in [3, 4] {
        let workload = tensor_workload(atoms);
        workload_counts.push(workload.force().len());
        let stage = run_workload(
            workload,
            rules.clone(),
            Limits::synthesis(),
            Limits::minimize(),
            false,
        );
        stage_rule_counts.push(stage.len());
        rules.extend(stage);
    }
    let all_rules_primary_valid = rules.iter().all(|rule| rule.is_valid());
    let mut learned_rules = rules.to_str_vec();
    learned_rules.sort();
    println!(
        "{}",
        serde_json::to_string(&Output {
            experiment_name: "ENUMO_TENSOR_DOMAIN_FEASIBILITY",
            evaluator_authored_domain: true,
            is_frozen_boolean_a7: false,
            workload_atom_limits: vec![3, 4],
            workload_counts,
            stage_rule_counts,
            learned_rules,
            all_rules_primary_valid,
            primary_vector_samples: samples().len(),
            validation_v6_accessed: false,
        })
        .unwrap()
    );
}
