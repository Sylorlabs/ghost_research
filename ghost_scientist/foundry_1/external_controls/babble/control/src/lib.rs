//! Build wrapper for byte-exact Babble core algorithm modules.

pub mod ast_node {
    include!("../../source/src/ast_node.rs");
}
#[path = "../../source/src/co_occurrence.rs"]
pub mod co_occurrence;
#[path = "../../source/src/dfta.rs"]
mod dfta;
pub mod extract {
    include!("../../source/src/extract/mod.rs");
}
#[path = "../../source/src/learn.rs"]
pub mod learn;
#[path = "../../source/src/rewrites.rs"]
pub mod rewrites;
#[path = "../../source/src/sexp.rs"]
pub mod sexp;
#[path = "../../source/src/simple_lang.rs"]
pub mod simple_lang;
#[path = "../../source/src/teachable.rs"]
pub mod teachable;
