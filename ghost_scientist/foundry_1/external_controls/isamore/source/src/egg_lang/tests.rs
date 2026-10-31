use std::fs;

use anyhow::Ok;
use babble::Pretty;
use egg::{RecExpr, rewrite};

use crate::{
  common::setup_logger_with_level,
  rdg::tests::{loop_mem, pow_2_n},
};

use super::*;

#[test]
fn loop_mem_egraph() {
  let rdg_egg = loop_mem().to_egg();
  let mut egraph: egg::EGraph<RdgEggLang, ()> = egg::EGraph::default();
  egraph.add_expr(&rdg_egg);
  let egraph = egg::Runner::default().with_egraph(egraph).run(&[]).egraph;
  egraph.dot().to_png("__loop_mem.png").unwrap();
}

#[test]
fn loop_mem_parse() {
  let rdg_egg: RecExpr<RdgEggLang> = loop_mem().to_egg();
  let rdg_egg_str = rdg_egg.to_string();
  let parsed_rdg_egg: RecExpr<RdgEggLang> = rdg_egg_str.parse().unwrap();

  assert_eq!(rdg_egg.to_string(), parsed_rdg_egg.to_string());
}

#[test]
fn pow_2_n_rewrite() {
  setup_logger_with_level("warn");
  let rdg_egg = pow_2_n().to_egg();
  let rdg_egg_expr =
    RdgEggLang::build_babble_expr_from_recexpr(rdg_egg.clone());
  println!("{}", Pretty::new(Arc::new(rdg_egg_expr.clone())));
  let mut egraph = egg::EGraph::new(());
  egraph.add_expr(&rdg_egg);
  let rules = &[rewrite!("mul2-shl1"; "(mul ?a (2i))" => "(shl ?a (1i))")];
  let runner = egg::Runner::default().with_egraph(egraph).run(rules);
  runner.egraph.dot().to_png("__pow_2_n_rewrite.png").unwrap();
}

#[test]
fn cdios_2d_2d_conv_parse() -> anyhow::Result<()> {
  setup_logger_with_level("warn");
  let rdg = crate::rdg::tests::cdios_2d_2d_conv();
  let egg = rdg.to_egg();
  // log::warn!("{}", egg.to_string());
  let babble_expr = RdgEggLang::build_babble_expr_from_recexpr(egg.clone());
  log::warn!("get babble expr");
  println!("{}", Pretty::new(Arc::new(babble_expr.clone())));
  Ok(())
}

#[test]
fn cdios_fft_parse() -> anyhow::Result<()> {
  setup_logger_with_level("warn");
  let rdg = crate::rdg::tests::cdios_fft();
  let egg = rdg.to_egg();
  let babble_expr = RdgEggLang::build_babble_expr_from_recexpr(egg.clone());
  println!("{}", Pretty::new(Arc::new(babble_expr.clone())));
  Ok(())
}

#[test]
fn jlm_all_parse() -> anyhow::Result<()> {
  setup_logger_with_level("warn");
  let paths = ["tests/jlm"];
  for path in paths {
    let dir = fs::read_dir(path)?;
    for entry in dir {
      let entry = entry?;
      let path = entry.path();
      if path.is_file() && path.to_str().unwrap().ends_with(".rvsdg") {
        log::warn!("parsing {}", path.to_str().unwrap());
        let rdg = match crate::rdg::from_jlm_rvsdg::rdg_from_file(path.clone())
        {
          Result::Ok(rdg) => rdg,
          Result::Err(_e) => {
            log::error!("error parsing {}", path.to_str().unwrap());
            continue;
          }
        };
        let _egg = rdg.to_egg();
      }
    }
  }
  Ok(())
}

#[test]
fn cdios_all_parse() -> anyhow::Result<()> {
  setup_logger_with_level("warn");
  let paths = ["tests/cdios"];
  for path in paths {
    let dir = fs::read_dir(path)?;
    for entry in dir {
      let entry = entry?;
      let path = entry.path();
      if path.is_file() && path.to_str().unwrap().ends_with(".rvsdg") {
        log::warn!("parsing {}", path.to_str().unwrap());
        let rdg = match crate::rdg::from_jlm_rvsdg::rdg_from_file(path.clone())
        {
          Result::Ok(rdg) => rdg,
          Result::Err(_e) => {
            log::error!("error parsing {}", path.to_str().unwrap());
            continue;
          }
        };
        let _egg = rdg.to_egg();
      }
    }
  }
  Ok(())
}

#[test]
fn liquid_all_parse() -> anyhow::Result<()> {
  setup_logger_with_level("warn");
  let paths = [
    "tests/liquid/rvsdgfiles/0_examples",
    "tests/liquid/rvsdgfiles/agc_ll",
    "tests/liquid/rvsdgfiles/audio_ll",
    "tests/liquid/rvsdgfiles/buffer_ll",
    "tests/liquid/rvsdgfiles/channel_ll",
    "tests/liquid/rvsdgfiles/dotprod_ll",
    "tests/liquid/rvsdgfiles/equalization_ll",
    "tests/liquid/rvsdgfiles/fec_ll",
    "tests/liquid/rvsdgfiles/fft_ll",
    "tests/liquid/rvsdgfiles/filter_ll",
    "tests/liquid/rvsdgfiles/framing_ll",
    "tests/liquid/rvsdgfiles/math_ll",
    "tests/liquid/rvsdgfiles/matrix_ll",
    "tests/liquid/rvsdgfiles/modem_ll",
    "tests/liquid/rvsdgfiles/nco_ll",
    "tests/liquid/rvsdgfiles/optim_ll",
    "tests/liquid/rvsdgfiles/quantization_ll",
    "tests/liquid/rvsdgfiles/random_ll",
    "tests/liquid/rvsdgfiles/sequence_ll",
    "tests/liquid/rvsdgfiles/utility_ll",
    "tests/liquid/rvsdgfiles/vector_ll",
  ];

  // for every path, parse the included rvsdg file to egg
  for path in paths {
    let dir = fs::read_dir(path)?;
    for entry in dir {
      let entry = entry?;
      let path = entry.path();
      if path.is_file() && path.to_str().unwrap().ends_with(".rvsdg") {
        log::warn!("parsing {}", path.to_str().unwrap());
        let rdg = match crate::rdg::from_jlm_rvsdg::rdg_from_file(path.clone())
        {
          Result::Ok(rdg) => rdg,
          Result::Err(_e) => {
            log::error!("error parsing {}", path.to_str().unwrap());
            continue;
          }
        };
        let _egg = rdg.to_egg();
      }
    }
  }

  Ok(())
}
