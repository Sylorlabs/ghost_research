use ruler::{enumo::Ruleset, DeriveType, Limits};
use serde::Serialize;
use serde_json::Value;

#[path = "../../upstream_tests/bool.rs"]
mod upstream_bool;
use upstream_bool::Bool;

#[derive(Serialize)]
struct Output {
    baseline_rules: usize,
    transformed_rules: usize,
    baseline_derives_transformed: usize,
    baseline_misses_transformed: Vec<String>,
    transformed_derives_baseline: usize,
    transformed_misses_baseline: Vec<String>,
}

fn read_rules(path: &str) -> Vec<String> {
    let value: Value =
        serde_json::from_slice(&std::fs::read(path).expect("read result"))
            .expect("parse result");
    let observed = value.get("observed").unwrap_or(&value);
    observed["learned_rules"]
        .as_array()
        .expect("learned_rules array")
        .iter()
        .map(|value| value.as_str().unwrap().to_owned())
        .collect()
}

fn main() {
    let mut args = std::env::args().skip(1);
    let baseline_path = args.next().expect("baseline result");
    let transformed_path = args.next().expect("transformed result");
    let baseline_strings = read_rules(&baseline_path);
    let transformed_strings = read_rules(&transformed_path);
    let baseline: Ruleset<Bool> = Ruleset::new(&baseline_strings);
    let transformed: Ruleset<Bool> = Ruleset::new(&transformed_strings);
    let (baseline_can, baseline_cannot) = baseline.derive(
        DeriveType::LhsAndRhs,
        &transformed,
        Limits::deriving(),
    );
    let (transformed_can, transformed_cannot) = transformed.derive(
        DeriveType::LhsAndRhs,
        &baseline,
        Limits::deriving(),
    );
    let mut baseline_misses_transformed = baseline_cannot.to_str_vec();
    baseline_misses_transformed.sort();
    let mut transformed_misses_baseline = transformed_cannot.to_str_vec();
    transformed_misses_baseline.sort();
    let output = Output {
        baseline_rules: baseline.len(),
        transformed_rules: transformed.len(),
        baseline_derives_transformed: baseline_can.len(),
        baseline_misses_transformed,
        transformed_derives_baseline: transformed_can.len(),
        transformed_misses_baseline,
    };
    println!("{}", serde_json::to_string(&output).unwrap());
}
