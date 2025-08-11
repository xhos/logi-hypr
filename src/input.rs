use anyhow::Result;
use evdev::{Device, KeyCode, RelativeAxisCode};
use std::{
	fs, os::unix::fs::FileTypeExt, path::PathBuf, sync::mpsc::Sender, thread, time::Instant,
};
use tracing::{debug, info, warn};

#[derive(Debug, Clone)]
pub enum InputEvent {
	GestureTap,
	GestureSwipe(SwipeDirection),
	HorizontalScroll(i32),
}

#[derive(Debug, Clone, Copy)]
pub enum SwipeDirection {
	Left,
	Right,
	Up,
	Down,
}

pub struct InputManager {
	tap_timeout_ms: u64,
	movement_threshold: i32,
}

impl InputManager {
	pub fn new(tap_timeout_ms: u64, movement_threshold: i32) -> Self {
		Self {
			tap_timeout_ms,
			movement_threshold,
		}
	}

	pub fn start_monitoring(self, tx: Sender<InputEvent>) -> Result<()> {
		info!("scanning for input devices");

		let devices = self.find_gesture_devices()?;

		if devices.is_empty() {
			warn!("no gesture-capable devices found");
		} else {
			info!("monitoring {} devices for gestures", devices.len());
			for device_path in devices {
				self.spawn_device_thread(device_path, tx.clone());
			}
		}

		Ok(())
	}

	fn find_gesture_devices(&self) -> Result<Vec<PathBuf>> {
		let mut devices = Vec::new();

		for entry in fs::read_dir("/dev/input")? {
			let entry = entry?;
			let path = entry.path();

			if self.is_event_device(&entry, &path)? {
				if let Ok(device) = Device::open(&path) {
					if self.has_gesture_capability(&device) {
						info!("found gesture device: {}", path.display());
						devices.push(path);
					}
				}
			}
		}

		Ok(devices)
	}

	fn is_event_device(&self, entry: &fs::DirEntry, path: &PathBuf) -> Result<bool> {
		Ok(
			entry.file_type()?.is_char_device()
				&& path
					.file_name()
					.unwrap()
					.to_string_lossy()
					.starts_with("event"),
		)
	}

	fn has_gesture_capability(&self, device: &Device) -> bool {
		device
			.supported_keys()
			.map_or(false, |keys| keys.contains(KeyCode::BTN_FORWARD))
	}

	fn spawn_device_thread(&self, path: PathBuf, tx: Sender<InputEvent>) {
		let tap_timeout = self.tap_timeout_ms;
		let movement_threshold = self.movement_threshold;

		thread::spawn(move || {
			if let Err(e) = Self::monitor_device(path.clone(), tap_timeout, movement_threshold, tx) {
				warn!("device thread error for {}: {}", path.display(), e);
			}
		});
	}

	fn monitor_device(
		path: PathBuf,
		tap_timeout_ms: u64,
		movement_threshold: i32,
		tx: Sender<InputEvent>,
	) -> Result<()> {
		let mut device = Device::open(&path)?;
		let mut gesture = GestureState::new(tap_timeout_ms, movement_threshold);

		debug!("listening on {}", path.display());

		loop {
			for event in device.fetch_events()? {
				match event.destructure() {
					evdev::EventSummary::Key(_, KeyCode::BTN_FORWARD, value) => {
						if value == 1 {
							gesture.start();
						} else if let Some(event) = gesture.finish() {
							let _ = tx.send(event);
						}
					}

					evdev::EventSummary::RelativeAxis(_, axis, value) => {
						let event = match axis {
							RelativeAxisCode::REL_X => gesture.move_x(value),
							RelativeAxisCode::REL_Y => gesture.move_y(value),
							RelativeAxisCode::REL_HWHEEL => Some(InputEvent::HorizontalScroll(value)),
							_ => None,
						};

						if let Some(event) = event {
							let _ = tx.send(event);
						}
					}

					_ => {}
				}
			}
		}
	}
}

struct GestureState {
	active: bool,
	moved: bool,
	start_time: Instant,
	accumulated_x: i32,
	accumulated_y: i32,
	tap_timeout_ms: u64,
	movement_threshold: i32,
}

impl GestureState {
	fn new(tap_timeout_ms: u64, movement_threshold: i32) -> Self {
		Self {
			active: false,
			moved: false,
			start_time: Instant::now(),
			accumulated_x: 0,
			accumulated_y: 0,
			tap_timeout_ms,
			movement_threshold,
		}
	}

	fn start(&mut self) {
		*self = Self::new(self.tap_timeout_ms, self.movement_threshold);
		self.active = true;
		self.start_time = Instant::now();
		debug!("gesture started");
	}

	fn finish(&mut self) -> Option<InputEvent> {
		if !self.active {
			return None;
		}

		self.active = false;

		if !self.moved && self.start_time.elapsed().as_millis() <= self.tap_timeout_ms as u128 {
			debug!("tap detected");
			Some(InputEvent::GestureTap)
		} else {
			None
		}
	}

	fn move_x(&mut self, delta: i32) -> Option<InputEvent> {
		if !self.active {
			return None;
		}

		self.accumulated_x += delta;
		self.check_threshold()
	}

	fn move_y(&mut self, delta: i32) -> Option<InputEvent> {
		if !self.active {
			return None;
		}

		self.accumulated_y += delta;
		self.check_threshold()
	}

	fn check_threshold(&mut self) -> Option<InputEvent> {
		let (abs_x, abs_y) = (self.accumulated_x.abs(), self.accumulated_y.abs());

		if abs_x >= self.movement_threshold && abs_x > abs_y {
			self.moved = true;
			let direction = if self.accumulated_x < 0 {
				SwipeDirection::Left
			} else {
				SwipeDirection::Right
			};

			self.reset_accumulation();
			debug!("horizontal swipe: {:?}", direction);
			Some(InputEvent::GestureSwipe(direction))
		} else if abs_y >= self.movement_threshold && abs_y > abs_x {
			self.moved = true;
			let direction = if self.accumulated_y < 0 {
				SwipeDirection::Up
			} else {
				SwipeDirection::Down
			};

			self.reset_accumulation();
			debug!("vertical swipe: {:?}", direction);
			Some(InputEvent::GestureSwipe(direction))
		} else {
			None
		}
	}

	fn reset_accumulation(&mut self) {
		self.accumulated_x = 0;
		self.accumulated_y = 0;
	}
}
