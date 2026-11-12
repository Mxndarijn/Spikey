//! fastsim-rs: the Rust FastSim (docs/FASTSIM_RS.md).
//!   fastsim-rs parity <cases.txt> [--jobs N]     check against Godot's sim
mod bots;
mod dotnet_random;
mod parity;
mod setups;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut jobs = 0usize;
    let mut rest = Vec::new();
    let mut i = 0;
    while i < args.len() {
        if args[i] == "--jobs" && i + 1 < args.len() {
            jobs = args[i + 1].parse().expect("--jobs N");
            i += 2;
            continue;
        }
        rest.push(args[i].clone());
        i += 1;
    }
    if jobs > 0 {
        rayon::ThreadPoolBuilder::new().num_threads(jobs).build_global().expect("thread pool");
    }
    let mode = rest.first().map(|s| s.as_str()).unwrap_or("");
    let code = match mode {
        "parity" => parity::run(rest.get(1).map(|s| s.as_str()).unwrap_or("parity.txt")),
        _ => {
            eprintln!("usage: fastsim-rs parity <cases.txt> [--jobs N]");
            2
        }
    };
    std::process::exit(code);
}
