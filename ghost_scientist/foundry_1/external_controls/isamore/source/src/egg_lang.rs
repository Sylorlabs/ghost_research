//! Egg language binding of RDG program

mod opinfo;
mod parse;
mod print;
mod teach;

pub mod schedule;
#[cfg(test)]
mod tests;
use babble::{
  AstNode, DiscriminantEq,
  au_filter::TypeAnalysis,
  teachable::{
    ShieldingBop, ShieldingConst, ShieldingOp, ShieldingTop, ShieldingUop,
  },
};
use egg::{FromOp, Language, RecExpr};
use graphviz_rust::attributes::width;
pub use parse::*;
// pub use print::*;
pub mod ast;
pub mod synth_enumo;

use babble::extract::beam_pareto::TypeInfo;
use babble::runner::OperationInfo;
use itertools::Itertools;
use std::{
  borrow::Borrow,
  cmp::Ordering,
  collections::HashMap,
  fmt::{Display, Formatter},
  hash::{Hash, Hasher},
  ops::Neg,
  rc::Rc,
  str::FromStr,
  sync::Arc,
  vec,
};

use ordered_float::OrderedFloat;
use strum::{Display, EnumIter, EnumString};

#[derive(Debug, Clone)]
pub struct RdgEgg {
  pub op: RdgEggOp,
  pub info: RdgEggInfo,
}

// 注意: bbs的信息只为了记录，Hash、Eq、PartialEq等操作不需要
// 不考虑VecOp的ty是因为可以在AstNode中考虑，而如果考虑了ty，
// 会导致rewrite匹配不到
impl PartialEq for RdgEgg {
  fn eq(&self, other: &Self) -> bool {
    // RdgEgg相同，必须要op和type都相同
    self.op == other.op
  }
}

impl Eq for RdgEgg {}

impl Hash for RdgEgg {
  fn hash<H: Hasher>(&self, state: &mut H) {
    self.op.hash(state);
  }
}

impl PartialOrd for RdgEgg {
  fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
    Some(self.cmp(other))
  }
}

impl Ord for RdgEgg {
  fn cmp(&self, other: &Self) -> Ordering {
    use RdgEggOp::*;
    match (&self.op, &other.op) {
      // Dummy/Arg 要同时比 op 和 info.bbs
      (Dummy(_), Dummy(_)) | (Arg(_), Arg(_)) => {
        // 先按 op 的内部值排序（比如 Hole 编号）
        match self.op.cmp(&other.op) {
          Ordering::Equal => {
            // op 相同，再比 bbs
            self.info.bbs.cmp(&other.info.bbs)
          }
          ord => ord,
        }
      }

      // 其它情况，仅按 op 排序
      _ => self.op.cmp(&other.op),
    }
  }
}

// 为RdgEgg实现PatialEq<String> trait,这是为了比较简单地构造符号关系表
impl PartialEq<String> for RdgEgg {
  fn eq(&self, other: &String) -> bool {
    let op = self.op.to_string();
    op == *other
  }
}

impl Display for RdgEgg {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(
      f,
      "{}",
      self.op /* if !self.info.is_empty() {
               *   format!("[{}]", self.info)
               * } else {
               *   "".to_string()
               * } */
    )
  }
}

#[derive(Default, Debug, Clone)]
pub struct RdgEggInfo {
  pub bbs: Vec<String>,
  pub result_tys: Vec<EggType>,
}

impl RdgEggInfo {
  pub fn is_empty(&self) -> bool {
    self.bbs.is_empty()
  }
  pub fn with_tys(self, tys: Vec<EggType>) -> Self {
    Self {
      result_tys: tys,
      ..self
    }
  }
}

impl Display for RdgEggInfo {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(
      f,
      "{}|{}",
      self
        .result_tys
        .iter()
        .map(|ty| ty.to_string())
        .collect::<Vec<_>>()
        .join(","),
      self.bbs.join(",")
    )
  }
}
impl PartialEq for RdgEggInfo {
  fn eq(&self, _other: &Self) -> bool {
    // 这里实际上写了一个类型的比较函数，针对一个rewrite，使用lhs
    // search过程中，其中的中间节点不会有任何ty，
    // 因此默认如果self和other的tys有一个为空，就默认相等，否则正常比较
    if self.result_tys.is_empty() || _other.result_tys.is_empty() {
      return true;
    }
    if self.result_tys.len() != _other.result_tys.len() {
      return false;
    }
    self.result_tys == _other.result_tys
  }
}

impl Eq for RdgEggInfo {}

impl PartialOrd for RdgEggInfo {
  fn partial_cmp(&self, _other: &Self) -> Option<Ordering> {
    self.result_tys.partial_cmp(&_other.result_tys)
  }
}

impl Ord for RdgEggInfo {
  fn cmp(&self, _other: &Self) -> Ordering {
    self.result_tys.cmp(&_other.result_tys)
  }
}

impl From<RdgEggOp> for RdgEgg {
  fn from(op: RdgEggOp) -> Self {
    match op {
      RdgEggOp::Const(RdgConst::Int(_, w)) => RdgEgg {
        op,
        info: RdgEggInfo::default()
          .with_tys(vec![EggType::IntT(w.map(|w| w as usize))]),
      },
      RdgEggOp::Const(RdgConst::Float(_, w)) => RdgEgg {
        op,
        info: RdgEggInfo::default()
          .with_tys(vec![EggType::float(w.map(|w| w as usize).unwrap_or(64))]),
      },
      _ => RdgEgg {
        op,
        info: RdgEggInfo::default(),
      },
    }
  }
}

#[derive(Debug, Clone, PartialOrd, Ord, PartialEq, Eq, Hash, Display)]
pub enum RdgEggOp {
  /// List (required by babble)
  #[strum(to_string = "list")]
  List,
  /// An anonymous function (required by babble)
  #[strum(to_string = "λ")]
  Lambda,
  /// Apply a babble function (required by babble)
  #[strum(to_string = "apply")]
  Apply,
  /// A DeBrujn indexed lambda variable (required by babble)
  #[strum(to_string = "var")]
  Var(babble::DeBruijnIndex),
  /// A library function binding (required by babble)
  #[strum(to_string = "lib")]
  Lib(babble::LibId, OrderedFloat<f64>, OrderedFloat<f64>, usize),
  /// A reference to a lib var (required by babble)
  #[strum(to_string = "libvar")]
  LibVar(babble::LibId),
  /// #operands = 0
  #[strum(to_string = "{0}")]
  Const(RdgConst),
  /// #operands = 3
  #[strum(to_string = "{0}")]
  Top(TernaryOp),
  /// #operands = 2
  #[strum(to_string = "{0}")]
  Bop(BinaryOp),
  /// #operands = 1
  #[strum(to_string = "{0}")]
  Uop(UnaryOp),
  /// #operands = 1
  #[strum(to_string = "{0}")]
  Get(GetOp),
  /// #operands >=2
  #[strum(to_string = "{0}")]
  Tuple(Tuple),
  /// #operands = 2 + #branch
  #[strum(to_string = "switch")]
  Switch,
  /// #operands = 2
  #[strum(to_string = "dowhile")]
  DoWhile,
  /// #operands = 0
  #[strum(to_string = "{0}")]
  Arg(Arg),
  /// #operands = 1
  #[strum(to_string = "{0}")]
  Function(Function),
  /// #operands = variable
  /// Used for any unsupported operations
  #[strum(to_string = "{0}")]
  Dummy(Dummy),

  /// #operands = 2
  #[strum(to_string = "io_barrier")]
  IOBarrier,

  #[strum(to_string = "{0}")]
  VectorOp(VectorOp),

  #[strum(to_string = "{0}")]
  RulerVar(egg::Symbol),

  #[strum(to_string = "{0}")]
  OpPack(OpPack),

  #[strum(to_string = "op_select")]
  OpSelect,
  // 用于在babble的meta-au中使用，此Op和其他所有的Op都可以相等
  // 注意，这一个类型永远只能用作匹配，不能放在EGraph里面，
  // 也永远不能插入到Hash相关的数据结构中，否则会造成错误！！！
  #[strum(to_string = "op_mask")]
  OpMask,
}

impl RdgEggOp {
  pub fn with(self, info: RdgEggInfo) -> RdgEgg {
    RdgEgg { op: self, info }
  }
}

impl DiscriminantEq for RdgEgg {
  fn discriminant_eq(&self, other: &Self) -> bool {
    // 判断相同的条件的是op本身相同
    self.op == other.op
  }
}

// 为RdgEgg实现Default trait
impl Default for RdgEgg {
  fn default() -> Self {
    RdgEggOp::Const(RdgConst::int(0, Some(64))).into()
  }
}

/// 表示数据的不同来源
#[derive(Debug, Clone, PartialEq, Eq, Hash, Copy, PartialOrd, Ord)]
pub enum GetDataSource {
  /// 函数参数，第 ith 个
  Arg(usize),

  /// do-while 循环内部的变量
  DoWhileVar(usize),

  /// 占位或临时变量
  Dummy(usize),

  /// switch 分支结果，第 ith 个分支
  SwitchBranch(usize),

  /// 向量（vector）元素，第 ith 个元素
  VecElement(usize),

  /// 从Load/ Store中获取的值
  MemState(usize),
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct GetOp {
  pub source: GetDataSource,
  // pub ty: EggType,
}
impl GetOp {
  /// 构造一个新的 GetOp，从给定的数据源获取值
  pub fn new(source: GetDataSource) -> Self {
    Self { source }
  }
  /// 获取数据源的索引
  pub fn index(&self) -> usize {
    match self.source {
      GetDataSource::Arg(i) => i,
      GetDataSource::DoWhileVar(i) => i,
      GetDataSource::Dummy(i) => i,
      GetDataSource::SwitchBranch(i) => i,
      GetDataSource::VecElement(i) => i,
      GetDataSource::MemState(i) => i,
    }
  }
}

impl Display for GetOp {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    // let ty_str = format!("{}", self.ty);
    match &self.source {
      GetDataSource::Arg(i) => write!(f, "get<Arg[{}]>", i),
      GetDataSource::DoWhileVar(i) => {
        write!(f, "get<DoWhileVar[{}]>", i)
      }
      GetDataSource::Dummy(i) => write!(f, "get<Dummy[{}]>", i),
      GetDataSource::SwitchBranch(i) => {
        write!(f, "get<SwitchBranch[{}]>", i)
      }
      GetDataSource::VecElement(i) => {
        write!(f, "get<VecElement[{}]>", i)
      }
      GetDataSource::MemState(i) => {
        write!(f, "get<MemState[{}]>", i)
      }
    }
  }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Tuple {}
impl Display for Tuple {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "tuple")
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Arg {
  pub bbs: Vec<String>,
}

impl Display for Arg {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    if self.bbs.is_empty() {
      write!(f, "arg")
    } else {
      // join 用逗号分隔
      let inner = self.bbs.join(",");
      write!(f, "arg[{}]", inner)
    }
  }
}

impl Arg {
  pub fn genericize(&mut self) {
    // 清空 bbs
    self.bbs.clear();
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Function {
  name: String,
}
impl Display for Function {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "function[{}]", self.name)
  }
}
impl From<String> for Function {
  fn from(value: String) -> Self {
    Self { name: value }
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct Dummy {
  name: String,
}

impl Dummy {
  pub fn new(name: String) -> Self {
    Self { name }
  }
}

impl Display for Dummy {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "dummy[{}]", self.name)
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct OpPack {
  /// ALUConfig构建了一个ALU的demo，其中的String分别包括一种操作，
  /// 为了方便没有用RdgEggOp
  pub config: Vec<String>,
}
impl Display for OpPack {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "op_pack[{}]", self.config.join(","))
  }
}

// #[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
// pub struct OpSelect {
//   /// ALUSelect从ALUConfig中选择一个操作，是一个计算节点
//   pub idx: usize,
// }
// impl Display for OpSelect {
//   fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
//     write!(f, "op_select[{}]", self.idx)
//   }
// }

#[derive(Debug, Clone, Hash, PartialOrd, Ord)]
pub enum EggType {
  IntT(Option<usize>),
  FloatT(Option<usize>),
  VectorT(Box<EggType>, Option<usize>),
  Unknown,
}

impl TypeAnalysis for EggType {
  fn width(&self) -> Option<u32> {
    match self {
      EggType::IntT(Some(n)) => Some(*n as u32),
      EggType::IntT(None) => Some(32),
      EggType::FloatT(Some(n)) => Some(*n as u32),
      EggType::FloatT(None) => Some(32),
      EggType::VectorT(ty, _) => ty.width(),
      EggType::Unknown => None,
    }
  }
  fn length(&self) -> u32 {
    match self {
      EggType::VectorT(_, Some(size)) => *size as u32,
      EggType::VectorT(_, None) => 1, // 默认长度为1
      _ => 1,                         // 非向量类型默认长度为1
    }
  }
  fn is_state_type(&self) -> bool {
    if matches!(self, EggType::IntT(Some(0))) {
      return true;
    }
    false
  }
  fn extra_vector_bits(&self) -> u8 {
    2
  }
}

impl Display for EggType {
  fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
    match self {
      EggType::IntT(Some(n)) => write!(f, "int<{}>", n),
      EggType::IntT(None) => write!(f, "int"),
      EggType::FloatT(Some(n)) => write!(f, "float<{}>", n),
      EggType::FloatT(None) => write!(f, "float"),
      EggType::VectorT(inner, Some(size)) => {
        write!(f, "vector<{};{}>", inner, size)
      }
      EggType::VectorT(inner, None) => write!(f, "vector<{}>", inner),
      EggType::Unknown => write!(f, "unknown"),
    }
  }
}

impl PartialEq for EggType {
  fn eq(&self, other: &Self) -> bool {
    match (self, other) {
      (EggType::IntT(Some(a)), EggType::IntT(Some(b))) => a == b,
      (EggType::IntT(None), EggType::IntT(None)) => true,
      (EggType::IntT(None), EggType::IntT(w))
      | (EggType::IntT(w), EggType::IntT(None)) => {
        // 注意，w可能是Some(0),
        // 这表示这个类型是一个状态类型，这个类型不能和None比较
        if let Some(w) = w { *w != 0 } else { true }
      }
      (EggType::FloatT(Some(a)), EggType::FloatT(Some(b))) => a == b,
      (EggType::FloatT(None), EggType::FloatT(None))
      | (EggType::FloatT(None), EggType::FloatT(_))
      | (EggType::FloatT(_), EggType::FloatT(None)) => true,
      (
        EggType::VectorT(a, Some(size_a)),
        EggType::VectorT(b, Some(size_b)),
      ) => {
        if size_a == size_b {
          a == b
        } else {
          false
        }
      }
      (EggType::VectorT(a, None), EggType::VectorT(b, None))
      | (EggType::VectorT(a, None), EggType::VectorT(b, Some(_)))
      | (EggType::VectorT(a, Some(_)), EggType::VectorT(b, None)) => a == b,
      // Unknown可以和任何类型比较
      // (EggType::Unknown, _) | (_, EggType::Unknown) => true,
      (EggType::Unknown, EggType::Unknown) => true,
      _ => false,
    }
  }
}

impl Eq for EggType {}

impl Default for EggType {
  fn default() -> Self {
    EggType::Unknown
  }
}

impl FromStr for EggType {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    let s = s.trim();

    // 处理特殊类型
    match s {
      "bool" => return Ok(Self::IntT(Some(1))),
      "unknown" => return Ok(Self::Unknown),
      _ => {}
    }

    // 解析IntT
    if let Some(inner) =
      s.strip_prefix("int<").and_then(|s| s.strip_suffix('>'))
    {
      let size = inner.parse().map_err(|_| RdgEggParseError::Unknown)?;
      return Ok(Self::IntT(Some(size)));
    }
    if s == "int" {
      return Ok(Self::IntT(None));
    }

    // 解析FloatT
    if let Some(inner) =
      s.strip_prefix("float<").and_then(|s| s.strip_suffix('>'))
    {
      let size = inner.parse().map_err(|_| RdgEggParseError::Unknown)?;
      return Ok(Self::FloatT(Some(size)));
    }
    if s == "float" {
      return Ok(Self::FloatT(None));
    }

    // 解析VectorT
    if let Some(inner) =
      s.strip_prefix("vector<").and_then(|s| s.strip_suffix('>'))
    {
      let mut parts = inner.splitn(2, ';');
      let elem_type = parts.next().ok_or(RdgEggParseError::Unknown)?;
      let size_part = parts.next();

      let elem_type = elem_type.parse()?;
      let size = size_part
        .map(|s| s.parse())
        .transpose()
        .map_err(|_| RdgEggParseError::Unknown)?;

      return Ok(Self::VectorT(Box::new(elem_type), size));
    }

    Err(RdgEggParseError::Unknown)
  }
}

impl EggType {
  /// 判断是否为数值类型（整数或浮点）
  pub fn is_numeric(&self) -> bool {
    // TODO: can unknwon be handled?
    matches!(
      self,
      EggType::IntT(_) | EggType::FloatT(_) | EggType::Unknown
    )
  }
  /// 判断是否为整数
  pub fn is_int(&self) -> bool {
    matches!(self, EggType::IntT(_) | EggType::Unknown)
  }

  pub fn int(width: usize) -> Self {
    EggType::IntT(Some(width))
  }
  pub fn float(width: usize) -> Self {
    EggType::FloatT(Some(width))
  }

  pub fn is_vector(&self) -> bool {
    matches!(self, EggType::VectorT(_, _))
  }
}

#[derive(Debug, Clone, PartialOrd, Ord, Hash)]
pub enum RdgConst {
  Int(i64, Option<u32>),                 // i64, 位宽
  Float(OrderedFloat<f64>, Option<u32>), // f64, 位宽
  VecInt(Vec<i64>, u32),
  VecFloat(Vec<OrderedFloat<f64>>, u32),
}

impl PartialEq for RdgConst {
  fn eq(&self, other: &Self) -> bool {
    match (self, other) {
      (RdgConst::Int(a, Some(aw)), RdgConst::Int(b, Some(bw))) => {
        a == b && aw == bw
      }
      (RdgConst::Int(a, None), RdgConst::Int(b, _))
      | (RdgConst::Int(a, _), RdgConst::Int(b, None)) => a == b,
      (RdgConst::Float(a, Some(aw)), RdgConst::Float(b, Some(bw))) => {
        a == b && aw == bw
      }
      (RdgConst::Float(a, None), RdgConst::Float(b, _))
      | (RdgConst::Float(a, _), RdgConst::Float(b, None)) => a == b,
      (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) => a == b && aw == bw,
      _ => false,
    }
  }
}
impl Eq for RdgConst {}

const PROTECT_LIMIT: i64 = 10000000000000000;

macro_rules! same_type_then_protect {
  ($a:ident, $b:ident => $e:expr; $tyi:ident, $tyf:ident) => {
    match $a.same_type_with($b) {
      SameType::Int($a, aw, $b, bw) => {
        let _x = $e;
        let merged_width = match (aw, bw) {
          (Some(a), Some(b)) => Some(a.max(b)),
          (Some(a), None) => Some(a),
          (None, Some(b)) => Some(b),
          (None, None) => None,
        };
        if _x < PROTECT_LIMIT && _x > -PROTECT_LIMIT {
          Some(RdgConst::$tyi(_x, merged_width))
        } else {
          None
        }
      }
      SameType::Float($a, aw, $b, bw) => {
        let merged_width = match (aw, bw) {
          (Some(a), Some(b)) => Some(a.max(b)),
          (Some(a), None) => Some(a),
          (None, Some(b)) => Some(b),
          (None, None) => None,
        };
        Some(RdgConst::$tyf($e, merged_width))
      }
      SameType::None => None,
    }
  };
  ($a:ident, $b:ident => $e:expr; $tyi:ident) => {
    match $a.same_type_with($b) {
      SameType::Int($a, aw, $b, bw) => {
        let _x = $e;
        if _x < PROTECT_LIMIT && _x > -PROTECT_LIMIT {
          Some(RdgConst::$tyi(_x, aw.max(bw)))
        } else {
          None
        }
      }
      SameType::Float(_, _, _, _) => None,
      SameType::None => None,
    }
  };
}
macro_rules! same_type_then {
  ($a:ident, $b:ident => $e:expr; $tyi:ident, $tyf:ident) => {
    match $a.same_type_with($b) {
      SameType::Int($a, aw, $b, bw) => {
        let merged_width = match (aw, bw) {
          (Some(a), Some(b)) => Some(a.max(b)),
          (Some(a), None) => Some(a),
          (None, Some(b)) => Some(b),
          (None, None) => None,
        };
        Some(RdgConst::$tyi(($e).into(), merged_width))
      }
      SameType::Float($a, aw, $b, bw) => {
        let merged_width = match (aw, bw) {
          (Some(a), Some(b)) => Some(a.max(b)),
          (Some(a), None) => Some(a),
          (None, Some(b)) => Some(b),
          (None, None) => None,
        };
        Some(RdgConst::$tyf(($e).into(), merged_width))
      }
      SameType::None => None,
    }
  };
  ($a:ident, $b:ident => $e:expr; $tyi:ident) => {
    match $a.same_type_with($b) {
      SameType::Int($a, aw, $b, bw) => Some(RdgConst::$tyi(($e).into())),
      SameType::Float(_, _) => None,
      SameType::None => None,
    }
  };
}

impl RdgConst {
  pub fn int(i: i64, width: Option<u32>) -> Self {
    Self::Int(i, width)
  }

  pub fn float(f: f64, width: Option<u32>) -> Self {
    Self::Float(f.into(), width)
  }

  pub fn vec_int(v: Vec<i64>, width: u32) -> Self {
    Self::VecInt(v, width)
  }

  pub fn as_int(&self) -> Option<(i64, Option<u32>)> {
    // 返回值和位宽
    match self {
      Self::Int(i, w) => Some((*i, *w)),
      _ => None,
    }
  }

  pub fn as_float(&self) -> Option<(f64, Option<u32>)> {
    // 返回值和位宽
    match self {
      Self::Float(f, w) => Some(((*f).into(), *w)),
      _ => None,
    }
  }

  pub fn same_type_with(&self, other: &Self) -> SameType {
    if let (Some((a, aw)), Some((b, bw))) = (self.as_int(), other.as_int()) {
      SameType::Int(a, aw, b, bw) // 需要修改 SameType 定义
    } else if let (Some((a, aw)), Some((b, bw))) =
      (self.as_float(), other.as_float())
    {
      SameType::Float(a, aw, b, bw) // 需要修改 SameType 定义
    } else {
      SameType::None
    }
  }

  pub fn select(cond: &Self, thn: &Self, els: &Self) -> Option<RdgConst> {
    match cond.as_int() {
      Some((x, _))
        if (x == 0 || x == 1) && thn.same_type_with(els).as_bool() =>
      {
        if x != 0 {
          Some(thn.clone())
        } else {
          Some(els.clone())
        }
      }
      _ => None,
    }
  }

  pub fn bop(bop: BinaryOp, lhs: &Self, rhs: &Self) -> Option<RdgConst> {
    use BinaryOp as B;
    match bop {
      B::Add => same_type_then_protect!(lhs, rhs => lhs + rhs; int, float),
      B::Sub => same_type_then_protect!(lhs, rhs => lhs - rhs; int, float),
      B::Mul => same_type_then_protect!(lhs, rhs => lhs * rhs; int, float),
      B::Div => match lhs.same_type_with(rhs) {
        SameType::Int(lhs, lhsw, rhs, rhsw) => {
          if rhs != 0 {
            Some(RdgConst::int(lhs / rhs, lhsw.max(rhsw)))
          } else {
            None
          }
        }
        SameType::Float(lhs, lhsw, rhs, rhsw) => {
          if rhs != 0f64 {
            Some(RdgConst::float(lhs / rhs, lhsw.max(rhsw)))
          } else {
            None
          }
        }
        SameType::None => None,
      },
      B::Mod => match lhs.same_type_with(rhs) {
        SameType::Int(lhs, lhsw, rhs, rhsw) => {
          if rhs != 0 {
            Some(RdgConst::int(lhs % rhs, lhsw.max(rhsw)))
          } else {
            None
          }
        }
        SameType::Float(_, _, _, _) => None,
        SameType::None => None,
      },
      B::Eq => same_type_then!(lhs, rhs => lhs == rhs; int, int),
      B::Ne => same_type_then!(lhs, rhs => lhs != rhs; int, int),
      B::LessThan => same_type_then!(lhs, rhs => lhs < rhs; int, int),
      B::GreaterThan => same_type_then!(lhs, rhs=>lhs > rhs; int, int),
      B::LessEq => same_type_then!(lhs, rhs => lhs <= rhs; int, int),
      B::GreaterEq => same_type_then!(lhs, rhs => lhs >= rhs; int, int),
      B::Shl => match lhs.same_type_with(rhs) {
        SameType::Int(lhs, lhsw, rhs, rhsw) => {
          if lhs >= 0 && rhs >= 0 && rhs < 64 && (lhs << rhs < PROTECT_LIMIT) {
            Some(RdgConst::int(lhs << rhs, lhsw.max(rhsw)))
          } else {
            None
          }
        }
        SameType::Float(_, _, _, _) => None,
        SameType::None => None,
      },
      B::Shr => match lhs.same_type_with(rhs) {
        SameType::Int(lhs, lhsw, rhs, rhsw) => {
          if lhs >= 0 && rhs >= 0 && rhs < 64 {
            Some(RdgConst::int(lhs >> rhs, lhsw.max(rhsw)))
          } else {
            None
          }
        }
        SameType::Float(_, _, _, _) => None,
        SameType::None => None,
      },
      B::And => same_type_then_protect!(lhs, rhs => lhs & rhs; int),
      B::Or => same_type_then_protect!(lhs, rhs => lhs | rhs; int),
      B::Xor => same_type_then_protect!(lhs, rhs => lhs ^ rhs; int),
      B::Max => same_type_then!(lhs, rhs => lhs.max(rhs); int, float),
      B::Min => same_type_then!(lhs, rhs => lhs.min(rhs); int, float),
      B::Load => todo!(),
      B::StateMerge => todo!(),
    }
  }

  pub fn abs(&self) -> Option<RdgConst> {
    match self {
      RdgConst::Int(i, iw) => Some(RdgConst::int(i.abs(), *iw)),
      RdgConst::Float(ordered_float, fw) => {
        Some(RdgConst::float(ordered_float.abs(), *fw))
      }
      RdgConst::VecInt(_, _) => None,
      RdgConst::VecFloat(_, _) => None,
    }
  }
  pub fn not(&self) -> Option<RdgConst> {
    match self {
      RdgConst::Int(i, iw) => Some(RdgConst::int((*i != 0) as i64, *iw)),
      RdgConst::Float(f, fw) => Some(RdgConst::int(f.ne(&0.0) as i64, *fw)),
      RdgConst::VecInt(_, _) => None,
      RdgConst::VecFloat(_, _) => None,
    }
  }
  pub fn neg(&self) -> Option<RdgConst> {
    match self {
      RdgConst::Int(i, iw) => Some(RdgConst::int(-i, *iw)),
      RdgConst::Float(f, fw) => Some(RdgConst::float(-f.into_inner(), *fw)),
      RdgConst::VecInt(_, _) => None,
      RdgConst::VecFloat(_, _) => None,
    }
  }
  pub fn uop(uop: UnaryOp, x: &Self) -> Option<RdgConst> {
    match uop {
      UnaryOp::Abs => x.abs(),
      UnaryOp::Not => x.not(),
      UnaryOp::Neg => x.neg(),
      UnaryOp::Cast(_) => todo!(),
    }
  }
  // 加入向量操作符
  pub fn vec_abs(&self) -> Option<RdgConst> {
    match self {
      RdgConst::VecInt(v, iw) => {
        Some(RdgConst::VecInt(v.iter().map(|x| x.abs()).collect(), *iw))
      }
      _ => None,
    }
  }
  pub fn vec_not(&self) -> Option<RdgConst> {
    match self {
      RdgConst::VecInt(v, iw) => Some(RdgConst::VecInt(
        v.iter().map(|x| (*x != 0) as i64).collect(),
        *iw,
      )),
      _ => None,
    }
  }
  /// element‑wise add
  pub fn vec_add(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let v = a.iter().zip(b.iter()).map(|(x, y)| x + y).collect();
        Some(RdgConst::vec_int(v, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise subtract
  pub fn vec_sub(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let v = a.iter().zip(b.iter()).map(|(x, y)| x - y).collect();
        Some(RdgConst::vec_int(v, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise multiply
  pub fn vec_mul(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let v = a.iter().zip(b.iter()).map(|(x, y)| x * y).collect();
        Some(RdgConst::vec_int(v, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise division (None on div-by-zero)
  pub fn vec_div(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let mut out = Vec::with_capacity(a.len());
        for (x, y) in a.iter().zip(b.iter()) {
          if *y == 0 {
            return None;
          }
          out.push(x / y);
        }
        Some(RdgConst::vec_int(out, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise remainder
  pub fn vec_rem(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let mut out = Vec::with_capacity(a.len());
        for (x, y) in a.iter().zip(b.iter()) {
          if *y == 0 {
            return None;
          }
          out.push(x % y);
        }
        Some(RdgConst::vec_int(out, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise bitwise and
  pub fn vec_and(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let v = a.iter().zip(b.iter()).map(|(x, y)| x & y).collect();
        Some(RdgConst::vec_int(v, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// element‑wise bitwise or
  pub fn vec_or(&self, other: &Self) -> Option<RdgConst> {
    if let (RdgConst::VecInt(a, aw), RdgConst::VecInt(b, bw)) = (self, other) {
      if a.len() == b.len() {
        let v = a.iter().zip(b.iter()).map(|(x, y)| x | y).collect();
        Some(RdgConst::vec_int(v, *aw.max(bw)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// multiply‑accumulate: acc[i] + a[i] * b[i]
  pub fn vec_mac(acc: &Self, a: &Self, b: &Self) -> Option<RdgConst> {
    if let (
      RdgConst::VecInt(v0, w0),
      RdgConst::VecInt(v1, w1),
      RdgConst::VecInt(v2, w2),
    ) = (acc, a, b)
    {
      if v0.len() == v1.len() && v1.len() == v2.len() {
        let v = v0
          .iter()
          .zip(v1.iter().zip(v2.iter()))
          .map(|(c, (x, y))| c + x * y)
          .collect();
        Some(RdgConst::vec_int(v, *w0.max(w1).max(w2)))
      } else {
        None
      }
    } else {
      None
    }
  }

  /// signum: -1,0,1 element‑wise
  pub fn vec_sgn(&self) -> Option<RdgConst> {
    if let RdgConst::VecInt(v, iw) = self {
      let out = v
        .iter()
        .map(|x| match x.cmp(&0) {
          std::cmp::Ordering::Less => -1,
          std::cmp::Ordering::Equal => 0,
          std::cmp::Ordering::Greater => 1,
        })
        .collect();
      Some(RdgConst::vec_int(out, *iw))
    } else {
      None
    }
  }

  /// zero‑extend each element to the same width
  pub fn vec_sext(&self) -> Option<RdgConst> {
    if let RdgConst::VecInt(v, iw) = self {
      // 这里简单保持元素不变，只更新位宽为自身的 max(旧宽, 新宽)
      Some(RdgConst::vec_int(v.clone(), *iw))
    } else {
      None
    }
  }

  pub fn vec_neg(&self) -> Option<RdgConst> {
    if let RdgConst::VecInt(v, iw) = self {
      let out = v.iter().map(|x| -x).collect();
      Some(RdgConst::vec_int(out, *iw))
    } else {
      None
    }
  }
}

#[derive(Debug, Clone, Copy)]
pub enum SameType {
  Int(i64, Option<u32>, i64, Option<u32>), // 添加位宽信息
  Float(f64, Option<u32>, f64, Option<u32>), // 添加位宽信息
  None,
}

impl SameType {
  pub fn as_bool(&self) -> bool {
    match self {
      SameType::None => false,
      _ => true,
    }
  }
}

impl FromStr for RdgConst {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    if let Some((num_str, rest)) = s.split_once('i') {
      let num = num_str
        .parse::<i64>()
        .map_err(|_| RdgEggParseError::Unknown)?;
      let width = if rest.is_empty() {
        None
      } else {
        Some(rest.parse::<u32>().map_err(|_| RdgEggParseError::Unknown)?)
      };
      Ok(RdgConst::Int(num, width))
    } else if let Some((num_str, rest)) = s.split_once('f') {
      let num = num_str
        .parse::<f64>()
        .map_err(|_| RdgEggParseError::Unknown)?;
      let width = if rest.is_empty() {
        None
      } else {
        Some(rest.parse::<u32>().map_err(|_| RdgEggParseError::Unknown)?)
      };
      Ok(RdgConst::Float(OrderedFloat(num), width))
    } else {
      Err(RdgEggParseError::Unknown)
    }
  }
}
impl std::fmt::Display for RdgConst {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    match self {
      Self::Int(i, iw) => {
        if let Some(w) = iw {
          write!(f, "{}i{}", i, w)
        } else {
          write!(f, "{}i", i)
        }
      }
      Self::Float(flt, fw) => {
        if let Some(w) = fw {
          write!(f, "{}f{}", flt, w)
        } else {
          write!(f, "{}f", flt)
        }
      }
      Self::VecInt(v, iw) => {
        write!(f, "[")?;
        for (i, x) in v.iter().enumerate() {
          if i != 0 {
            write!(f, ",")?;
          }
          write!(f, "{}", x)?;
        }
        write!(f, "]vi{}", iw)
      }
      Self::VecFloat(v, fw) => {
        write!(f, "[")?;
        for (i, x) in v.iter().enumerate() {
          if i != 0 {
            write!(f, ",")?;
          }
          write!(f, "{}", x)?;
        }
        write!(f, "]vf{}", fw)
      }
    }
  }
}

#[derive(
  Debug,
  Clone,
  Copy,
  PartialEq,
  Eq,
  EnumIter,
  PartialOrd,
  Ord,
  Hash,
  Display,
  EnumString,
)]
pub enum TernaryOp {
  #[strum(to_string = "store")]
  Store,
  #[strum(to_string = "select")]
  Select,
}

#[derive(
  Debug,
  Clone,
  PartialEq,
  Copy,
  Eq,
  PartialOrd,
  Ord,
  Hash,
  Display,
  EnumIter,
  EnumString,
)]
pub enum BinaryOp {
  #[strum(to_string = "add")]
  Add,
  #[strum(to_string = "sub")]
  Sub,
  #[strum(to_string = "mul")]
  Mul,
  #[strum(to_string = "div")]
  Div,
  #[strum(to_string = "mod")]
  Mod,
  #[strum(to_string = "eq")]
  Eq,
  #[strum(to_string = "ne")]
  Ne,
  #[strum(to_string = "lt")]
  LessThan,
  #[strum(to_string = "gt")]
  GreaterThan,
  #[strum(to_string = "le")]
  LessEq,
  #[strum(to_string = "ge")]
  GreaterEq,
  #[strum(to_string = "max")]
  Max,
  #[strum(to_string = "min")]
  Min,
  #[strum(to_string = "shl")]
  Shl,
  #[strum(to_string = "shr")]
  Shr,
  #[strum(to_string = "and")]
  And,
  #[strum(to_string = "or")]
  Or,
  #[strum(to_string = "xor")]
  Xor,
  #[strum(to_string = "statemerge")]
  StateMerge,
  #[strum(to_string = "load")]
  Load, // 这里的Load是一个特殊的二元操作符
}

// #[derive(Debug, Clone, PartialOrd, Ord, Hash)]
// pub enum Load {
//   Any,
//   Typed(EggType),
// }

// impl Display for Load {
//   fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
//     match self {
//       Load::Any => write!(f, "load"),
//       Load::Typed(ty) => write!(f, "load<{}>", ty),
//     }
//   }
// }

// impl FromStr for Load {
//   type Err = RdgEggParseError;

//   fn from_str(s: &str) -> Result<Self, Self::Err> {
//     if s == "load" {
//       Ok(Load::Any)
//     } else if let Some(inner) =
//       s.strip_prefix("load<").and_then(|s| s.strip_suffix('>'))
//     {
//       let ty = inner.parse()?; // EggType::from_str
//       Ok(Load::Typed(ty))
//     } else {
//       Err(RdgEggParseError::Unknown)
//     }
//   }
// }

// impl PartialEq for Load {
//   fn eq(&self, other: &Self) -> bool {
//     // Any类型可以匹配任意的
//     match (self, other) {
//       (Load::Any, _) | (_, Load::Any) => true,
//       (Load::Typed(ty1), Load::Typed(ty2)) => ty1 == ty2,
//     }
//   }
// }

// impl Eq for Load {}

#[derive(
  Debug,
  Clone,
  Copy,
  PartialEq,
  Eq,
  EnumIter,
  PartialOrd,
  Ord,
  Hash,
  Display,
  EnumString,
)]
pub enum UnaryOp {
  #[strum(to_string = "abs")]
  Abs,
  #[strum(to_string = "not")]
  Not,
  #[strum(to_string = "neg")]
  Neg,
  #[strum(to_string = "{0}")]
  Cast(CastOp),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash, Display)]
pub enum CastOp {
  #[strum(to_string = "zext{0}")]
  ZExt(CastRange),
  #[strum(to_string = "sext{0}")]
  SExt(CastRange),
  #[strum(to_string = "trunc{0}")]
  Trunc(CastRange),
  #[strum(to_string = "fptrunc")]
  FPTrunc,
  #[strum(to_string = "fpext")]
  FPExt,
}

impl FromStr for CastOp {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    if s == "fptrunc" {
      return Ok(CastOp::FPTrunc);
    }
    if s == "fpext" {
      return Ok(CastOp::FPExt);
    }

    // handle "sext[8->16]"
    if let Some(arg) = s.strip_prefix("sext[").and_then(|s| s.strip_suffix(']'))
    {
      let range = arg.parse::<CastRange>()?;
      return Ok(CastOp::SExt(range));
    }
    if s == "sext" {
      return Ok(CastOp::SExt(CastRange::Any));
    }

    if let Some(arg) = s.strip_prefix("zext[").and_then(|s| s.strip_suffix(']'))
    {
      let range = arg.parse::<CastRange>()?;
      return Ok(CastOp::ZExt(range));
    }
    if s == "zext" {
      return Ok(CastOp::ZExt(CastRange::Any));
    }

    if let Some(arg) =
      s.strip_prefix("trunc[").and_then(|s| s.strip_suffix(']'))
    {
      let range = arg.parse::<CastRange>()?;
      return Ok(CastOp::Trunc(range));
    }
    if s == "trunc" {
      return Ok(CastOp::Trunc(CastRange::Any));
    }

    Err(RdgEggParseError::Unknown)
  }
}

impl Default for CastOp {
  fn default() -> Self {
    CastOp::ZExt(CastRange::Any)
  }
}

#[derive(Debug, Clone, Copy, PartialOrd, Ord, Hash)]
pub enum CastRange {
  Any,
  WithWidth(usize, usize), // (from, to)
}

impl Display for CastRange {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    match self {
      CastRange::Any => write!(f, "any"),
      CastRange::WithWidth(from, to) => write!(f, "[{}->{}]", from, to),
    }
  }
}

impl FromStr for CastRange {
  type Err = RdgEggParseError;

  fn from_str(s: &str) -> Result<Self, Self::Err> {
    if s == "any" {
      return Ok(CastRange::Any);
    }

    if let Some(inner) = s.strip_prefix('[').and_then(|s| s.strip_suffix(']')) {
      let parts: Vec<&str> = inner.split("->").collect();
      if parts.len() != 2 {
        return Err(RdgEggParseError::Unknown);
      }
      let from = parts[0].parse().map_err(|_| RdgEggParseError::Unknown)?;
      let to = parts[1].parse().map_err(|_| RdgEggParseError::Unknown)?;
      return Ok(CastRange::WithWidth(from, to));
    }

    Err(RdgEggParseError::Unknown)
  }
}
impl PartialEq for CastRange {
  fn eq(&self, other: &Self) -> bool {
    match (self, other) {
      (CastRange::Any, _) | (_, CastRange::Any) => true,
      (CastRange::WithWidth(f1, t1), CastRange::WithWidth(f2, t2)) => {
        f1 == f2 && t1 == t2
      }
    }
  }
}

impl Eq for CastRange {}

#[derive(
  Debug,
  Clone,
  PartialEq,
  Eq,
  PartialOrd,
  Ord,
  Hash,
  EnumIter,
  EnumString,
  Display,
)]
pub enum VectorOp {
  #[strum(to_string = "vec")]
  Vec,
  #[strum(to_string = "vec_add")]
  VecAdd,
  #[strum(to_string = "vec_cmp")]
  VecCmp,
  #[strum(to_string = "vec_sub")]
  VecSub,
  #[strum(to_string = "vec_mul")]
  VecMul,
  #[strum(to_string = "vec_div")]
  VecDiv,
  #[strum(to_string = "vec_mac")]
  VecMac,
  #[strum(to_string = "vec_neg")]
  VecNeg,
  #[strum(to_string = "vec_not")]
  VecNot,
  #[strum(to_string = "vec_abs")]
  VecAbs,
  #[strum(to_string = "vec_rem")]
  VecRem,
  #[strum(to_string = "vec_and")]
  VecAnd,
  #[strum(to_string = "vec_or")]
  VecOr,
  #[strum(to_string = "vec_xor")]
  VecXor,
  #[strum(to_string = "vec_sext")]
  VecSext,
  #[strum(to_string = "vec_zext")]
  VecZext,
  #[strum(to_string = "vec_trunc")]
  VecTrunc,
  #[strum(to_string = "vec_fptrunc")]
  VecFPTrunc,
  #[strum(to_string = "vec_fpext")]
  VecFPExt,
  #[strum(to_string = "vec_load")]
  VecLoad,
  #[strum(to_string = "vec_store")]
  VecStore,
  #[strum(to_string = "vec_shr")]
  VecShr,
  #[strum(to_string = "vec_shl")]
  VecShl,
  #[strum(to_string = "concat")]
  Concat,
  #[strum(to_string = "gather{0}")]
  Gather(Gather),
  #[strum(to_string = "shuffle{0}")]
  Shuffle(Shuffle),
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct Gather {
  pub indices: Vec<usize>,
}
impl Display for Gather {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "[{}]", self.indices.iter().join(","))
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash, Default)]
pub struct Shuffle {
  pub indices: Vec<usize>,
}

impl Display for Shuffle {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    write!(f, "[{}]", self.indices.iter().join(","))
  }
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct RdgEggLang {
  pub ast: babble::AstNode<RdgEgg>,
}

impl RdgEggLang {
  pub fn op(&self) -> &RdgEgg {
    self.ast.operation()
  }

  pub fn args(&self) -> &[egg::Id] {
    self.ast.args()
  }

  pub fn new<I>(op: RdgEgg, args: I) -> Self
  where
    I: IntoIterator<Item = egg::Id>,
  {
    Self {
      ast: babble::AstNode::new(op, args),
    }
  }
}

impl Language for RdgEggLang {
  type Discriminant = <babble::AstNode<RdgEgg> as Language>::Discriminant;

  fn discriminant(&self) -> Self::Discriminant {
    self.ast.discriminant()
  }

  fn matches(&self, other: &Self) -> bool {
    self.ast.matches(&other.ast)
  }

  fn children(&self) -> &[egg::Id] {
    self.ast.children()
  }

  fn children_mut(&mut self) -> &mut [egg::Id] {
    self.ast.children_mut()
  }
}

impl FromOp for RdgEggLang {
  type Error = <babble::AstNode<RdgEgg> as FromOp>::Error;

  fn from_op(op: &str, children: Vec<egg::Id>) -> Result<Self, Self::Error> {
    Ok(Self {
      ast: <babble::AstNode<RdgEgg> as FromOp>::from_op(op, children)?,
    })
  }
}

impl Display for RdgEggLang {
  fn fmt(&self, f: &mut Formatter<'_>) -> std::fmt::Result {
    self.ast.fmt(f)
  }
}

impl RdgEggLang {
  pub fn build_recexpr_of_astnode(
    recexpr: RecExpr<RdgEggLang>,
  ) -> RecExpr<babble::AstNode<RdgEgg>> {
    recexpr
      .into_iter()
      .map(|x| x.ast)
      .collect::<Vec<_>>()
      .into()
  }
  pub fn build_recexpr_of_self(
    recexpr_astnode: RecExpr<babble::AstNode<RdgEgg>>,
  ) -> RecExpr<Self> {
    recexpr_astnode
      .into_iter()
      .map(|ast| Self { ast })
      .collect::<Vec<_>>()
      .into()
  }
  pub fn build_babble_expr_from_recexpr(
    recexpr: RecExpr<RdgEggLang>,
  ) -> babble::Expr<RdgEgg> {
    Self::build_recexpr_of_astnode(recexpr).into()
  }
  pub fn build_recexpr_from_rc_expr(expr: RcRdgEggExpr) -> RecExpr<RdgEggLang> {
    let rdg_expr: &RdgEggExpr = expr.borrow();
    let babble_expr: babble::Expr<RdgEgg> = rdg_expr.clone().into_babble_expr();
    let recexpr_astnode: RecExpr<babble::AstNode<RdgEgg>> = babble_expr.into();
    Self::build_recexpr_of_self(recexpr_astnode)
  }
}

pub type RcRdgEggExpr = Rc<RdgEggExpr>;

#[derive(Debug, Clone)]
pub struct RdgEggExpr {
  ast: babble::AstNode<RdgEgg, RcRdgEggExpr>,
}

impl RdgEggExpr {
  pub fn new<I>(op: RdgEgg, args: I) -> Self
  where
    I: IntoIterator<Item = RcRdgEggExpr>,
  {
    RdgEggExpr {
      ast: AstNode::new(op, args),
    }
  }

  pub fn into_babble_expr(self) -> babble::Expr<RdgEgg> {
    fn build(
      table: &mut HashMap<*const RdgEggExpr, Arc<babble::Expr<RdgEgg>>>,
      rc_expr: Rc<RdgEggExpr>,
    ) -> Arc<babble::Expr<RdgEgg>> {
      let key = rc_expr.as_ref() as *const RdgEggExpr;
      if let Some(rc_babble_expr) = table.get(&key) {
        return rc_babble_expr.clone();
      }
      let (op, args) = rc_expr.as_ref().ast.clone().into_parts();
      let rc_babble_expr = Arc::new(babble::Expr(babble::AstNode::new(
        op,
        args.into_iter().map(|x| build(table, x)),
      )));
      table.insert(key, rc_babble_expr.clone());
      rc_babble_expr
    }
    let mut table = HashMap::new();
    build(&mut table, Rc::new(self)).as_ref().clone()
  }
}

#[test]
fn test_typematch() {
  use babble::rewrites::TypeMatch;
  let input = "where(?x: int, ?y: int, ?z: int)";
  let output: TypeMatch<EggType> = TypeMatch::from_str(input).unwrap();
  println!("{:?}", output);
}

#[test]
fn test_parse_const() {
  let input = "1i1";
  let output: RdgConst = RdgConst::from_str(input).unwrap();
  println!("{:?}", output);
  assert_eq!(output, RdgConst::Int(1, Some(1)));
}

#[test]
fn test_equivalent() {
  let op = RdgEggOp::Dummy(Dummy {
    name: "IOBarrier".to_string(),
  });
  let mut info1 = RdgEggInfo::default();
  info1.bbs.push("convolution_1#if.then.2.1".to_string());
  let mut info2 = RdgEggInfo::default();
  info2.bbs.push("cross_product#entry".to_string());
  let egg1 = RdgEgg {
    op: op.clone(),
    info: info1,
  };
  let egg2 = RdgEgg {
    op: op.clone(),
    info: info2,
  };
  println!("egg1 == egg2: {}", egg1 == egg2);
}
