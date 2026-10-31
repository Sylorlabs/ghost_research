use babble::au_filter::CiEncodingConfig;
use babble::bb_query::BBQuery;
use babble::perf_infer::{self, expr_perf_infer};
use babble::rewrites::TypeMatch;
use babble::schedule::{cycles_for_every_function, rec_cost};
use babble::vectorize::VectorConfig;
use babble::{AstNode, ast_node::Expr, rewrites};
use enumo::HashSet;
use graphviz_rust::attributes::start;
use log::debug;

use crate::egg_lang::ast::max;
use crate::egg_lang::schedule::{LangArea, LangDelay};
use crate::egg_lang::{BinaryOp, EggType, RdgEggInfo};
use crate::egg_lang::{RdgEgg, RdgEggOp};

use crate::preprocess::{preprocess, preprocess_arg, types_restore};

use babble::extract::beam_pareto::ISAXAnalysis;
use babble::{LibId, PartialExpr};
// use babble::extract::beam_pareto::LibExtractor;
use babble::expand::{ExpandMessage, MetaAUConfig};
use babble::runner::{
  BabbleParetoRunner, ExtractResult, FindPackConfig, LiblearnConfig,
  OperationInfo, ParetoConfig, ParetoRunner,
};
use egg::{
  AstSize, CostFunction, EGraph, ENodeOrVar, Extractor, Id, LpExtractor,
  Pattern, RecExpr, Rewrite, Runner, Symbol, Var,
};
use rand::seq::{IndexedRandom, SliceRandom};
use serde::Deserialize;
use serde_json::json;
use std::collections::HashSet as StdHashSet;
use std::fmt::Display;
use std::fs::File;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};
use std::{collections::HashMap, fmt::Debug};
use std::{default::Default, time::Instant};
use std::{fs, vec};

pub type IsaxAnalysis = ISAXAnalysis<RdgEgg, EggType>; // KnapsackLibCost<RdgEgg, RdgEggAreaCost, RdgEggDelayCost>;

/// 定义一个日志记录器，用于记录算法流程
#[derive(Debug)]
pub struct ReportRecorder {
  records: Vec<serde_json::Value>, // 记录在内存里
  path: PathBuf,                   // 记住文件路径
}

impl ReportRecorder {
  pub fn new(
    workspace_dir: &str,
    log_file: &str,
  ) -> Result<Self, Box<dyn std::error::Error>> {
    let path = Path::new(workspace_dir).join(log_file);
    Ok(Self {
      records: Vec::new(),
      path,
    })
  }

  pub fn record_phase(
    &mut self,
    name: &str,
    metrics: &HashMap<String, String>,
  ) -> Result<(), Box<dyn std::error::Error>> {
    // let timestamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs();

    let log_entry = json!({
        "phase": name,
        // "timestamp": timestamp,
        "metrics": metrics,
    });

    self.records.push(log_entry);
    Ok(())
  }

  pub fn record_pareto_solution(
    &mut self,
    name: &str,
    speedup: f32,
    performance_gain: usize,
    area: usize,
    lib_ids: StdHashSet<usize>,
    func_speedup: HashMap<String, f64>,
  ) -> Result<(), Box<dyn std::error::Error>> {
    let log_entry = json!({
        "pareto_optimal_solution": name,
        "speedup": speedup,
        "performance_gain": performance_gain,
        "area": area,
        "func_speedup": func_speedup,
        "lib_ids": lib_ids,
    });
    self.records.push(log_entry);
    Ok(())
  }

  pub fn finalize(&mut self) -> Result<(), Box<dyn std::error::Error>> {
    let serialized = serde_json::to_string_pretty(&self.records)?;
    std::fs::write(&self.path, serialized)?;
    Ok(())
  }
}

/// 定义AppConfig，用于存储应用程序的配置
#[derive(Debug, Deserialize, Clone)]
pub struct AppConfig {
  pub rvsdg_path: String,
  pub profile_path: String,
  pub workspace_dir: String,
  pub log_file: String,
  pub isax_config: ISAXConfig,
}

/// 从文件中读取配置
pub fn load_config(
  path: &str,
) -> Result<AppConfig, Box<dyn std::error::Error>> {
  let content = fs::read_to_string(path)?;
  Ok(toml::from_str(&content)?)
}
/// 初始化工作区
pub fn init_workspace(config: &AppConfig) -> Result<(), std::io::Error> {
  // 创建主目录
  fs::create_dir_all(&config.workspace_dir)?;
  // 创建learned_libs子目录
  let libs_dir = Path::new(&config.workspace_dir).join("learned_libs");
  fs::create_dir_all(libs_dir)?;
  Ok(())
}

/// phase mode, 定义使用哪种模式进行库学习
#[derive(Debug, Deserialize, Copy, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum PhaseMode {
  /// 使用saturating规则
  Saturating,
  /// 使用size_decrease规则
  SizeDecrease,
  /// 使用三部分循环
  Cyclic,
  /// 混合模式
  Mixed,
  /// 层进式
  Layered,
  /// random
  // Random,
  /// 没有规则
  None,
}

/// phase config
#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
pub struct PhaseConfig {
  /// 使用的模式
  pub mode: PhaseMode,
  // 共进行多少轮
  pub phases: usize,
  /// 是否加入向量化phase
  pub enable_vectorize_phase: bool,
  /// 是否加入meta_AU phase
  pub enable_meta_au_phase: bool,
  /// 是否加入类型聚合phase
  pub enable_widths_merge: bool,
}

impl Default for PhaseConfig {
  fn default() -> Self {
    Self {
      mode: PhaseMode::Saturating,
      phases: 5,
      enable_vectorize_phase: false,
      enable_meta_au_phase: false,
      enable_widths_merge: false,
    }
  }
}

/// 定义extract的配置
#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
pub struct ExtractConfig {
  pub final_beams: usize,
  pub inter_beams: usize,
  pub lib_iter_limit: usize,
  pub lps: usize,
  pub learn_constants: bool,
  pub max_arity: Option<usize>,
  pub clock_period: usize,
}

impl Default for ExtractConfig {
  fn default() -> Self {
    Self {
      final_beams: 5,
      inter_beams: 3,
      lib_iter_limit: 1,
      lps: 1,
      learn_constants: false,
      max_arity: Some(2),
      clock_period: 1000,
    }
  }
}

/// 定义ISAXConfig，用于存储ISAX算法的配置
#[derive(Debug, Deserialize, Clone, PartialEq)]
pub struct ISAXConfig {
  pub phase_config: PhaseConfig,
  pub extract_config: ExtractConfig,
  pub liblearn_config: LiblearnConfig,
  pub vectorize_config: VectorConfig,
  pub op_pack_config: MetaAUConfig,
  pub ci_encoding_config: CiEncodingConfig,
  pub find_pack_config: FindPackConfig,
  pub max_frontiers_to_keep: usize,
}

impl Default for ISAXConfig {
  fn default() -> Self {
    Self {
      phase_config: PhaseConfig::default(),
      extract_config: ExtractConfig::default(),
      liblearn_config: LiblearnConfig::default(),
      vectorize_config: VectorConfig::default(),
      op_pack_config: MetaAUConfig::default(),
      ci_encoding_config: CiEncodingConfig::default(),
      find_pack_config: FindPackConfig::default(),
      max_frontiers_to_keep: 3,
    }
  }
}

/// 定义ISAXResult, 用于存储ISAX算法的结果
#[derive(Debug)]
pub struct ISAXResult {
  /// 最佳egraph和根节点的Id
  pub extract_results: Vec<ExtractResult<RdgEgg, EggType>>,
}
/// 为ISAXResult实现default
impl Default for ISAXResult {
  fn default() -> Self {
    Self {
      extract_results: Vec::new(),
    }
  }
}
/// 为ISAXResult实现new
impl ISAXResult {
  pub fn update_frontier(
    &mut self,
    new_frontier: Vec<ExtractResult<RdgEgg, EggType>>,
  ) -> bool {
    println!("\n[Frontier] Updating Pareto Frontier...");

    let past_frontier = self.extract_results.clone();

    // 1. 合并新旧解
    self.extract_results.extend(new_frontier);

    // 2.0 去重：相同expr的解去掉
    let mut unique_results = HashSet::default();
    self.extract_results.retain(|result| {
      let expr_str = result.expr.clone();
      if unique_results.contains(&expr_str) {
        false // 已经存在，去掉
      } else {
        unique_results.insert(expr_str);
        true // 保留
      }
    });

    // 2.1 去重：相同libs的解去掉
    let mut unique_libs = HashSet::default();
    self.extract_results.retain(|result| {
      let mut libs_set: Vec<_> = result.libs.keys().cloned().collect();
      libs_set.sort_unstable(); // 排序以确保相同的lib顺序
      if unique_libs.contains(&libs_set) {
        false // 已经存在，去掉
      } else {
        unique_libs.insert(libs_set);
        true // 保留
      }
    });

    // 3. 计算真正的 Pareto Frontier（不被支配的解）
    let mut pareto_frontier = Vec::new();
    for candidate in &self.extract_results {
      let dominated = self.extract_results.iter().any(|other| {
        other.area <= candidate.area
          && other.cycles <= candidate.cycles
          && (other.area < candidate.area || other.cycles < candidate.cycles)
      });
      if !dominated {
        pareto_frontier.push(candidate.clone());
      }
    }

    // 4. 更新 frontier
    self.extract_results = pareto_frontier;

    println!(
      "   Pareto Solutions ({} total):",
      self.extract_results.len()
    );
    for (i, egraph) in self.extract_results.iter().enumerate() {
      println!(
        "     {:>2}. Area: {:<8} | cycles: {:<8} | lib_ids: {:?}",
        i + 1,
        egraph.area,
        egraph.cycles,
        egraph.libs.keys()
      );
    }

    past_frontier != self.extract_results
  }

  pub fn prune(&mut self, num_to_keep: usize) {
    // 使用cycles和 area进行排序
    self.extract_results.sort_by(|a, b| {
      (a.cycles as usize)
        .cmp(&(b.cycles as usize))
        .then(a.area.cmp(&b.area))
    });
    // 保留前num_to_keep个解
    if self.extract_results.len() > num_to_keep {
      println!(
        "Pruning Pareto Frontier from {} to {} solutions",
        self.extract_results.len(),
        num_to_keep
      );
      self.extract_results.truncate(num_to_keep);
    }
  }
}

#[derive(Debug, Clone)]
pub struct ISAXLibs {
  /// 学习的库的RecExpr
  pub lib_exprs: HashMap<usize, RecExpr<AstNode<RdgEgg>>>,
  /// 学习的库的Pattern(实际上是applier部分)
  pub learned_libs: HashMap<usize, Pattern<AstNode<RdgEgg>>>,
  /// 学习的库的重写和类型匹配
  pub lib_rewrites: HashMap<
    usize,
    (Rewrite<AstNode<RdgEgg>, IsaxAnalysis>, TypeMatch<EggType>),
  >,
  /// 一个HashSet，输入searcher，用来判断lib是否重复
  searchers: HashSet<PartialExpr<RdgEgg, Var>>,
}

impl ISAXLibs {
  /// 创建一个新的ISAXLibs
  pub fn new() -> Self {
    Self {
      lib_exprs: HashMap::default(),
      learned_libs: HashMap::default(),
      lib_rewrites: HashMap::default(),
      searchers: HashSet::default(),
    }
  }

  /// 添加一个库
  pub fn add_lib(
    &mut self,
    searcher: PartialExpr<RdgEgg, Var>,
    lib: (usize, Pattern<AstNode<RdgEgg>>),
    rewrite: Rewrite<AstNode<RdgEgg>, IsaxAnalysis>,
    type_match: TypeMatch<EggType>,
  ) {
    // 如果searcher已经存在，则不添加
    if !self.searchers.contains(&searcher) {
      self.searchers.insert(searcher.clone());

      // 将Pattern转换为RecExpr
      let searcher_ast = Pattern::from(searcher).ast.clone();
      let new_expr = searcher_ast
        .iter()
        .map(|node| match node {
          egg::ENodeOrVar::ENode(ast_node) => {
            let new_node = (*ast_node).clone();
            new_node
          }
          egg::ENodeOrVar::Var(var) => {
            // 搜索var对应的类型信息
            let tys = type_match.type_map.get(var).cloned().unwrap_or_default();
            let ty = if tys.is_empty() {
              EggType::default()
            } else {
              tys[0].clone()
            };
            let new_name = format!("{}:{}", var, ty);
            AstNode::leaf(RdgEgg {
              op: RdgEggOp::RulerVar(Symbol::from(new_name)),
              info: RdgEggInfo {
                result_tys: tys.clone(),
                ..Default::default()
              },
            })
          }
        })
        .collect::<Vec<AstNode<RdgEgg>>>();
      let mut expr = RecExpr::from(new_expr);
      expr_perf_infer(&mut expr);
      // 添加到lib_exprs中
      self.lib_exprs.insert(lib.0, expr);
      // 添加到learned_libs中
      self.learned_libs.insert(lib.0, lib.1);
      // 添加到lib_rewrites中
      self.lib_rewrites.insert(lib.0, (rewrite, type_match));
    }
  }
}

/// 决定使用的规则集
#[derive(Debug, Clone, Copy)]
pub enum RuleMode {
  IntSaturating,
  Overflowing,
  SizeDecrease,
  Cyclic,
  Random,
  FloatSaturating,
  None,
}

impl Display for RuleMode {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    match self {
      RuleMode::IntSaturating => write!(f, "int_saturating"),
      RuleMode::Overflowing => write!(f, "overflowing"),
      RuleMode::SizeDecrease => write!(f, "size_decrease"),
      RuleMode::Cyclic => write!(f, "cyclic"),
      RuleMode::Random => write!(f, "random"),
      RuleMode::FloatSaturating => write!(f, "float_saturating"),
      RuleMode::None => write!(f, "none"),
    }
  }
}

/// 定义ISAXRunner，用于运行ISAX算法
#[derive(Debug)]
pub struct ISAXRunner {
  /// 初始表达式
  pub exprs: Vec<Expr<RdgEgg>>,
  /// 如果第一轮用了向量化，那么之后就会使用egraph作为初始的输入
  pub vectorized_egraph_with_root:
    Option<(EGraph<AstNode<RdgEgg>, IsaxAnalysis>, Id)>,
  /// BB query
  pub bb_query: BBQuery,
  pub area_estimator: LangArea,
  pub delay_estimator: LangDelay,
  /// 重写规则
  pub rewrites: Vec<Rewrite<AstNode<RdgEgg>, IsaxAnalysis>>,
  /// overflow rules
  pub ordered_overflow_rules: Vec<Rewrite<AstNode<RdgEgg>, IsaxAnalysis>>,
  /// 选择的库
  pub lib_message: ExpandMessage<RdgEgg, EggType>,
  /// 最终结果
  pub result: ISAXResult,
  /// 文件名
  pub filename: String,
  /// 配置
  pub config: ISAXConfig,
  /// peak_egraph_size:
  pub peak_egraph_size: (usize, usize),
  /// 记录器
  pub recorder: ReportRecorder,
}

fn load_rules(file_name: &str) -> Vec<Rewrite<AstNode<RdgEgg>, IsaxAnalysis>> {
  rewrites::from_file(PathBuf::from(file_name)).unwrap_or_default()
}

impl ISAXRunner {
  /// 创建一个新的ISAXRunner
  pub fn new(
    exprs: Vec<Expr<RdgEgg>>,
    bb_query: BBQuery,
    area_estimator: LangArea,
    delay_estimator: LangDelay,
    rewrites: Vec<Rewrite<AstNode<RdgEgg>, IsaxAnalysis>>,
    filename: &str,
    isax_config: ISAXConfig,
    recorder: ReportRecorder,
  ) -> Self {
    Self {
      exprs,
      vectorized_egraph_with_root: None,
      bb_query,
      area_estimator,
      delay_estimator,
      rewrites,
      ordered_overflow_rules: Vec::new(), // 初始化为空
      lib_message: ExpandMessage::default(),
      result: ISAXResult::default(),
      filename: filename.to_string(),
      config: isax_config,
      peak_egraph_size: (0, 0), // 初始化为0
      recorder: recorder,
    }
  }
  fn determine_iters(&self, mode: RuleMode) -> usize {
    match mode {
      RuleMode::IntSaturating | RuleMode::FloatSaturating => {
        5 //最多五次
      }
      RuleMode::SizeDecrease | RuleMode::Cyclic | RuleMode::Random => {
        // 2次
        2
      }
      _ => {
        // 1次(增长规模巨大，不适合多次迭代；或者没有规则)
        1
      }
    }
  }
  fn init_ordered_overflow_rules(&mut self) {
    // 选择一半Overflow的规则，
    let rules = load_rules("resources/libsel_rewrites/overflowing.rules");
    let exprs = self
      .exprs
      .clone()
      .into_iter()
      .map(RecExpr::from)
      .collect::<Vec<_>>();
    // 加入egraph中
    let mut egraph = EGraph::new(ISAXAnalysis::default());
    for expr in exprs.iter() {
      egraph.add_expr(expr);
    }
    // 先用所有rules进行重写
    let runner = Runner::<_, _, ()>::new(IsaxAnalysis::default())
      .with_egraph(egraph)
      .with_iter_limit(5)
      .run(&rules);
    let mut match_map = Vec::new();
    for rule in rules.iter() {
      let result = rule.search(&runner.egraph);
      if result.len() > 0 {
        // 如果有匹配的结果，就加入match_map
        match_map.push((rule.clone(), result.len()));
      }
    }
    // 按照匹配的结果数量进行排序
    match_map.sort_by(|a, b| b.1.cmp(&a.1));
    self.ordered_overflow_rules = match_map
      .into_iter()
      .map(|(rule, _)| rule)
      .collect::<Vec<_>>()
  }
  /// load_rewrites函数，根据RuleMode进行重写规则的加载
  fn load_rules_one_pass(
    &self,
    mode: RuleMode,
    iter: usize,
    vectorize: bool,
  ) -> (Vec<Rewrite<AstNode<RdgEgg>, IsaxAnalysis>>, usize) {
    let mut rules = match mode {
      RuleMode::None => Vec::new(),
      RuleMode::IntSaturating => {
        load_rules("resources/libsel_rewrites/int_saturating.rules")
      }
      RuleMode::Overflowing => load_rules("resources/prune_rewrites/all.rules"),
      RuleMode::SizeDecrease => {
        load_rules("resources/libsel_rewrites/size_decreasing.rules")
      }
      RuleMode::Cyclic => match iter % 3 {
        0 => {
          load_rules("resources/libsel_rewrites/size_increase_saturating.rules")
        }
        1 => {
          load_rules("resources/libsel_rewrites/size_decrease_saturating.rules")
        }
        2 => load_rules(
          "resources/libsel_rewrites/size_decrease_no_saturating.rules",
        ),
        _ => {
          load_rules("resources/libsel_rewrites/size_decrease_saturating.rules")
        }
      },
      RuleMode::FloatSaturating => {
        load_rules("resources/libsel_rewrites/float_saturating.rules")
      }
      RuleMode::Random => {
        // 分成两半
        let ordered_overflow_rules = self.ordered_overflow_rules.clone();
        // 已经排序好了，从中间分成两半
        let (high_rules, light_rules) =
          ordered_overflow_rules.split_at(ordered_overflow_rules.len() / 2);
        // 随机选择一半
        let mut rng = rand::rng();
        let mut selected_rules: Vec<_> = high_rules
          .choose_multiple(&mut rng, high_rules.len() / 2)
          .cloned()
          .collect();
        selected_rules.extend(
          light_rules
            .choose_multiple(&mut rng, light_rules.len() / 2)
            .cloned(),
        );
        // 返回选择的规则
        selected_rules
      }
    };

    // 不能直接将lib_rewrites的值添加到rules中，
    // let lib_rules = self.libs.lib_rewrites.values().map(|v| v.0.clone());
    // rules.extend(lib_rules);

    // 添加向量化规则
    if vectorize {
      let transform_rules =
        load_rules("resources/libsel_rewrites/transform_vec_saturating.rules");
      rules.extend(transform_rules);
    }

    (rules, self.determine_iters(mode))
  }

  fn initial_cycles(&self) -> (f64, HashMap<String, f64>) {
    println!("=== Calculating initial latency ===");
    let recexprs: Vec<RecExpr<AstNode<RdgEgg>>> =
      self.exprs.clone().into_iter().map(RecExpr::from).collect();
    let mut init_latency = 0.0;
    let mut func_cycles = HashMap::new();
    for recexpr in recexprs.iter() {
      // println!("Size of initial expr: {}", recexpr.len());
      let (cycles, _area) = rec_cost(recexpr, &self.bb_query, HashMap::new());
      let partial_func_cycles =
        cycles_for_every_function(recexpr, &self.bb_query, HashMap::new());
      // 将每个函数的cycles添加到func_cycles中
      for (func, cycles) in partial_func_cycles.iter() {
        let entry = func_cycles.entry(func.clone()).or_insert(0.0);
        *entry += *cycles as f64;
      }
      init_latency += cycles;
    }
    println!("- Initial latency: {} cycles", init_latency);
    (init_latency, func_cycles)
  }

  /// 定义prune函数，
  /// 首先将表达式转化成Recexpr，之后建立egraph，应用给定的重写规则进行剪枝
  fn prune(&mut self, message: &mut HashMap<String, String>) {
    println!("========== Pruning Phase ==========");
    // 打开文件，如果不存在则创建, 以追加的方式打开文件
    let filename = self.filename.clone();
    let _file = std::fs::OpenOptions::new()
      .append(true)
      .open(filename)
      .unwrap();

    let extract_with_size = |egraph: &EGraph<AstNode<RdgEgg>, IsaxAnalysis>,
                             root| {
      let extractor = Extractor::new(egraph, AstSize);
      extractor.find_best(root).1
      // let mut lp_extractor = LpExtractor::new(egraph, AstSize);
      // lp_extractor.solve(root)
    };
    let compute_cost =
      |new_recexprs: &Vec<RecExpr<AstNode<RdgEgg>>>| -> (usize, usize) {
        println!("- Using AstSize to compute cost");
        let mut size = 0;
        let mut cycles = 0;
        for recexpr in new_recexprs.iter() {
          let mut ast_size = AstSize;
          let expr_size = AstSize::cost_rec(&mut ast_size, recexpr);
          size += expr_size;
          let cost = rec_cost(recexpr, &self.bb_query, HashMap::new());
          cycles += cost.0 as usize;
        }
        (size, cycles)
      };

    let exprs = self.exprs.clone();
    let mut recexprs: Vec<RecExpr<AstNode<RdgEgg>>> =
      exprs.into_iter().map(RecExpr::from).collect();
    for recexpr in recexprs.iter_mut() {
      expr_perf_infer(recexpr);
    }

    // 进行预处理
    let preprocess_time = Instant::now();
    println!("[Subphase 1] 🔍 Preprocessing expressions...");

    let new_recexprs: Vec<RecExpr<AstNode<RdgEgg>>> =
      // if self.config.phase_config.enable_vectorize {
        recexprs
          .iter()
          .map(|recexpr| preprocess_arg(recexpr.clone()))
          .map(|recexpr| preprocess(recexpr.clone()))
          .collect();

    // } else {
    //   recexprs
    // };
    // 打印表达式

    let exprs: Vec<Expr<RdgEgg>> = new_recexprs
      .iter()
      .map(|recexpr| Expr::from(recexpr.clone()))
      .collect();
    self.exprs = exprs;
    let preprocess_time = preprocess_time.elapsed();
    message.insert(
      "Preprocess_time".to_string(),
      format!("{:?}s", preprocess_time.as_secs_f32()),
    );
    println!(
      "[Subphase 1] ✅ Preprocessing completed in {:?}",
      preprocess_time
    );

    let time = Instant::now();

    // 在之前的版本中，会将除了arg和get节点的类型设置为空，
    // 这样是为了配合rewrite的search，因为search过程中使用的节点的类型是空的，
    // 在之后将Op的PartialEq改成了，如果一个result_tys是空集，那么就默认相等，
    // 因此目前不需要清空所有类型，并且删除type_infor_map
    // 对于每个recexpr，进行预处理
    // FIXME: 个人觉得这么处理可能还是不行，
    // 因为load和store要求所有的地址都是连续的
    // for recexpr in new_recexprs.iter() {
    //   for (id, node) in recexpr.as_ref().iter().enumerate() {
    //     println!("{} node: {:?}", id, node);
    //   }
    // }
    // 计算初始delay，结果是所有Recexpr中的最大值,计算初始area
    let (init_size, init_cycles) = compute_cost(&new_recexprs);

    message.insert(
      "preprocess_time".to_string(),
      format!("{:?}s", time.elapsed().as_secs_f32()),
    );
    message.insert("init_astsize".to_string(), format!("{:?}", init_size));

    println!(
      "- initial astsize for expr: {}(warning: this can be a big number), initial cycles: {}",
      init_size, init_cycles
    );

    let time = Instant::now();
    // 应用重写规则
    // 设定超时时间，默认为10h
    let timeout = std::time::Duration::from_secs(36000);
    println!(
      "[Subphase 2] ⚙️ Building and running e-graph(Using all the rewrites)..."
    );
    // 构建一个egraph
    let mut egraph = EGraph::<AstNode<RdgEgg>, IsaxAnalysis>::default();

    let roots = new_recexprs
      .iter()
      .map(|recexpr| egraph.add_expr(recexpr))
      .collect::<Vec<_>>();
    egraph.rebuild();

    // egraph.dot().to_png("target/sat1.png").unwrap();
    let runner = Runner::<_, _, ()>::new(IsaxAnalysis::default())
      .with_egraph(egraph)
      .with_time_limit(timeout)
      .with_iter_limit(10000)
      .run(&self.rewrites);
    let mut egraph = runner.egraph;
    // egraph.dot().to_png("target/sat1.png").unwrap();
    // 添加bbs信息
    babble::perf_infer::perf_infer(&mut egraph, &roots);

    println!(
      "[Subphase 2] ✅ E-graph built and rewrites applied in {:?}",
      time.elapsed()
    );

    println!(
      "- initial egraph size: {}, initial_eclass_size: {}",
      egraph.total_size(),
      egraph.classes().len()
    );

    let best_exprs: Vec<RecExpr<AstNode<RdgEgg>>> = roots
      .iter()
      .map(|root| extract_with_size(&egraph, *root))
      .map(|expr| types_restore(expr))
      .collect();
    // 打印表达式
    for expr in best_exprs.iter() {
      for (node_id, node) in expr.as_ref().iter().enumerate() {
        println!("{} node: {:?}", node_id, node);
      }
    }

    let best_nodes: usize = best_exprs
      .iter()
      .map(|recexpr| recexpr.as_ref().len())
      .sum();

    message.insert(
      "normalize_time".to_string(),
      format!("{:?}s", time.elapsed().as_secs_f32()),
    );

    message.insert("best_nodes".to_string(), format!("{:?}", best_nodes));

    let (optimized_size, optimized_cycles) = compute_cost(&best_exprs);
    println!(
      "- optimized expr astsize: {}, optimized nodes: {}, optimized cycles: {}",
      optimized_size, best_nodes, optimized_cycles
    );
    // 如果最终gain大于最初的gain，返回最终表达式，否则返回初始表达式
    if optimized_cycles < init_cycles {
      // 将RecExpr转化为Expr
      let extracted_expr = best_exprs
        .iter()
        .map(|recexpr| Expr::from(recexpr.clone()))
        .collect::<Vec<_>>();
      self.exprs = extracted_expr;
    }
  }

  fn lib_select_one_pass(
    &mut self,
    mode: RuleMode,
    iter: usize,
    enable_widths_merge: bool,
    vectorize: bool,
    enable_meta_au: bool,
  ) -> bool {
    println!(
      "\n--- [PASS {}: RuleMode = {}, Vectorize = {}, MetaAU = {}] ---",
      iter, mode, vectorize, enable_meta_au
    );
    let exprs = self.exprs.clone();
    // 根据vectorize参数决定是否向量化
    let mut new_vectorize_config = self.config.vectorize_config.clone();
    new_vectorize_config.vectorize = vectorize;
    let mut new_op_pack_config = self.config.op_pack_config.clone();
    new_op_pack_config.enable_meta_au = enable_meta_au;
    // Create a ParetoConfig with custom settings
    let pareto_config = ParetoConfig {
      final_beams: self.config.extract_config.final_beams,
      inter_beams: self.config.extract_config.inter_beams,
      lib_iter_limit: self.config.extract_config.lib_iter_limit,
      lps: self.config.extract_config.lps,
      learn_constants: self.config.extract_config.learn_constants,
      max_arity: self.config.extract_config.max_arity,
      clock_period: self.config.extract_config.clock_period,
      area_estimator: self.area_estimator.clone(),
      delay_estimator: self.delay_estimator.clone(),
      enable_widths_merge: enable_widths_merge,
      liblearn_config: self.config.liblearn_config.clone(),
      vectorize_config: new_vectorize_config,
      op_pack_config: new_op_pack_config,
      ci_encoding_config: self.config.ci_encoding_config.clone(),
      find_pack_config: self.config.find_pack_config.clone(),
    };

    println!("  📦 Loading rewrite rules...");
    // Create cost models
    let lift_dsrs = if vectorize {
      load_rules(
        self
          .config
          .vectorize_config
          .lift_rules
          .clone()
          .unwrap()
          .as_str(),
      )
    } else {
      Vec::new()
    };
    let lower_dsrs = if vectorize {
      load_rules(
        self
          .config
          .vectorize_config
          .lower_rules
          .clone()
          .unwrap()
          .as_str(),
      )
    } else {
      Vec::new()
    };
    let transform_dsrs = if vectorize {
      load_rules(
        self
          .config
          .vectorize_config
          .transform_rules
          .clone()
          .unwrap()
          .as_str(),
      )
    } else {
      Vec::new()
    };
    let (mut dsrs, dsr_rewrite_iters) =
      self.load_rules_one_pass(mode.clone(), iter, vectorize);
    // 除此之外，需要load一些必须的规则(在这里表示交换律，否则匹配会非常少)

    if !matches!(mode, RuleMode::None) {
      let must_rules = load_rules("resources/libsel_rewrites/must.rules");
      dsrs.extend(must_rules);
    }
    println!(
      "   • Loaded {} domain-specific rewrite rules (DSRs)",
      dsrs.len()
    );
    // Create a ParetoRunner with no domain-specific rewrites
    let mut runner = ParetoRunner::new(
      dsrs,
      dsr_rewrite_iters,
      self.bb_query.clone(),
      self.lib_message.clone(),
      pareto_config,
    );
    if vectorize {
      // 如果本phase是向量化阶段，就加入向量化的DSRs
      runner.with_vectorize_dsrs(lift_dsrs, lower_dsrs, transform_dsrs);
    }

    println!("  🚀 Starting Pareto optimization...");
    // Run the experiment
    let pareto_result = if self.vectorized_egraph_with_root.is_some() {
      println!("   • Using existing vectorized egraph as initial input");
      // 如果已经有了向量化的egraph，就使用它作为初始输入
      let (egraph, root) = self.vectorized_egraph_with_root.clone().unwrap();

      runner.run_egraph(&[root], egraph)
    } else {
      println!("   • Using initial expressions as input");
      // 否则就使用初始表达式
      runner.run_multi(exprs)
    };
    // self.selected_libs.push(result.final_expr);
    // let vec_final_expr = vec![result.final_expr.clone()];
    // Print the results
    if vectorize {
      println!("      📊 Vectorization phase change the initial egraph");
      self.vectorized_egraph_with_root =
        pareto_result.vectorized_egraph_with_root.clone();
    }

    // self.lib_rewrites = pareto_result.rewrites;
    self
      .lib_message
      .extend_from_messages(&pareto_result.lib_message);
    // self
    //   .lib_rewrites
    //   .extend(pareto_result.rewrites_with_conditon);
    // let recexprs = self.type_complete(&pareto_result.learned_lib);
    let liblearn_egraph_size = pareto_result.egraph_size;
    if liblearn_egraph_size.1 > self.peak_egraph_size.1 {
      // 更新peak_egraph_size
      self.peak_egraph_size = liblearn_egraph_size;
    }

    // 读取liblearn_eclass_size和liblearn_egraph_size,
    // 如果message和pareto中存在这两个键，那么取最大值
    // 更新frontier
    let updated = self.result.update_frontier(pareto_result.extract_results);
    if updated {
      println!(
        "✅ Frontier updated. New frontier size: {}",
        self.result.extract_results.len()
      );
    } else {
      println!("⚠️  Frontier NOT updated. Iter = {}, Mode = {}", iter, mode);
    }
    println!("--- [PASS {} COMPLETE] ---\n", iter);
    updated
  }

  fn lib_select(&mut self) {
    println!("\n========== Library Selection Phase ==========");
    self.run_vector_and_merge_passes();
    self.run_phase_mode_passes();

    println!("=> Library Selection Phase Completed.\n");
  }

  fn run_vector_and_merge_passes(&mut self) {
    if self.config.phase_config.enable_vectorize_phase {
      println!("🔧 Running vector pass...");
      self.lib_select_one_pass(RuleMode::None, 0, false, true, false);
    }
    if self.config.phase_config.enable_widths_merge {
      println!("🔧 Running merge pass...");
      self.lib_select_one_pass(RuleMode::IntSaturating, 0, true, false, false);
    }
  }

  // TODO:目前暂且不启用meta_AU
  fn run_meta_au_passes(&mut self) {
    if self.config.phase_config.enable_meta_au_phase {
      println!("🔧 Running meta AU pass...");
      self.lib_select_one_pass(RuleMode::IntSaturating, 0, false, false, true);
    }
  }

  fn run_phase_mode_passes(&mut self) {
    println!("🔧 Running phase mode passes...");
    let max_iters = self.config.phase_config.phases;
    match self.config.phase_config.mode {
      PhaseMode::Saturating => {
        for iter in 0..max_iters {
          self.lib_select_one_pass(
            RuleMode::IntSaturating,
            iter,
            false,
            false,
            false,
          );
        }
      }
      PhaseMode::None => {
        for iter in 0..max_iters {
          self.lib_select_one_pass(RuleMode::None, iter, false, false, false);
        }
      }
      PhaseMode::SizeDecrease => {
        for iter in 0..max_iters {
          self.lib_select_one_pass(
            RuleMode::SizeDecrease,
            iter,
            false,
            false,
            false,
          );
        }
      }
      PhaseMode::Cyclic => {
        for iter in 0..max_iters {
          self.lib_select_one_pass(RuleMode::Cyclic, iter, false, false, false);
        }
      }
      PhaseMode::Mixed => self.run_mixed_mode(max_iters),
      _ => {
        // Layered特殊处理
      }
    }
    if self.config.phase_config.mode == PhaseMode::Layered {
      self.run_layered_mode(max_iters);
    } else if self.config.phase_config.mode != PhaseMode::None {
      // 其他模式只运行一次float pass
      self.lib_select_one_pass(
        RuleMode::FloatSaturating,
        self.config.phase_config.phases,
        false,
        false,
        false,
      );
    }
  }

  fn run_layered_mode(&mut self, max_iters: usize) {
    // 三段式，一次用Int_saturating, 一次用Float_saturating, 一次用Overflowing,
    // 循环做，不需要其他策略
    let mut iter_cnt = 0;
    while iter_cnt < max_iters {
      match iter_cnt {
        0 => {
          println!("layered mode, using int_saturating rules");
          self.lib_select_one_pass(
            RuleMode::IntSaturating,
            iter_cnt,
            false,
            false,
            false,
          );
        }
        1 => {
          println!("layered mode, using float_saturating rules");
          self.lib_select_one_pass(
            RuleMode::FloatSaturating,
            iter_cnt,
            false,
            false,
            false,
          );
        }
        // 2 => {
        //   println!("layered mode, using overflowing rules");
        //   self.lib_select_one_pass(
        //     RuleMode::Overflowing,
        //     iter_cnt,
        //     false,
        //     false,
        //     false,
        //     message,
        //   );
        // }
        _ => {
          // 全部使用random rules
          println!("layered mode, using random rules");
          self.lib_select_one_pass(
            RuleMode::Random,
            iter_cnt,
            false,
            false,
            false,
          );
        }
      }
      iter_cnt += 1;
    }
  }

  fn run_mixed_mode(&mut self, max_iters: usize) {
    let mut iter_cnt = 0;

    // Saturating phase
    while iter_cnt < max_iters {
      println!("mixed mode, using saturating rules");
      if !self.lib_select_one_pass(
        RuleMode::IntSaturating,
        iter_cnt,
        false,
        false,
        false,
      ) {
        break;
      }
      iter_cnt += 1;
    }

    // SizeDecrease phase
    while iter_cnt < max_iters {
      println!("mixed mode, using delay_decrease rules");
      if !self.lib_select_one_pass(
        RuleMode::SizeDecrease,
        iter_cnt,
        false,
        false,
        false,
      ) {
        break;
      }
      iter_cnt += 1;
    }

    // Cyclic + Random phase
    while iter_cnt < max_iters {
      println!("mixed mode, using cyclic rules");
      self.lib_select_one_pass(RuleMode::Cyclic, iter_cnt, false, false, false);
      iter_cnt += 1;
    }
  }

  /// 定义run函数，运行ISAX算法
  pub fn run(&mut self) {
    let filename = self.filename.clone();
    // 打开文件，如果不存在则创建, 以追加的方式打开文件
    let mut file = std::fs::OpenOptions::new()
      .write(true)
      .truncate(true)
      .create(true)
      .open(filename)
      .unwrap();

    // 全程只做一次剪枝，之后只做库选择
    let mut message = HashMap::new();
    let start_time = Instant::now();
    self.prune(&mut message);
    // let _err = self.recorder.record_phase("PRUNE", &message);
    let mut message = HashMap::new();

    let select_time = Instant::now();
    // 进行库选择
    self.lib_select();
    let best_exprs = self
      .exprs
      .iter()
      .map(|expr| {
        // 将Expr<RdgEgg>转化为RecExpr<AstNode<RdgEgg>>
        RecExpr::from(expr.clone())
      })
      .collect::<Vec<_>>();
    let mut test_egraph = EGraph::<AstNode<RdgEgg>, IsaxAnalysis>::default();
    // 将best_exprs添加到egraph中
    for expr in best_exprs.iter() {
      test_egraph.add_expr(expr);
    }
    let all_time = start_time.elapsed();
    message.insert(
      "total_time".to_string(),
      format!("{:?}s", all_time.as_secs_f32()),
    );
    message.insert(
      "initial_eclass_size".to_string(),
      format!("{:?}", test_egraph.classes().len()),
    );
    message.insert(
      "initial_egraph_size".to_string(),
      format!("{:?}", test_egraph.total_size()),
    );
    // 记录peak egraph size
    message.insert(
      "peak_eclass_size".to_string(),
      format!("{:?}", self.peak_egraph_size.0),
    );
    message.insert(
      "peak_enode_size".to_string(),
      format!("{:?}", self.peak_egraph_size.1),
    );
    let _ = self.recorder.record_phase("MAIN", &message);

    let (init_latency, init_func_cycles) = self.initial_cycles();

    self.result.prune(self.config.max_frontiers_to_keep);

    let mut message = HashMap::new();

    let mut cost_frontier = vec![];
    let mut lib_set = HashSet::default();
    let mut lib_reuse: HashMap<_, usize> = HashMap::default();

    let mut lib_op_count: HashMap<_, usize> = HashMap::default();

    for es in self.result.extract_results.iter() {
      // 将所有的lib添加到lib_set中
      for (id, cnt) in es.lib_reuses.iter() {
        lib_set.insert(*id);
        lib_reuse
          .entry(*id)
          .and_modify(|e| *e = (*e).max(*cnt)) // 取最大值
          .or_insert(*cnt);
        // 统计lib的大小
        let ast = es.libs.get(id).unwrap().ast.clone();
        let opcount = ast
          .iter()
          .map(|n| match n {
            ENodeOrVar::ENode(node) => {
              if node.operation().is_vector_op() {
                node.operation().get_vec_len()
              } else {
                match node.operation().op {
                  RdgEggOp::Lambda
                  | RdgEggOp::Apply
                  | RdgEggOp::Lib(_, _, _, _)
                  | RdgEggOp::RulerVar(_)
                  | RdgEggOp::LibVar(_) => 0, /* Lambda, Apply, Lib, */
                  // RulerVar, LibVar不算操作
                  _ => 1, // 其他操作算1个操作
                }
              }
            }
            ENodeOrVar::Var(_) => 0, // Var不算操作
          })
          .sum::<usize>();
        lib_op_count
          .entry(*id)
          .and_modify(|e| *e = (*e).max(opcount)) // 取最大值
          .or_insert(opcount);
      }
    }
    let num_libs = lib_set.len();
    let average_reuse_time = if num_libs > 0 {
      let all_reuse_time: usize = lib_reuse.values().sum(); // 所有最大值之和
      all_reuse_time as f64 / num_libs as f64
    } else {
      0.0
    };
    let average_lib_size = if num_libs > 0 {
      let all_lib_size: usize = lib_op_count.values().sum(); // 所有lib大小之和
      all_lib_size as f64 / num_libs as f64
    } else {
      0.0
    };
    message.insert("num_libs".to_string(), format!("{:?}", num_libs));
    message.insert(
      "average_reuse_time".to_string(),
      format!("{:.2}", average_reuse_time),
    );
    message.insert(
      "average_lib_op_count".to_string(),
      format!("{:.2}", average_lib_size),
    );
    let _ = self.recorder.record_phase("LIB_MESSAGE", &message);

    for (idx, es) in self.result.extract_results.iter().enumerate() {
      let mut final_recexpr: RecExpr<AstNode<RdgEgg>> = es.expr.clone().into();
      expr_perf_infer(&mut final_recexpr);
      let mut lib_ids = StdHashSet::new();
      for node in final_recexpr.iter() {
        if let RdgEggOp::Lib(LibId(id), _, _, _) = node.operation().op {
          // println!("lib node: {:?}", node);
          lib_ids.insert(id);
        }
      }
      let cycles = es.cycles as f64;
      let area = es.area;
      let speedup = init_latency / cycles;
      let gain = (init_latency - cycles) as usize;
      let final_func_cycles = es.func_cycles.clone();
      // 对比initial和final的func_cycles, 将有加速比的函数存进HashMap中
      let mut func_speedup = HashMap::new();
      for (func, final_cycles) in final_func_cycles.iter() {
        if let Some(init_cycles) = init_func_cycles.get(func) {
          if *init_cycles > 0.0 {
            let speedup = *init_cycles / *final_cycles as f64;
            if speedup > 1.0 {
              func_speedup.insert(func.clone(), speedup);
            }
          }
        }
      }
      debug!("Final gain: {} cycles", gain);
      debug!("initial latency: {} cycles", init_latency);
      debug!("Pareto cost: ({}, {})", gain, area);
      debug!("Speedup: {}", speedup);
      cost_frontier.push((gain, area, speedup, func_speedup.clone()));
      let _ = self.recorder.record_pareto_solution(
        &format!("solution {}", idx),
        speedup as f32,
        gain,
        area,
        lib_ids,
        func_speedup,
      );
    }

    let select_time = select_time.elapsed();
    message.insert(
      "Liblearn_time".to_string(),
      format!("{:?}s", select_time.as_secs_f32()),
    );
    // 输出每个Pareto Frontier的总speedup，和每个函数的speedup
    for (i, (_, _, speedup, func_speedup)) in cost_frontier.iter().enumerate() {
      println!(
        "Pareto Frontier {}: Speedup = {:.4}, Functions Speedup: ",
        i, speedup
      );
      for (func, speedup) in func_speedup.iter() {
        println!("Function {}: Speedup = {:.4}", func, speedup);
      }
    }

    // 输出Frontier信息
    println!("Pareto Frontier: [");
    for (gain, area, speedup, _) in cost_frontier.iter() {
      println!("  Gain: {}, Area: {}, Speedup: {:.4}", gain, area, speedup);
    }
    println!("]");

    let _err = self.recorder.finalize();

    for (i, es) in self.result.extract_results.iter().enumerate() {
      let _ = writeln!(
        file,
        "Solution {}: area {}, cycles {}",
        i, es.area, es.cycles
      );
      // 打印所有lib
      for (id, lib) in es.libs.iter() {
        Self::lib_serialize(&mut file, *id, lib);
      }
    }
  }

  /// Write the ast of lib in json format
  fn lib_serialize(file: &mut File, id: usize, lib: &Pattern<AstNode<RdgEgg>>) {
    // Create a JSON representation of each node in the AST
    let mut nodes = Vec::new();
    for (i, node) in lib.ast.iter().enumerate() {
      match node {
        ENodeOrVar::ENode(ast_node) => {
          let json_node = json!({
            "id": i,
            "op": format!("{:?}", ast_node.operation().op),
            "args": ast_node.args(),
          });
          nodes.push(json_node);
        }
        ENodeOrVar::Var(var) => {
          let json_node = json!({
            "id": i,
            "op": format!("Var({})", var),
            "args": [],
          });
          nodes.push(json_node);
        }
      }
    }

    // Write the JSON representation to the file
    let json = json!({ "lib id": id, "nodes": nodes });
    let _ = writeln!(file, "{}", serde_json::to_string_pretty(&json).unwrap());
  }
}
