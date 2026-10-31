use std::io::Result;

fn main() -> Result<()> {
    prost_build::compile_protos(
        &["proto/estimator_model.proto"],
        &["proto/"],
    )?;
    Ok(())
}
