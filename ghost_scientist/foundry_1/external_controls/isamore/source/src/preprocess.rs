use crate::{
  RdgEgg,
  egg_lang::{
    Arg, BinaryOp, Dummy, RdgConst, RdgEggInfo, RdgEggOp, TernaryOp, Tuple,
  },
};
use babble::{AstNode, Expr, extract::beam_pareto::TypeInfo};
use egg::{Id, RecExpr};
use std::{collections::HashMap, sync::Arc, vec};
use z3::ast::Ast;
/// 主要用来处理mem节点
/// 目前的处理方式是，去掉深嵌套的关系，也就是完全取消state的继承关系，
/// 遍历store和load节点的args，如果args[len()-1]不是Const节点，
/// 就新建一个state节点 除此之外，我会取消和Ld节点输出相关的所有get节点，
/// 只只输出一个节点数据， 另外一个节点就会新建一个state节点
/// 之后删去所有的IOB节点，将地址重定向到输入
pub(crate) fn preprocess(
  recexpr: RecExpr<AstNode<RdgEgg>>,
) -> RecExpr<AstNode<RdgEgg>> {
  // for (id, node) in recexpr.iter().enumerate() {
  //   println!("{}: {:?}", id, node);
  // }
  let mut new_nodes = Vec::new();
  let mut stores = Vec::new();
  // 收集load节点和store节点对应的地址节点，如果地址节点不是add节点，
  // 那么进行手动重写，将addr替换成add addr + 0iSome(64)
  // 用于收集新旧Id的映射关系 观察是，如果IOB节点的第一个节点不是add节点，
  // 就将其替换成add节点
  let mut nodes_to_be_replaced_to_add = HashMap::new();
  for (id, node) in recexpr.iter().enumerate() {
    if matches!(node.operation().op, RdgEggOp::IOBarrier) {
      let addr = recexpr.as_ref()[usize::from(node.args()[0])].clone();
      if !matches!(addr.operation().op, RdgEggOp::Bop(BinaryOp::Add)) {
        nodes_to_be_replaced_to_add.insert(
          usize::from(node.args()[0]),
          node.operation().info.bbs.clone(),
        );
      }
    }
  }
  let mut id_old_to_new = HashMap::new();

  // 遍历原始的RecExpr
  for (node_id, node) in recexpr.iter().enumerate() {
    let mut add_node = true;
    // 如果当前节点是get节点，并且get节点的子节点是load节点
    match node.operation().op.clone() {
      RdgEggOp::Get(getop) => {
        let child = recexpr.as_ref()[usize::from(node.args()[0])].clone();
        if matches!(child.operation().op, RdgEggOp::Bop(BinaryOp::Load)) {
          add_node = false;
          let idx = getop.index();
          // 0为值，1为状态
          if idx == 0 {
            //值节点，将node.args()[0]作为get(0)的替换
            let new_id =
              id_old_to_new.get(&usize::from(node.args()[0])).unwrap();
            id_old_to_new.insert(node_id, usize::from(*new_id));
          }
          // 1为状态节点，将其替换成自己新加的state节点
          else {
            // 新建一个state节点
            let state_node =
              AstNode::leaf(RdgEggOp::Const(RdgConst::Int(0, Some(0))).into());
            new_nodes.push(state_node);
            // 将当前节点的args[0]替换成新加的state节点
            id_old_to_new.insert(node_id, new_nodes.len() - 1);
          }
        }
      }
      RdgEggOp::IOBarrier => {
        add_node = false;
        // IOB节点的第一个参数是地址，将这个地址重定向到当前节点即可
        let new_id = id_old_to_new.get(&usize::from(node.args()[0])).unwrap();
        id_old_to_new.insert(node_id, new_id.clone());
      }
      _ => {
        // 如果子节点中有store节点，就加入新的state常量节点
        for arg in node.args() {
          let child = recexpr.as_ref()[usize::from(*arg)].clone();
          if matches!(child.operation().op, RdgEggOp::Top(TernaryOp::Store)) {
            // 新建一个state节点
            let state_node =
              AstNode::leaf(RdgEggOp::Const(RdgConst::Int(0, Some(0))).into());
            new_nodes.push(state_node);
            // 更新Id映射关系
            id_old_to_new.insert(usize::from(arg.clone()), new_nodes.len() - 1);
          }
        }
      }
    }

    if add_node {
      // // 如果当前节点是store或者load节点，
      // // 那么就需要看最后一个参数是不是Const类型，如果不是就需要新建state节点
      let mut new_node = node.clone();
      // if matches!(node.operation().op, RdgEggOp::Load(_))
      //   || matches!(node.operation().op, RdgEggOp::Top(TernaryOp::Store))
      // {
      //   // 如果最后一个参数不是Const类型，则新建一个state节点
      //   let last_arg = recexpr.as_ref()
      //     [usize::from(node.args()[node.args().len() - 1])]
      //   .clone();
      //   if !matches!(last_arg.operation().op, RdgEggOp::Const(_)) {
      //     // 新建一个state节点
      //     let state_node =
      //       AstNode::leaf(RdgEggOp::Const(RdgConst::Int(0, Some(0))).into());
      //     new_nodes.push(state_node);
      //     // 更新Id映射关系
      //     id_old_to_new.insert(
      //       usize::from(node.args()[node.args().len() - 1]),
      //       new_nodes.len() - 1,
      //     );
      //   }
      // }
      // 根据id_old_to_new映射关系更新当前节点的args
      for i in 0..node.args().len() {
        if let Some(new_id) = id_old_to_new.get(&usize::from(node.args()[i])) {
          new_node.args_mut()[i] = Id::from(*new_id);
        } else {
          println!("{}: {:?}", node_id, node);
          panic!("id:{:?} not found", node.args()[i]);
        }
      }
      // 如果当前节点不是get节点，并且不是IOB节点，则将其添加到新节点列表中
      // 将当前节点添加到新节点列表中
      new_nodes.push(new_node);
      // 更新Id映射关系
      if nodes_to_be_replaced_to_add.get(&node_id).is_some() {
        // 加入add节点，将id_old_to_new中的映射替换成add节点
        let bbs = nodes_to_be_replaced_to_add.get(&node_id).unwrap();
        let zero =
          AstNode::leaf(RdgEggOp::Const(RdgConst::Int(0, Some(64))).into());
        new_nodes.push(zero);
        let add_op = RdgEgg {
          op: RdgEggOp::Bop(BinaryOp::Add),
          info: RdgEggInfo {
            bbs: bbs.clone(),
            ..Default::default()
          },
        };
        let add_node = AstNode::new(add_op, vec![
          Id::from(new_nodes.len() - 2),
          Id::from(new_nodes.len() - 1),
        ]);
        new_nodes.push(add_node);
      }

      id_old_to_new.insert(node_id, new_nodes.len() - 1);

      // 如果当前节点是store节点，则将其添加到stores列表中
      if matches!(node.operation().op, RdgEggOp::Top(TernaryOp::Store)) {
        stores.push(new_nodes.len() - 1);
      }
    }
  }
  // 拿到最后一个节点id
  let last_id = new_nodes.len() - 1;
  // 加入vec节点，将所有的store节点作为vec的子节点
  // println!("stores: {:?}, last_id: {}", stores, last_id);
  if stores.len() < 2 {
    // 新建一个tuple节点，将last_id和store节点作为子节点
    if stores.len() == 1 {
      let tuple_node = AstNode::new(
        RdgEgg {
          op: RdgEggOp::Tuple(Tuple {}),
          info: RdgEggInfo {
            bbs: new_nodes[last_id].operation().info.bbs.clone(),
            result_tys: new_nodes[last_id].operation().info.result_tys.clone(),
          },
        },
        vec![Id::from(last_id), Id::from(stores[0])],
      );
      new_nodes.push(tuple_node);
    }
    return RecExpr::from(new_nodes);
  }

  // 将store节点按照bbs的信息进行分类，并分别封装
  let mut store_map: HashMap<Vec<String>, Vec<Id>> = HashMap::new();
  for store_id in stores {
    let store_node = &new_nodes[store_id];
    let bbs = store_node.operation().info.bbs.clone();
    if !store_map.contains_key(&bbs) {
      store_map.insert(bbs, vec![Id::from(store_id)]);
    } else {
      store_map.get_mut(&bbs).unwrap().push(Id::from(store_id));
    }
  }
  // 将store_map中的每个bbs对应的store节点封装成一个list节点,
  // list节点也需要加入对应的bbs信息
  let mut list_nodes = Vec::new();
  let mut big_bbs = vec![];
  let mut ss = Vec::new();
  for (bbs, store_ids) in store_map {
    let mut store_ids = store_ids;
    store_ids.sort();
    let list_node = AstNode::new(
      RdgEgg {
        op: RdgEggOp::List,
        info: RdgEggInfo {
          bbs: bbs.clone(),
          ..Default::default()
        },
      },
      store_ids.clone(),
    );
    big_bbs.extend(bbs.clone());
    new_nodes.push(list_node);
    list_nodes.push(Id::from(new_nodes.len() - 1));
    ss.push((bbs, Id::from(new_nodes.len() - 1)));
  }
  ss.sort_by(|a, b| a.0.cmp(&b.0));
  big_bbs.sort();
  // 最后将所有的list节点封装成一个list节点,bbs为空
  if list_nodes.len() > 1 {
    let list_node = AstNode::new(
      RdgEgg {
        op: RdgEggOp::List,
        info: RdgEggInfo {
          bbs: big_bbs,
          ..Default::default()
        },
      },
      ss.iter().map(|(_, id)| id.clone()).collect::<Vec<_>>(),
    );
    new_nodes.push(list_node);
  };

  // 最后将list节点和最后一个节点封装成一个tuple节点
  let tuple_node = AstNode::new(
    RdgEgg {
      op: RdgEggOp::Tuple(Tuple {}),
      info: RdgEggInfo {
        bbs: new_nodes[last_id].operation().info.bbs.clone(),
        result_tys: new_nodes[last_id].operation().info.result_tys.clone(),
      },
    },
    vec![Id::from(last_id), Id::from(new_nodes.len() - 1)],
  );
  new_nodes.push(tuple_node);

  // for (id, node) in new_nodes.clone().iter().enumerate() {
  //   println!("{}: {:?}", id, node);
  // }

  RecExpr::from(new_nodes)
}

// pub(crate) fn transfer_get_arg_to_dummy(
//   recexpr: RecExpr<AstNode<RdgEgg>>,
// ) -> RecExpr<AstNode<RdgEgg>> {
//   // for (id, node) in recexpr.iter().enumerate() {
//   //   println!("{}: {:?}", id, node);
//   // }
//   let mut new_nodes = Vec::new();

//   let mut id_old_to_new = HashMap::new();

//   // 遍历原始的RecExpr
//   for (node_id, node) in recexpr.iter().enumerate() {
//     // 如果是Tuple节点，则只需要根据id_old_to_new映射关系更新args即可
//     if matches!(node.operation().op, RdgEggOp::Tuple(_)) {
//       let mut new_node = node.clone();
//       for i in 0..node.args().len() {
//         if let Some(new_id) = id_old_to_new.get(&usize::from(node.args()[i]))
// {           new_node.args_mut()[i] = Id::from(*new_id);
//         } else {
//           println!("{}: {:?}", node_id, node);
//           panic!("id:{:?} not found", node.args()[i]);
//         }
//       }
//       new_nodes.push(new_node);
//       id_old_to_new.insert(node_id, new_nodes.len() - 1);
//       continue;
//     }
//     // 其他节点，需要识别对应的子节点是不是get_arg链，如果是，
// 就加入dummy节点，     // 将arg重定位到dummy
//     let mut new_node = node.clone();
//     let children = node
//       .args()
//       .iter()
//       .map(|arg| (arg.clone(), recexpr.as_ref()[usize::from(*arg)].clone()))
//       .collect::<Vec<_>>();
//     for (i, child) in children.iter().enumerate() {
//       let mut flag = false;
//       if matches!(child.1.operation().op, RdgEggOp::Get(_)) {
//         // 继续观察子节点
//         if matches!(
//           recexpr.as_ref()[usize::from(child.1.args()[0])]
//             .operation()
//             .op,
//           RdgEggOp::Arg(_)
//         ) {
//           // 如果是get_arg链，就加入dummy节点
//           let dummy_name =
//             format!("get_arg_{}_{}", child.0, child.1.args()[0]).to_string();
//           let dummy_op = RdgEgg {
//             op: RdgEggOp::Dummy(Dummy::new(dummy_name)),
//             info: RdgEggInfo {
//               bbs: node.operation().info.bbs.clone(),
//               result_tys: node.operation().info.result_tys.clone(),
//             },
//           };
//           new_nodes.push(AstNode::leaf(dummy_op));
//           // 更新Id映射关系
//           id_old_to_new.insert(usize::from(child.0), new_nodes.len() - 1);

//           // 将当前节点的args中的get_arg替换成dummy节点
//           new_node.args_mut()[i] = Id::from(new_nodes.len() - 1);
//           flag = true;
//         }
//       }
//       if !flag {
//         // 如果不是get_arg链，就将当前节点的args中的子节点替换成新节点
//         if let Some(new_id) = id_old_to_new.get(&usize::from(child.0)) {
//           new_node.args_mut()[i] = Id::from(*new_id);
//         } else {
//           println!("{}: {:?}", node_id, node);
//           panic!("id:{:?} not found", child.0);
//         }
//       }
//     }
//     // 将当前节点添加到新节点列表中
//     new_nodes.push(new_node);
//     // 更新Id映射关系
//     id_old_to_new.insert(node_id, new_nodes.len() - 1);
//   }
//   RecExpr::from(new_nodes)
// }

// 主要用来处理arg节点，将bbs信息提取出来放入arg中
pub(crate) fn preprocess_arg(
  recexpr: RecExpr<AstNode<RdgEgg>>,
) -> RecExpr<AstNode<RdgEgg>> {
  let mut new_recexpr = recexpr.clone();
  for (node_id, node) in recexpr.iter().enumerate() {
    if matches!(node.operation().op, RdgEggOp::Arg(_)) {
      // 如果是arg节点，将bbs信息提取出来放入arg中
      let bbs = node.operation().info.bbs.clone();
      let mut new_node = node.clone();
      new_node.operation_mut().op = RdgEggOp::Arg(Arg { bbs });
      new_recexpr.as_mut()[node_id] = new_node;
    }
  }
  new_recexpr
}

pub(crate) fn types_restore(
  recexpr: RecExpr<AstNode<RdgEgg>>,
) -> RecExpr<AstNode<RdgEgg>> {
  // 使用类型推导恢复类型信息
  let mut new_recexpr = recexpr.clone();
  for (node_id, node) in recexpr.iter().enumerate() {
    // 如果是Const节点，恢复类型信息
    let mut new_node = node.clone();
    if new_node.operation_mut().info.result_tys.is_empty() {
      let child_tys = new_node
        .args()
        .iter()
        .map(|arg| {
          let child = new_recexpr.as_ref()[usize::from(*arg)].clone();
          child.operation().info.result_tys[0].clone()
        })
        .collect::<Vec<_>>();
      let rtype = new_node.get_rtype(&child_tys);
      new_node.operation_mut().info.result_tys = vec![rtype];
      new_recexpr.as_mut()[node_id] = new_node;
    }
  }
  new_recexpr
}
