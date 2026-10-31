#![warn(
    clippy::all,
    clippy::pedantic,
    anonymous_parameters,
    elided_lifetimes_in_paths,
    missing_copy_implementations,
    missing_debug_implementations,
    single_use_lifetimes,
    // trivial_casts,
    unreachable_pub,
    unused_lifetimes
)]
#![allow(clippy::non_ascii_literal)]
#![feature(pattern)]
use babble::{
  ast_node::Expr,
  bb_query,
  rewrites,
};
use std::{
  collections::{BTreeMap, BTreeSet},
  path::Path,
};



use crate::egg_lang::{
  RdgEgg,
  schedule::{LangArea, LangDelay},
};

pub mod common;
pub mod egg_lang;
pub mod experiment;
pub mod rdg;
pub mod rules;
pub mod runner;

mod preprocess;

fn choose_bb_according_to_hotness(
  bb_query: &bb_query::BBQuery,
) -> BTreeSet<String> {
  let mut func_exec = BTreeMap::new(); // 有序
  let mut bb_exec_vec = Vec::new();
  let mut total_exec_count = 0;

  // 统计每个 function 的总执行次数，同时收集所有 BB
  for (bb, entry) in bb_query.map.iter() {
    let func = bb.split('#').next().unwrap_or(bb).trim();
    let exec_count = entry.execution_count;
    func_exec
      .entry(func.to_string())
      .and_modify(|e| *e += exec_count)
      .or_insert(exec_count);
    bb_exec_vec.push((bb.to_string(), exec_count));
    total_exec_count += exec_count;
  }

  // 如果 function 数 < 10，直接返回所有 function（有序）
  if func_exec.len() < 10 {
    return func_exec.keys().cloned().collect();
  }

  // 按执行次数降序 + BB 名字升序（确保稳定性）
  bb_exec_vec.sort_by(|a, b| b.1.cmp(&a.1).then_with(|| a.0.cmp(&b.0)));

  let mut bb_set = BTreeSet::new();
  let mut func_set = BTreeSet::new();

  // 至少保留的 function 数
  let func_num_threshold = 10;
  let func_threshold = (total_exec_count as f64 * 0.7) as usize;

  let mut func_exec_count = 0;
  for (bb, _) in bb_exec_vec {
    let func = bb.split('#').next().unwrap_or(&bb).trim();
    if func == "main" {
      continue; // 跳过 main
    }
    // 如果已达到 80% 执行次数且 function 数 ≥10，就停止
    if func_exec_count >= func_threshold && func_set.len() >= func_num_threshold
    {
      break;
    }
    bb_set.insert(bb.clone());
    if !func_set.contains(func) {
      func_set.insert(func.to_string());
      if let Some(&exec_count) = func_exec.get(func) {
        func_exec_count += exec_count;
      }
    }
  }

  func_set
}

/// Run a single configuration (moved from main.rs)
pub fn run_single_config(
  config_path: &str,
) -> Result<(), Box<dyn std::error::Error>> {
  use crate::egg_lang::schedule::{LangArea, LangDelay};
  use crate::egg_lang::{RdgEgg, RdgEggLang};
  use crate::rdg::from_jlm_rvsdg::rdg_from_file;
  use crate::runner::{
    ISAXRunner, ReportRecorder, init_workspace, load_config,
  };
  use std::path::PathBuf;

  // Load configuration
  let config = load_config(config_path)?;

  // Initialize workspace
  init_workspace(&config)?;

  let profile_path = config.profile_path;
  let bb_query = bb_query::BBQuery::new(profile_path);
  let chosen_funcs = choose_bb_according_to_hotness(&bb_query);
  println!("Chosen functions: {:?}", chosen_funcs);
  // let mut bb_query_hashmap = HashMap::new();
  // bb_query_hashmap.insert(
  //   "test".to_string(),
  //   BBEntry::new("t".to_string(), 1, 2000, 2000.0, 1, 1, 1.0, 1.0),
  // );
  // let bb_query = BBQuery {
  //   map: bb_query_hashmap,
  // };

  // Initialize report recorder
  let reporter = ReportRecorder::new(&config.workspace_dir, &config.log_file)?;
  env_logger::init();

  let filename = config.rvsdg_path;

  // Create example expressions (you can modify this as needed)
  // let vecexpr = vec![dot_mul_expr(
  //   &[1, 2, 3, 4],
  //   &[5, 6, 7, 8],
  //   &[9, 10, 11, 12],
  //   &[13, 14, 15, 16],
  // )];
  // let vecexpr = vec![dot_expr(&[1, 2, 3, 4], &[5, 6, 7, 8])];
  // let vecexpr = vec![add_mul_fussion_expr1(&[1, 2, 3, 4], &[5, 6, 7, 8])];
  // let vecexpr = vec![
  //   add_expr((3, 64), (1, 64)),
  //   add_expr((2, 64), (1, 64)),
  //   add_expr((4, 64), (1, 64)),
  // ];
  // let vecexpr = vec![
  //   add_mul_mul_expr(2, 1),
  //   add_mul_mul_expr(3, 1),
  //   add_mul_mul_expr(4, 1),
  //   add_mul_mul_expr(5, 1),
  // ];

  // let rdg_egg = rdg_from_file(filename.clone()).unwrap().to_egg();
  // let rdgegg: Expr<RdgEgg> =
  //   RdgEggLang::build_babble_expr_from_recexpr(rdg_egg);
  // let vec_rdgegg = vec![rdgegg];

  let path = Path::new(&filename);
  let mut vec_rdgegg = Vec::new();

  if path.is_file() {
    // 单个文件情况
    let mut rdg_program = rdg_from_file(path).unwrap();
    rdg_program.delete_main_function();
    // rdg_program
    //   .delete_functions_according_to_bbs_info(&bb_query, &chosen_funcs);
    let rdg_egg = rdg_program.to_egg();
    let rdgegg: Expr<RdgEgg> =
      RdgEggLang::build_babble_expr_from_recexpr(rdg_egg);
    vec_rdgegg.push(rdgegg);
  } else if path.is_dir() {
    // 目录情况：遍历所有子文件
    for entry in std::fs::read_dir(path).unwrap() {
      let entry = entry.unwrap();
      let path = entry.path();

      if path.is_file() {
        let rdg = rdg_from_file(&path);
        if rdg.is_err() {
          eprintln!("Error reading RDG from file: {}", path.display());
          continue;
        }
        let mut rdg_program = rdg_from_file(path).unwrap();
        rdg_program
          .delete_functions_according_to_bbs_info(&bb_query, &chosen_funcs);
        let rdg_egg = rdg_program.to_egg();
        let rdgegg: Expr<RdgEgg> =
          RdgEggLang::build_babble_expr_from_recexpr(rdg_egg);
        vec_rdgegg.push(rdgegg);
      }
    }
  } else {
    panic!("Provided path is neither a file nor a directory");
  }

  // vec_rdgegg = vecexpr;
  // vec_rdgegg = vec![add_mul_mul_expr(2, 3), add_mul_mul_expr(4, 5)];

  // Extract filename for learned libs
  let filename = filename.split("/").last().unwrap();
  let filename = format!(
    "{}/learned_libs/{}.lib",
    config.workspace_dir,
    filename.split(".").next().unwrap()
  );

  // Read rewrite rules
  println!("Reading dsr file");
  let dsrs =
    rewrites::from_file(PathBuf::from("resources/prune_rewrites/all.rules"))
      .unwrap_or_default();
  println!("Read {} dsrs", dsrs.len());

  // Create ISAXRunner
  let mut isax_runner = ISAXRunner::new(
    vec_rdgegg,
    bb_query,
    LangArea::default(),
    LangDelay::default(),
    dsrs,
    &filename,
    config.isax_config,
    reporter,
  );

  let _result = isax_runner.run();
  Ok(())
}
