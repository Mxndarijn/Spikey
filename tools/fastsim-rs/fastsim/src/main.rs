//! fastsim-rs: the Rust FastSim (docs/FASTSIM_RS.md).
//!   fastsim-rs parity <cases.txt> [--jobs N]          check against Godot's sim (and so C# FastSim)
//!   fastsim-rs speed [--seeds 32] [--cap T] [--first 0] [--memo 1] [BlindPlanner options] [--jobs N]
//!                                                      BlindPlanner runs: ticks/s and the taps
//!                                                      fingerprint of C# `rl review speed`
//!   fastsim-rs bench                                   sim copy / step time (Program.cs Bench)
mod bots;
mod checks;
mod human;
mod yardstick;
mod dotnet_random;
mod fxhash;
mod parity;
mod setups;
mod speed;
mod modes;
mod honesty_mode;
mod measure;
mod review;
mod boss;
mod difficulty;

#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let mut jobs = 0usize;
    let mut rest = Vec::new();
    let mut opts = speed::Opts::new();
    let mut i = 0;
    while i < args.len() {
        if let Some(k) = args[i].strip_prefix("--") {
            let v = if i + 1 < args.len() { args[i + 1].clone() } else { String::new() };
            if k == "jobs" {
                jobs = v.parse().expect("--jobs N");
            } else {
                opts.insert(k.to_string(), v);
            }
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
        "speed" => speed::speed(&opts),
        "bench" => speed::bench(),
        "simspeed" => speed::simspeed(&opts),
        "check" => checks::run(&rest[1..], &opts),
        "human" => human::run(&rest[1..], &opts),
        "yardstick" => yardstick::run(&rest[1..], &opts),
        "measure" => measure::run(&rest[1..], &opts),
        "search" | "searchruns" | "rooms" | "runs" | "reaction" | "odds" | "scan" => modes::run(mode, &rest[1..], &opts),
        "variants" => modes::variants::run(&rest[1..], &opts),
        "honesty" => honesty_mode::run(&rest[1..], &opts),
        "sameseed" => checks::sameseed::run_mode(&rest[1..], &opts),
        "runfile" => bots::run_file::RunFile::run_mode(
            rest.get(1).map(|s| s.parse().expect("seed")).unwrap_or(1),
            rest.get(2).map(|s| s.parse().expect("bot seed")).unwrap_or(1),
            opts.get("out").map(|s| s.as_str()).unwrap_or("run.json"),
        ),
        "boss" => boss::run(&rest[1..], &opts),
        "difficulty" => difficulty::run(&rest[1..], &opts),
        "rl" if rest.get(1).map(|s| s.as_str()) == Some("review") => review::run(&rest[2..], &opts),
        _ => {
            eprintln!("usage: fastsim-rs parity <cases.txt> | speed [options] | bench   [--jobs N]");
            2
        }
    };
    std::process::exit(code);
}
