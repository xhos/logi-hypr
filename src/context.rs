use crate::{
	config::{Config, ScrollRule},
	input::{InputEvent, SwipeDirection},
};
use anyhow::Result;
use regex::Regex;
use serde::Deserialize;
use std::{
	sync::Mutex,
	time::{Duration, Instant},
};
use tokio::process::Command;
use tracing::{debug, info, warn};

pub struct EventHandler {
	gestures: [String; 5],
	scroll_rules: Vec<CompiledScrollRule>,
	focus_cache: Mutex<(Instant, String)>,
	focus_poll_ms: u64,
}

struct CompiledScrollRule {
	pattern: Regex,
	right_commands: Vec<String>,
	left_commands: Vec<String>,
}

impl EventHandler {
	pub fn new(config: &Config) -> Result<Self> {
		let scroll_rules = config
			.scroll
			.rules
			.iter()
			.map(Self::compile_rule)
			.collect::<Result<Vec<_>>>()?;

		let cache_time = Instant::now() - Duration::from_millis(config.scroll.focus_poll_ms);

		Ok(Self {
			gestures: [
				config.gesture.commands.tap.clone(),
				config.gesture.commands.left.clone(),
				config.gesture.commands.right.clone(),
				config.gesture.commands.up.clone(),
				config.gesture.commands.down.clone(),
			],
			scroll_rules,
			focus_cache: Mutex::new((cache_time, String::new())),
			focus_poll_ms: config.scroll.focus_poll_ms,
		})
	}

	fn compile_rule(rule: &ScrollRule) -> Result<CompiledScrollRule> {
		Ok(CompiledScrollRule {
			pattern: Regex::new(&rule.window_class_regex)?,
			right_commands: rule.scroll_right_commands.clone(),
			left_commands: rule.scroll_left_commands.clone(),
		})
	}

	pub async fn handle_event(&self, event: InputEvent) -> Result<()> {
		match event {
			InputEvent::GestureTap => self.execute_gesture(0, "tap").await,
			InputEvent::GestureSwipe(direction) => {
				let (idx, name) = match direction {
					SwipeDirection::Left => (1, "swipe left"),
					SwipeDirection::Right => (2, "swipe right"),
					SwipeDirection::Up => (3, "swipe up"),
					SwipeDirection::Down => (4, "swipe down"),
				};
				self.execute_gesture(idx, name).await
			}
			InputEvent::HorizontalScroll(delta) => self.handle_scroll(delta).await,
		}
	}

	async fn execute_gesture(&self, idx: usize, name: &str) -> Result<()> {
		let command = &self.gestures[idx];

		if command.trim().is_empty() {
			debug!("no command for {}", name);
			return Ok(());
		}

		info!("executing {} -> {}", name, command);
		self.run_command(command).await
	}

	async fn handle_scroll(&self, delta: i32) -> Result<()> {
		let window_class = self.get_window_class().await?;

		for rule in &self.scroll_rules {
			if rule.pattern.is_match(&window_class) {
				let commands = if delta > 0 {
					&rule.right_commands
				} else {
					&rule.left_commands
				};

				debug!(
					"scroll rule matched for '{}': {} commands",
					window_class,
					commands.len()
				);

				for command in commands {
					self.run_command(command).await?;
				}
				return Ok(());
			}
		}

		debug!("no scroll rule for '{}'", window_class);
		Ok(())
	}

	async fn get_window_class(&self) -> Result<String> {
		{
			let cache = self.focus_cache.lock().unwrap();
			if cache.0.elapsed().as_millis() < self.focus_poll_ms as u128 {
				return Ok(cache.1.clone());
			}
		}

		let class = self.query_active_window().await?;

		{
			let mut cache = self.focus_cache.lock().unwrap();
			*cache = (Instant::now(), class.clone());
		}

		Ok(class)
	}

	async fn query_active_window(&self) -> Result<String> {
		#[derive(Deserialize)]
		struct Window {
			class: String,
		}

		let output = Command::new("hyprctl")
			.args(["-j", "activewindow"])
			.output()
			.await?;

		if !output.status.success() {
			warn!("hyprctl failed");
			return Ok(String::new());
		}

		match serde_json::from_slice::<Window>(&output.stdout) {
			Ok(window) => {
				debug!("active window: '{}'", window.class);
				Ok(window.class)
			}
			Err(_) => {
				debug!("could not parse window info");
				Ok(String::new())
			}
		}
	}

	async fn run_command(&self, command: &str) -> Result<()> {
		if command.trim().is_empty() {
			return Ok(());
		}

		debug!("executing: {}", command);

		let output = Command::new("sh").args(["-c", command]).output().await?;

		if !output.status.success() {
			let stderr = String::from_utf8_lossy(&output.stderr);
			warn!("command failed: {}", stderr.trim());
		}

		Ok(())
	}
}
