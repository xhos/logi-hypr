use anyhow::Result;
use clap::Parser;
use std::{path::PathBuf, sync::mpsc};
use tracing::{error, info, warn};

mod config;
mod context;
mod input;

use config::Config;
use context::EventHandler;
use input::{InputEvent, InputManager};

#[derive(Parser)]
struct Args {
	#[arg(long, default_value = "~/.config/logi-hypr/config.toml")]
	config: PathBuf,

	#[arg(short, long)]
	verbose: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
	let args = Args::parse();

	init_logging(args.verbose);
	check_hyprland();

	let config = load_config(&args.config)?;
	let handler = EventHandler::new(&config)?;

	info!("starting gesture handler");
	run_event_loop(config, handler).await
}

async fn run_event_loop(config: Config, handler: EventHandler) -> Result<()> {
	let (tx, rx) = mpsc::channel::<InputEvent>();
	let input_manager = InputManager::new(
		config.gesture.tap_timeout_ms,
		config.gesture.movement_threshold,
	);

	std::thread::spawn(move || {
		if let Err(e) = input_manager.start_monitoring(tx) {
			error!("input monitoring failed: {}", e);
		}
	});

	info!("event loop started");

	while let Ok(event) = rx.recv() {
		if let Err(e) = handler.handle_event(event).await {
			error!("event handling failed: {}", e);
		}
	}

	warn!("event channel closed");
	Ok(())
}

fn init_logging(verbose: bool) {
	std::env::set_var("RUST_LOG", if verbose { "debug" } else { "info" });
	tracing_subscriber::fmt::init();
}

fn check_hyprland() {
	match std::env::var("HYPRLAND_INSTANCE_SIGNATURE") {
		Ok(sig) => info!("running in hyprland instance: {}", &sig[..8]),
		Err(_) => warn!("not running in hyprland, stuff may not work"),
	}
}

fn load_config(path: &PathBuf) -> Result<Config> {
	Config::from_file(path).or_else(|e| {
		warn!("failed to load config from {}: {}", path.display(), e);
		info!("using default configuration");
		Ok(Config::default())
	})
}
