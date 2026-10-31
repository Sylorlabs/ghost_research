use stitch_core::{multistep_compression, MultistepCompressionConfig};

#[derive(serde::Deserialize)]
struct Request {
    programs: Vec<String>,
    iterations: usize,
    max_arity: usize,
    threads: usize,
    silent: bool,
}

fn main() {
    let request: Request = serde_json::from_reader(std::io::stdin())
        .expect("read JSON control request from stdin");
    let mut config = MultistepCompressionConfig::new();
    config.iterations = request.iterations;
    config.step.max_arity = request.max_arity;
    config.step.threads = request.threads;
    config.silent = request.silent;
    let (_, result) = multistep_compression(
        &request.programs,
        None,
        None,
        None,
        None,
        &config,
    );
    println!("{}", serde_json::to_string(&result).expect("serialize result"));
}
