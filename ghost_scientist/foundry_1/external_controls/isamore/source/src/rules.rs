use crate::egg_lang::{EggType, RdgEgg};
use babble::{AstNode, extract::beam_pareto::ISAXAnalysis, rewrites};
use egg::{Pattern, Rewrite};
use itertools::Itertools;
use std::{
  fmt::Debug,
  io::{Result, Write},
  path::PathBuf,
};
#[derive(Debug, PartialEq, Clone)]
pub struct BinOpSearcher {
  pub left_var: String,
  pub right_var: String,
  pub full_pattern: Pattern<AstNode<RdgEgg>>,
  pub vec_pattern: Pattern<AstNode<RdgEgg>>,
  pub op_pattern: Pattern<AstNode<RdgEgg>>,
  pub zero_pattern: Pattern<AstNode<RdgEgg>>,
}

pub fn build_litvec_rule(
  vec_width: usize,
) -> Vec<egg::Rewrite<AstNode<RdgEgg>, ()>> {
  let mut gets: Vec<String> = Vec::with_capacity(vec_width);
  for i in 0..vec_width {
    gets.push(format!("(get ?a ?i{})", i))
  }
  let all_gets = gets.join(" ");

  let searcher: egg::Pattern<AstNode<RdgEgg>> =
    format!("(Vec {})", all_gets).parse().unwrap();
  let applier: egg::Pattern<AstNode<RdgEgg>> =
    format!("(LitVec {})", all_gets).parse().unwrap();

  let mut res = vec![egg::rewrite!("litvec"; { searcher } => { applier })];

  // add rules of the form (Vec 0 (get ?a ?n0) ..) => (VecLit 0 (get ?a ?n0) ..)
  for lit in 0..1 {
    for w in 0..vec_width {
      let mut all_gets_search = gets.clone();
      let mut all_gets_apply = gets.clone();
      all_gets_search[w] = lit.to_string();
      all_gets_apply[w] = lit.to_string();
      let searcher: egg::Pattern<AstNode<RdgEgg>> =
        format!("(vec {})", all_gets_search.join(" "))
          .parse()
          .unwrap();
      let applier: egg::Pattern<AstNode<RdgEgg>> =
        format!("(lit_vec {})", all_gets_apply.join(" "))
          .parse()
          .unwrap();
      let name = format!("litvec-{lit}-{w}");
      res.push(egg::rewrite!(name; { searcher } => { applier }))
    }
  }

  res
}
fn generate_rewrite_rule(op: &str, count: usize, operands: usize) -> String {
  let mut lhs_parts = Vec::new();
  let mut rhs_vecs: Vec<Vec<String>> = vec![Vec::new(); operands];

  let mut var_index = 1;

  for _ in 0..count {
    let mut vars = Vec::new();
    for j in 0..operands {
      let var = format!("?a{}", var_index);
      rhs_vecs[j].push(var.clone());
      vars.push(var);
      var_index += 1;
    }
    lhs_parts.push(format!("({} {})", op, vars.join(" ")));
  }

  let lhs = format!("(vec {})", lhs_parts.join(" "));
  let rhs_vec_parts: Vec<String> = rhs_vecs
    .into_iter()
    .map(|group| format!("(vec {})", group.join(" ")))
    .collect();
  let op = match op {
    "mod" => "rem",
    _ => op,
  };
  let rhs = format!("(vec_{} {})", op, rhs_vec_parts.join(" "));

  // format!("{} ==> {}", lhs, rhs)
  format!("{} ==> {}", rhs, lhs)
}

fn write_rules() -> Result<()> {
  let mut file = std::fs::OpenOptions::new()
    .append(true) // 设置为追加模式
    .create(true) // 如果文件不存在则创建
    .open("resources/test.rules")?; // 打开文件
  for i in 2..9 {
    writeln!(file, "{}", generate_rewrite_rule("not", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("neg", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("abs", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("add", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("mul", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("sub", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("div", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("mod", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("and", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("or", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("xor", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("shl", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("shr", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("sext", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("zext", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("trunc", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("fptrunc", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("fpext", i, 1))?;
    writeln!(file, "{}", generate_rewrite_rule("load", i, 2))?;
    writeln!(file, "{}", generate_rewrite_rule("store", i, 3))?;
  }
  Ok(())
}

pub fn handwrite_rules()
-> Vec<Rewrite<AstNode<RdgEgg>, ISAXAnalysis<RdgEgg, EggType>>> {
  let vector_rules =
    rewrites::from_file(PathBuf::from("resources/vector.rules"))
      .unwrap_or_default();
  vector_rules
}

/// 生成向量元素提取规则（跳过长度为1的向量）
///
/// 格式示例: (get<VecElement[0]> (vec ?x1 ?x2)) ==> ?x1
pub fn generate_vec_element_rules(
  max_index: usize,
  min_vec_len: usize,
  max_vec_len: usize,
) -> Vec<String> {
  let mut rules = Vec::new();

  for index in 0..max_index {
    for vec_len in min_vec_len..=max_vec_len {
      // 生成变量部分 ?x1 ?x2 ... ?xN
      let vars: Vec<String> =
        (1..=vec_len).map(|i| format!("?x{}", i)).collect();
      let vars_str = vars.join(" ");

      // 确保索引在有效范围内
      if index < vec_len {
        let left = format!("(get<VecElement[{}]> (vec {}))", index, vars_str);
        let right = format!("?x{}", index + 1);
        rules.push(format!("{} ==> {}", left, right));
      }
    }
  }

  rules
}

#[test]
fn test_list_to_concats() {
  let rules = handwrite_rules();
  println!("{:?}", rules);
}

#[test]
fn test_write_rules() {
  write_rules().unwrap();
  // let rules = generate_vec_element_rules(8, 2, 8); // 从长度2开始
  // // 将rules写入文件
  // let mut file = std::fs::OpenOptions::new()
  //   .append(true) // 设置为追加模式
  //   .create(true) // 如果文件不存在则创建
  //   .open("resources/libsel_rewrites/get_vec.rules") // 打开文件
  //   .unwrap();
  // for rule in rules {
  //   writeln!(file, "{}", rule).unwrap();
  // }
}

#[test]
fn test_parse_rules() {
  let input1 = "(select ?a ?b ?c) <==> (select ?a ?c ?b)where(?a: [int |
  float], ?b: float<64>, ?c: vector<int<64>;16>)";
  let input2 = "(add ?a
  ?b) ==> (add ?b ?a) where (all: bool)";
  let _rewrites: Vec<Rewrite<AstNode<RdgEgg>, ISAXAnalysis<RdgEgg, EggType>>> =
    babble::rewrites::parse(input1).unwrap();
  let _rewrites2: Vec<Rewrite<AstNode<RdgEgg>, ISAXAnalysis<RdgEgg, EggType>>> =
    babble::rewrites::parse(input2).unwrap();
  let rewrites3: Vec<Rewrite<AstNode<RdgEgg>, ISAXAnalysis<RdgEgg, EggType>>> =
    rewrites::from_file(PathBuf::from("resources/all.rules"))
      .unwrap_or_default();
  // println!("{:?}", rewrites);
}
