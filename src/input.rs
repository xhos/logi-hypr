use anyhow::Result;
use evdev::{Device, KeyCode, RelativeAxisCode};
use std::{
	collections::HashSet,
	fs,
	os::{fd::AsRawFd, unix::fs::FileTypeExt},
	path::{Path, PathBuf},
	sync::{mpsc::Sender, Arc, Mutex},
	thread,
	time::Instant,
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

type ActiveSet = Arc<Mutex<HashSet<PathBuf>>>;

impl InputManager {
	pub fn new(tap_timeout_ms: u64, movement_threshold: i32) -> Self {
		Self {
			tap_timeout_ms,
			movement_threshold,
		}
	}

	pub fn start_monitoring(self, tx: Sender<InputEvent>) -> Result<()> {
		let active: ActiveSet = Arc::new(Mutex::new(HashSet::new()));

		info!("scanning for input devices");
		for path in find_event_devices()? {
			self.try_attach(path, &tx, &active);
		}

		if active.lock().unwrap().is_empty() {
			info!("no gesture-capable devices found yet — watching for hot-plug");
		}

		self.watch_udev(tx, active)
	}

	fn try_attach(&self, path: PathBuf, tx: &Sender<InputEvent>, active: &ActiveSet) {
		if active.lock().unwrap().contains(&path) {
			return;
		}

		let device = match Device::open(&path) {
			Ok(d) => d,
			Err(_) => return,
		};

		if !has_gesture_capability(&device) {
			return;
		}
		drop(device);

		active.lock().unwrap().insert(path.clone());
		info!("attached gesture device: {}", path.display());
		self.spawn_device_thread(path, tx.clone(), active.clone());
	}

	fn spawn_device_thread(&self, path: PathBuf, tx: Sender<InputEvent>, active: ActiveSet) {
		let tap_timeout = self.tap_timeout_ms;
		let movement_threshold = self.movement_threshold;

		thread::spawn(move || {
			if let Err(e) = monitor_device(&path, tap_timeout, movement_threshold, tx) {
				warn!("device thread for {} ended: {}", path.display(), e);
			}
			active.lock().unwrap().remove(&path);
		});
	}

	fn watch_udev(&self, tx: Sender<InputEvent>, active: ActiveSet) -> Result<()> {
		let socket = udev::MonitorBuilder::new()?
			.match_subsystem("input")?
			.listen()?;

		info!("watching udev for hot-plugged input devices");

		loop {
			wait_readable(socket.as_raw_fd())?;

			for event in socket.iter() {
				if event.event_type() != udev::EventType::Add {
					continue;
				}
				let Some(devnode) = event.devnode() else {
					continue;
				};
				if !is_event_node(devnode) {
					continue;
				}
				self.try_attach(devnode.to_path_buf(), &tx, &active);
			}
		}
	}
}

fn find_event_devices() -> Result<Vec<PathBuf>> {
	let mut out = Vec::new();
	for entry in fs::read_dir("/dev/input")? {
		let entry = entry?;
		let path = entry.path();
		if entry.file_type()?.is_char_device() && is_event_node(&path) {
			out.push(path);
		}
	}
	Ok(out)
}

fn is_event_node(path: &Path) -> bool {
	path.file_name()
		.and_then(|n| n.to_str())
		.map(|n| n.starts_with("event"))
		.unwrap_or(false)
}

fn has_gesture_capability(device: &Device) -> bool {
	device
		.supported_keys()
		.map_or(false, |keys| keys.contains(KeyCode::BTN_FORWARD))
}

fn wait_readable(fd: std::os::fd::RawFd) -> std::io::Result<()> {
	let mut pfd = libc::pollfd {
		fd,
		events: libc::POLLIN,
		revents: 0,
	};
	let r = unsafe { libc::poll(&mut pfd, 1, -1) };
	if r < 0 {
		Err(std::io::Error::last_os_error())
	} else {
		Ok(())
	}
}

fn monitor_device(
	path: &Path,
	tap_timeout_ms: u64,
	movement_threshold: i32,
	tx: Sender<InputEvent>,
) -> Result<()> {
	let mut device = Device::open(path)?;
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
