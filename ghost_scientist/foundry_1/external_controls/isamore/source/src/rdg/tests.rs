use std::{default, env, sync::Arc};

use anyhow::Ok;
use babble::Pretty;
use contruct::RdgBuilder;
use from_jlm_rvsdg::rdg_from_file;

use crate::{common::setup_logger_with_level, egg_lang::RdgEggLang};

use super::*;

#[test]
fn loop_mem_print() -> anyhow::Result<()> {
  let program = loop_mem();
  println!("{:#?}", program);
  Ok(())
}

#[test]
fn loop_mem_to_egg() -> anyhow::Result<()> {
  unsafe {
    env::set_var("RUST_LOG", "warn");
  }
  env_logger::init();
  let rdgegg = loop_mem().to_egg();

  println!(
    "{}",
    Pretty::new(Arc::new(RdgEggLang::build_babble_expr_from_recexpr(rdgegg)))
  );
  Ok(())
}

#[test]
fn jlm_loop_return_to_egg() -> anyhow::Result<()> {
  println!("{:?}", jlm_loop_return());
  let rdgegg = jlm_loop_return().to_egg();

  println!(
    "{}",
    Pretty::new(Arc::new(RdgEggLang::build_babble_expr_from_recexpr(rdgegg)))
  );
  Ok(())
}
#[test]
fn jlm_do_while_to_egg() -> anyhow::Result<()> {
  setup_logger_with_level("info");
  println!("{:?}", jlm_do_while());
  let rdgegg = jlm_do_while().to_egg();

  println!(
    "{}",
    Pretty::new(Arc::new(RdgEggLang::build_babble_expr_from_recexpr(rdgegg)))
  );
  Ok(())
}

#[test]
fn jlm_factorial_to_egg() -> anyhow::Result<()> {
  println!("{:?}", jlm_factorial());
  let rdgegg = jlm_factorial().to_egg();

  println!(
    "{}",
    Pretty::new(Arc::new(RdgEggLang::build_babble_expr_from_recexpr(rdgegg)))
  );
  Ok(())
}
#[test]
fn jlm_long_double_to_egg() -> anyhow::Result<()> {
  println!("{:?}", jlm_long_double());
  let rdgegg = jlm_long_double().to_egg();

  println!(
    "{}",
    Pretty::new(Arc::new(RdgEggLang::build_babble_expr_from_recexpr(rdgegg)))
  );
  Ok(())
}
#[test]
fn cdios_2d_2d_conv_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // println!("{:?}", jlm_2d_2d_conv());
  let rdgegg = cdios_2d_2d_conv().to_egg();
  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_2d_conv_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  let rdgegg = cdios_2d_conv().to_egg();
  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_2d_matrix_mul_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // env_logger::init();
  // log::warn!("{:?}", jlm_2d_matrix_mul());
  let rdgegg = cdios_2d_matrix_mul().to_egg();
  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_fft_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // env_logger::init();
  // log::warn!("{:?}", jlm_fft());
  let rdgegg = cdios_fft().to_egg();

  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_matrix_mul_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // env_logger::init();
  // log::warn!("{:?}", jlm_matrix_mul());
  let rdgegg = cdios_matrix_mul().to_egg();

  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}

#[test]
fn cdios_multi_mat_mul_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // println!("{:?}", jlm_multi_mat_mul());
  let rdgegg = cdios_multi_mat_mul().to_egg();

  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_point_product_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // println!("{:?}", jlm_point_product());
  let rdgegg = cdios_point_product().to_egg();
  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
#[test]
fn cdios_stencil_2d_to_egg() -> anyhow::Result<()> {
  crate::common::setup_logger_with_level(
    std::env::var("RUST_LOG").unwrap_or("info".to_string()),
  );
  // println!("{:?}", jlm_stencil_2d());
  let rdgegg = cdios_stencil_2d().to_egg();
  log::warn!("finish rdgegg");

  log::info!("rdgegg:\n{:?}", rdgegg);

  // println!("{}",
  // Pretty(&RdgEggLang::build_babble_expr_from_recexpr(rdgegg)));
  Ok(())
}
// int x[n], y[n];
// for (int i = 0; i < n; i++) {
//   y[i] = x[i];
// }
pub fn loop_mem() -> RdgProgram {
  let mut builder = RdgBuilder::default();

  let n = builder.lit_int(4, Some(RdgType::Int(32)));
  let x_alloca = builder.alloc(n.clone(), RdgType::Int(32));
  let y_alloca = builder.alloc(n.clone(), RdgType::Int(32));

  let ty_ptr_int = RdgType::Pointer;

  let x_ptr = x_alloca.get(0, ty_ptr_int.clone());
  let y_ptr = y_alloca.get(0, ty_ptr_int.clone());
  let alloca_state = builder.statemerge(
    x_alloca.get(1, RdgType::State),
    y_alloca.get(1, RdgType::State),
  );

  let i_0 = builder.lit_int(0, Some(RdgType::Int(32)));
  // args: i, n, x_ptr, y_ptr, state
  let i = builder.arg(0, RdgType::Int(32));
  let n_args = builder.arg(1, RdgType::Int(32));
  let x_ptr_arg = builder.arg(2, ty_ptr_int.clone());
  let y_ptr_arg = builder.arg(3, ty_ptr_int.clone());
  let state_arg = builder.arg(4, RdgType::State);

  let one = builder.lit_int(1, Some(RdgType::Int(32)));
  let i_plus_1 = builder.add(i.clone(), one, Some(RdgType::Int(32)));
  let i_less_than_n = builder.lt(i_plus_1.clone(), n_args.clone());
  let x_i =
    builder.ptradd(x_ptr_arg.clone(), i.clone(), Some(ty_ptr_int.clone()));
  let y_i =
    builder.ptradd(y_ptr_arg.clone(), i.clone(), Some(ty_ptr_int.clone()));
  let ld = builder.load(x_i, state_arg, Some(RdgType::Int(32)));
  let st =
    builder.store(y_i, ld.get(0, RdgType::Int(32)), ld.get(1, RdgType::State));

  let theta = builder.theta(
    i_less_than_n,
    &[i_0, n.clone(), x_ptr.clone(), y_ptr.clone(), alloca_state],
    &[
      i_plus_1,
      n_args.clone(),
      x_ptr_arg.clone(),
      y_ptr_arg.clone(),
      st,
    ],
    default::Default::default(),
    vec![
      RdgType::Int(32),
      RdgType::Int(32),
      RdgType::Pointer,
      RdgType::Pointer,
      RdgType::State,
    ],
  );

  builder.push_function(
    "main",
    vec![Some(theta.get(4, RdgType::State))],
    default::Default::default(),
  );
  builder.into_program()
}

// int x=1;
// for (int i = 0; i < n; i++) {
//   x = x * 2;
// }

pub fn pow_2_n() -> RdgProgram {
  let mut builder = RdgBuilder::default();

  let n = builder.lit_int(4, Some(RdgType::Int(32)));
  let i_0 = builder.lit_int(0, Some(RdgType::Int(32)));
  let x_1 = builder.lit_int(1, Some(RdgType::Int(32)));
  let i = builder.arg(0, RdgType::Int(32));
  let x_arg = builder.arg(1, RdgType::Int(32));
  let one = builder.lit_int(1, Some(RdgType::Int(32)));
  let i_plus_1 = builder.add(i.clone(), one, Some(RdgType::Int(32)));
  let cond = builder.lt(i_plus_1.clone(), n.clone());
  let two = builder.lit_int(2, Some(RdgType::Int(32)));
  let x_mul_2 = builder.mul(x_arg.clone(), two.clone(), Some(RdgType::Int(32)));
  let theta = builder.theta(
    cond,
    &[i_0, x_1],
    &[i_plus_1, x_mul_2],
    default::Default::default(),
    vec![RdgType::Int(32), RdgType::Int(32)],
  );

  builder.push_function(
    "main",
    vec![Some(theta.get(1, RdgType::Int(32)))],
    default::Default::default(),
  );
  builder.into_program()
}

pub fn jlm_loop_return() -> RdgProgram {
  rdg_from_file("tests/jlm/test-loop-return.rvsdg").unwrap()
}
pub fn jlm_do_while() -> RdgProgram {
  rdg_from_file("tests/jlm/test-do-while.rvsdg").unwrap()
}
pub fn jlm_factorial() -> RdgProgram {
  rdg_from_file("tests/jlm/test-factorial.rvsdg").unwrap()
}
pub fn jlm_long_double() -> RdgProgram {
  rdg_from_file("tests/jlm/test-long-double.rvsdg").unwrap()
}
pub fn cdios_2d_2d_conv() -> RdgProgram {
  rdg_from_file("tests/cdios/2d-2d-conv.rvsdg").unwrap()
}
pub fn cdios_2d_conv() -> RdgProgram {
  rdg_from_file("tests/cdios/2d-conv.rvsdg").unwrap()
}
pub fn cdios_2d_matrix_mul() -> RdgProgram {
  rdg_from_file("tests/cdios/2d-matrix-multiply.rvsdg").unwrap()
}
pub fn cdios_fft() -> RdgProgram {
  rdg_from_file("tests/cdios/fft.rvsdg").unwrap()
}
pub fn cdios_matrix_mul() -> RdgProgram {
  rdg_from_file("tests/cdios/matrix-multiply.rvsdg").unwrap()
}

pub fn cdios_multi_mat_mul() -> RdgProgram {
  rdg_from_file("tests/cdios/multi-mat-mul.rvsdg").unwrap()
}

pub fn cdios_point_product() -> RdgProgram {
  rdg_from_file("tests/cdios/point-product.rvsdg").unwrap()
}
pub fn cdios_stencil_2d() -> RdgProgram {
  rdg_from_file("tests/cdios/stencil-2d.rvsdg").unwrap()
}

pub fn liquid_temp() -> RdgProgram {
  rdg_from_file(
    "tests/liquid/rvsdgfiles/0_examples/agc_crcf_qpsk_example.rvsdg",
  )
  .unwrap()
}
