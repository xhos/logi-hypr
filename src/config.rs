use anyhow::{Context, Result};
use serde::Deserialize;
use std::path::Path;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
	pub gesture: GestureConfig,
	pub scroll: ScrollConfig,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GestureConfig {
	pub tap_timeout_ms: u64,
	pub movement_threshold: i32,
	pub commands: GestureCommands,
}

#[derive(Debug, Clone, Deserialize)]
pub struct GestureCommands {
	#[serde(default)]
	pub tap: String,
	#[serde(default)]
	pub swipe_left: String,
	#[serde(default)]
	pub swipe_right: String,
	#[serde(default)]
	pub swipe_up: String,
	#[serde(default)]
	pub swipe_down: String,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ScrollConfig {
	pub focus_poll_ms: u64,
	#[serde(default)]
	pub rules: Vec<ScrollRule>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct ScrollRule {
	pub window_class_regex: String,
	#[serde(default)]
	pub scroll_right_commands: Vec<String>,
	#[serde(default)]
	pub scroll_left_commands: Vec<String>,
}

impl Config {
	pub fn from_file<P: AsRef<Path>>(path: P) -> Result<Self> {
		let path = path.as_ref();
		let expanded = shellexpand::tilde(&path.to_string_lossy()).into_owned();

		let content = std::fs::read_to_string(&expanded)
			.with_context(|| format!("failed to read config: {}", expanded))?;

		toml::from_str(&content).with_context(|| format!("invalid config format: {}", expanded))
	}
}

impl Default for Config {
	fn default() -> Self {
		Self {
			gesture: GestureConfig {
				tap_timeout_ms: 200,
				movement_threshold: 30,
				commands: GestureCommands {
					tap: "hyprctl dispatch exec wofi".into(),
					swipe_left: "hyprctl dispatch workspace -1".into(),
					swipe_right: "hyprctl dispatch workspace +1".into(),
					swipe_up: "hyprctl dispatch movetoworkspace -1".into(),
					swipe_down: "hyprctl dispatch movetoworkspace +1".into(),
				},
			},
			scroll: ScrollConfig {
				focus_poll_ms: 100,
				rules: vec![
					ScrollRule {
						window_class_regex: "spotify".into(),
						scroll_right_commands: vec!["wpctl set-volume @DEFAULT_AUDIO_SINK@ +5%".into()],
						scroll_left_commands: vec!["wpctl set-volume @DEFAULT_AUDIO_SINK@ -5%".into()],
					},
					ScrollRule {
						window_class_regex: "gimp".into(),
						scroll_right_commands: vec!["xdotool key ctrl+plus".into()],
						scroll_left_commands: vec!["xdotool key ctrl+minus".into()],
					},
				],
			},
		}
	}
}
