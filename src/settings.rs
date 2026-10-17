//! Settings in %APPDATA%\MusicVisualizer\settings2.txt (key=value lines) + "start with Windows".

use std::path::PathBuf;
use windows::core::PCWSTR;
use windows::Win32::System::Registry::*;

pub const FPS: [u32; 3] = [30, 60, 0]; // 0 = match the display (vsync)
pub const QUALITY: [&str; 3] = ["Low", "Balanced", "High"];
pub const QUALITY_SCALE: [f32; 3] = [0.5, 0.75, 1.0];
pub const SENS: [&str; 3] = ["Low", "Normal", "High"];
pub const SENS_VAL: [f32; 3] = [0.75, 1.0, 1.35];
pub const SIZES: [(&str, u32, u32); 4] = [("Small", 320, 180), ("Medium", 480, 270), ("Large", 720, 405), ("Huge", 960, 540)];

#[derive(Clone)]
pub struct Settings {
    pub look: usize,
    pub auto: bool,
    pub album: bool,
    pub song: bool,
    pub mouse: bool,
    pub top: bool,
    pub fps: usize,
    pub quality: usize,
    pub sens: usize,
    pub size: i32, // -1 = custom
    pub bounds: Option<(i32, i32, u32, u32)>,
}

impl Default for Settings {
    fn default() -> Self {
        Settings { look: 0, auto: false, album: true, song: true, mouse: false, top: true, fps: 2, quality: 1, sens: 1, size: 1, bounds: None }
    }
}

fn path() -> PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
    PathBuf::from(base).join("MusicVisualizer").join("settings2.txt")
}

impl Settings {
    pub fn load() -> Self {
        let mut s = Settings::default();
        let Ok(text) = std::fs::read_to_string(path()) else { return s };
        let (mut x, mut y, mut w, mut h) = (0i32, 0i32, 0u32, 0u32);
        for line in text.lines() {
            let Some((k, v)) = line.split_once('=') else { continue };
            let n: i64 = v.trim().parse().unwrap_or(0);
            match k.trim() {
                "look" => s.look = n.max(0) as usize,
                "auto" => s.auto = n != 0,
                "album" => s.album = n != 0,
                "song" => s.song = n != 0,
                "mouse" => s.mouse = n != 0,
                "top" => s.top = n != 0,
                "fps" => s.fps = (n as usize).min(2),
                "quality" => s.quality = (n as usize).min(2),
                "sens" => s.sens = (n as usize).min(2),
                "size" => s.size = (n as i32).clamp(-1, 3),
                "x" => x = n as i32,
                "y" => y = n as i32,
                "w" => w = n as u32,
                "h" => h = n as u32,
                _ => {}
            }
        }
        if w > 0 && h > 0 {
            s.bounds = Some((x, y, w, h));
        }
        s
    }

    pub fn save(&self) {
        let p = path();
        let _ = std::fs::create_dir_all(p.parent().unwrap());
        let (x, y, w, h) = self.bounds.unwrap_or((0, 0, 0, 0));
        let b = |v: bool| v as i32;
        let _ = std::fs::write(
            p,
            format!(
                "look={}\nauto={}\nalbum={}\nsong={}\nmouse={}\ntop={}\nfps={}\nquality={}\nsens={}\nsize={}\nx={x}\ny={y}\nw={w}\nh={h}\n",
                self.look, b(self.auto), b(self.album), b(self.song), b(self.mouse), b(self.top), self.fps, self.quality, self.sens, self.size
            ),
        );
    }
}

fn wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

const RUN_KEY: &str = r"Software\Microsoft\Windows\CurrentVersion\Run";
const VALUE: &str = "MusicVisualizer";

pub fn startup_on() -> bool {
    unsafe {
        let mut key = HKEY::default();
        if RegOpenKeyExW(HKEY_CURRENT_USER, PCWSTR(wide(RUN_KEY).as_ptr()), None, KEY_READ, &mut key).is_err() {
            return false;
        }
        let ok = RegQueryValueExW(key, PCWSTR(wide(VALUE).as_ptr()), None, None, None, None).is_ok();
        let _ = RegCloseKey(key);
        ok
    }
}

pub fn set_startup(on: bool) {
    unsafe {
        let mut key = HKEY::default();
        if RegOpenKeyExW(HKEY_CURRENT_USER, PCWSTR(wide(RUN_KEY).as_ptr()), None, KEY_SET_VALUE, &mut key).is_err() {
            return;
        }
        if on {
            let exe = std::env::current_exe().map(|p| p.display().to_string()).unwrap_or_default();
            let v = wide(&format!("\"{exe}\" --hidden"));
            let bytes = std::slice::from_raw_parts(v.as_ptr() as *const u8, v.len() * 2);
            let _ = RegSetValueExW(key, PCWSTR(wide(VALUE).as_ptr()), None, REG_SZ, Some(bytes));
        } else {
            let _ = RegDeleteValueW(key, PCWSTR(wide(VALUE).as_ptr()));
        }
        let _ = RegCloseKey(key);
    }
}
