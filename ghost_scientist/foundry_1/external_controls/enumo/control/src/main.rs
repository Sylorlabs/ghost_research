use ruler::{
    enumo::{Filter, Metric, Ruleset, Workload},
    recipe_utils::{base_lang, iter_metric, run_workload},
    DeriveType, Limits,
};
use serde::Serialize;

#[path = "../../upstream_tests/bool.rs"]
mod upstream_bool;
use upstream_bool::Bool;

const EXPECTED: &[&str] = &[
    "(^ ?b ?a) ==> (^ ?a ?b)",
    "(& ?b ?a) ==> (& ?a ?b)",
    "(| ?b ?a) ==> (| ?a ?b)",
    "(& ?a ?a) <=> ?a",
    "?a <=> (~ (~ ?a))",
    "?a <=> (| ?a ?a)",
    "(-> ?a ?a) ==> true",
    "(^ ?a ?a) ==> false",
    "(| ?a false) <=> ?a",
    "?a <=> (-> true ?a)",
    "?a <=> (& ?a true)",
    "?a <=> (^ false ?a)",
    "(~ ?a) <=> (-> ?a false)",
    "(~ ?a) <=> (^ ?a true)",
    "(-> ?b (~ ?a)) <=> (~ (& ?b ?a))",
    "(~ (^ ?b ?a)) ==> (^ ?b (~ ?a))",
    "(-> (~ ?b) ?a) ==> (| ?a ?b)",
    "(-> ?b (~ ?a)) ==> (^ ?a (-> ?a ?b))",
    "(| ?b ?a) ==> (-> (-> ?b ?a) ?a)",
    "(-> ?b ?a) <=> (-> (| ?a ?b) ?a)",
    "(| ?b ?a) <=> (| ?a (^ ?b ?a))",
    "(& ?b ?a) ==> (& ?b (-> ?b ?a))",
    "(| ?b (& ?b ?a)) ==> ?b",
    "(& ?a (| ?b ?a)) ==> ?a",
    "(& ?a (-> ?b ?a)) ==> ?a",
    "(-> (-> ?a ?b) ?a) ==> ?a",
    "(-> ?c (-> ?b ?a)) <=> (-> (& ?c ?b) ?a)",
    "(| ?c (| ?b ?a)) ==> (| ?a (| ?b ?c))",
    "(-> ?c (-> ?b ?a)) ==> (-> ?b (-> ?c ?a))",
    "(^ ?c (^ ?b ?a)) ==> (^ ?a (^ ?c ?b))",
];

#[derive(Serialize)]
struct Output {
    workload_counts: Vec<usize>,
    stage_rule_counts: Vec<usize>,
    total_rules: usize,
    expected_rules: usize,
    derivable_expected: usize,
    nonderivable_expected: usize,
    learned_rules: Vec<String>,
}

fn iter_bool(n: usize) -> Workload {
    iter_metric(base_lang(2), "EXPR", Metric::Atoms, n)
        .filter(Filter::Contains("VAR".parse().unwrap()))
        .plug("VAL", &Workload::new(["true", "false"]))
        .plug("VAR", &Workload::new(["a", "b", "c"]))
        .plug("OP1", &Workload::new(["~"]))
        .plug("OP2", &Workload::new(["&", "|", "^", "->"]))
}

fn main() {
    let mut all_rules: Ruleset<Bool> = Ruleset::default();
    let mut workload_counts = Vec::new();
    let mut stage_rule_counts = Vec::new();
    for n in [3, 4, 5] {
        let workload = iter_bool(n);
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
    let expected: Ruleset<Bool> = Ruleset::new(EXPECTED);
    let (can, cannot) = all_rules.derive(
        DeriveType::LhsAndRhs,
        &expected,
        Limits::deriving(),
    );
    let mut learned_rules = all_rules.to_str_vec();
    learned_rules.sort();
    let output = Output {
        workload_counts,
        stage_rule_counts,
        total_rules: all_rules.len(),
        expected_rules: expected.len(),
        derivable_expected: can.len(),
        nonderivable_expected: cannot.len(),
        learned_rules,
    };
    println!("{}", serde_json::to_string(&output).unwrap());
}
