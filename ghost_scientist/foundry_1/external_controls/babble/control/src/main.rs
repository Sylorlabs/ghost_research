use babble::{
    ast_node::{AstNode, Expr, Pretty},
    co_occurrence::COBuilder,
    extract::{apply_libs, beam::PartialLibCost},
    learn::LearnedLibrary,
    sexp::Program,
};
use egg::{AstSize, CostFunction, EGraph, RecExpr, Runner};
use serde::Serialize;

#[path = "../../source/src/bin/list/lang.rs"]
mod lang;
use lang::ListOp;

#[derive(Serialize)]
struct Output {
    initial_cost: usize,
    final_cost: usize,
    candidate_patterns: usize,
    deduplicated_patterns: usize,
    chosen_libraries: usize,
    learned_bodies: Vec<String>,
    rewritten: String,
}

fn main() {
    let input = std::fs::read_to_string(
        std::env::args().nth(1).expect("fixture path"),
    )
    .expect("read fixture");
    let expressions: Vec<Expr<ListOp>> = Program::parse(&input)
        .expect("parse Babble fixture")
        .0
        .into_iter()
        .map(|sexp| sexp.try_into().expect("valid list expression"))
        .collect();
    let recexprs: Vec<RecExpr<AstNode<ListOp>>> = expressions
        .into_iter()
        .map(Into::into)
        .collect();
    let initial_cost =
        recexprs.iter().map(|expr| AstSize.cost_rec(expr)).sum::<usize>() + 1;
    let mut egraph = EGraph::new(PartialLibCost::new(400, 400, 1, false));
    let roots = recexprs
        .iter()
        .map(|expr| egraph.add_expr(expr))
        .collect::<Vec<_>>();
    egraph.rebuild();

    let saturated = Runner::<_, _, ()>::new(PartialLibCost::empty())
        .with_egraph(egraph)
        .with_iter_limit(3)
        .run(&[]);
    let aeg = saturated.egraph;
    let co_occurs = COBuilder::new(&aeg, &roots).run();
    let mut learned = LearnedLibrary::new(&aeg, false, None, co_occurs);
    let candidate_patterns = learned.size();
    learned.deduplicate(&aeg);
    let deduplicated_patterns = learned.size();
    let rewrites: Vec<_> = learned.rewrites().collect();
    let bodies: Vec<_> = learned.libs().map(|body| body.to_string()).collect();

    let selected = Runner::<_, _, ()>::new(PartialLibCost::new(400, 400, 1, false))
        .with_egraph(aeg.clone())
        .with_iter_limit(1)
        .with_node_limit(1_000_000)
        .run(rewrites.iter());
    let mut selection_graph = selected.egraph;
    let combined_root =
        selection_graph.add(AstNode::new(ListOp::List, roots.iter().copied()));
    let mut costs = selection_graph[selection_graph.find(combined_root)]
        .data
        .clone();
    costs.set.sort_unstable_by_key(|entry| entry.full_cost);
    let chosen = costs.set.first().expect("at least one extraction");
    let chosen_rewrites = chosen
        .libs
        .iter()
        .map(|lib| rewrites[lib.0 .0].clone())
        .collect::<Vec<_>>();
    let learned_bodies = chosen
        .libs
        .iter()
        .map(|lib| bodies[lib.0 .0].clone())
        .collect::<Vec<_>>();
    let lifted = apply_libs(aeg, &roots, &chosen_rewrites);
    let final_cost = AstSize.cost_rec(&lifted);
    let rewritten = Pretty(&Expr::from(lifted)).to_string();
    let output = Output {
        initial_cost,
        final_cost,
        candidate_patterns,
        deduplicated_patterns,
        chosen_libraries: chosen_rewrites.len(),
        learned_bodies,
        rewritten,
    };
    println!("{}", serde_json::to_string(&output).expect("serialize output"));
}
