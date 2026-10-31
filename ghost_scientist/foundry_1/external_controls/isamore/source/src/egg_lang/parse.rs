use super::*;
use babble::ParseLibIdError;
use std::panic;
use std::str::{
  FromStr,
  pattern::{Pattern, ReverseSearcher},
};

#[derive(Clone, Copy, Display, Debug)]
pub enum RdgEggParseError {
  Unknown,
}

impl std::error::Error for RdgEggParseError {}

impl FromStr for RdgEgg {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    let op = match s {
      "apply" | "@" => RdgEggOp::Apply,
      "lambda" | "λ" => RdgEggOp::Lambda,
      "list" => RdgEggOp::List,
      "tuple" => RdgEggOp::Tuple(Tuple {}),
      "switch" => RdgEggOp::Switch,
      "dowhile" => RdgEggOp::DoWhile,
      input => input
        .parse()
        .map(RdgEggOp::Var)
        .or_else(|_| input.parse().map(RdgEggOp::LibVar))
        .or_else(|_| {
          input
            .strip_prefix("lib ")
            .ok_or(ParseLibIdError::NoLeadingL)
            .and_then(|x| {
              x.parse().map(|id| {
                RdgEggOp::Lib(
                  id,
                  OrderedFloat(0.0_f64),
                  OrderedFloat(0.0_f64),
                  0,
                )
              })
            })
        })
        .or_else(|_| input.parse().map(RdgEggOp::Const))
        .or_else(|_| input.parse().map(RdgEggOp::VectorOp))
        .or_else(|_| input.parse().map(RdgEggOp::Top))
        .or_else(|_| input.parse().map(RdgEggOp::Bop))
        // .or_else(|_| input.parse().map(RdgEggOp::Load))
        .or_else(|_| {
          let castop: Result<CastOp, _> = input.parse(); // 尝试解析 input 为 CastOp

          castop.map_or_else(
              |_| Err("Parse failed".to_string()),  // 如果解析失败，返回 Err
              |castop| Ok(RdgEggOp::Uop(UnaryOp::Cast(castop)))  // 如果解析成功，返回 Ok
          )
        })
        .or_else(|_| input.parse().map(RdgEggOp::Uop))
        .or_else(|_| input.parse().map(RdgEggOp::Get))
        .or_else(|_| input.parse().map(RdgEggOp::Arg))
        .or_else(|_| input.parse().map(RdgEggOp::Function))
        .or_else(|_| input.parse().map(RdgEggOp::RulerVar))
        .ok()
        .unwrap_or_else(|| panic!("CANNOT PARSE! \n{}", input)),
    };

    Ok(op.into())
  }
}

pub fn delimited_by<'a, P1: Pattern, P2: Pattern>(
  s: &'a str,
  l: P1,
  r: P2,
) -> Option<&'a str>
where
  for<'b> P2::Searcher<'b>: ReverseSearcher<'b>,
{
  s.strip_prefix(l).and_then(|s| s.strip_suffix(r))
}

pub fn split_twice<'a>(
  s: &'a str,
  delim: &str,
) -> Option<(&'a str, &'a str, &'a str)> {
  let (s1, s) = s.split_once(delim)?;
  let (s2, s3) = s.split_once(delim)?;
  Some((s1, s2, s3))
}

impl FromStr for GetOp {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    // 首先尝试拆分 "get<...>[: ...]" 部分
    let parts: Vec<&str> = s.splitn(2, ':').map(str::trim).collect();

    // 解析 get<...> 部分
    let inner = parts[0]
      .strip_prefix("get<")
      .and_then(|tail| tail.strip_suffix('>'))
      .ok_or(RdgEggParseError::Unknown)?;

    // 解析 Variant[idx]
    let (variant, idx) = parse_variant_idx(inner)?;

    // 解析可选的类型部分（默认为 Unknown 类型）
    let ty = if parts.len() > 1 {
      parts[1].parse::<EggType>()?
    } else {
      EggType::Unknown // 假设 EggType 有 Unknown 变体
    };

    Ok(GetOp::new(variant))
  }
}

/// 辅助函数：解析 "Variant[idx]" 格式
fn parse_variant_idx(
  s: &str,
) -> Result<(GetDataSource, usize), RdgEggParseError> {
  let open_bracket = s.find('[').ok_or(RdgEggParseError::Unknown)?;
  let close_bracket = s.rfind(']').ok_or(RdgEggParseError::Unknown)?;
  if close_bracket <= open_bracket + 1 {
    return Err(RdgEggParseError::Unknown);
  }

  let variant = &s[..open_bracket];
  let idx_str = &s[open_bracket + 1..close_bracket];
  let idx = idx_str
    .parse::<usize>()
    .map_err(|_| RdgEggParseError::Unknown)?;

  let source = match variant {
    "Arg" => GetDataSource::Arg(idx),
    "DoWhileVar" => GetDataSource::DoWhileVar(idx),
    "Dummy" => GetDataSource::Dummy(idx),
    "SwitchBranch" => GetDataSource::SwitchBranch(idx),
    "VecElement" => GetDataSource::VecElement(idx),
    "MemState" => GetDataSource::MemState(idx),
    _ => return Err(RdgEggParseError::Unknown),
  };

  Ok((source, idx))
}
impl FromStr for Arg {
  type Err = RdgEggParseError;
  fn from_str(s: &str) -> Result<Self, Self::Err> {
    let s = s.trim();
    // 必须以 "arg" 开头
    if let Some(rest) = s.strip_prefix("arg") {
      let rest = rest.trim();
      if rest.is_empty() {
        // 纯 "arg"
        return Ok(Arg { bbs: Vec::new() });
      }
      // 期望 "[...]" 包裹
      if rest.starts_with('[') && rest.ends_with(']') {
        let inner = &rest[1..rest.len() - 1];
        // 如果方括号内为空或者全空白，则 bbs 为空 Vec
        if inner.trim().is_empty() {
          return Ok(Arg { bbs: Vec::new() });
        }
        // 否则按逗号分隔，trim 每项
        let mut bbs = Vec::new();
        for part in inner.split(',') {
          let name = part.trim();
          if name.is_empty() {
            // 出现如 "arg[a,,b]" 中间空项，视为格式错误
            return Err(RdgEggParseError::Unknown);
          }
          // 你可以根据需要验证 name 合法性（如匹配特定正则）
          bbs.push(name.to_string());
        }
        return Ok(Arg { bbs });
      }
      // 如果 rest 不是空且不符合方括号格式，则报错
      Err(RdgEggParseError::Unknown)
    } else {
      Err(RdgEggParseError::Unknown)
    }
  }
}

impl FromStr for Function {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    s.strip_prefix("function")
      .and_then(|s| delimited_by(s, '[', ']'))
      .and_then(|s| {
        Some(Function {
          name: s.to_string(),
        })
      })
      .ok_or(RdgEggParseError::Unknown)
  }
}

impl FromStr for Dummy {
  type Err = RdgEggParseError;
  fn from_str(s: &str) -> Result<Self, Self::Err> {
    s.strip_prefix("dummy")
      .and_then(|s| delimited_by(s, '[', ']'))
      .and_then(|s| {
        Some(Dummy {
          name: s.to_string(),
        })
      })
      .ok_or(RdgEggParseError::Unknown)
  }
}
