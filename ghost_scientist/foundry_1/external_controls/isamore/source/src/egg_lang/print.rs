use babble::{Expr, Printable, Printer, ast_node::Memoize};

use super::*;

impl Printable for RdgEgg {
  fn precedence(&self) -> babble::Precedence {
    // all operations need to be surrounded with parens
    100
  }

  fn print_naked<W: std::fmt::Write + Default + Clone + ToString>(
    expr: Arc<babble::Expr<Self>>,
    printer: &mut babble::Printer<W>,
    memoizer: &mut dyn Memoize<Key = *const Expr<Self>>,
  ) -> std::fmt::Result {
    // print the info
    if !expr.0.operation().info.is_empty() {
      write!(printer.writer, "{{{}}} ", expr.0.operation().info)?;
    }
    match (&expr.0.operation().op, expr.0.args()) {
      (
        RdgEggOp::Var(_)
        | RdgEggOp::LibVar(_)
        | RdgEggOp::Lambda
        | RdgEggOp::Lib(_, _, _, _)
        | RdgEggOp::Apply,
        _,
      ) => {
        write!(printer.writer, "<ERROR! binding-expr>")
      }
      (&RdgEggOp::List, ts) => printer.in_brackets(|p| {
        p.indented(&mut |p: &mut Printer<W>| {
          p.vsep(
            &mut |p: &mut Printer<W>, i: usize| {
              p.print_in_context(ts[i].clone(), 0, memoizer)
            },
            ts.len(),
            ",",
          )
        })
      }),
      (RdgEggOp::Const(constant), []) => {
        write!(printer.writer, "{constant}")?;
        Ok(())
      }
      // 处理 OpPack
      (RdgEggOp::OpPack(cfg), []) => {
        write!(printer.writer, "{}", cfg)?;
        Ok(())
      }

      // 处理 OpSelect
      (RdgEggOp::OpSelect, []) => {
        write!(printer.writer, "op_select")?;
        Ok(())
      }
      (RdgEggOp::Top(top), [a, b, c]) => {
        let args = [a, b, c];
        printer.chain(
          &mut |p: &mut Printer<W>| write!(p.writer, "{top}"),
          &mut |p: &mut Printer<W>| {
            p.indentation += 1;
            p.vsep(
              &mut |p: &mut Printer<W>, i: usize| {
                p.print(args[i].clone(), memoizer)
              },
              3,
              " ",
            )?;
            p.indentation -= 1;
            Ok(())
          },
          " ",
        )
      }
      (RdgEggOp::Bop(bop), [a, b]) => {
        let args = [a, b];
        printer.chain(
          &mut |p: &mut Printer<W>| write!(p.writer, "{bop}"),
          &mut |p: &mut Printer<W>| {
            p.indented(&mut |p: &mut Printer<W>| {
              p.vsep(
                &mut |p: &mut Printer<W>, i: usize| {
                  p.print(args[i].clone(), memoizer)
                },
                2,
                " ",
              )
            })
          },
          " ",
        )
      }
      (RdgEggOp::Uop(uop), [a]) => {
        let a_ref = a.clone();
        let memoizer_ref = &mut *memoizer;
        printer.chain(
          &mut |p: &mut Printer<W>| write!(p.writer, "{uop}"),
          &mut |p: &mut Printer<W>| p.print(a_ref.clone(), memoizer_ref),
          " ",
        )
      }
      (RdgEggOp::Get(get_op), [a]) => {
        write!(printer.writer, "{get_op} ")?;
        printer.print(a.clone(), memoizer)
      }
      (RdgEggOp::Tuple(tuple_op), args) => printer.chain(
        &mut |p: &mut Printer<W>| {
          write!(p.writer, "{tuple_op}")?;
          Ok(())
        },
        &mut |p: &mut Printer<W>| {
          p.indented(&mut |p: &mut Printer<W>| {
            p.vsep(
              &mut |p: &mut Printer<W>, i: usize| {
                p.print(args[i].clone(), memoizer)
              },
              args.len(),
              " ",
            )
          })
        },
        " ",
      ),
      (RdgEggOp::Switch, [cond, input, cases @ ..]) => {
        write!(printer.writer, "switch")?;
        printer.indented(&mut |p: &mut Printer<W>| {
          p.new_line()?;
          p.print(cond.clone(), memoizer)
        })?;
        printer.indented(&mut |p: &mut Printer<W>| {
          p.new_line()?;
          p.print(input.clone(), memoizer)
        })?;
        printer.indented(&mut |p: &mut Printer<W>| {
          p.vsep(
            &mut |p: &mut Printer<W>, i: usize| {
              p.new_line()?;
              p.print(cases[i].clone(), memoizer)
            },
            cases.len(),
            "",
          )
        })
      }
      (RdgEggOp::DoWhile, [inputs, pred_and_body]) => {
        write!(printer.writer, "dowhile")?;
        printer.indented(&mut |p: &mut Printer<W>| {
          p.new_line()?;
          p.print(inputs.clone(), memoizer)
        })?;

        printer.indented(&mut |p: &mut Printer<W>| {
          p.new_line()?;
          p.print(pred_and_body.clone(), memoizer)
        })
      }
      (RdgEggOp::Arg(arg), []) => {
        write!(printer.writer, "{}", arg)?;
        Ok(())
      }
      (RdgEggOp::Function(func), [body]) => {
        write!(printer.writer, "{} ", func)?;
        printer.print(body.clone(), memoizer)
      }
      (RdgEggOp::Dummy(name), args) => printer.chain(
        &mut |p: &mut Printer<W>| write!(p.writer, "{name}"),
        &mut |p: &mut Printer<W>| {
          p.indented(&mut |p: &mut Printer<W>| {
            p.vsep(
              &mut |p: &mut Printer<W>, i: usize| {
                p.print(args[i].clone(), memoizer)
              },
              args.len(),
              "",
            )
          })
        },
        " ",
      ),
      (RdgEggOp::IOBarrier, [a, b]) => {
        let args = [a, b];
        printer.chain(
          &mut |p: &mut Printer<W>| write!(p.writer, "io_barrier"),
          &mut |p: &mut Printer<W>| {
            p.indented(&mut |p: &mut Printer<W>| {
              p.vsep(
                &mut |p: &mut Printer<W>, i: usize| {
                  p.print(args[i].clone(), memoizer)
                },
                2,
                " ",
              )
            })
          },
          " ",
        )
      }

      (RdgEggOp::VectorOp(vec_op), args) => {
        use VectorOp::*;
        match (vec_op, args) {
          // 一元操作
          (
            VecNeg | VecSext | VecZext | VecTrunc | VecFPExt | VecFPTrunc,
            [a],
          ) => printer.chain(
            &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
            &mut |p: &mut Printer<W>| p.print(a.clone(), memoizer),
            " ",
          ),

          // 二元操作
          (
            VecAdd | VecSub | VecMul | VecDiv | VecRem | VecAnd | VecOr
            | Concat | VecLoad,
            [a, b],
          ) => {
            let args = [a, b];
            printer.chain(
              &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
              &mut |p: &mut Printer<W>| {
                p.indented(&mut |p| {
                  p.vsep(&mut |p, i| p.print(args[i].clone(), memoizer), 2, " ")
                })
              },
              " ",
            )
          }

          // 三元操作
          (VecMac | VecStore, [a, b, c]) => {
            let args = [a, b, c];
            printer.chain(
              &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
              &mut |p: &mut Printer<W>| {
                p.indented(&mut |p| {
                  p.vsep(&mut |p, i| p.print(args[i].clone(), memoizer), 3, " ")
                })
              },
              " ",
            )
          }
          // gather操作
          (Gather(gather), [a]) => {
            let indices = gather.indices.clone();
            let args = [a];
            printer.chain(
              &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
              &mut |p: &mut Printer<W>| {
                p.indented(&mut |p| {
                  p.vsep(
                    &mut |p, i| {
                      if i == 0 {
                        write!(p.writer, "{}", indices[i])
                      } else {
                        write!(p.writer, ", {}", indices[i])
                      }
                    },
                    indices.len(),
                    " ",
                  )?;
                  p.new_line()?;
                  p.print(args[0].clone(), memoizer)
                })
              },
              " ",
            )
          }
          // shuffle操作
          (Shuffle(shuffle), [a, b]) => {
            let indices = shuffle.indices.clone();

            let args = [a, b];

            printer.chain(
              &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
              &mut |p: &mut Printer<W>| {
                p.indented(&mut |p| {
                  // 打印 indices
                  p.vsep(
                    &mut |p, i| {
                      if i == 0 {
                        write!(p.writer, "{}", indices[i])
                      } else {
                        write!(p.writer, ", {}", indices[i])
                      }
                    },
                    indices.len(),
                    " ",
                  )?;
                  p.new_line()?;

                  p.print(args[0].clone(), memoizer)?;
                  p.print(args[1].clone(), memoizer)?;

                  Ok(())
                })
              },
              " ",
            )
          }

          // 多参数（例如 vec, lit_vec）
          (Vec, items) => printer.chain(
            &mut |p: &mut Printer<W>| write!(p.writer, "{vec_op}"),
            &mut |p: &mut Printer<W>| {
              p.indented(&mut |p| {
                p.vsep(
                  &mut |p, i| p.print(items[i].clone(), memoizer),
                  items.len(),
                  " ",
                )
              })
            },
            " ",
          ),

          // fallback
          _ => {
            write!(printer.writer, "<ERROR! {vec_op} with {} args>", args.len())
          }
        }
      }

      (op, args) => {
        write!(printer.writer, "<ERROR! {op} with {} args>", args.len())
      }
    }?;

    Ok(())
  }
}
