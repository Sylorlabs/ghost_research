use ruler::{
    enumo::{Filter, Metric, Ruleset, Workload},
    recipe_utils::{base_lang, iter_metric, run_workload},
    Limits,
};
use serde::Serialize;

#[path = "../../upstream_tests/bool.rs"]
mod upstream_bool;
use upstream_bool::Bool;

#[derive(Serialize)]
struct Output {
    workload_counts: Vec<usize>,
    stage_rule_counts: Vec<usize>,
    total_rules: usize,
    learned_rules: Vec<String>,
}

fn transformed_bool(n: usize) -> Workload {
    iter_metric(base_lang(2), "EXPR", Metric::Atoms, n)
        .filter(Filter::Contains("VAR".parse().unwrap()))
        .plug("VAL", &Workload::new(["false", "true"]))
        .plug("VAR", &Workload::new(["z", "x", "y"]))
        .plug("OP1", &Workload::new(["~"]))
        .plug("OP2", &Workload::new(["->", "^", "|", "&"]))
}

fn main() {
    let mut all_rules: Ruleset<Bool> = Ruleset::default();
    let mut workload_counts = Vec::new();
    let mut stage_rule_counts = Vec::new();
    for n in [3, 4, 5] {
        let workload = transformed_bool(n);
        workload_counts.push(workload.force().len());
        let stage = run_workload(
            workload,
            all_rules.clone(),
            Limits::synthesis(),
            Limits::minimize(),
            false,
        );
        stage_rule_counts.push(stage.len());
        all_rules.extend(stage);
    }
    let mut learned_rules = all_rules.to_str_vec();
    learned_rules.sort();
    let output = Output {
        workload_counts,
        stage_rule_counts,
        total_rules: all_rules.len(),
        learned_rules,
    };
    println!("{}", serde_json::to_string(&output).unwrap());
}
