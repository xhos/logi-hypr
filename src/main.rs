use anyhow::Result;
use clap::Parser;
use serde_json;
use std::{collections::HashMap, sync::mpsc};
use tracing::{error, info, warn};

mod config;
mod context;
mod input;

use config::{Config, GestureConfig, GestureCommands, ScrollConfig, ScrollRule};
use context::EventHandler;
use input::{InputEvent, InputManager};

#[derive(Parser)]
struct Args {
	#[arg(long, default_value = "200")]
	tap_timeout_ms: u64,

	#[arg(long, default_value = "100")]
	movement_threshold: i32,

	#[arg(long, default_value = "200")]
	focus_poll_ms: u64,

	#[arg(long)]
	gesture_commands: Option<String>,

	#[arg(long)]
	scroll_rules: Option<String>,

	#[arg(short, long)]
	verbose: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
	let args = Args::parse();

	init_logging(args.verbose);
	check_hyprland();

	let config = build_config_from_args(&args)?;
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

fn build_config_from_args(args: &Args) -> Result<Config> {
	let gesture_commands = if let Some(commands_json) = &args.gesture_commands {
		serde_json::from_str::<HashMap<String, String>>(commands_json)
			.map_err(|e| anyhow::anyhow!("Failed to parse gesture commands JSON: {}", e))?
	} else {
		HashMap::new()
	};

	let scroll_rules = if let Some(rules_json) = &args.scroll_rules {
		serde_json::from_str::<Vec<ScrollRule>>(rules_json)
			.map_err(|e| anyhow::anyhow!("Failed to parse scroll rules JSON: {}", e))?
	} else {
		Vec::new()
	};

	Ok(Config {
		gesture: GestureConfig {
			tap_timeout_ms: args.tap_timeout_ms,
			movement_threshold: args.movement_threshold,
			commands: GestureCommands {
				tap: gesture_commands.get("tap").cloned().unwrap_or_default(),
				swipe_left: gesture_commands.get("swipe_left").cloned().unwrap_or_default(),
				swipe_right: gesture_commands.get("swipe_right").cloned().unwrap_or_default(),
				swipe_up: gesture_commands.get("swipe_up").cloned().unwrap_or_default(),
				swipe_down: gesture_commands.get("swipe_down").cloned().unwrap_or_default(),
			},
		},
		scroll: ScrollConfig {
			focus_poll_ms: args.focus_poll_ms,
			rules: scroll_rules,
		},
	})
}
