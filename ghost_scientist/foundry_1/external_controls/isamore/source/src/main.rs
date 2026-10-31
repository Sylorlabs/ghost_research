use clap::{Parser, Subcommand};

use isamore::common::setup_logger_with_level;
use isamore::experiment::{
  EvalRunner, Explorer, load_design_space, load_explorer_options,
};
use isamore::run_single_config;
use std::fs;
use std::io::{self, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

#[derive(Parser, Debug)]
#[command(author, version, about)]
struct Args {
  #[command(subcommand)]
  command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
  /// Run a single configuration
  Single {
    /// Config file path
    #[arg(short, long, default_value = "src/config.toml")]
    config: PathBuf,
  },
  /// Run experiments with multiple configurations
  Experiment {
    /// Design space file path
    #[arg(short, long, default_value = "design-space.toml")]
    design_space: PathBuf,
    /// Explorer options file path
    #[arg(short, long, default_value = "explorer-options.toml")]
    explorer_options: PathBuf,
    /// Maximum number of concurrent experiments (default: 4, set to 1 for
    /// sequential)
    #[arg(short = 'j', long, default_value = "4")]
    max_concurrent: usize,
    /// Force sequential execution even if max_concurrent > 1
    #[arg(long)]
    sequential: bool,
  },
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
  let args = Args::parse();

  match args.command {
    Commands::Single { config } => {
      println!("Running single configuration: {}", config.display());
      run_single_config(config.to_str().unwrap())?;
    }
    Commands::Experiment {
      design_space,
      explorer_options,
      max_concurrent,
      sequential,
    } => {
      println!("Running experiment with:");
      println!("  Design space: {}", design_space.display());
      println!("  Explorer options: {}", explorer_options.display());

      // Determine execution mode
      let use_concurrent = !sequential && max_concurrent > 1;
      if use_concurrent {
        println!(
          "  Execution mode: Concurrent (max {} workers)",
          max_concurrent
        );
      } else {
        println!("  Execution mode: Sequential");
      }

      // Load configuration files
      let design_space = load_design_space(design_space.to_str().unwrap())?;
      let explorer_options =
        load_explorer_options(explorer_options.to_str().unwrap())?;

      // Set up minimal global logging (most logs will go to config-specific
      // files)
      let logging_level =
        explorer_options.logging_level.as_deref().unwrap_or("warn");
      setup_logger_with_level(logging_level);

      // Create workspace directories for all benchmarks
      for benchmark_config in &explorer_options.benchmarks {
        if benchmark_config.len() >= 3 {
          let workspace_dir = &benchmark_config[2];
          fs::create_dir_all(workspace_dir)?;
          println!("Created workspace directory: {}", workspace_dir);
        }
      }

      // Create explorer and runner
      let explorer = Explorer::new(design_space, explorer_options);
      let mut runner =
        EvalRunner::new_with_concurrency(explorer, max_concurrent);

      // Run experiments with chosen execution mode
      let experiment_results = runner.run_with_options(use_concurrent)?;

      println!("Experiment completed!");
      println!("Total configurations run: {}", experiment_results.len());


      let successful_runs =
        experiment_results.iter().filter(|r| r.success).count();
      let failed_runs = experiment_results.len() - successful_runs;

      println!("Successful runs: {}", successful_runs);
      println!("Failed runs: {}", failed_runs);

      if failed_runs > 0 {
        println!("Failed configurations:");
        for result in experiment_results.iter().filter(|r| !r.success) {
          println!(
            "  - {}: {}",
            result.config_name,
            result.error_message.as_deref().unwrap_or("Unknown error")
          );
        }
      }

      // Show performance summary
      if use_concurrent {
        println!(
          "Concurrent execution completed with {} workers",
          max_concurrent
        );
      }
    }
  }

  Ok(())
}
