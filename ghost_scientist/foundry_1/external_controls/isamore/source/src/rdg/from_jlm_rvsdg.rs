//! Parse JLM RVSDG text to RVSDG

use crate::rdg::*;
use anyhow::bail;
use indexmap::IndexMap;
/// parse JLM RVSDG text to RVSDG
/// jlm_rvsdg: the text of the JLM RVSDG, it should look like the
/// following: ```
/// []{
///   o0 := LAMBDA[fac]
///     [a1, a2, a3]{
///       o4 := undef
///       o5 := undef
///     }
///   }
///   ...
/// }
/// ```
///
use pest::Parser;
use pest_derive::Parser;
use std::fs;
use std::path::Path;

#[derive(Parser)]
#[grammar = "src/jlm.pest"]
struct RvsdgParser;

pub fn jlm_to_rvsdg(jlm_rvsdg: &str) -> anyhow::Result<RdgProgram> {
  let rvsdg = parse_rvsdg(jlm_rvsdg);
  rvsdg
}

pub fn parse_rvsdg(input: &str) -> anyhow::Result<RdgProgram> {
  let mut pairs = match RvsdgParser::parse(Rule::program, input) {
    Ok(pairs) => pairs,
    Err(e) => {
      eprintln!("Parsing error: {}", e);
      eprintln!("Error details: {:?}", e);
      // Try to show context around the error
      let lines: Vec<&str> = input.lines().collect();
      match &e.line_col {
        pest::error::LineColLocation::Pos((line_num, col_num)) => {
          eprintln!("Error at line {}, column {}", line_num, col_num);
          if *line_num > 0 && *line_num <= lines.len() {
            let line = lines[*line_num - 1];
            eprintln!("Line content: {}", line);
            eprintln!(
              "Error position: {}^",
              " ".repeat(col_num.saturating_sub(1))
            );
          }
        }
        pest::error::LineColLocation::Span(
          (start_line, start_col),
          (end_line, end_col),
        ) => {
          eprintln!(
            "Error from line {}, column {} to line {}, column {}",
            start_line, start_col, end_line, end_col
          );
          if *start_line > 0 && *start_line <= lines.len() {
            let line = lines[*start_line - 1];
            eprintln!("Line content: {}", line);
            eprintln!(
              "Error position: {}^",
              " ".repeat(start_col.saturating_sub(1))
            );
          }
        }
      }
      bail!(e)
    }
  };
  let mut functions = vec![];
  let pair = pairs.next().unwrap();
  let whole = pair.into_inner().next().unwrap();

  for pair in whole.into_inner() {
    if let Rule::funcexpr = pair.as_rule() {
      let function = pair.into_inner().nth(1).unwrap();
      if let Rule::function = function.as_rule() {
        let new_functions = parse_function(function);
        functions.extend(new_functions);
      } else if let Rule::phi = function.as_rule() {
        let phi_functions: Vec<RdgFunction> = parse_phi(function);
        functions.extend(phi_functions);
      }
    }
  }

  Ok(RdgProgram { functions })
}

pub fn parse_bb_info(pair: pest::iterators::Pair<'_, Rule>) -> BBInfo {
  let mut bb_info = vec![];
  for bb_info_pair in pair.into_inner() {
    log::info!("bb_info_pair: {}", bb_info_pair.as_str());
    // split by "," and trim, keep only non-empty strings
    bb_info.extend(bb_info_pair.as_str().split(',').filter_map(|s| {
      let s = s.trim();
      if !s.is_empty() {
        Some(s.to_string())
      } else {
        None
      }
    }));
  }
  log::info!("bb_info: {:?}", bb_info);
  bb_info
}

struct JlmToRvsdg<'a> {
  nodes: &'a mut Vec<RdgBody>,
  current_args: Vec<Operand>,
  translation_cache: IndexMap<String, Operand>,
  bb_info: BBInfo,
}

impl JlmToRvsdg<'_> {
  fn set_bb_info(&mut self, bb_info: BBInfo) {
    self.bb_info = bb_info;
  }

  fn translate_subregion(
    &mut self,
    branch: pest::iterators::Pair<'_, Rule>,
    ident: Option<String>,
  ) -> (Vec<Operand>, Option<Operand>, BBInfo) {
    let mut inner_pairs = branch.into_inner();
    let args = parse_branch_args(inner_pairs.next().unwrap());
    let mut converter: JlmToRvsdg<'_> = JlmToRvsdg {
      nodes: &mut self.nodes,
      // initial arguments are the first n arguments
      current_args: args
        .iter()
        .enumerate()
        .map(|(i, (ty, _))| Operand::Arg {
          index: i,
          ty: ty.clone(),
        })
        .collect(),
      translation_cache: IndexMap::new(),
      bb_info: vec![],
    };
    for (i, (_, ident)) in args.iter().enumerate() {
      // println!("add-to-cache: {}", ident);
      converter
        .translation_cache
        .insert(ident.to_string(), converter.current_args[i].clone());
    }

    let bb_info_pair = inner_pairs.next().unwrap();
    let bb_info = parse_bb_info(bb_info_pair);

    converter.set_bb_info(bb_info);

    let mut operands = vec![];
    for expr in inner_pairs.clone() {
      if let Rule::results = expr.as_rule() {
        operands = converter.parse_branch_results(expr);
      } else {
        converter.convert_expr(expr.clone(), &mut vec![]);
      }
    }
    if let Some(ident) = ident {
      // println!("get-from-cache: {}", ident);
      return (
        operands,
        Some(converter.translation_cache.get(&ident).unwrap().clone()),
        converter.bb_info.clone(),
      );
    }
    (operands, None, converter.bb_info.clone())
  }

  fn push_basic(
    &mut self,
    basic: BasicExpr<Operand>,
    types: Vec<RdgType>,
  ) -> Vec<Operand> {
    let new_id = self.nodes.len();
    let num_outputs = basic.num_outputs();
    self.nodes.push(RdgBody::BasicOp {
      expr: basic,
      output_tys: types.clone(),
    });

    (0..num_outputs)
      .map(|i: usize| Operand::Project {
        index: i,
        node_id: new_id,
        ty: types[i].clone(),
      })
      .collect()
  }

  fn parse_branch_results(
    &mut self,
    pair: pest::iterators::Pair<'_, Rule>,
  ) -> Vec<Operand> {
    pair
      .into_inner()
      .filter_map(|result_pair| {
        let mut results_parts = result_pair.into_inner();
        let first_part = results_parts.next().unwrap();
        if let Rule::ident = first_part.as_rule() {
          let _ident = first_part.as_str().to_string();
          let mut typed_ident = results_parts.next().unwrap().into_inner();
          let ident = typed_ident.next().unwrap().as_str();
          Some(self.translation_cache.get(ident).unwrap().clone())
        } else {
          None
        }
      })
      .collect()
  }

  fn parse_results(
    &mut self,
    pair: pest::iterators::Pair<'_, Rule>,
  ) -> Vec<Option<Operand>> {
    pair
      .into_inner()
      .map(|result_pair| {
        let mut result_parts = result_pair.into_inner();
        let first_part = result_parts.next().unwrap();
        if let Rule::ident = first_part.as_rule() {
          let ident = first_part.as_str().to_string();
          Some(self.translation_cache.get(&ident).unwrap().clone())
        } else {
          let mut typed_ident = first_part.into_inner();
          let ident = typed_ident.next().unwrap().as_str();
          if self.translation_cache.get(ident).is_none() {
            eprintln!("No find ident {}.", ident);
            return None;
          }
          Some(self.translation_cache.get(ident).unwrap().clone())
        }
      })
      .collect()
  }

  fn parse_typed_idents(
    &mut self,
    pairs: pest::iterators::Pairs<'_, Rule>,
  ) -> Vec<(RdgType, Operand)> {
    let mut operand_types = vec![];
    let mut pairs_iter = pairs.into_iter();

    while let Some(pair) = pairs_iter.next() {
      let mut typed_ident = pair.into_inner();
      let operand = typed_ident.next().unwrap().as_str();
      let type_ = typed_ident.next().unwrap().as_str();
      if let Some(branch_operands) = self.translation_cache.get(operand) {
        operand_types.push((parse_rvsdg_type(type_), branch_operands.clone()));
      } else {
        eprintln!("No find ident {}.", operand);
      }
    }
    operand_types
  }

  fn convert_expr(
    &mut self,
    pair: pest::iterators::Pair<'_, Rule>,
    functions: &mut Vec<RdgFunction>,
  ) {
    // let pair_backup = pair.clone();
    let mut inner_pairs = pair.into_inner();
    let mut idents_info = vec![];
    let expr_type;
    let _idents = inner_pairs.next().unwrap();
    if let Rule::typed_idents = _idents.as_rule() {
      idents_info = parse_rvsdg_idents(_idents.into_inner());
      expr_type = inner_pairs.next().unwrap();
    } else {
      expr_type = _idents;
    }

    // println!("convert expr: {}", expr_type.as_str());
    match expr_type.as_rule() {
      Rule::Const => {
        // println!("meet const: {}", expr_type.as_str());
        let mut const_info = expr_type.into_inner();
        let const_type = const_info.next().unwrap();
        let ty = idents_info[0].0.clone();
        let literal_value;
        if let Rule::consttype = const_type.as_rule() {
          let value_str = const_info.next().unwrap().as_str();
          literal_value = match &ty {
            RdgType::Int(_) => {
              Literal::Int(value_str.parse::<i64>().unwrap_or(0))
            }
            RdgType::CTL(_) => {
              Literal::Int(value_str.parse::<i64>().unwrap_or(0))
            }
            _ => panic!("Unexpected type for const value: {:?}", ty),
          };
        } else if let Rule::fptypes = const_type.as_rule() {
          let fp_numbers = const_type.into_inner().next().unwrap().as_str();
          let fp_number = fp_numbers.parse::<f64>().unwrap();
          literal_value = Literal::Float(OrderedFloat(fp_number));
        } else {
          panic!("Unexpected const grammar");
        }

        let res = self
          .push_basic(BasicExpr::Const(literal_value, ty.clone()), vec![
            ty.clone(),
          ]);
        for (i, (_, ident)) in idents_info.into_iter().enumerate() {
          self.translation_cache.insert(ident.clone(), res[i].clone());
        }
      }
      Rule::binary => {
        let mut binarys = expr_type.clone().into_inner();
        let binary_op = binarys.next().unwrap();
        let ident = idents_info[0].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut typed_ident_first = binarys.next().unwrap().into_inner();
        let ident_first = typed_ident_first.next().unwrap().as_str();
        let operand_first =
          self.translation_cache.get(ident_first).unwrap().clone();
        let mut typed_ident_second = binarys.next().unwrap().into_inner();
        let ident_second = typed_ident_second.next().unwrap().as_str();
        let operand_second =
          self.translation_cache.get(ident_second).unwrap().clone();
        if let Some(vop) = value_op_from_binary_op(binary_op.as_str()) {
          let operands: Vec<Operand> = self.push_basic(
            BasicExpr::Op(vop, vec![operand_first, operand_second]),
            rdg_types,
          );
          // eprintln!("add to cache: {}", ident);
          self
            .translation_cache
            .insert(ident.to_string(), operands[0].clone());
        }
      }
      Rule::vecconst => {
        let mut vecconsts = expr_type.clone().into_inner();
        let _op = vecconsts.next().unwrap();
        let ident = idents_info[0].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut operands = vec![];
        for operand in vecconsts {
          let mut typed_ident = operand.into_inner();
          let ident = typed_ident.next().unwrap().as_str();
          let operand = self.translation_cache.get(ident).unwrap().clone();
          operands.push(operand);
        }
        let results = self
          .push_basic(BasicExpr::Op(PrimOp::VECConstant, operands), rdg_types);
        self
          .translation_cache
          .insert(ident.to_string(), results[0].clone());
      }
      Rule::vecfneg => {
        let mut vecfnegs = expr_type.clone().into_inner();
        let ident = idents_info[0].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        // println!("vecfnegs: get typed_indent from {}", vecfnegs.as_str());
        let mut typed_ident = vecfnegs.next().unwrap().into_inner();
        let operand_ident = typed_ident.next().unwrap().as_str();
        let operand =
          self.translation_cache.get(operand_ident).unwrap().clone();
        let results = self
          .push_basic(BasicExpr::Op(PrimOp::VECFNeg, vec![operand]), rdg_types);
        self
          .translation_cache
          .insert(ident.to_string(), results[0].clone());
      }
      Rule::getelementptr => {
        let ident = idents_info[0].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut idents = expr_type.into_inner().next().unwrap().into_inner();
        let mut typed_ident_ptr = idents.next().unwrap().into_inner();
        let ptr_ident = typed_ident_ptr.next().unwrap().as_str();
        let ptr_operand =
          self.translation_cache.get(ptr_ident).unwrap().clone();
        //skip second ident
        let mut typed_offset_ident =
          idents.nth(idents.len() - 1).unwrap().into_inner();
        let offset_ident = typed_offset_ident.next().unwrap().as_str();
        let offset_operand =
          self.translation_cache.get(offset_ident).unwrap().clone();
        let operands = self.push_basic(
          BasicExpr::Op(PrimOp::PtrAdd, vec![ptr_operand, offset_operand]),
          rdg_types,
        );
        self
          .translation_cache
          .insert(ident.to_string(), operands[0].clone());
      }
      Rule::load => {
        let value = idents_info[0].1.clone();
        let state = idents_info[1].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut idents = expr_type.into_inner();
        let mut typed_ident_ptr = idents.next().unwrap().into_inner();
        let ptr_ident = typed_ident_ptr.next().unwrap().as_str();
        let ptr_operand =
          self.translation_cache.get(ptr_ident).unwrap().clone();
        let mut typed_ident_state = idents.next().unwrap().into_inner();
        let state_ident = typed_ident_state.next().unwrap().as_str();
        let state_operand: Operand =
          self.translation_cache.get(state_ident).unwrap().clone();
        let operands = self.push_basic(
          BasicExpr::Op(PrimOp::Load, vec![ptr_operand, state_operand]),
          rdg_types,
        );
        self
          .translation_cache
          .insert(value.to_string(), operands[0].clone());
        self
          .translation_cache
          .insert(state.to_string(), operands[1].clone());
      }
      Rule::statemerge => {
        let mut idents = expr_type.into_inner();
        let mut typed_ident_state1 = idents.next().unwrap().into_inner();
        let state1_ident = typed_ident_state1.next().unwrap().as_str();
        let state1_operand =
          self.translation_cache.get(state1_ident).unwrap().clone();
        let mut typed_ident_state2 = idents.next().unwrap().into_inner();
        let state2_ident = typed_ident_state2.next().unwrap().as_str();
        let state2_operand =
          self.translation_cache.get(state2_ident).unwrap().clone();
        let ident = idents_info[0].1.clone();
        let rdg_types: Vec<RdgType> = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let operands = self.push_basic(
          BasicExpr::Op(PrimOp::StateMerge, vec![
            state1_operand,
            state2_operand,
          ]),
          rdg_types,
        );
        self
          .translation_cache
          .insert(ident.to_string(), operands[0].clone());
      }
      Rule::store => {
        let ident = idents_info[0].1.clone();
        let rdg_types: Vec<RdgType> = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut idents = expr_type.into_inner();
        let mut typed_ident_ptr = idents.next().unwrap().into_inner();
        let ptr_ident = typed_ident_ptr.next().unwrap().as_str();
        let ptr_operand =
          self.translation_cache.get(ptr_ident).unwrap().clone();
        let mut typed_ident_value = idents.next().unwrap().into_inner();
        let value_ident = typed_ident_value.next().unwrap().as_str();
        let value_operand =
          self.translation_cache.get(value_ident).unwrap().clone();
        let mut typed_ident_state = idents.next().unwrap().into_inner();
        let state_ident = typed_ident_state.next().unwrap().as_str();
        let state_operand =
          self.translation_cache.get(state_ident).unwrap().clone();
        let operands = self.push_basic(
          BasicExpr::Op(PrimOp::Store, vec![
            ptr_operand,
            value_operand,
            state_operand,
          ]),
          rdg_types,
        );
        self
          .translation_cache
          .insert(ident.to_string(), operands[0].clone());
      }
      Rule::gamma => {
        let rdg_types: Vec<RdgType> = idents_info
          .iter()
          .map(|(rdg_type, _)| rdg_type.clone())
          .collect();

        let mut gammas = expr_type.clone().into_inner();
        let mut idents = gammas.next().unwrap().into_inner();
        let mut typed_ident_pred = idents.next().unwrap().into_inner();
        let pred_ident = typed_ident_pred.next().unwrap().as_str();
        let pred = self.translation_cache.get(pred_ident).unwrap().clone();
        let inputs = self
          .parse_typed_idents(idents.clone())
          .iter()
          .map(|(_, op)| op.clone())
          .collect();
        let mut case_regions = vec![];
        let mut case_bb_infos = vec![];
        for case_expr in gammas {
          let (case_region, _, case_bb_info) =
            self.translate_subregion(case_expr.clone(), None);
          case_regions.push(case_region);
          case_bb_infos.push(case_bb_info);
        }

        let new_id = self.nodes.len();
        let res: Vec<Operand> = (0..idents_info.len())
          .map(|i| Operand::Project {
            index: i,
            node_id: new_id,
            ty: idents_info[i].0.clone(),
          })
          .collect();

        for (i, (_, ident)) in idents_info.into_iter().enumerate() {
          self.translation_cache.insert(ident, res[i].clone());
        }

        self.nodes.push(RdgBody::Gamma {
          pred,
          inputs,
          outputs: case_regions,
          bb_infos: case_bb_infos,
          output_tys: rdg_types,
        });
      }
      Rule::theta => {
        let rdg_types: Vec<RdgType> = idents_info
          .iter()
          .map(|(rdg_type, _)| rdg_type.clone())
          .collect();
        let mut thetas = expr_type.into_inner();
        let mut theta_first = thetas.next().unwrap();
        let mut inputs = vec![];
        if let Rule::typed_idents = theta_first.as_rule() {
          inputs = self
            .parse_typed_idents(theta_first.clone().into_inner())
            .iter()
            .map(|(_, op)| op.clone())
            .collect();
          theta_first = thetas.next().unwrap();
        }
        let branch_results = theta_first.clone().into_inner().last().unwrap();
        let branch_result = branch_results.into_inner().next().unwrap();
        let mut typed_ident_pred =
          branch_result.into_inner().next().unwrap().into_inner();
        let pred_ident = typed_ident_pred.next().unwrap().as_str();

        let (theta_region, pred_opt, theta_bb_info) = self.translate_subregion(
          theta_first.clone(),
          Some(pred_ident.to_string()),
        );
        let new_id = self.nodes.len();
        let res: Vec<Operand> = (0..idents_info.len())
          .map(|i| Operand::Project {
            index: i,
            node_id: new_id,
            ty: idents_info[i].0.clone(),
          })
          .collect();

        for (i, (_, ident)) in idents_info.into_iter().enumerate() {
          self.translation_cache.insert(ident, res[i].clone());
        }

        self.nodes.push(RdgBody::Theta {
          pred: pred_opt.unwrap(),
          inputs,
          outputs: theta_region,
          bb_info: theta_bb_info,
          output_tys: rdg_types,
        });
      }
      Rule::cast => {
        let mut casts = expr_type.clone().into_inner();
        let cast_op = casts.next().unwrap();
        let ident = idents_info[0].1.clone();
        let rdg_types = idents_info
          .into_iter()
          .map(|(rdg_type, _)| rdg_type)
          .collect();
        let mut typed_ident = casts.next().unwrap().into_inner();
        let source_ident = typed_ident.next().unwrap().as_str();
        let operand = self.translation_cache.get(source_ident).unwrap().clone();
        let mut from = 32;
        let mut to = 32;
        match cast_op.clone().as_rule() {
          Rule::sext | Rule::zext | Rule::tr => {
            // 获取from和to的值
            let mut inner = cast_op.clone().into_inner();
            from = inner.next().unwrap().as_str().parse().unwrap();
            to = inner.next().unwrap().as_str().parse().unwrap();
          }
          _ => {}
        };
        if let Some(vop) = value_op_from_cast_op(cast_op.as_str(), from, to) {
          let operands =
            self.push_basic(BasicExpr::Op(vop, vec![operand]), rdg_types);
          self
            .translation_cache
            .insert(ident.to_string(), operands[0].clone());
        }
      }

      Rule::iobarrier => {
        let mut parts = expr_type.clone().into_inner();

        let mut typed_ident_first = parts.next().unwrap().into_inner();
        let ident_first = typed_ident_first.next().unwrap().as_str();
        let operand_first =
          self.translation_cache.get(ident_first).unwrap().clone();

        let mut typed_ident_second = parts.next().unwrap().into_inner();
        let ident_second = typed_ident_second.next().unwrap().as_str();
        let operand_second =
          self.translation_cache.get(ident_second).unwrap().clone();

        let ident = idents_info[0].1.clone();

        let rdg_types = idents_info
          .iter()
          .map(|(rdg_type, _)| rdg_type.clone())
          .collect();

        let operands = self.push_basic(
          BasicExpr::Op(PrimOp::IOBarrier, vec![operand_first, operand_second]),
          rdg_types,
        );

        self
          .translation_cache
          .insert(ident.to_string(), operands[0].clone());
      }

      Rule::dummy_expr => {
        // Name (operand)*
        let mut idents = expr_type.into_inner();
        let expr_name = idents.next().unwrap().as_str();
        let mut operands = vec![];
        while let Some(typed_ident) = idents.next() {
          let ident = typed_ident.into_inner().next().unwrap().as_str();
          let operand = self
            .translation_cache
            .get(ident)
            .unwrap_or_else(|| {
              panic!("No find ident {}.", ident);
            })
            .clone();
          operands.push(operand);
        }
        let num_outputs = idents_info.len();
        let rdg_types = idents_info
          .iter()
          .map(|(rdg_type, _)| rdg_type.clone())
          .collect();
        let produced_operands = self.push_basic(
          BasicExpr::Dummy(expr_name.to_string(), operands, num_outputs),
          rdg_types,
        );
        for (i, (_, ident)) in idents_info.into_iter().enumerate() {
          self
            .translation_cache
            .insert(ident, produced_operands[i].clone());
        }
      }
      Rule::delta | Rule::function => {
        functions.extend(parse_function(expr_type));
      }
      _ => panic!("Unsupported expression type: {:?}", expr_type.as_rule()),
    }
  }
}

fn parse_function(
  function: pest::iterators::Pair<'_, Rule>,
) -> Vec<RdgFunction> {
  let mut inner_pairs = function.into_inner();
  let func_name = inner_pairs.next().unwrap().as_str().to_string();
  let typed_idents = inner_pairs.next().unwrap();

  // get func def
  let args = if let Rule::typed_idents = typed_idents.as_rule() {
    inner_pairs.next().unwrap()
  } else {
    typed_idents
  };

  let _func_sig = format!(
    "parse args for function {}, args: {}",
    func_name,
    args.as_str()
  );

  // println!("{}", _func_sig);

  let args_info = parse_args(args);

  let mut nodes = vec![];
  let mut converter = JlmToRvsdg {
    nodes: &mut nodes,
    // initial arguments are the first n arguments
    current_args: args_info
      .iter()
      .enumerate()
      .map(|(i, (ty, _))| Operand::Arg {
        index: i,
        ty: ty.clone(),
      })
      .collect(),
    translation_cache: IndexMap::new(),
    bb_info: vec![],
  };

  let mut args_type: Vec<RdgType> = vec![];
  for (i, (_type, _ident)) in args_info.iter().enumerate() {
    args_type.push(_type.clone());
    converter
      .translation_cache
      .insert(_ident.to_string(), converter.current_args[i].clone());
  }

  let bb_info_pair = inner_pairs.next().unwrap();
  let bb_info = parse_bb_info(bb_info_pair);

  // println!("{}, bb_info: {:?}", _func_sig, bb_info);

  let mut functions = vec![];
  let mut results = vec![];
  for expr in inner_pairs {
    if let Rule::results = expr.as_rule() {
      results = converter.parse_results(expr.clone());
    } else {
      converter.convert_expr(expr.clone(), &mut functions);
    }
  }

  functions.push(RdgFunction {
    name: func_name,
    nodes,
    results,
    bb_info,
  });
  functions
}

fn parse_phi(phi: pest::iterators::Pair<'_, Rule>) -> Vec<RdgFunction> {
  let mut functions = vec![];
  for expr in phi.into_inner() {
    if let Rule::funcexpr = expr.as_rule() {
      let function = expr.clone().into_inner().last().unwrap();
      if let Rule::function = function.as_rule() {
        let function = parse_function(function);
        functions.extend(function);
      } else if let Rule::delta = function.as_rule() {
        let function = expr.into_inner().last().unwrap();
        let delta = parse_function(function);
        functions.extend(delta);
      } else {
        panic!(
          "Phi must only have lambda functions! {:?}",
          function.as_rule()
        );
      }
    }
  }
  functions
}

fn parse_args(pair: pest::iterators::Pair<'_, Rule>) -> Vec<(RdgType, String)> {
  let pair_str = pair.as_str();
  pair
    .into_inner()
    .map(|arg_pair| {
      let mut arg_parts: pest::iterators::Pairs<'_, Rule> =
        arg_pair.into_inner();
      let arg_str = arg_parts.as_str();

      let first_part = if let Some(first_part) = arg_parts.next() {
        first_part
      } else {
        panic!(
          "No argument found for function arg [{}] in args [{}]",
          arg_str, pair_str
        );
      };
      if let Rule::ident = first_part.as_rule() {
        // ident <= typed_ident
        let _ident = first_part.as_str();
        let typed_ident = arg_parts.last().unwrap().into_inner();
        let _type = if let Some(ty) = typed_ident.clone().last() {
          parse_rvsdg_type(ty.as_str())
        } else {
          panic!(
            "No type found for ident: {}, left-hand side is {}; The whole arg is {}",
            typed_ident.as_str(),
            _ident,
            arg_str
          );
        };
        (_type, _ident.to_string())
      } else {
        // typed_ident
        let mut typed_ident = first_part.into_inner();
        let ident = typed_ident.next().unwrap().as_str();
        let type_str = typed_ident.next().unwrap().as_str();
        let _type = parse_rvsdg_type(type_str);
        (_type, ident.to_string())
      }
    })
    .collect()
}

fn parse_branch_args(
  pair: pest::iterators::Pair<'_, Rule>,
) -> Vec<(RdgType, String)> {
  pair
    .into_inner()
    .map(|arg_pair| {
      let mut arg_parts = arg_pair.into_inner();
      let ident = arg_parts.next().unwrap().as_str().to_string();
      let branch_arg_parts = arg_parts.next().unwrap().into_inner();
      let type_str = branch_arg_parts
        .last()
        .unwrap()
        .into_inner()
        .last()
        .unwrap()
        .as_str();
      let rvsdg_type = parse_rvsdg_type(type_str);
      (rvsdg_type, ident)
    })
    .collect()
}

fn parse_vector_type(type_str: &str) -> Option<RdgType> {
  // vector type should be like "fixedvector<float:2>"
  if let Some(vec_type) = type_str.strip_prefix("fixedvector_") {
    let (type_str, num_str) = vec_type.split_once("_").unwrap();
    let type_ = parse_rvsdg_type(type_str);
    let num = num_str.parse::<usize>().unwrap();
    Some(RdgType::Vector(Box::new(type_), num))
  } else {
    None
  }
}

fn parse_array_type(type_str: &str) -> Option<RdgType> {
  if let Some(array_type) = type_str.strip_prefix("array_") {
    let (num_str, type_str) = array_type.split_once("_").unwrap();
    let type_ = parse_rvsdg_type(type_str);
    let num = num_str.parse::<usize>().unwrap();
    Some(RdgType::Vector(Box::new(type_), num))
  } else {
    None
  }
}

fn parse_rvsdg_type(type_str: &str) -> RdgType {
  if let Some(num_str) = type_str
    .strip_prefix("ctl(")
    .and_then(|s| s.strip_suffix(")"))
  {
    if let Ok(num) = num_str.parse::<i32>() {
      return RdgType::CTL(num);
    } else {
      panic!("Invalid CTL number: {}", num_str);
    }
  }
  match type_str {
    "bit1" => RdgType::Int(1),
    s if s.starts_with("bit") => {
      let width_s = s.strip_prefix("bit").unwrap();
      RdgType::Int(width_s.parse().unwrap())
    }
    "iostate" => RdgType::State,
    "mem" => RdgType::State,
    "ptr" => RdgType::Pointer,
    "vararg" => RdgType::Int(32),
    "float" => RdgType::Float(32),
    "double" => RdgType::Float(64),
    //FIXME: this is fake
    "x86fp80" => RdgType::Float(64),
    // FIXME: this is a hack
    "struct" => RdgType::Int(64),
    x => {
      // try parse vector type
      if let Some(vec_type) = parse_vector_type(x) {
        return vec_type;
      }
      if let Some(array_type) = parse_array_type(x) {
        return array_type;
      }
      panic!("Unknown type: {}", x);
    }
  }
}

fn parse_rvsdg_idents(
  pairs: pest::iterators::Pairs<'_, Rule>,
) -> Vec<(RdgType, String)> {
  let mut operand_types = vec![];
  let mut pairs_iter = pairs.into_iter();

  while let Some(pair) = pairs_iter.next() {
    let mut typed_ident_pairs = pair.into_inner();
    let ident = typed_ident_pairs.next().unwrap().as_str();
    let type_pair = typed_ident_pairs.next().unwrap();
    let rvsdg_type = parse_rvsdg_type(type_pair.as_str());
    operand_types.push((rvsdg_type, ident.to_string()));
  }
  operand_types
}

fn value_op_from_binary_op(bop: &str) -> Option<PrimOp> {
  match bop {
    // Integer operators
    "IAdd" => Some(PrimOp::Add),
    "ISub" => Some(PrimOp::Sub),
    "IMul" => Some(PrimOp::Mul),
    "ISDiv" => Some(PrimOp::Div),
    "IUDiv" => Some(PrimOp::Div),
    "ISMod" => Some(PrimOp::Mod),
    "IUMod" => Some(PrimOp::Mod),
    "IAShr" => Some(PrimOp::Shr),
    "IShl" => Some(PrimOp::Shl),
    "IShr" => Some(PrimOp::Shr),
    "IAnd" => Some(PrimOp::And),
    "IOr" => Some(PrimOp::Or),
    "IXor" => Some(PrimOp::Xor),
    "IEq" => Some(PrimOp::Eq),
    "INe" => Some(PrimOp::Ne),
    "ISge" => Some(PrimOp::Ge),
    "ISgt" => Some(PrimOp::Gt),
    "ISle" => Some(PrimOp::Le),
    "ISlt" => Some(PrimOp::Lt),
    "IUge" => Some(PrimOp::Ge),
    "IUgt" => Some(PrimOp::Gt),
    "IUle" => Some(PrimOp::Le),
    "IUlt" => Some(PrimOp::Lt),
    // Floating-point operators
    "FPOP add" => Some(PrimOp::Fadd),
    "FPOP sub" => Some(PrimOp::Fsub),
    "FPOP mul" => Some(PrimOp::Fmul),
    "FPOP div" => Some(PrimOp::Fdiv),

    // Floating-point comparisons
    "FPCMP olt" => Some(PrimOp::Flt),
    "FPCMP ole" => Some(PrimOp::Fle),
    "FPCMP oeq" => Some(PrimOp::Feq),
    "FPCMP ogt" => Some(PrimOp::Fgt),
    "FPCMP oge" => Some(PrimOp::Fge),
    "FPCMP ult" => Some(PrimOp::Flt),
    "FPCMP ule" => Some(PrimOp::Fle),
    "FPCMP ueq" => Some(PrimOp::Feq),
    "FPCMP ugt" => Some(PrimOp::Fgt),
    "FPCMP uge" => Some(PrimOp::Fge),
    // FIXME: these are fake
    "FPCMP une" => Some(PrimOp::Feq),
    "FPCMP uno" => Some(PrimOp::Feq),
    "FPCMP ord" => Some(PrimOp::Feq),
    "FPCMP one" => Some(PrimOp::Feq),

    // Pointer comparisons
    "PTRCMP eq" => Some(PrimOp::Eq),
    "PTRCMP gt" => Some(PrimOp::Gt),
    "PTRCMP ge" => Some(PrimOp::Ge),
    "PTRCMP lt" => Some(PrimOp::Lt),
    "PTRCMP le" => Some(PrimOp::Le),
    "PTRCMP ne" => Some(PrimOp::Ne),

    // Vector operations
    "VECFPOP add" => Some(PrimOp::VECFPOPAdd),
    "VECFPOP sub" => Some(PrimOp::VECFPOPSub),
    "VECFPOP mul" => Some(PrimOp::VECFPOPMul),
    "VECFPOP div" => Some(PrimOp::VECFPOPDiv),
    "VECFPCMP olt" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ole" => Some(PrimOp::VECFPCMP),
    "VECFPCMP oeq" => Some(PrimOp::VECFPCMP),
    "VECFPCMP one" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ogt" => Some(PrimOp::VECFPCMP),
    "VECFPCMP oge" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ult" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ule" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ueq" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ugt" => Some(PrimOp::VECFPCMP),
    "VECFPCMP uge" => Some(PrimOp::VECFPCMP),
    "VECFPCMP une" => Some(PrimOp::VECFPCMP),
    "VECFPCMP uno" => Some(PrimOp::VECFPCMP),
    "VECFPCMP ord" => Some(PrimOp::VECFPCMP),

    // Unsupported operations
    _ => {
      println!("Unsupported binary operation: {}", bop);
      None
    }
  }
}

fn value_op_from_cast_op(
  cast_op: &str,
  from: usize,
  to: usize,
) -> Option<PrimOp> {
  // 首先使用"["切割cast_op字符串，取第一个部分
  let cast_op = cast_op.split('[').next().unwrap_or(cast_op);
  match cast_op {
    "ZExt" => Some(PrimOp::ZExt(from, to)),
    "SEXT" => Some(PrimOp::SExt(from, to)),
    "TRUNC" => Some(PrimOp::Trunc(from, to)),
    "FPTrunc" => Some(PrimOp::FPTrunc),
    "FPExt" => Some(PrimOp::FPExt),
    _ => {
      println!("Unsupported cast operation: {}", cast_op);
      None
    }
  }
}

// fn parse_const_type(const_type: &str) -> RdgType {
//   match const_type {
//     "I64" | "I32" | "I16" | "I8" | "I1" => RdgType::Int,
//     _ if const_type.starts_with("CTL(") => {
//       let inner = &const_type[4..const_type.len()];
//       inner
//         .parse::<i32>()
//         .map(RdgType::CTL)
//         .unwrap_or_else(|_| panic!("Invalid CTL format: {}", const_type))
//     }
//     _ => panic!("Unknown const type: {}", const_type),
//   }
// }

pub fn rdg_from_file<P: AsRef<Path>>(path: P) -> anyhow::Result<RdgProgram> {
  let jlm = fs::read_to_string(path.as_ref())?;
  // println!("{}",jlm);
  jlm_to_rvsdg(&jlm)
}

#[test]
fn test_jlm_to_rvsdg_from_file() {
  use std::env;
  let current_dir =
    env::current_dir().expect("Failed to get current directory");
  println!("Current directory: {:?}", current_dir);

  let file_path = "tests/jlm/test-loop-return.rvsdg";

  let jlm_content =
    fs::read_to_string(file_path).expect("Failed to read JLM RVSDG file");

  match jlm_to_rvsdg(&jlm_content) {
    Ok(rvsdg) => {
      println!("Successfully parsed RVSDG");
      println!("{:?}", rvsdg);
    }
    Err(e) => panic!("Failed to parse JLM RVSDG: {:?}", e),
  }
}
