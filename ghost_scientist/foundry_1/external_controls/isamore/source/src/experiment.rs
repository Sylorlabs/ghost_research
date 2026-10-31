//! # Experiment Runner with Concurrent Execution Support
//!
//! This module provides infrastructure for running experiments with multiple
//! configurations, supporting both sequential and concurrent execution modes.
//!
//! ## Key Components
//!
//! - **`Explorer`**: Generates configurations based on design space
//!   specifications
//! - **`EvalRunner`**: Executes experiments with configurable concurrency
//! - **Design Space**: TOML configuration defining parameter spaces to explore
//! - **Explorer Options**: TOML configuration controlling experiment execution
//!
//! ## Concurrent Execution
//!
//! The experiment runner supports concurrent execution using a thread pool
//! approach:
//!
//! - Each configuration runs in its own subprocess to ensure isolation
//! - Results and logs are captured per-configuration in separate directories
//! - Progress is reported in real-time across all worker threads
//! - Failed experiments don't block other experiments from completing

use crate::egg_lang::{RdgEgg, RdgEggLang};
use crate::rdg::from_jlm_rvsdg::rdg_from_file;
use crate::runner::{
  AppConfig, ExtractConfig, ISAXConfig, ISAXRunner, ReportRecorder,
  init_workspace, load_config,
};
use babble::au_filter::CiEncodingConfig;
use babble::extract::beam_pareto::ParetoCost;
use babble::runner::AUMergeMod;
use babble::vectorize::VectorConfig;
use babble::{Expr, bb_query, rewrites};
use chrono;
use clap::ValueEnum;
use core::str;
use crossbeam::channel::{Receiver, Sender, bounded};
use crossbeam::thread::Scope;
use graphviz_rust::print;
use indicatif::{MultiProgress, ProgressBar, ProgressStyle};
use libc::{RLIMIT_AS, RLIMIT_CPU, rlimit, setrlimit};
use log::{self, warn};
use regex::{self, Regex};
use ron::de;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fmt::Display;
use std::fs::{self, File};
use std::io::Write;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use std::vec;
use toml;

fn translate_able_to_symbol(value: &String) -> String {
  if value == "enable" {
    "y".to_string()
  } else {
    "n".to_string()
  }
}

fn translate_bool_to_symbol(value: bool) -> String {
  if value {
    "y".to_string()
  } else {
    "n".to_string()
  }
}

/// Free function for logging to a configuration-specific file.
fn log_to_config_file_static(log_file: &PathBuf, level: &str, message: &str) {
  if let Ok(mut file) = std::fs::OpenOptions::new()
    .create(true)
    .write(true)
    .append(true)
    .open(log_file)
  {
    let timestamp = chrono::Local::now().format("%H:%M:%S");
    let _ = writeln!(file, "[{}] {} - {}", timestamp, level, message);
  }
}

/// Design space configuration that defines all possible configuration options
#[derive(Debug, Deserialize, Clone)]
pub struct DesignSpace {
  pub phase_config: PhaseConfigSpace,
  // pub vectorize_config: VectorizeConfigSpace,
  pub ci_encoding_config: CiEncodingConfigSpace,
  pub liblearn_config: LiblearnConfigSpace,
  pub extract_config: Option<ExtractConfigSpace>,
}

// #[derive(Debug, Deserialize, Clone)]
// pub struct VectorizeConfigSpace {
//   pub max_vec_len: Vec<u32>,
// }

#[derive(Debug, Deserialize, Clone)]
pub struct CiEncodingConfigSpace {
  pub enable_packed_access: Vec<bool>,
  pub enable_register_grouping: Vec<bool>,
  pub grouping_hand_bits: Vec<u32>,
  pub enable_register_neighboring: Vec<bool>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct PhaseConfigSpace {
  pub phases: Vec<u32>,
  pub modes: Vec<String>,
  pub vectorize: Vec<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct LiblearnConfigSpace {
  pub au_merge: Vec<String>,
  pub au_merge_sample_num: Vec<u32>,
  pub au_cost: Vec<String>, // cost function to use
  pub au_enum: Vec<String>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct ExtractConfigSpace {
  pub beams: Vec<u32>,
  pub clock_period: Vec<u32>,
}

/// Explorer options that control which configurations to explore
#[derive(Debug, Deserialize, Clone)]
pub struct ExplorerOptions {
  pub benchmarks: Vec<Vec<String>>,
  pub path_prefix: Vec<String>,
  pub coi: Vec<String>, // configuration of interest
  pub strategy: String,
  pub default_config: String, // path to the default configuration file
  pub logging_level: Option<String>, // logging level
}

/// Exploration strategy
#[derive(Debug, Clone, Copy, ValueEnum)]
pub enum ExplorationStrategy {
  Naive,
  Optimize,
}

/// A single configuration instance
#[derive(Debug, Clone)]
pub struct Config {
  pub config_identifier: String, /* Unique name for this configuration,
                                  * e.g., benchmark_mode_vectorize */
  pub app_config: AppConfig, // The actual configuration settings
  pub benchmark: Benchmark,  /* Base benchmark details (paths before
                              * config-specific workspace) */
}

#[derive(Debug, Clone)]
pub struct Benchmark {
  pub rvsdg_path: String,
  pub profile_path: String,
  pub workspace_dir: String,
}

/// Explorer that generates configurations based on design space
#[derive(Debug, Clone)]
pub struct Explorer {
  design_space: DesignSpace,
  options: ExplorerOptions,
  strategy: ExplorationStrategy,
}

impl Explorer {
  pub fn new(design_space: DesignSpace, options: ExplorerOptions) -> Self {
    let strategy = match options.strategy.as_str() {
      "naive" => ExplorationStrategy::Naive,
      "optimize" => ExplorationStrategy::Optimize,
      _ => ExplorationStrategy::Naive,
    };

    Self {
      design_space,
      options,
      strategy,
    }
  }

  /// Generate all configurations according to the design space and options
  pub fn generate_configs(
    &self,
  ) -> Result<Vec<Config>, Box<dyn std::error::Error>> {
    // Get benchmarks to run
    let benchmarks = self.get_benchmarks()?;

    // Generate configurations based on strategy
    let configs = match self.strategy {
      ExplorationStrategy::Naive => self.generate_naive_configs(&benchmarks)?,
      ExplorationStrategy::Optimize => {
        self.generate_optimized_configs(&benchmarks)?
      }
    };

    Ok(configs)
  }

  fn get_benchmarks(
    &self,
  ) -> Result<Vec<Benchmark>, Box<dyn std::error::Error>> {
    let mut benchmarks = Vec::new();

    for benchmark_config in &self.options.benchmarks {
      if benchmark_config.len() >= 3 {
        let rvsdg_path = self.resolve_path(&benchmark_config[0])?;
        let profile_path = self.resolve_path(&benchmark_config[1])?;
        let workspace_dir = self.resolve_path(&benchmark_config[2])?;

        benchmarks.push(Benchmark {
          rvsdg_path,
          profile_path,
          workspace_dir,
        });
      }
    }

    Ok(benchmarks)
  }

  fn resolve_path(
    &self,
    path: &str,
  ) -> Result<String, Box<dyn std::error::Error>> {
    if path.starts_with("<") && path.ends_with(">") {
      // Skip template paths
      return Ok(path.to_string());
    }

    // Apply path prefix if specified
    if let Some(prefix) = self.options.path_prefix.first() {
      if prefix == "$pwd" {
        return Ok(path.to_string());
      } else {
        return Ok(format!("{}/{}", prefix, path));
      }
    }

    Ok(path.to_string())
  }

  fn generate_naive_configs(
    &self,
    benchmarks: &[Benchmark],
  ) -> Result<Vec<Config>, Box<dyn std::error::Error>> {
    let mut configs = Vec::new();
    let base_app_config_template = load_config(&self.options.default_config)?;

    let coi = &self.options.coi;
    let should_explore_phase =
      coi.iter().any(|c| c.starts_with("phase_config"));
    let should_explore_liblearn =
      coi.iter().any(|c| c.starts_with("liblearn_config"));
    let should_explore_extract =
      coi.iter().any(|c| c.starts_with("extract_config"));
    let should_explore_vectorize =
      coi.iter().any(|c| c.starts_with("vectorize_config"));
    let should_explore_ci_encoding =
      coi.iter().any(|c| c.starts_with("ci_encoding_config"));

    for benchmark in benchmarks {
      if benchmark.rvsdg_path.starts_with("<") {
        continue; // Skip template benchmarks
      }

      let benchmark_name_part =
        self.extract_benchmark_name(&benchmark.rvsdg_path);
      log::info!(
        "Generating configurations for benchmark: {}",
        benchmark_name_part
      );

      let get_config_from_isax_config = |options: Vec<(ISAXConfig, String)>| -> Result<
        Vec<Config>,
        Box<dyn std::error::Error>,
      > {
        let mut configs = Vec::new();
        for (isax_config, config_identifier) in options {
          // Finalize AppConfig settings dependent on identifier
          let mut current_app_config = base_app_config_template.clone();
          current_app_config.rvsdg_path = benchmark.rvsdg_path.clone();
          current_app_config.profile_path = benchmark.profile_path.clone();
          current_app_config.isax_config = isax_config;
          // 需要加工一下config_identifier,在前面加入benchmark的名字
          if config_identifier.is_empty() {
            continue;
          }
          let config_identifier =
            format!("{}_{}", benchmark_name_part, config_identifier);
          let mut config_specific_workspace_dir =
            PathBuf::from(&benchmark.workspace_dir);
          config_specific_workspace_dir.push(&config_identifier);
          current_app_config.workspace_dir =
            config_specific_workspace_dir.to_string_lossy().into_owned();
          current_app_config.log_file = format!("{}.json", config_identifier); // For ReportRecorder

          self.prepare_config_environment_and_serialize(&current_app_config)?;

          configs.push(Config {
            config_identifier: config_identifier.clone(),
            app_config: current_app_config,
            benchmark: benchmark.clone(),
          });
        }
        Ok(configs)
      };
      // 0. Generate base configuration
      let base_name = format!("default").to_string();
      configs.extend(get_config_from_isax_config(vec![(
        base_app_config_template.isax_config.clone(),
        base_name,
      )])?);

      // 1. Generate Phase Options
      let phase_options = self.collect_phase_options(
        &base_app_config_template.isax_config,
        should_explore_phase,
      );
      // println!("Total phase options: {}", phase_options.len());
      configs.extend(get_config_from_isax_config(phase_options)?);

      // 2. Generate Liblearn Options
      let liblearn_options = self.collect_liblearn_options(
        &base_app_config_template.isax_config,
        should_explore_liblearn,
      );
      // println!("Total liblearn options: {}", liblearn_options.len());
      configs.extend(get_config_from_isax_config(liblearn_options)?);

      // 3. Generate Extract Options
      let extract_options = self.collect_extract_options(
        &base_app_config_template.isax_config,
        should_explore_extract,
      );
      // println!("Total extract options: {}", extract_options.len());
      configs.extend(get_config_from_isax_config(extract_options)?);

      // // 4. Generate Vectorize Options
      // let vectorize_options = self.collect_vectorize_options(
      //   &base_app_config_template.isax_config,
      //   should_explore_vectorize,
      // );
      // // println!("Total vectorize options: {}", vectorize_options.len());
      // configs.extend(get_config_from_isax_config(vectorize_options)?);

      // 5. Generate CI Encoding Options
      let ci_encoding_options = self.collect_ci_encoding_options(
        &base_app_config_template.isax_config,
        should_explore_ci_encoding,
      );
      // println!("Total CI encoding options: {}", ci_encoding_options.len());
      configs.extend(get_config_from_isax_config(ci_encoding_options)?);
    }
    Ok(configs)
  }

  // Helper function to collect phase options
  fn collect_phase_options(
    &self,
    base_phase_config: &ISAXConfig,
    should_explore: bool,
  ) -> Vec<(ISAXConfig, String)> {
    let mut options = Vec::new();
    if !should_explore {
      options.push((base_phase_config.clone(), "".to_string()));
      return options;
    }

    let space = &self.design_space.phase_config;
    if space.modes.is_empty()
      || space.vectorize.is_empty()
      || space.phases.is_empty()
    {
      // If any dimension of exploration is empty, effectively don't explore
      // phase space beyond base
      options.push((base_phase_config.clone(), "".to_string()));
      return options;
    }

    for mode_str in &space.modes {
      for vectorize_str in &space.vectorize {
        for phase in &space.phases {
          // vectorize不允许其他模式
          if vectorize_str == "enable" {
            if mode_str != "layered" {
              continue;
            }
          }
          let mut current_phase_config = base_phase_config.clone();
          current_phase_config.phase_config.mode = match mode_str.as_str() {
            "saturating" => crate::runner::PhaseMode::Saturating,
            "size_decrease" => crate::runner::PhaseMode::SizeDecrease,
            "cyclic" => crate::runner::PhaseMode::Cyclic,
            "mixed" => crate::runner::PhaseMode::Mixed,
            "none" => crate::runner::PhaseMode::None,
            "layered" => crate::runner::PhaseMode::Layered,
            _ => {
              log::warn!(
                "Unknown phase mode '{}', defaulting to Mixed.",
                mode_str
              );
              crate::runner::PhaseMode::Mixed
            }
          };
          current_phase_config.phase_config.enable_vectorize_phase =
            vectorize_str == "enable";
          current_phase_config.phase_config.phases = *phase as usize;

          let id = format!(
            "mode_{}_vec_{}_phases_{}",
            mode_str,
            translate_able_to_symbol(vectorize_str),
            phase
          );
          // 跳过default
          if current_phase_config == *base_phase_config {
            continue;
          }
          options.push((current_phase_config, id));
        }
      }
    }

    if options.is_empty() {
      // Fallback if loops didn't run
      options.push((base_phase_config.clone(), "".to_string()));
    }
    options
  }

  // fn collect_vectorize_options(
  //   &self,
  //   base_vectorize_config: &ISAXConfig,
  //   should_explore: bool,
  // ) -> Vec<(ISAXConfig, String)> {
  //   let mut options = Vec::new();
  //   if !should_explore
  //     || self.design_space.vectorize_config.max_vec_len.is_empty()
  //   // || !base_vectorize_config.phase_config.enable_vectorize_phase
  //   {
  //     options.push((base_vectorize_config.clone(), "".to_string()));
  //     return options;
  //   }
  //   let mut new_base_vectorize_config = base_vectorize_config.clone();
  //   new_base_vectorize_config
  //     .phase_config
  //     .enable_vectorize_phase = true;

  //   let space = &self.design_space.vectorize_config;

  //   for max_vec_len in &space.max_vec_len {
  //     let mut current_vectorize_config = new_base_vectorize_config.clone();
  //     current_vectorize_config.vectorize_config.max_vec_len =
  //       *max_vec_len as usize;

  //     // Construct ID
  //     let id = format!("max_vec_len_{}", max_vec_len);
  //     // If the config is the same as base, skip it
  //     if current_vectorize_config == *base_vectorize_config {
  //       continue;
  //     }
  //     options.push((current_vectorize_config, id));
  //   }

  //   options
  // }

  fn collect_ci_encoding_options(
    &self,
    base_ci_encoding_config: &ISAXConfig,
    should_explore: bool,
  ) -> Vec<(ISAXConfig, String)> {
    let mut options = Vec::new();
    if !should_explore
      || self
        .design_space
        .ci_encoding_config
        .enable_packed_access
        .is_empty()
    {
      options.push((base_ci_encoding_config.clone(), "".to_string()));
      return options;
    }

    let space = &self.design_space.ci_encoding_config;

    // using pa, pg, pn for packed access, register grouping, and
    // register neighboring respectively
    // using Cartesian product to explore combinations
    for pa in &space.enable_packed_access {
      for pg in &space.enable_register_grouping {
        for pn in &space.enable_register_neighboring {
          let mut current_ci_encoding_config = base_ci_encoding_config.clone();
          current_ci_encoding_config
            .ci_encoding_config
            .packed_access
            .enabled = *pa;
          current_ci_encoding_config
            .ci_encoding_config
            .register_grouping
            .enabled = *pg;
          current_ci_encoding_config
            .ci_encoding_config
            .register_neighboring
            .enabled = *pn;

          // if pg is enabled, we need to set hand_bits
          if *pg {
            for hand_bits in &space.grouping_hand_bits {
              current_ci_encoding_config
                .ci_encoding_config
                .register_grouping
                .hand_bits = *hand_bits as u8;
              // Construct ID
              let id = format!(
                "pa_{}_pg_{}_hand_{}_pn_{}",
                translate_bool_to_symbol(*pa),
                translate_bool_to_symbol(*pg),
                hand_bits,
                translate_bool_to_symbol(*pn)
              );
              options.push((current_ci_encoding_config.clone(), id));
            }
          } else {
            // Construct ID
            let id = format!(
              "pa_{}_pg_{}_pn_{}",
              translate_bool_to_symbol(*pa),
              translate_bool_to_symbol(*pg),
              translate_bool_to_symbol(*pn)
            );
            // 跳过default
            if current_ci_encoding_config == *base_ci_encoding_config {
              continue;
            }
            options.push((current_ci_encoding_config, id));
          }
        }
      }
    }
    if options.is_empty() {
      // Fallback if loops didn't run
      options.push((base_ci_encoding_config.clone(), "".to_string()));
    }
    options
  }

  // Helper function to collect liblearn options
  fn collect_liblearn_options(
    &self,
    base_liblearn_config: &ISAXConfig,
    should_explore: bool,
  ) -> Vec<(ISAXConfig, String)> {
    let mut options = Vec::new();
    if !should_explore {
      options.push((base_liblearn_config.clone(), "".to_string()));
      return options;
    }

    let space = &self.design_space.liblearn_config;

    // Create iterators for each parameter, using base if space is empty for
    // that param

    let au_merge_iter = if space.au_merge.is_empty() {
      vec![(
        base_liblearn_config.liblearn_config.au_merge_mod.clone(),
        "".to_string(),
      )]
    } else {
      space
        .au_merge
        .iter()
        .map(|s_val| {
          (
            match s_val.as_str() {
              "cartesian" => babble::runner::AUMergeMod::Cartesian,
              "boundary" => babble::runner::AUMergeMod::Boundary,
              "kd" => babble::runner::AUMergeMod::Kd,
              "random" => babble::runner::AUMergeMod::Random,
              _ => {
                log::warn!(
                  "Unknown liblearn au_merge_mod '{}', defaulting to Greedy.",
                  s_val
                );
                babble::runner::AUMergeMod::Boundary
              }
            },
            format!("merge_{}", s_val),
          )
        })
        .collect()
    };

    let costfunction = if space.au_cost.is_empty() {
      vec![(
        base_liblearn_config.liblearn_config.cost.clone(),
        "".to_string(),
      )]
    } else {
      space
        .au_cost
        .iter()
        .map(|s_val| {
          (
            match s_val.as_str() {
              "delay" => babble::runner::LiblearnCost::Delay,
              "size" => babble::runner::LiblearnCost::Size,
              "latencygainarea" => {
                babble::runner::LiblearnCost::LatencyGainArea
              }
              _ => {
                log::warn!(
                  "Unknown liblearn cost function '{}', defaulting to Delay.",
                  s_val
                );
                babble::runner::LiblearnCost::Delay
              }
            },
            format!("cost_{}", s_val),
          )
        })
        .collect()
    };

    let sample_num_iter = if space.au_merge_sample_num.is_empty() {
      vec![(
        base_liblearn_config.liblearn_config.sample_num,
        "".to_string(),
      )]
    } else {
      space
        .au_merge_sample_num
        .iter()
        .map(|&val| (val as usize, format!("sample_{}", val)))
        .collect()
    };

    let au_enum_iter = if space.au_enum.is_empty() {
      vec![(
        base_liblearn_config.liblearn_config.enum_mode.clone(),
        "".to_string(),
      )]
    } else {
      space
        .au_enum
        .iter()
        .map(|s_val| {
          (
            match s_val.as_str() {
              "all" => babble::runner::EnumMode::All,
              "pruning_vanilla" => babble::runner::EnumMode::PruningVanilla,
              "pruning_gold" => babble::runner::EnumMode::PruningGold,
              "cluster_test" => babble::runner::EnumMode::ClusterTest,
              _ => {
                log::warn!("Unknown enum_mode '{}', defaulting to All.", s_val);
                babble::runner::EnumMode::All
              }
            },
            format!("enum_{}", s_val),
          )
        })
        .collect()
    };

    for (merge_val, merge_id) in &au_merge_iter {
      for (cs, cs_id) in &costfunction {
        for (enum_val, enum_id) in &au_enum_iter {
          if matches!(merge_val, AUMergeMod::Random)
            || matches!(merge_val, AUMergeMod::Kd)
          {
            for (sample_val, sample_id) in &sample_num_iter {
              let mut current_liblearn_config = base_liblearn_config.clone();
              current_liblearn_config.liblearn_config.au_merge_mod =
                merge_val.clone();
              current_liblearn_config.liblearn_config.sample_num = *sample_val;
              current_liblearn_config.liblearn_config.enum_mode =
                enum_val.clone();
              current_liblearn_config.liblearn_config.cost = cs.clone();
              // Other fields like hamming_threshold, jaccard_threshold,
              // max_lib_size remain from base.

              let id_parts: Vec<String> = [merge_id, cs_id, sample_id, enum_id]
                .iter()
                .filter(|s_ref_ref| !s_ref_ref.is_empty())
                .map(|s_ref_ref| (*s_ref_ref).clone())
                .collect();
              options.push((current_liblearn_config, id_parts.join("_")));
            }
          } else {
            // 不需要sample_num
            let mut current_liblearn_config = base_liblearn_config.clone();
            current_liblearn_config.liblearn_config.au_merge_mod =
              merge_val.clone();
            current_liblearn_config.liblearn_config.enum_mode =
              enum_val.clone();
            current_liblearn_config.liblearn_config.cost = cs.clone();
            let id_parts: Vec<String> = [merge_id, cs_id, enum_id]
              .iter()
              .filter(|s_ref_ref| !s_ref_ref.is_empty())
              .map(|s_ref_ref| (*s_ref_ref).clone())
              .collect();
            // 跳过default
            if current_liblearn_config == *base_liblearn_config {
              continue;
            }
            options.push((current_liblearn_config, id_parts.join("_")));
          }
        }
      }
    }
    if options.is_empty() {
      // Fallback if loops didn't run (e.g. all space sub-vectors were empty,
      // though logic above tries to prevent this)
      options.push((base_liblearn_config.clone(), "".to_string()));
    }
    options
  }

  // Helper function to collect extract options
  fn collect_extract_options(
    &self,
    base_extract_config: &ISAXConfig,
    should_explore: bool,
  ) -> Vec<(ISAXConfig, String)> {
    let mut options = Vec::new();
    if !should_explore || self.design_space.extract_config.is_none() {
      options.push((base_extract_config.clone(), "".to_string()));
      return options;
    }

    let space = self.design_space.extract_config.as_ref().unwrap();
    if space.beams.is_empty() || space.clock_period.is_empty() {
      // If any dimension of exploration is empty, effectively don't explore
      // extract space beyond base
      options.push((base_extract_config.clone(), "".to_string()));
      return options;
    }
    for beam in &space.beams {
      for clock_period in &space.clock_period {
        let mut current_extract_config = base_extract_config.clone();
        // inter and final beams are the same in this context
        current_extract_config.extract_config.final_beams = *beam as usize;
        current_extract_config.extract_config.inter_beams = *beam as usize;
        current_extract_config.extract_config.clock_period =
          *clock_period as usize;

        // Construct ID
        let id = format!("beams_{}_clock_{}", beam, clock_period);
        // 跳过default
        if current_extract_config == *base_extract_config {
          continue;
        }
        options.push((current_extract_config, id));
      }
    }

    if options.is_empty() {
      // Fallback if loops didn't run
      options.push((base_extract_config.clone(), "".to_string()));
    }
    options
  }

  fn generate_optimized_configs(
    &self,
    benchmarks: &[Benchmark],
  ) -> Result<Vec<Config>, Box<dyn std::error::Error>> {
    // TODO: Implement optimization-based configuration generation
    // For now, fall back to naive approach
    self.generate_naive_configs(benchmarks)
  }

  fn extract_benchmark_name(&self, path: &str) -> String {
    Self::extract_benchmark_name_static(path)
  }

  fn extract_benchmark_name_static(path: &str) -> String {
    Path::new(path)
      .file_stem()
      .unwrap_or_default()
      .to_string_lossy()
      .to_string()
  }

  fn prepare_config_environment_and_serialize(
    &self,
    app_config: &AppConfig,
  ) -> Result<PathBuf, Box<dyn std::error::Error>> {
    let config_specific_workspace_dir =
      PathBuf::from(&app_config.workspace_dir);

    fs::create_dir_all(&config_specific_workspace_dir).map_err(|e| {
      format!(
        "Failed to create config_specific_workspace_dir {:?}: {}",
        config_specific_workspace_dir, e
      )
    })?;

    let learned_libs_dir = config_specific_workspace_dir.join("learned_libs");
    fs::create_dir_all(&learned_libs_dir).map_err(|e| {
      format!(
        "Failed to create learned_libs directory {:?}: {}",
        learned_libs_dir, e
      )
    })?;

    log::debug!(
      "Created config_specific_workspace_dir: {:?}",
      config_specific_workspace_dir
    );
    log::debug!("Created learned_libs directory: {:?}", learned_libs_dir);

    let serialized_config_path =
      config_specific_workspace_dir.join("config.toml");

    let config_content = self.serialize_config(app_config)?;
    fs::write(&serialized_config_path, config_content).map_err(|e| {
      format!(
        "Failed to write serialized config file {:?}: {}",
        serialized_config_path, e
      )
    })?;

    log::debug!(
      "Successfully wrote serialized config file: {:?}",
      serialized_config_path
    );

    Ok(serialized_config_path)
  }

  fn serialize_config(
    &self,
    config: &AppConfig,
  ) -> Result<String, Box<dyn std::error::Error>> {
    // Convert AppConfig to TOML format
    // This is a simplified version - you might want to use a proper TOML
    // serializer
    let content = format!(
      r#"rvsdg_path = "{}"
profile_path = "{}"
workspace_dir = "{}"
log_file = "{}"

[isax_config]
max_frontiers_to_keep = {}

[isax_config.phase_config]
mode = "{}"
phases = {}
enable_vectorize_phase = {}
enable_meta_au_phase = {}
enable_widths_merge = {}

[isax_config.extract_config]
final_beams = {}
inter_beams = {}
lib_iter_limit = {}
lps = {}
learn_constants = {}
max_arity = {}
clock_period = {}

[isax_config.liblearn_config]
cost = "{}"
au_merge_mod = "{}"
enum_mode = "{}"
sample_num = {}
hamming_threshold = {}
jaccard_threshold = {}
max_libs = {}
min_lib_size = {}
max_lib_size = {}

[isax_config.vectorize_config]
enable_gather = {}
enable_shuffle = {}
enable_post_check = {}
max_vec_len = {}
lift_rules = "{}"
lower_rules = "{}"
transform_rules = "{}"

[isax_config.op_pack_config]
prune_eclass_pair = {}
learn_trivial = {}
num_meta_au_mask = {}
max_operation = {}

[isax_config.ci_encoding_config]
max_total_bits = {}
default_bits_per_register = {}

[isax_config.ci_encoding_config.packed_access]
enabled = {}
max_packed_width = {}
pack_sizes = [{}]

[isax_config.ci_encoding_config.register_grouping]
enabled = {}
hand_bits = {}
dis_bits = {}
max_hands = {}
allow_override = {}
override_bits = {}

[isax_config.ci_encoding_config.register_neighboring]
enabled = {}
neighbor_extra_bits = {}
max_neighbors = {}


[isax_config.find_pack_config]
prune_similar = {}
learn_trivial = {}
"#,
      config.rvsdg_path,
      config.profile_path,
      config.workspace_dir,
      config.log_file,
      config.isax_config.max_frontiers_to_keep,
      match config.isax_config.phase_config.mode {
        crate::runner::PhaseMode::Saturating => "saturating",
        crate::runner::PhaseMode::SizeDecrease => "size_decrease",
        crate::runner::PhaseMode::Cyclic => "cyclic",
        crate::runner::PhaseMode::Mixed => "mixed",
        crate::runner::PhaseMode::None => "none",
        crate::runner::PhaseMode::Layered => "layered",
      },
      config.isax_config.phase_config.phases,
      config.isax_config.phase_config.enable_vectorize_phase,
      config.isax_config.phase_config.enable_meta_au_phase,
      config.isax_config.phase_config.enable_widths_merge,
      config.isax_config.extract_config.final_beams,
      config.isax_config.extract_config.inter_beams,
      config.isax_config.extract_config.lib_iter_limit,
      config.isax_config.extract_config.lps,
      config.isax_config.extract_config.learn_constants,
      config
        .isax_config
        .extract_config
        .max_arity
        .map_or("null".to_string(), |v| v.to_string()),
      config.isax_config.extract_config.clock_period,
      match config.isax_config.liblearn_config.cost {
        babble::runner::LiblearnCost::Delay => "delay",
        babble::runner::LiblearnCost::Size => "size",
        babble::runner::LiblearnCost::LatencyGainArea => "latencygainarea",
      },
      match config.isax_config.liblearn_config.au_merge_mod {
        babble::runner::AUMergeMod::Random => "random",
        babble::runner::AUMergeMod::Kd => "kd",
        babble::runner::AUMergeMod::Boundary => "boundary",
        babble::runner::AUMergeMod::Cartesian => "cartesian",
      },
      match config.isax_config.liblearn_config.enum_mode {
        babble::runner::EnumMode::All => "all",
        babble::runner::EnumMode::PruningVanilla => "pruning_vanilla",
        babble::runner::EnumMode::PruningGold => "pruning_gold",
        babble::runner::EnumMode::ClusterTest => "cluster_test",
      },
      config.isax_config.liblearn_config.sample_num,
      config.isax_config.liblearn_config.hamming_threshold,
      config.isax_config.liblearn_config.jaccard_threshold,
      config.isax_config.liblearn_config.max_libs,
      config.isax_config.liblearn_config.min_lib_size,
      config.isax_config.liblearn_config.max_lib_size,
      config.isax_config.vectorize_config.enable_gather,
      config.isax_config.vectorize_config.enable_shuffle,
      config.isax_config.vectorize_config.enable_post_check,
      config.isax_config.vectorize_config.max_vec_len,
      config
        .isax_config
        .vectorize_config
        .lift_rules
        .as_ref()
        .map_or("".to_string(), |v| v.clone()),
      config
        .isax_config
        .vectorize_config
        .lower_rules
        .as_ref()
        .map_or("".to_string(), |v| v.clone()),
      config
        .isax_config
        .vectorize_config
        .transform_rules
        .as_ref()
        .map_or("".to_string(), |v| v.clone()),
      config.isax_config.op_pack_config.prune_eclass_pair,
      config.isax_config.op_pack_config.learn_trivial,
      config.isax_config.op_pack_config.num_meta_au_mask,
      config.isax_config.op_pack_config.max_operation,
      config.isax_config.ci_encoding_config.max_total_bits,
      config
        .isax_config
        .ci_encoding_config
        .default_bits_per_register,
      config.isax_config.ci_encoding_config.packed_access.enabled,
      config
        .isax_config
        .ci_encoding_config
        .packed_access
        .max_packed_width,
      config
        .isax_config
        .ci_encoding_config
        .packed_access
        .pack_sizes
        .iter()
        .map(|v| v.to_string())
        .collect::<Vec<_>>()
        .join(", "),
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .enabled,
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .hand_bits,
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .dis_bits,
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .max_hands,
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .allow_override,
      config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .override_bits,
      config
        .isax_config
        .ci_encoding_config
        .register_neighboring
        .enabled,
      config
        .isax_config
        .ci_encoding_config
        .register_neighboring
        .neighbor_extra_bits,
      config
        .isax_config
        .ci_encoding_config
        .register_neighboring
        .max_neighbors,
      config.isax_config.find_pack_config.prune_similar,
      config.isax_config.find_pack_config.learn_trivial,
    );

    Ok(content)
  }

  fn setup_config_logging(&self, log_file: &PathBuf, config: &Config) {
    Self::setup_config_logging_static(log_file, config);
  }

  fn setup_config_logging_static(log_file: &PathBuf, config: &Config) {
    // Write a header to the log file indicating which configuration is starting
    if let Ok(mut file) = std::fs::OpenOptions::new()
      .create(true)
      .write(true)
      .truncate(true)
      .open(log_file)
    {
      let _ = writeln!(
        file,
        "=== Experiment Log for Configuration: {} ===",
        config.config_identifier
      );
      let _ =
        writeln!(file, "Benchmark RVSDG: {}", config.app_config.rvsdg_path);
      let _ = writeln!(
        file,
        "Benchmark Profile: {}",
        config.app_config.profile_path
      );
      let _ = writeln!(
        file,
        "Workspace (Config Specific): {}",
        config.app_config.workspace_dir
      );
      let _ = writeln!(
        file,
        "Workspace (Benchmark Base): {}",
        config.benchmark.workspace_dir
      );
      let serialized_config_toml_path =
        PathBuf::from(&config.app_config.workspace_dir).join("config.toml");
      let _ = writeln!(
        file,
        "Serialized Config File: {:?}",
        serialized_config_toml_path
      );
      let _ = writeln!(
        file,
        "Started at: {}",
        chrono::Local::now().format("%Y-%m-%d %H:%M:%S")
      );
      let _ = writeln!(file, "{}", "=".repeat(60));
      let _ = writeln!(file, "");
    }
  }
}

/// Results from running experiments
#[derive(Debug, Serialize, Clone)]
pub struct ExperimentResults {
  pub config_name: String,
  pub benchmark_name: String,
  pub success: bool,
  pub error_message: Option<String>,
  pub run_time_ms: u64,
  pub memory_mb: f64,
  // pub memory_usage_gb: f64,
  pub frontiers: Vec<FrontierEntry>,
  // Configuration parameters as separate columns
  pub phase_mode: Option<String>,
  pub vectorize: Option<String>,
  pub meta_au: Option<String>,
  pub phases: Option<u32>,
  pub max_vec_len: Option<u32>,
  pub enable_packed_access: Option<bool>,
  pub enable_register_grouping: Option<bool>,
  pub grouping_hand_bits: Option<u8>,
  pub enable_register_neighboring: Option<bool>,
  pub au_merge: Option<String>,
  pub au_merge_sample_num: Option<usize>,
  pub au_enum: Option<String>,
  pub extract_beams: Option<usize>,
  pub extract_clock_period: Option<usize>,

  // Additional metrics stored as key-value pairs
  pub metrics: HashMap<String, String>,
}

/// Runner that executes configurations and collects results
///
/// The EvalRunner supports both sequential and concurrent execution of
/// experiments.
///
/// # Examples
///
/// ```rust
/// // Create a runner with default concurrency (4 workers)
/// let mut runner = EvalRunner::new(explorer, results_path);
///
/// // Create a runner with custom concurrency
/// let mut runner = EvalRunner::new_with_concurrency(explorer, results_path, 8);
///
/// // Run experiments concurrently (default)
/// let results = runner.run()?;
///
/// // Run experiments sequentially
/// let results = runner.run_with_options(false)?;
///
/// // Change concurrency at runtime
/// runner.set_max_concurrent(16);
/// ```
#[derive(Debug, Clone)]
pub struct EvalRunner {
  explorer: Explorer,
  results_path: PathBuf,
  max_concurrent: usize,
  progress_bar: Option<ProgressBar>,
}

impl EvalRunner {
  pub fn new(explorer: Explorer) -> Self {
    Self::new_with_concurrency(explorer, 4)
  }

  pub fn new_with_concurrency(
    explorer: Explorer,
    max_concurrent: usize,
  ) -> Self {
    // Automatically determine results path as workspace/result.csv
    let results_path = PathBuf::from("cimg-enum.csv");
    Self {
      explorer,
      results_path,
      max_concurrent,
      progress_bar: None,
    }
  }

  /// Run all generated configurations and collect results
  pub fn run(
    &mut self,
  ) -> Result<Vec<ExperimentResults>, Box<dyn std::error::Error>> {
    self.run_with_options(true)
  }

  /// Run with option to use concurrent or sequential execution
  pub fn run_with_options(
    &mut self,
    use_concurrent: bool,
  ) -> Result<Vec<ExperimentResults>, Box<dyn std::error::Error>> {
    let configs = self.explorer.generate_configs()?;

    if use_concurrent && self.max_concurrent > 1 {
      // Only show high-level progress to console
      println!(
        "Generated {} configurations to run with max {} concurrent jobs",
        configs.len(),
        self.max_concurrent
      );

      // Use concurrent execution
      let results = self.run_concurrent(configs)?;
      self.save_results(&results)?;
      Ok(results)
    } else {
      // Use sequential execution
      println!(
        "Generated {} configurations to run sequentially",
        configs.len()
      );
      let results = self.run_sequential(configs)?;
      self.save_results(&results)?;
      Ok(results)
    }
  }

  /// Run configurations sequentially (original behavior)
  fn run_sequential(
    &self,
    configs: Vec<Config>,
  ) -> Result<Vec<ExperimentResults>, Box<dyn std::error::Error>> {
    let mut results = Vec::new();

    for (i, config) in configs.iter().enumerate() {
      // Minimal console output - just progress
      println!(
        "Running configuration {}/{}: {}",
        i + 1,
        configs.len(),
        config.config_identifier
      );

      let result = Self::run_single_config_static(config);

      // Minimal console feedback
      if result.success {
        let average_gain =
          result.frontiers.iter().map(|f| f.gain).sum::<usize>() as f64
            / result.frontiers.len() as f64;
        println!("  ✓ Success (average_perf: {})", average_gain);
      } else {
        println!(
          "  ✗ Failed: {}",
          result.error_message.as_deref().unwrap_or("Unknown error")
        );
      }

      results.push(result);
    }

    Ok(results)
  }

  /// Run configurations concurrently using Crossbeam's thread pool
  fn run_concurrent(
    &self,
    configs: Vec<Config>,
  ) -> Result<Vec<ExperimentResults>, Box<dyn std::error::Error>> {
    let total_configs = configs.len();

    if total_configs == 0 {
      return Ok(Vec::new());
    }

    // Create progress bar
    let pb = ProgressBar::new(total_configs as u64);
    pb.set_style(
      ProgressStyle::default_bar()
        .template("{spinner:.green} [{elapsed_precise}] [{bar:40.cyan/blue}] {pos}/{len} ({eta})")
        .unwrap()
        .progress_chars("#>-"),
    );

    // Create channels for communication
    let (tx, rx) = bounded::<ExperimentResults>(total_configs);
    let results = Arc::new(Mutex::new(Vec::new()));
    let completed_count = Arc::new(Mutex::new(0usize));
    let pb = Arc::new(Mutex::new(pb));

    // Clone the receiver end for collecting results
    let results_clone = Arc::clone(&results);
    let completed_clone = Arc::clone(&completed_count);
    let pb_clone = Arc::clone(&pb);

    // Spawn result collector thread
    let collector_handle = std::thread::spawn(move || {
      for result in rx {
        let mut results_guard = results_clone.lock().unwrap();
        let mut count_guard = completed_clone.lock().unwrap();
        let pb_guard = pb_clone.lock().unwrap();

        results_guard.push(result.clone());
        *count_guard += 1;
        pb_guard.inc(1);

        // Print result to stdout
        if result.success {
          let average_gain =
            result.frontiers.iter().map(|f| f.gain).sum::<usize>() as f64
              / result.frontiers.len() as f64;
          println!(
            "✓ {}: Completed with average_perf {:.2} (runtime: {}ms, memory: {:.2}MB)",
            result.config_name,
            average_gain,
            result.run_time_ms,
            result.memory_mb
          );
        } else {
          println!(
            "✗ {}: Failed - {}",
            result.config_name,
            result.error_message.as_deref().unwrap_or("Unknown error")
          );
        }

        drop(count_guard);
        drop(results_guard);
        drop(pb_guard);
      }
    });

    // Create a thread pool with limited workers
    let configs = Arc::new(configs);
    let config_index = Arc::new(Mutex::new(0usize));
    let actual_workers = std::cmp::min(self.max_concurrent, total_configs);

    println!(
      "Starting {} worker threads for {} configurations",
      actual_workers, total_configs
    );

    // Use Crossbeam's thread scope for better thread management
    crossbeam::thread::scope(|scope| {
      for worker_id in 0..actual_workers {
        let configs_clone = Arc::clone(&configs);
        let config_index_clone = Arc::clone(&config_index);
        let tx_clone = tx.clone();
        let worker_pb_clone = Arc::clone(&pb); // Clone pb (the Arc<Mutex<ProgressBar>>) for this worker

        scope.spawn(move |_| {
          loop {
            // Get the next configuration to process
            let config_to_process = {
              let mut index_guard = config_index_clone.lock().unwrap();
              if *index_guard >= configs_clone.len() {
                break; // No more configs to process
              }
              let current_index = *index_guard;
              *index_guard += 1;
              drop(index_guard);
              current_index
            };

            let config = &configs_clone[config_to_process];

            // Report when a configuration starts
            // Lock stdout for printing to avoid garbled output with progress
            // bar
            {
              let pb_guard = worker_pb_clone.lock().unwrap(); // Use the worker-specific clone
              pb_guard.println(format!(
                "🚀 Starting configuration: {} ({} / {})",
                config.config_identifier,
                config_to_process + 1,
                total_configs
              ));
            }

            let start_time = Instant::now();

            // Execute the configuration
            let result = EvalRunner::run_single_config_static(config);
            let run_time = start_time.elapsed();

            // Add detailed metrics
            let mut metrics = result.metrics;
            metrics.insert("worker_id".to_string(), worker_id.to_string());
            metrics.insert(
              "queue_position".to_string(),
              config_to_process.to_string(),
            );
            metrics.insert(
              "actual_run_time_ms".to_string(),
              run_time.as_millis().to_string(),
            );

            let result = ExperimentResults { metrics, ..result };

            // Send result back
            if tx_clone.send(result).is_err() {
              log::error!(
                "Worker {}: Failed to send result to collector",
                worker_id
              );
              break;
            }
          }
        });
      }
    })
    .map_err(|e| format!("Thread pool error: {:?}", e))?;

    // CRITICAL: Drop the main sender so the collector thread knows all senders
    // are done. Without this, the collector thread will wait forever
    // because the main `tx` is still alive even after all worker threads
    // finish (and their `tx_clone`s are dropped). This is what causes the
    // program to hang after completion.
    drop(tx);

    // Wait for collector to finish
    collector_handle
      .join()
      .map_err(|_| "Collector thread panicked")?;

    // Extract results
    let results_guard = results.lock().unwrap();
    let final_results = results_guard.clone();
    drop(results_guard);

    // Finish progress bar
    let pb_guard = pb.lock().unwrap();
    pb_guard.finish_with_message("Concurrent execution completed");

    println!(
      "\nConcurrent execution completed. {} results collected.",
      final_results.len()
    );

    Ok(final_results)
  }

  /// Static version of run_single_config that can be called from worker threads
  fn run_single_config_static(config: &Config) -> ExperimentResults {
    let start_time = std::time::Instant::now();

    // Set up output redirection to the configuration's own directory
    let config_dir = PathBuf::from(&config.app_config.workspace_dir);

    let stdout_file = config_dir.join("stdout.log");
    let stderr_file = config_dir.join("stderr.log");
    let experiment_log_file =
      config_dir.join(format!("{}.log", config.config_identifier));

    // Set up per-configuration logging to file
    Explorer::setup_config_logging_static(&experiment_log_file, config);

    // Create a wrapper script to redirect output and run the configuration
    let result = Self::execute_config_with_redirection_static(
      config,
      &stdout_file,
      &stderr_file,
      &experiment_log_file,
    );

    // let run_time = start_time.elapsed().as_millis() as u64;

    // Extract parameters from AppConfig for ExperimentResults
    let phase_mode_opt =
      Some(match config.app_config.isax_config.phase_config.mode {
        crate::runner::PhaseMode::Saturating => "saturating".to_string(),
        crate::runner::PhaseMode::SizeDecrease => "size_decrease".to_string(),
        crate::runner::PhaseMode::Cyclic => "cyclic".to_string(),
        crate::runner::PhaseMode::Mixed => "mixed".to_string(),
        crate::runner::PhaseMode::None => "none".to_string(),
        crate::runner::PhaseMode::Layered => "layered".to_string(),
      });
    let vectorize_opt = Some(
      if config
        .app_config
        .isax_config
        .phase_config
        .enable_vectorize_phase
      {
        "enable".to_string()
      } else {
        "disable".to_string()
      },
    );
    let meta_au_opt: Option<String> = Some(
      if config
        .app_config
        .isax_config
        .phase_config
        .enable_meta_au_phase
      {
        "enable".to_string()
      } else {
        "disable".to_string()
      },
    );
    let phases_opt =
      Some(config.app_config.isax_config.phase_config.phases as u32);
    let max_vec_len_opt =
      Some(config.app_config.isax_config.vectorize_config.max_vec_len as u32);
    let enable_packed_access_opt = Some(
      config
        .app_config
        .isax_config
        .ci_encoding_config
        .packed_access
        .enabled,
    );
    let enable_register_grouping_opt = Some(
      config
        .app_config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .enabled,
    );
    let grouping_hand_bits_opt = Some(
      config
        .app_config
        .isax_config
        .ci_encoding_config
        .register_grouping
        .hand_bits,
    );
    let enable_register_neighboring_opt = Some(
      config
        .app_config
        .isax_config
        .ci_encoding_config
        .register_neighboring
        .enabled,
    );

    let au_merge_opt = Some(
      match config.app_config.isax_config.liblearn_config.au_merge_mod {
        babble::runner::AUMergeMod::Random => "random".to_string(), /* Assuming this variant exists */
        babble::runner::AUMergeMod::Kd => "kd".to_string(),
        babble::runner::AUMergeMod::Boundary => "boundary".to_string(),
        babble::runner::AUMergeMod::Cartesian => "cartesian".to_string(),
      },
    );
    let au_merge_sample_num_opt =
      Some(config.app_config.isax_config.liblearn_config.sample_num as usize);
    let au_enum_opt = Some(
      match config.app_config.isax_config.liblearn_config.enum_mode {
        babble::runner::EnumMode::All => "all".to_string(),
        babble::runner::EnumMode::PruningVanilla => {
          "pruning_vanilla".to_string()
        }
        babble::runner::EnumMode::PruningGold => "pruning_gold".to_string(),
        babble::runner::EnumMode::ClusterTest => "cluster_test".to_string(),
      },
    );
    let beams_opt =
      Some(config.app_config.isax_config.extract_config.final_beams as usize);
    let clock_period_opt =
      Some(config.app_config.isax_config.extract_config.clock_period as usize);
    match result {
      Ok((frontiers, memory)) => {
        let run_time = start_time.elapsed().as_millis() as u64;

        // Try to read stdout and extract speedup
        let speedup = if stdout_file.exists() {
          match std::fs::read_to_string(&stdout_file) {
            Ok(stdout_content) => {
              Self::extract_speedup_from_stdout(&stdout_content)
            }
            Err(_) => None,
          }
        } else {
          None
        };

        let result = ExperimentResults {
          config_name: config.config_identifier.clone(),
          benchmark_name: Explorer::extract_benchmark_name_static(
            &config.app_config.rvsdg_path,
          ),
          success: true,
          error_message: None,
          run_time_ms: run_time,
          memory_mb: memory,
          frontiers,
          phase_mode: phase_mode_opt,
          vectorize: vectorize_opt,
          meta_au: meta_au_opt,
          phases: phases_opt,
          max_vec_len: max_vec_len_opt,
          enable_packed_access: enable_packed_access_opt,
          enable_register_grouping: enable_register_grouping_opt,
          grouping_hand_bits: grouping_hand_bits_opt,
          enable_register_neighboring: enable_register_neighboring_opt,
          au_merge: au_merge_opt,
          au_merge_sample_num: au_merge_sample_num_opt,
          au_enum: au_enum_opt,
          extract_beams: beams_opt,
          extract_clock_period: clock_period_opt,
          metrics: HashMap::new(),
        };

        let total = result.frontiers.len() as f64;

        let (average_gain, average_speed_up) = if total > 0.0 {
          let (sum_gain, sum_speedup) = result.frontiers.iter().fold(
            (0.0, 0.0),
            |(sum_gain, sum_speedup), entry| {
              (
                sum_gain + entry.gain as f64,
                sum_speedup + entry.speedup as f64,
              )
            },
          );
          (sum_gain / total, sum_speedup / total)
        } else {
          (0.0, 0.0)
        };

        // Log success to configuration's log file
        log_to_config_file_static(
          &experiment_log_file,
          "INFO",
          &format!(
            "Configuration completed successfully with average_perf: {} (runtime: {}ms, memory: {:.2}MB)",
            average_gain, run_time, memory
          ),
        );

        result
      }
      Err(e) => {
        let run_time = start_time.elapsed().as_millis() as u64;
        let result = ExperimentResults {
          config_name: config.config_identifier.clone(),
          benchmark_name: Explorer::extract_benchmark_name_static(
            &config.app_config.rvsdg_path,
          ),
          success: false,
          error_message: Some(e.to_string()),
          run_time_ms: run_time,
          memory_mb: 0.0, // Memory not available on error
          frontiers: Vec::new(),
          phase_mode: None,
          vectorize: None,
          meta_au: None,
          phases: None,
          max_vec_len: None,
          enable_packed_access: None,
          enable_register_grouping: None,
          grouping_hand_bits: None,
          enable_register_neighboring: None,
          au_merge: None,
          au_merge_sample_num: None,
          au_enum: None,
          extract_beams: None,
          extract_clock_period: None,
          metrics: HashMap::new(),
        };

        // Log failure to configuration's log file
        log_to_config_file_static(
          &experiment_log_file,
          "ERROR",
          &format!(
            "Configuration failed after {}ms: {}",
            run_time,
            e.to_string()
          ),
        );

        result
      }
    }
  }

  fn execute_config_with_redirection_static(
    config: &Config,
    stdout_file: &PathBuf,
    stderr_file: &PathBuf,
    experiment_log_file: &PathBuf,
  ) -> Result<(Vec<FrontierEntry>, f64), Box<dyn std::error::Error>> {
    log_to_config_file_static(
      experiment_log_file,
      "INFO",
      &format!("Executing configuration: {}", config.config_identifier),
    );

    if let Err(e) = init_workspace(&config.app_config) {
      log_to_config_file_static(
        experiment_log_file,
        "ERROR",
        &format!(
          "Failed to initialize workspace {}: {}",
          config.app_config.workspace_dir, e
        ),
      );
      return Err(e.into());
    }
    log_to_config_file_static(
      experiment_log_file,
      "INFO",
      &format!("Initialized workspace: {}", config.app_config.workspace_dir),
    );

    // Path to the config.toml file that was serialized by
    // prepare_config_environment_and_serialize
    let serialized_config_toml_path =
      PathBuf::from(&config.app_config.workspace_dir).join("config.toml");

    // Execute using the single binary approach with output capture
    Self::execute_single_config_subprocess_static(
      &serialized_config_toml_path,
      stdout_file,
      stderr_file,
      experiment_log_file,
    )
  }

  fn execute_single_config_subprocess_static(
    config_file_to_run: &Path,
    stdout_file: &PathBuf,
    stderr_file: &PathBuf,
    experiment_log_file: &PathBuf,
  ) -> Result<(Vec<FrontierEntry>, f64), Box<dyn std::error::Error>> {
    log_to_config_file_static(
      experiment_log_file,
      "INFO",
      "Starting subprocess execution",
    );

    log_to_config_file_static(
      experiment_log_file,
      "DEBUG",
      &format!("Using config file for subprocess: {:?}", config_file_to_run),
    );

    // open the stdout and stderr file
    let stdout_capture_file = File::create(stdout_file).map_err(|e| {
      format!("Failed to create stdout_file {:?}: {}", stdout_file, e)
    })?;
    let stderr_capture_file = File::create(stderr_file).map_err(|e| {
      format!("Failed to create stderr_file {:?}: {}", stderr_file, e)
    })?;

    // 限制参数
    // let mem_limit_bytes: u64 = 20 * 1024 * 1024 * 1024; // 20 GB
    // let time_limit_secs: u64 = 3600;

    let mut command = Command::new("systemd-run");
    command
      .arg("--user")
      .arg("--scope")
      .arg("-p")
      .arg("MemoryMax=500G")
      .arg("-p")
      .arg("RuntimeMaxSec=43200s")
      // .arg(std::env::current_exe()?)
      // .arg("single")
      // .arg("--config")
      // .arg(config_file_to_run)
      .arg("/usr/bin/time")
      .arg("-f")
      .arg("PEAK_RSS_KB=%M") // 只输出类似：PEAK_RSS_KB=123456
      .arg(std::env::current_exe()?)
      .arg("single")
      .arg("--config")
      .arg(config_file_to_run)
      .stdout(Stdio::from(stdout_capture_file))
      .stderr(Stdio::from(stderr_capture_file));

    let status = command.status()?;

    log_to_config_file_static(
      experiment_log_file,
      "DEBUG",
      &format!("Subprocess completed with exit code: {:?}", status.code()),
    );

    if status.success() {
      let stdout_content = fs::read_to_string(stdout_file).map_err(|e| {
        format!(
          "Failed to read stdout_file {:?} for parsing cost: {}",
          stdout_file, e
        )
      })?;
      let stderr_content =
        fs::read_to_string(stderr_file).unwrap_or_else(|e| {
          format!("Failed to read stderr_file {:?}: {}", stderr_file, e)
        });
      log_to_config_file_static(
        experiment_log_file,
        "DEBUG",
        &format!("Subprocess stdout content:\n{}", stdout_content),
      );

      let memory =
        Self::extract_rrs_from_stderr(&stderr_content).unwrap_or(0.0);

      // Parse the final cost from the stdout content
      if let Some(pareto_frontier) =
        Self::extract_pareto_frontier_from_stdout(&stdout_content)
      {
        Ok((pareto_frontier, memory))
      } else {
        log_to_config_file_static(
          experiment_log_file,
          "ERROR",
          &format!(
            "Failed to parse final_cost from stdout content of file: {:?}",
            stdout_file
          ),
        );
        Err(
          format!(
            "Failed to parse final_cost from stdout file: {:?}",
            stdout_file
          )
          .into(),
        )
      }
    } else {
      let stderr_content =
        fs::read_to_string(stderr_file).unwrap_or_else(|e| {
          format!("Failed to read stderr_file {:?}: {}", stderr_file, e)
        });
      log_to_config_file_static(
        experiment_log_file,
        "ERROR",
        &format!("Subprocess failed with stderr:\n{}", stderr_content),
      );
      Err(
        format!("Subprocess execution failed. Stderr: {}", stderr_content)
          .into(),
      )
    }
  }

  fn log_to_config_file(&self, log_file: &PathBuf, level: &str, message: &str) {
    log_to_config_file_static(log_file, level, message);
  }

  fn save_results(
    &self,
    results: &[ExperimentResults],
  ) -> Result<(), Box<dyn std::error::Error>> {
    // Create results directory if it doesn't exist
    if let Some(parent) = self.results_path.parent() {
      fs::create_dir_all(parent)?;
    }

    // Convert results to CSV format with all configuration parameters as
    // columns
    let mut csv_content = String::new();

    // Create CSV header with all possible columns for Pandas DataFrame
    // compatibility
    csv_content.push_str(
      "config_name,benchmark_name,success,error_message,run_time_ms,memory_mb,frontiers,",
    );
    csv_content.push_str("phase_mode,vectorize,meta_au,phases,max_vec_len,enable_packed_access,enable_register_grouping,grouping_hand_bits,enable_register_neighboring,au_merge_mode,au_merge_sample_num,au_enum,extract_beams,clock_period\n");

    for result in results {
      // Helper function to format optional values
      let format_opt_str = |opt: &Option<String>| {
        opt.as_ref().map_or("".to_string(), |s| s.clone())
      };

      let format_opt_u32 =
        |opt: &Option<u32>| opt.map_or("".to_string(), |n| n.to_string());

      csv_content.push_str(&format!(
        "{},{},{},{},{},{:.2},\"[{}]\",{},{},{},{},{},{},{},{},{},{},{},{},{},{}\n",
        result.config_name,
        result.benchmark_name,
        result.success,
        result.error_message.as_deref().unwrap_or(" "),
        result.run_time_ms,
        result.memory_mb,
        result
          .frontiers
          .iter()
          .map(|f| f.to_string())
          .collect::<Vec<_>>()
          .join("; "),
        format_opt_str(&result.phase_mode),
        format_opt_str(&result.vectorize),
        format_opt_str(&result.meta_au),
        format_opt_u32(&result.phases),
        format_opt_u32(&result.max_vec_len),
        result.enable_packed_access.unwrap_or(false),
        result.enable_register_grouping.unwrap_or(false),
        result.grouping_hand_bits.unwrap_or(0),
        result.enable_register_neighboring.unwrap_or(false),
        format_opt_str(&result.au_merge),
        result.au_merge_sample_num.unwrap_or(0),
        format_opt_str(&result.au_enum),
        result.extract_beams.unwrap_or(0),
        result.extract_clock_period.unwrap_or(0),
      ));
    }

    fs::write(&self.results_path, csv_content)?;
    println!("Results saved to: {}", self.results_path.display());

    Ok(())
  }

  /// Extract speedup value from stdout content
  fn extract_speedup_from_stdout(stdout_content: &str) -> Option<f32> {
    use regex::Regex;

    // Look for "Speedup: <number>" pattern in stdout
    let re = Regex::new(r"Speedup:\s*([0-9\.eE+-]+)").ok()?;

    // Check each line for the speedup pattern
    for line in stdout_content.lines() {
      if let Some(captures) = re.captures(line) {
        if let Some(speedup_str) = captures.get(1) {
          if let Ok(speedup) = speedup_str.as_str().parse::<f32>() {
            return Some(speedup);
          }
        }
      }
    }

    None
  }
  /// Helper to extract Peak RRS from stderr
  fn extract_rrs_from_stderr(stderr_content: &str) -> Option<f64> {
    use regex::Regex;

    // Look for "PEAK_RSS_KB=<number>" pattern in stderr
    let re = Regex::new(r"PEAK_RSS_KB=(\d+)").ok()?;

    // Check each line for the RRS pattern
    for line in stderr_content.lines() {
      if let Some(captures) = re.captures(line) {
        if let Some(rrs_str) = captures.get(1) {
          if let Ok(rrs) = rrs_str.as_str().parse::<usize>() {
            // 输出用MB 表示
            let rrs = rrs as f64 / 1024.0; // Convert KB to MB
            return Some(rrs);
          }
        }
      }
    }

    None
  }

  /// Helper to extract multiple FrontierEntry from stdout.
  ///
  /// 期望 stdout 中含有类似：
  ///
  /// Pareto Frontier: [
  ///   Gain: 2328, Area: 6438, Speedup: 1.08
  ///   Gain: 2328, Area: 6262, Speedup: 1.08
  ///   Gain: 1688, Area: 6114, Speedup: 1.06
  /// ]
  ///
  /// 注意：项数不固定，可以 0 条或多条；
  /// 支持多行格式，中间可能有空行或前后空白。
  fn extract_pareto_frontier_from_stdout(
    stdout_content: &str,
  ) -> Option<Vec<FrontierEntry>> {
    // 1. 匹配整个 Pareto Frontier 块
    // (?i) 不区分大小写，(?s) 使 . 匹配包括换行在内的所有字符
    // 大致匹配 “Pareto Frontier: [ ... ]”，并捕获中括号之间的内容
    let block_re =
      Regex::new(r"(?is)Pareto Frontier:\s*\[\s*(.*?)\s*\]").ok()?;
    let entry_re = Regex::new(
      // 匹配单条记录，例如 "Gain: 2328, Area: 6438, Speedup: 1.08"
      // 不区分大小写可酌情加 (?i)，但这里字段名一般固定大小写
      r"Gain:\s*(\d+)\s*,\s*Area:\s*(\d+)\s*,\s*Speedup:\s*([0-9eE+\-\.]+)",
    )
    .ok()?;

    // 查找第一个符合 “Pareto Frontier” 块
    if let Some(block_caps) = block_re.captures(stdout_content) {
      let inner = block_caps.get(1).map(|m| m.as_str()).unwrap_or("");
      let mut results = Vec::new();

      // 在 inner 中逐条匹配 entry_re
      for caps in entry_re.captures_iter(inner) {
        // caps[1] -> gain, caps[2] -> area, caps[3] -> speedup
        // 解析 gain
        let gain = match caps.get(1).map(|m| m.as_str()) {
          Some(s) => {
            match s.parse::<usize>() {
              Ok(v) => v,
              Err(e) => {
                warn!("Failed to parse Gain '{}' as usize: {}", s, e);
                continue; // 跳过此条，继续下一条
              }
            }
          }
          None => {
            warn!("No capture group for Gain in Pareto Frontier entry");
            continue;
          }
        };
        // 解析 area
        let area = match caps.get(2).map(|m| m.as_str()) {
          Some(s) => match s.parse::<usize>() {
            Ok(v) => v,
            Err(e) => {
              warn!("Failed to parse Area '{}' as usize: {}", s, e);
              continue;
            }
          },
          None => {
            warn!("No capture group for Area in Pareto Frontier entry");
            continue;
          }
        };
        // 解析 speedup
        let speedup = match caps.get(3).map(|m| m.as_str()) {
          Some(s) => match s.parse::<f32>() {
            Ok(v) => v,
            Err(e) => {
              warn!("Failed to parse Speedup '{}' as f32: {}", s, e);
              continue;
            }
          },
          None => {
            warn!("No capture group for Speedup in Pareto Frontier entry");
            continue;
          }
        };
        results.push(FrontierEntry {
          gain,
          area,
          speedup,
        });
      }

      if results.is_empty() {
        warn!("Found Pareto Frontier block but no valid entries parsed.");
      }
      return Some(results);
    } else {
      // 没有找到 Pareto Frontier 区块
      warn!("Could not find 'Pareto Frontier: [ ... ]' in stdout content.");
      None
    }
  }
}

/// 表示 Pareto Frontier 中的一条记录
#[derive(Debug, Clone, Serialize, Copy)]
pub struct FrontierEntry {
  pub gain: usize,
  pub area: usize,
  pub speedup: f32,
}

impl Display for FrontierEntry {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    write!(
      f,
      "(Gain: {}, Area: {}, Speedup: {:.4})",
      self.gain, self.area, self.speedup
    )
  }
}

/// Load design space from file
pub fn load_design_space(
  path: &str,
) -> Result<DesignSpace, Box<dyn std::error::Error>> {
  let content = fs::read_to_string(path)?;
  Ok(toml::from_str(&content)?)
}

/// Load explorer options from file
pub fn load_explorer_options(
  path: &str,
) -> Result<ExplorerOptions, Box<dyn std::error::Error>> {
  let content = fs::read_to_string(path)?;
  Ok(toml::from_str(&content)?)
}
