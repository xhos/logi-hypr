use serde::Deserialize;

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
	pub left: String,
	#[serde(default)]
	pub right: String,
	#[serde(default)]
	pub up: String,
	#[serde(default)]
	pub down: String,
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


