//! The tray app: borderless dockable window, tray icon + menu, glass UI, settings panel, mouse control,
//! auto-pick, album colours, and the frame loop.

use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use tray_icon::menu::{CheckMenuItem, ContextMenu, Menu, MenuEvent, MenuItem, PredefinedMenuItem, Submenu};
use tray_icon::{MouseButton as TrayButton, MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent};
use winit::application::ApplicationHandler;
use winit::dpi::{PhysicalPosition, PhysicalSize};
use winit::event::{ElementState, MouseButton, MouseScrollDelta, WindowEvent};
use winit::event_loop::{ActiveEventLoop, ControlFlow};
use winit::keyboard::{Key, NamedKey};
use winit::platform::windows::{CornerPreference, WindowAttributesExtWindows};
use winit::raw_window_handle::{HasWindowHandle, RawWindowHandle};
use winit::window::{CursorIcon, Fullscreen, ResizeDirection, Window, WindowId, WindowLevel};

use crate::analyzer::Analyzer;
use crate::capture;
use crate::looks::{self, LOOKS};
use crate::media::{self, NowPlaying};
use crate::render::{Globals, Rect, Renderer, Ui, MAX_RECTS};
use crate::settings::{self, Settings, FPS, QUALITY, QUALITY_SCALE, SENS, SENS_VAL, SIZES};
use crate::state::Signals;
use crate::text::{self, Align, TextItem};

const GLYPHS: [&str; 6] = ["\u{E76B}", "\u{E76C}", "\u{E962}", "\u{E713}", "\u{E740}", "\u{E921}"];
const B_PREV: usize = 0;
const B_NEXT: usize = 1;
const B_MOUSE: usize = 2;
const B_SETTINGS: usize = 3;
const B_FULL: usize = 4;
const B_HIDE: usize = 5;
const MOONLIGHT: usize = 7;

struct Gpu {
    surface: wgpu::Surface<'static>,
    config: wgpu::SurfaceConfiguration,
    r: Renderer,
}

struct MenuIds {
    show: MenuItem,
    looks: Vec<CheckMenuItem>,
    auto: CheckMenuItem,
    mouse: CheckMenuItem,
    settings: MenuItem,
    full: MenuItem,
    ghost: CheckMenuItem,
    exit: MenuItem,
}

#[derive(Default)]
struct AutoState {
    bass: f32,
    mid: f32,
    beats: f32,
    hold: f32,
    since: f32,
    since_track: f32,
    flip: usize,
    fresh: bool,
}

pub fn log(msg: &str) {
    use std::io::Write;
    let p = std::path::PathBuf::from(std::env::var("APPDATA").unwrap_or_default()).join("MusicVisualizer").join("log.txt");
    if let Ok(mut f) = std::fs::OpenOptions::new().create(true).append(true).open(p) {
        let _ = writeln!(f, "{msg}");
    }
}

pub struct App {
    /// `--probe`: invisible self-test (window far off-screen, never focused, no tray), logs and exits
    probe: bool,
    frames: u64,
    window: Option<Arc<Window>>,
    gpu: Option<Gpu>,
    set: Settings,
    start_hidden: bool,
    capture: Arc<capture::Shared>,
    media: Arc<Mutex<NowPlaying>>,
    media_version: u32,
    title: String,
    an: Analyzer,
    sig: Signals,
    samples: Vec<f32>,
    audio_tex: Vec<f32>,
    t0: Instant,
    last_frame: Instant,
    look_start: f64,
    visible: bool,
    fullscreen: bool,
    pre_full: Option<(PhysicalPosition<i32>, PhysicalSize<u32>)>,
    enlarged: Option<(PhysicalPosition<i32>, PhysicalSize<u32>)>,
    ghost: bool,
    // input + UI animation
    cursor: (f32, f32),
    inside: bool,
    idle: f32,
    cursor_hidden: bool,
    hover: i32,
    pressed: i32,
    hover_anim: [f32; 6],
    shine_at: [f32; 6],
    ui_alpha: f32,
    click_pos: (f32, f32),
    click_time: f64,
    last_press: Instant,
    settings_open: bool,
    panel_t: f32,
    hover_row: i32,
    row_rects: Vec<[f32; 4]>,
    row_val_w: Vec<f32>,
    close_rect: [f32; 4],
    panel_rect: [f32; 4],
    name_timer: f32,
    song_timer: f32,
    hint: String,
    hint_timer: f32,
    text_items: Vec<TextItem>,
    text_size: (u32, u32),
    pal: [[f32; 4]; 3],
    album_ok: bool,
    last_move: Option<Instant>,
    auto: AutoState,
    tray: Option<TrayIcon>,
    menu: Option<Menu>,
    ids: Option<MenuIds>,
}

impl App {
    pub fn new(start_hidden: bool, probe: bool) -> Self {
        let set = Settings::load();
        let now = Instant::now();
        App {
            probe,
            frames: 0,
            window: None,
            gpu: None,
            start_hidden,
            capture: capture::start(),
            media: media::start(),
            media_version: 0,
            title: String::new(),
            an: Analyzer::new(),
            sig: Signals::default(),
            samples: Vec::new(),
            audio_tex: vec![0.0; (crate::render::AUDIO_W * crate::render::AUDIO_H) as usize],
            t0: now,
            last_frame: now,
            look_start: 0.0,
            visible: false,
            fullscreen: false,
            pre_full: None,
            enlarged: None,
            ghost: false,
            cursor: (0.0, 0.0),
            inside: false,
            idle: 0.0,
            cursor_hidden: false,
            hover: -1,
            pressed: -1,
            hover_anim: [0.0; 6],
            shine_at: [-9.0; 6],
            ui_alpha: 0.4,
            click_pos: (0.5, 0.5),
            click_time: -999.0,
            last_press: now - Duration::from_secs(5),
            settings_open: false,
            panel_t: 0.0,
            hover_row: -1,
            row_rects: Vec::new(),
            row_val_w: Vec::new(),
            close_rect: [0.0; 4],
            panel_rect: [0.0; 4],
            name_timer: 2.5,
            song_timer: 0.0,
            hint: String::new(),
            hint_timer: 0.0,
            text_items: Vec::new(),
            text_size: (0, 0),
            pal: looks::palette(LOOKS[set.look.min(LOOKS.len() - 1)].src),
            album_ok: false,
            last_move: None,
            auto: AutoState { since: 99.0, since_track: 99.0, ..Default::default() },
            tray: None,
            menu: None,
            ids: None,
            set,
        }
    }

    fn time(&self) -> f64 {
        self.t0.elapsed().as_secs_f64()
    }

    fn hwnd(&self) -> isize {
        let Some(w) = &self.window else { return 0 };
        match w.window_handle().map(|h| h.as_raw()) {
            Ok(RawWindowHandle::Win32(h)) => h.hwnd.get(),
            _ => 0,
        }
    }

    /// The monitor work area (screen minus taskbar) the window is on.
    fn work_area(&self) -> (i32, i32, i32, i32) {
        use windows::Win32::Foundation::{HWND, POINT};
        use windows::Win32::Graphics::Gdi::*;
        unsafe {
            let mon = if self.hwnd() != 0 {
                MonitorFromWindow(HWND(self.hwnd() as _), MONITOR_DEFAULTTONEAREST)
            } else {
                MonitorFromPoint(POINT { x: 0, y: 0 }, MONITOR_DEFAULTTOPRIMARY)
            };
            let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
            let _ = GetMonitorInfoW(mon, &mut mi);
            let r = mi.rcWork;
            (r.left, r.top, r.right, r.bottom)
        }
    }

    fn scale(&self) -> f32 {
        self.window.as_ref().map(|w| w.scale_factor() as f32).unwrap_or(1.0)
    }

    fn d(&self) -> f32 {
        self.scale() * if self.fullscreen { 1.35 } else { 1.0 }
    }

    fn hint(&mut self, s: &str) {
        self.hint = s.to_string();
        self.hint_timer = 3.0;
    }

    // ---------------- window management ----------------

    fn default_bounds(&self) -> (PhysicalPosition<i32>, PhysicalSize<u32>) {
        let (_, _, r, b) = self.work_area();
        let s = self.scale();
        let (w, h) = ((480.0 * s) as u32, (270.0 * s) as u32);
        let m = (12.0 * s) as i32;
        (PhysicalPosition::new(r - w as i32 - m, b - h as i32 - m), PhysicalSize::new(w, h))
    }

    fn show(&mut self) {
        let Some(w) = self.window.clone() else { return };
        if !self.visible && !self.probe {
            let (pos, size) = match self.set.bounds {
                Some((x, y, bw, bh)) => (PhysicalPosition::new(x, y), PhysicalSize::new(bw, bh)),
                None => self.default_bounds(),
            };
            w.set_outer_position(pos);
            let _ = w.request_inner_size(size);
        }
        if self.gpu.is_none() {
            self.create_gpu();
        }
        self.visible = true;
        w.set_visible(true);
        if self.probe {
            w.set_outer_position(PhysicalPosition::new(-20000, -20000));
        } else {
            w.focus_window();
        }
        self.capture.active.store(true, std::sync::atomic::Ordering::Relaxed);
        self.last_frame = Instant::now();
        self.name_timer = 2.5;
        self.song_timer = 4.0;
        w.request_redraw();
    }

    fn hide(&mut self) {
        if self.settings_open {
            self.close_settings();
        }
        if self.fullscreen {
            self.toggle_fullscreen();
        }
        if let Some(w) = &self.window {
            w.set_cursor_visible(true);
            w.set_visible(false);
        }
        self.cursor_hidden = false;
        self.visible = false;
        self.capture.active.store(false, std::sync::atomic::Ordering::Relaxed);
        // the GPU is created on first show and then kept: dropping it frees little (the driver stays loaded)
        unsafe {
            use windows::Win32::System::Threading::GetCurrentProcess;
            let _ = windows::Win32::System::Memory::SetProcessWorkingSetSizeEx(GetCurrentProcess(), usize::MAX, usize::MAX, Default::default());
        }
    }

    fn toggle_fullscreen(&mut self) {
        let Some(w) = self.window.clone() else { return };
        if self.settings_open {
            self.close_settings();
        }
        self.fullscreen = !self.fullscreen;
        if self.fullscreen {
            self.pre_full = Some((w.outer_position().unwrap_or_default(), w.inner_size()));
            w.set_fullscreen(Some(Fullscreen::Borderless(None)));
            w.set_window_level(WindowLevel::AlwaysOnTop);
        } else {
            w.set_fullscreen(None);
            w.set_window_level(if self.set.top { WindowLevel::AlwaysOnTop } else { WindowLevel::Normal });
            if let Some((p, s)) = self.pre_full.take() {
                w.set_outer_position(p);
                let _ = w.request_inner_size(s);
            }
            w.set_cursor_visible(true);
            self.cursor_hidden = false;
        }
    }

    /// Resize while staying glued to the screen corner/edge the window is docked nearest to.
    fn anchored(&self, pos: PhysicalPosition<i32>, old: PhysicalSize<u32>, new: PhysicalSize<u32>) -> PhysicalPosition<i32> {
        let (l, t, r, b) = self.work_area();
        let x = if pos.x + old.width as i32 / 2 > (l + r) / 2 { pos.x + old.width as i32 - new.width as i32 } else { pos.x };
        let y = if pos.y + old.height as i32 / 2 > (t + b) / 2 { pos.y + old.height as i32 - new.height as i32 } else { pos.y };
        PhysicalPosition::new(x.clamp(l, (r - new.width as i32).max(l)), y.clamp(t, (b - new.height as i32).max(t)))
    }

    fn step_size(&mut self, d: i32) {
        let Some(w) = self.window.clone() else { return };
        self.set.size = if self.set.size < 0 { 1 } else { (self.set.size + d).rem_euclid(SIZES.len() as i32) };
        let s = self.scale();
        let (_, sw, sh) = SIZES[self.set.size as usize];
        let new = PhysicalSize::new((sw as f32 * s) as u32, (sh as f32 * s) as u32);
        if let Some((p, old)) = self.enlarged {
            self.enlarged = Some((self.anchored(p, old, new), new));
        } else if !self.fullscreen {
            let pos = self.anchored(w.outer_position().unwrap_or_default(), w.inner_size(), new);
            w.set_outer_position(pos);
            let _ = w.request_inner_size(new);
            self.set.bounds = Some((pos.x, pos.y, new.width, new.height));
        }
        self.set.save();
    }

    /// Magnetic edges: after a move, snap to nearby screen edges (with a small gap) or the centre.
    fn snap(&mut self) {
        let Some(w) = self.window.clone() else { return };
        if self.fullscreen {
            return;
        }
        let Ok(p) = w.outer_position() else { return };
        let size = w.outer_size();
        let (l, t, r, b) = self.work_area();
        let s = self.scale();
        let (gap, snap) = ((8.0 * s) as i32, (28.0 * s) as i32);
        let (mut x, mut y) = (p.x, p.y);
        let (ww, wh) = (size.width as i32, size.height as i32);
        if (x - (l + gap)).abs() < snap { x = l + gap; }
        if (x + ww - (r - gap)).abs() < snap { x = r - gap - ww; }
        if (y - (t + gap)).abs() < snap { y = t + gap; }
        if (y + wh - (b - gap)).abs() < snap { y = b - gap - wh; }
        let mid = l + (r - l - ww) / 2;
        if (x - mid).abs() < snap { x = mid; }
        if (x, y) != (p.x, p.y) {
            w.set_outer_position(PhysicalPosition::new(x, y));
        }
        if self.enlarged.is_none() {
            let inner = w.inner_size();
            self.set.bounds = Some((x, y, inner.width, inner.height));
            self.set.save();
        }
    }

    fn open_settings(&mut self) {
        if self.settings_open {
            return;
        }
        self.settings_open = true;
        self.hover_row = -1;
        let Some(w) = self.window.clone() else { return };
        if self.fullscreen {
            return;
        }
        let s = self.scale();
        let need = PhysicalSize::new((420.0 * s) as u32, ((70.0 + 12.0 * 25.0) * s) as u32);
        let cur = w.inner_size();
        if cur.width < need.width || cur.height < need.height {
            let pos = w.outer_position().unwrap_or_default();
            self.enlarged = Some((pos, cur));
            let new = PhysicalSize::new(cur.width.max(need.width), cur.height.max(need.height));
            w.set_outer_position(self.anchored(pos, cur, new));
            let _ = w.request_inner_size(new);
        }
    }

    fn close_settings(&mut self) {
        self.settings_open = false;
        if let (Some((p, s)), Some(w)) = (self.enlarged.take(), self.window.clone()) {
            w.set_outer_position(p);
            let _ = w.request_inner_size(s);
        }
    }

    fn set_ghost(&mut self, on: bool) {
        self.ghost = on;
        if let Some(w) = &self.window {
            let _ = w.set_cursor_hittest(!on);
        }
        if let Some(ids) = &self.ids {
            ids.ghost.set_checked(on);
        }
        self.hint(if on { "Ghost mode: clicks pass through. Turn it off from the tray icon." } else { "Ghost mode off" });
    }

    fn set_look(&mut self, i: usize, manual: bool) {
        let i = i % LOOKS.len();
        if manual && self.set.auto {
            self.set.auto = false;
            self.hint("Auto-pick off");
        }
        if let Some(gpu) = &mut self.gpu {
            if let Err(e) = gpu.r.set_look(LOOKS[i].src) {
                let first = e.lines().find(|l| !l.trim().is_empty()).unwrap_or("").to_string();
                self.hint(&format!("{} failed to load: {first}", looks::name(LOOKS[i].src)));
                return;
            }
        }
        self.set.look = i;
        self.look_start = self.time();
        self.name_timer = 2.5;
        if !self.album_ok {
            self.pal = looks::palette(LOOKS[i].src);
        }
        if let Some(ids) = &self.ids {
            for (k, item) in ids.looks.iter().enumerate() {
                item.set_checked(k == i);
            }
        }
        self.set.save();
    }

    // ---------------- auto-pick ----------------

    fn auto_pick(&mut self, dt: f32) {
        const CATS: [&[usize]; 4] = [&[0, 1, 2], &[3, 4, 5], &[7], &[8, 6]];
        let a = &mut self.auto;
        let k = (dt / 5.0).min(1.0);
        a.bass += (self.an.bass - a.bass) * k;
        a.mid += (self.an.mid - a.mid) * k;
        a.beats += if self.an.beat { 0.2 } else { 0.0 } - a.beats * k;
        a.since += dt;
        a.since_track += dt;
        if self.an.vol < 0.0003 {
            return;
        }
        let beaty = a.beats > 0.9;
        let bassy = a.bass > 0.45 && a.bass > a.mid * 1.2;
        let cat = if beaty { if bassy { 0 } else { 1 } } else if a.mid > a.bass * 1.1 { 2 } else { 3 };
        let want = CATS[cat][a.flip % CATS[cat].len()];
        let cur_cat = CATS.iter().position(|c| c.contains(&self.set.look));
        let mut switch = None;
        if a.fresh && a.since_track > 5.0 {
            a.fresh = false;
            a.hold = 0.0;
            if want != self.set.look {
                switch = Some(want);
            }
        } else if cur_cat == Some(cat) {
            a.hold = 0.0;
        } else {
            a.hold += dt;
            if a.hold > 4.0 && a.since > 20.0 {
                switch = Some(want);
            }
        }
        if let Some(w) = switch {
            self.auto.since = 0.0;
            self.auto.hold = 0.0;
            self.set_look(w, false);
        }
    }

    // ---------------- UI layout ----------------

    fn button_rect(&self, i: usize, w: f32) -> [f32; 4] {
        let d = self.d();
        let (size, gap, m) = (30.0 * d, 7.0 * d, 10.0 * d);
        let n = GLYPHS.len() as f32;
        [w - m - (n - i as f32) * size - (n - 1.0 - i as f32) * gap, m, size, size]
    }

    fn hit_button(&self, x: f32, y: f32, w: f32) -> i32 {
        if self.settings_open {
            return -1;
        }
        for i in 0..GLYPHS.len() {
            let r = self.button_rect(i, w);
            if x >= r[0] - 3.0 && x <= r[0] + r[2] + 3.0 && y >= r[1] - 3.0 && y <= r[1] + r[3] + 3.0 {
                return i as i32;
            }
        }
        -1
    }

    fn rows(&self) -> Vec<(&'static str, String, bool)> {
        let on = |b: bool| if b { "on".to_string() } else { "off".to_string() };
        vec![
            ("Look", looks::name(LOOKS[self.set.look].src), false),
            ("Auto-pick look for the music", on(self.set.auto), true),
            ("Colours from album art", on(self.set.album), true),
            ("Show song title", on(self.set.song), true),
            ("Mouse control", on(self.set.mouse), true),
            ("Size", if self.set.size < 0 { "Custom".into() } else { SIZES[self.set.size as usize].0.into() }, false),
            ("Frame rate", if FPS[self.set.fps] == 0 { "Display".into() } else { format!("{} fps", FPS[self.set.fps]) }, false),
            ("Quality", QUALITY[self.set.quality].into(), false),
            ("Sensitivity", SENS[self.set.sens].into(), false),
            ("Always on top", on(self.set.top), true),
            ("Start with Windows", on(settings::startup_on()), true),
            ("Ghost mode (clicks pass through)", on(self.ghost), true),
        ]
    }

    fn change_row(&mut self, row: usize, dir: i32) {
        match row {
            0 => self.set_look((self.set.look as i32 + dir).rem_euclid(LOOKS.len() as i32) as usize, true),
            1 => self.set.auto = !self.set.auto,
            2 => self.set.album = !self.set.album,
            3 => self.set.song = !self.set.song,
            4 => self.set.mouse = !self.set.mouse,
            5 => self.step_size(dir),
            6 => self.set.fps = (self.set.fps as i32 + dir).rem_euclid(3) as usize,
            7 => self.set.quality = (self.set.quality as i32 + dir).rem_euclid(3) as usize,
            8 => self.set.sens = (self.set.sens as i32 + dir).rem_euclid(3) as usize,
            9 => {
                self.set.top = !self.set.top;
                if let (Some(w), false) = (&self.window, self.fullscreen) {
                    w.set_window_level(if self.set.top { WindowLevel::AlwaysOnTop } else { WindowLevel::Normal });
                }
            }
            10 => settings::set_startup(!settings::startup_on()),
            11 => {
                self.close_settings();
                self.set_ghost(!self.ghost);
            }
            _ => {}
        }
        if let Some(ids) = &self.ids {
            ids.auto.set_checked(self.set.auto);
            ids.mouse.set_checked(self.set.mouse);
        }
        self.set.save();
    }

    /// Builds this frame's glass rects and the text that goes on them.
    fn layout(&mut self, w: f32, h: f32) -> (Vec<Rect>, Vec<TextItem>) {
        let d = self.d();
        let t = self.time() as f32;
        let mut rects = Vec::new();
        let mut items = Vec::new();
        let rect = |r: [f32; 4], radius: f32, alpha: f32, hot: f32, kind: f32, shine: f32, press: f32| Rect {
            r,
            p: [radius, alpha, hot, kind],
            q: [shine, press, 0.0, 0.0],
        };
        let ir = |r: [f32; 4]| [r[0] as i32, r[1] as i32, r[2] as i32, r[3] as i32];
        let hide = 1.0 - self.panel_t;

        // buttons
        for i in 0..GLYPHS.len() {
            let mut r = self.button_rect(i, w);
            let a = self.hover_anim[i];
            let grow = 0.08 * a - if self.pressed == i as i32 { 0.07 } else { 0.0 };
            r = [r[0] - r[2] * grow / 2.0, r[1] - r[3] * grow / 2.0, r[2] * (1.0 + grow), r[3] * (1.0 + grow)];
            let alpha = self.ui_alpha * hide * (0.85 + 0.15 * a);
            if i == B_MOUSE && self.set.mouse {
                rects.push(rect([r[0] - 2.0 * d, r[1] - 2.0 * d, r[2] + 4.0 * d, r[3] + 4.0 * d], r[3], alpha, 0.0, 4.0, -1.0, 0.0));
            }
            rects.push(rect(r, r[3] / 2.0, alpha, a, 0.0, (t - self.shine_at[i]) / 0.55, if self.pressed == i as i32 { 1.0 } else { 0.0 }));
            let g = if i == B_FULL && self.fullscreen { "\u{E73F}" } else { GLYPHS[i] };
            let base = self.button_rect(i, w);
            items.push(TextItem { text: g.into(), rect: ir(base), size: 13.0 * d, bold: false, icon: true, align: Align::Center, channel: 0 });
        }

        // look name pill
        let name = format!("{}{}", if self.set.auto { "Auto \u{00B7} " } else { "" }, looks::name(LOOKS[self.set.look].src));
        let name_a = self.name_timer.clamp(0.0, 1.0).max(if self.inside { self.ui_alpha } else { 0.0 }) * hide;
        let nw = text::measure(&name, 14.0 * d, true) + 26.0 * d;
        let mut nr = [10.0 * d, 10.0 * d, nw, 30.0 * d];
        if nr[0] + nr[2] > self.button_rect(0, w)[0] - 6.0 * d {
            nr[1] = self.button_rect(0, w)[1] + 30.0 * d + 8.0 * d;
        }
        rects.push(rect(nr, nr[3] / 2.0, name_a, 0.0, 1.0, -1.0, 0.0));
        items.push(TextItem { text: name, rect: ir(nr), size: 14.0 * d, bold: true, icon: false, align: Align::Center, channel: 1 });

        // now playing
        let np = self.media.lock().unwrap().clone();
        let song_a = if self.set.song && !np.title.is_empty() {
            self.song_timer.clamp(0.0, 1.0).max(if self.inside { self.ui_alpha } else { 0.0 }) * hide
        } else {
            0.0
        };
        if song_a > 0.0 {
            let (ph, m) = (46.0 * d, 10.0 * d);
            let art = ph - 12.0 * d;
            let tw = text::measure(&np.title, 14.0 * d, true).max(text::measure(&np.artist, 12.0 * d, false));
            let pw = (w - 2.0 * m).min(360.0 * d).min(art + 28.0 * d + tw);
            let pr = [m, h - m - ph, pw, ph];
            rects.push(rect(pr, 14.0 * d, song_a, 0.0, 1.0, -1.0, 0.0));
            let ar = [pr[0] + 6.0 * d, pr[1] + 6.0 * d, art, art];
            if np.art.is_some() {
                rects.push(rect(ar, 9.0 * d, song_a, 0.0, 2.0, -1.0, 0.0));
            } else {
                items.push(TextItem { text: "\u{E8D6}".into(), rect: ir(ar), size: 14.0 * d, bold: false, icon: true, align: Align::Center, channel: 2 });
            }
            let tx = ar[0] + art + 10.0 * d;
            let twid = pr[0] + pr[2] - tx - 8.0 * d;
            items.push(TextItem { text: np.title.clone(), rect: [tx as i32, (pr[1] + 4.0 * d) as i32, twid as i32, (20.0 * d) as i32], size: 14.0 * d, bold: true, icon: false, align: Align::Left, channel: 2 });
            items.push(TextItem { text: np.artist.clone(), rect: [tx as i32, (pr[1] + 23.0 * d) as i32, twid as i32, (18.0 * d) as i32], size: 12.0 * d, bold: false, icon: false, align: Align::Left, channel: 2 });
        }

        // hint
        if self.hint_timer > 0.0 {
            let a = self.hint_timer.min(1.0);
            let hw = (text::measure(&self.hint, 12.5 * d, false) + 28.0 * d).min(w - 20.0 * d);
            let hr = [(w - hw) / 2.0, h / 2.0 - 15.0 * d, hw, 30.0 * d];
            rects.push(rect(hr, 15.0 * d, a, 0.0, 1.0, -1.0, 0.0));
            items.push(TextItem { text: self.hint.clone(), rect: ir(hr), size: 12.5 * d, bold: false, icon: false, align: Align::Center, channel: 3 });
        }

        // settings panel
        if self.panel_t > 0.01 {
            let k = self.panel_t;
            let rows = self.rows();
            let pw = (w - 20.0 * d).min(400.0 * d);
            let rh = 25.0 * d;
            let ph = 50.0 * d + rows.len() as f32 * rh;
            let p = [(w - pw) / 2.0, (h - ph) / 2.0 + (1.0 - k) * 12.0 * d, pw, ph];
            self.panel_rect = p;
            rects.push(rect(p, 16.0 * d, k, 0.0, 1.0, -1.0, 0.0));
            items.push(TextItem { text: "Settings".into(), rect: [(p[0] + 16.0 * d) as i32, (p[1] + 8.0 * d) as i32, (p[2] * 0.6) as i32, (28.0 * d) as i32], size: 15.0 * d, bold: true, icon: false, align: Align::Left, channel: 3 });
            let cr = [p[0] + p[2] - 34.0 * d, p[1] + 9.0 * d, 24.0 * d, 24.0 * d];
            self.close_rect = cr;
            rects.push(rect(cr, 12.0 * d, k * 0.9, 0.0, 0.0, -1.0, 0.0));
            items.push(TextItem { text: "\u{E711}".into(), rect: ir(cr), size: 10.0 * d, bold: false, icon: true, align: Align::Center, channel: 3 });
            self.row_rects.clear();
            self.row_val_w.clear();
            for (i, (label, value, toggle)) in rows.iter().enumerate() {
                let r = [p[0] + 8.0 * d, p[1] + 42.0 * d + i as f32 * rh, p[2] - 16.0 * d, rh];
                self.row_rects.push(r);
                if self.hover_row == i as i32 {
                    rects.push(rect(r, 8.0 * d, k, 0.0, 3.0, -1.0, 0.0));
                }
                items.push(TextItem { text: label.to_string(), rect: [(r[0] + 8.0 * d) as i32, r[1] as i32, (r[2] * 0.65) as i32, r[3] as i32], size: 12.5 * d, bold: false, icon: false, align: Align::Left, channel: 3 });
                if *toggle {
                    let on = value == "on";
                    let pill = [r[0] + r[2] - 44.0 * d, r[1] + 5.0 * d, 36.0 * d, r[3] - 10.0 * d];
                    rects.push(rect(pill, pill[3] / 2.0, k * if on { 1.0 } else { 0.7 }, 0.0, if on { 4.0 } else { 0.0 }, -1.0, 0.0));
                    let kd = pill[3] - 4.0 * d;
                    let knob = [if on { pill[0] + pill[2] - kd - 2.0 * d } else { pill[0] + 2.0 * d }, pill[1] + 2.0 * d, kd, kd];
                    rects.push(rect(knob, kd / 2.0, k, 1.0, 0.0, -1.0, 0.0));
                    self.row_val_w.push(pill[2]);
                } else {
                    let vw = text::measure(value, 12.5 * d, false);
                    self.row_val_w.push(vw);
                    let right = r[0] + r[2] - 16.0 * d;
                    items.push(TextItem { text: "\u{E76C}".into(), rect: [right as i32, r[1] as i32, (14.0 * d) as i32, r[3] as i32], size: 9.5 * d, bold: false, icon: true, align: Align::Center, channel: 3 });
                    items.push(TextItem { text: value.clone(), rect: [(right - vw - 2.0 * d) as i32, r[1] as i32, (vw + 4.0 * d) as i32, r[3] as i32], size: 12.5 * d, bold: false, icon: false, align: Align::Right, channel: 3 });
                    items.push(TextItem { text: "\u{E76B}".into(), rect: [(right - vw - 18.0 * d) as i32, r[1] as i32, (14.0 * d) as i32, r[3] as i32], size: 9.5 * d, bold: false, icon: true, align: Align::Center, channel: 3 });
                }
            }
        }
        rects.truncate(MAX_RECTS);
        (rects, items)
    }

    // ---------------- frame ----------------

    fn frame(&mut self) {
        let Some(window) = self.window.clone() else { return };
        let now = Instant::now();
        let dt = now.duration_since(self.last_frame).as_secs_f32().min(0.05);
        self.last_frame = now;
        let t = self.time();
        let size = window.inner_size();
        if size.width < 2 || size.height < 2 {
            return;
        }

        // audio
        self.capture.latest(&mut self.samples);
        let rate = self.capture.rate.load(std::sync::atomic::Ordering::Relaxed);
        self.an.sensitivity = SENS_VAL[self.set.sens];
        self.an.want_notes = self.set.look == MOONLIGHT;
        self.an.update(&self.samples, rate, t, dt);
        self.sig.step(&self.an, dt);
        if self.set.auto {
            self.auto_pick(dt);
        }

        // UI animation
        self.idle += dt;
        let mut target = if self.settings_open || self.inside { 1.0 } else { 0.4 };
        if self.fullscreen && self.idle > 2.5 && !self.settings_open {
            target = 0.0;
            if self.inside && !self.cursor_hidden {
                window.set_cursor_visible(false);
                self.cursor_hidden = true;
            }
        }
        self.ui_alpha += (target - self.ui_alpha) * (dt * 8.0).min(1.0);
        self.panel_t += (if self.settings_open { 1.0 } else { 0.0 } - self.panel_t) * (dt * 12.0).min(1.0);
        for i in 0..GLYPHS.len() {
            let hot = self.hover == i as i32;
            if hot && self.hover_anim[i] < 0.05 {
                self.shine_at[i] = t as f32;
            }
            self.hover_anim[i] += (if hot { 1.0 } else { 0.0 } - self.hover_anim[i]) * (dt * 14.0).min(1.0);
        }
        self.name_timer -= dt;
        self.song_timer -= dt;
        self.hint_timer -= dt;
        if let Some(lm) = self.last_move {
            if lm.elapsed() > Duration::from_millis(250) {
                self.last_move = None;
                self.snap();
            }
        }

        // media: new song, cover art, colours
        let np = self.media.lock().unwrap().clone();
        let mut new_art = None;
        if np.version != self.media_version {
            self.media_version = np.version;
            if np.title != self.title {
                self.title = np.title.clone();
                if !np.title.is_empty() {
                    self.song_timer = 6.0;
                    self.auto.flip += 1;
                    self.auto.since_track = 0.0;
                    self.auto.fresh = true;
                }
            }
            new_art = np.art.clone();
        }
        let target_pal = match (self.set.album, np.palette) {
            (true, Some(p)) => {
                self.album_ok = true;
                p
            }
            _ => {
                self.album_ok = false;
                looks::palette(LOOKS[self.set.look].src)
            }
        };
        let k = (dt * 1.5).min(1.0);
        for i in 0..3 {
            for c in 0..3 {
                self.pal[i][c] += (target_pal[i][c] - self.pal[i][c]) * k;
            }
        }

        // globals
        let qs = QUALITY_SCALE[self.set.quality];
        let scene = (((size.width as f32 * qs) as u32).max(2), ((size.height as f32 * qs) as u32).max(2));
        let mut g = Globals::default();
        if self.set.mouse && self.inside {
            g.mouse = [self.cursor.0 / size.width as f32, self.cursor.1 / size.height as f32];
            g.mouse_on = 1.0;
        }
        g.click_pos = [self.click_pos.0, self.click_pos.1];
        g.click_age = (t - self.click_time) as f32;
        self.sig.fill(&mut g, &self.an, t as f32, dt, scene, (t - self.look_start) as f32, self.set.quality as f32);
        g.pal0 = self.pal[0];
        g.pal1 = self.pal[1];
        g.pal2 = self.pal[2];

        let (w, h) = (size.width as f32, size.height as f32);
        let (rects, items) = self.layout(w, h);
        let mut ui = Ui::default();
        ui.screen = [w, h];
        ui.count = rects.len() as f32;
        ui.beat = self.sig.beat;
        ui.accent = [self.pal[0][0], self.pal[0][1], self.pal[0][2], 1.0];
        ui.fx = [0.9, 0.35, self.sig.beat * 0.55, if self.fullscreen { 1.0 } else { 0.0 }];
        let hide = 1.0 - self.panel_t;
        let name_a = self.name_timer.clamp(0.0, 1.0).max(if self.inside { self.ui_alpha } else { 0.0 }) * hide;
        let song_a = self.song_timer.clamp(0.0, 1.0).max(if self.inside { self.ui_alpha } else { 0.0 }) * hide;
        ui.text_alpha = [self.ui_alpha * hide, name_a, if self.set.song { song_a } else { 0.0 }, self.panel_t.max(self.hint_timer.clamp(0.0, 1.0))];
        for (i, r) in rects.iter().enumerate() {
            ui.rects[i] = *r;
        }

        let Some(gpu) = &mut self.gpu else { return };
        gpu.r.resize((size.width, size.height), scene);
        if items != self.text_items || self.text_size != (size.width, size.height) {
            let mask = text::render(&items, size.width, size.height);
            gpu.r.upload_text(&mask, size.width, size.height);
            self.text_items = items;
            self.text_size = (size.width, size.height);
        }
        if let Some(art) = new_art {
            gpu.r.upload_art(&art);
        }
        self.an.write_texture(&mut self.audio_tex);
        gpu.r.upload_audio(&self.audio_tex);

        let frame = match gpu.surface.get_current_texture() {
            Ok(f) => f,
            Err(_) => {
                gpu.surface.configure(&gpu.r.device, &gpu.config);
                return;
            }
        };
        let view = frame.texture.create_view(&Default::default());
        gpu.r.render(&view, &g, &ui);
        window.pre_present_notify();
        frame.present();
        self.frames += 1;
        if self.frames == 1 || self.frames % 120 == 0 {
            log(&format!("frame {} {}x{} scene {}x{} dt {:.1} ms vol {:.4} private {} MB", self.frames, size.width, size.height, scene.0, scene.1, dt * 1000.0, self.an.vol, private_mb()));
        }
    }

    fn reconfigure(&mut self, size: PhysicalSize<u32>) {
        if let Some(gpu) = &mut self.gpu {
            if size.width > 0 && size.height > 0 {
                gpu.config.width = size.width;
                gpu.config.height = size.height;
                gpu.surface.configure(&gpu.r.device, &gpu.config);
            }
        }
    }

    fn init(&mut self, el: &ActiveEventLoop) {
        let (mut pos, size) = match self.set.bounds {
            Some((x, y, w, h)) => (PhysicalPosition::new(x, y), PhysicalSize::new(w, h)),
            None => self.default_bounds(),
        };
        if self.probe {
            pos = PhysicalPosition::new(-20000, -20000);
        }
        log(&format!("init: pos {pos:?} size {size:?} probe {}", self.probe));
        let attrs = Window::default_attributes()
            .with_active(false)
            .with_title("Music Visualizer")
            .with_decorations(false)
            .with_resizable(true)
            .with_min_inner_size(PhysicalSize::new(200u32, 112u32))
            .with_inner_size(size)
            .with_position(pos)
            .with_visible(false)
            .with_window_level(if self.set.top { WindowLevel::AlwaysOnTop } else { WindowLevel::Normal })
            .with_skip_taskbar(true)
            .with_corner_preference(CornerPreference::Round)
            .with_window_icon(Some(make_icon_winit()));
        let window = Arc::new(el.create_window(attrs).expect("window"));
        self.window = Some(window);
        self.set.look = self.set.look.min(LOOKS.len() - 1);
        if !self.probe {
            self.build_tray();
        }
        if !self.start_hidden || self.probe {
            self.show();
        }
    }

    /// The GPU is created the first time the window is shown, so starting hidden in the tray stays tiny.
    fn create_gpu(&mut self) {
        let Some(window) = self.window.clone() else { return };
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor { backends: wgpu::Backends::DX12, ..Default::default() });
        let surface = instance.create_surface(window.clone()).expect("surface");
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::HighPerformance,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .expect("no GPU");
        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor { memory_hints: wgpu::MemoryHints::MemoryUsage, ..Default::default() })).expect("device");
        let caps = surface.get_capabilities(&adapter);
        let fmt = caps.formats.iter().copied().find(|f| !f.is_srgb()).unwrap_or(caps.formats[0]);
        let inner = window.inner_size();
        let config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format: fmt,
            width: inner.width.max(1),
            height: inner.height.max(1),
            present_mode: wgpu::PresentMode::AutoVsync,
            desired_maximum_frame_latency: 1, // lowest latency: visuals land right on the sound
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
        };
        surface.configure(&device, &config);
        log(&format!("gpu: {} | surface {fmt:?} {}x{} | present modes {:?}", adapter.get_info().name, config.width, config.height, caps.present_modes));
        let r = Renderer::new(device, queue, fmt);
        self.gpu = Some(Gpu { surface, config, r });
        self.text_items.clear(); // new renderer: text and cover must be uploaded again
        self.text_size = (0, 0);
        self.media_version = u32::MAX;
        let look = self.set.look;
        self.set.look = usize::MAX; // force load
        self.set_look(look, false);
    }

    fn build_tray(&mut self) {
        let menu = Menu::new();
        let show = MenuItem::new("Show / hide", true, None);
        let looks_menu = Submenu::new("Looks", true);
        let look_items: Vec<CheckMenuItem> = LOOKS.iter().enumerate().map(|(i, l)| CheckMenuItem::new(looks::name(l.src), true, i == self.set.look, None)).collect();
        for it in &look_items {
            let _ = looks_menu.append(it);
        }
        let auto = CheckMenuItem::new("Auto-pick look for the music", true, self.set.auto, None);
        let mouse = CheckMenuItem::new("Mouse control", true, self.set.mouse, None);
        let settings_item = MenuItem::new("Settingsâ€¦", true, None);
        let full = MenuItem::new("Full screen", true, None);
        let ghost = CheckMenuItem::new("Ghost mode (clicks pass through)", true, false, None);
        let exit = MenuItem::new("Exit", true, None);
        let _ = menu.append_items(&[&show, &looks_menu, &auto, &mouse, &PredefinedMenuItem::separator(), &settings_item, &full, &ghost, &PredefinedMenuItem::separator(), &exit]);
        let tray = TrayIconBuilder::new()
            .with_menu(Box::new(menu.clone()))
            .with_menu_on_left_click(false)
            .with_tooltip("Music Visualizer (click to show/hide)")
            .with_icon(make_icon_tray())
            .build()
            .ok();
        self.tray = tray;
        self.menu = Some(menu);
        self.ids = Some(MenuIds { show, looks: look_items, auto, mouse, settings: settings_item, full, ghost, exit });
    }

    fn poll_tray(&mut self, el: &ActiveEventLoop) {
        while let Ok(ev) = TrayIconEvent::receiver().try_recv() {
            if let TrayIconEvent::Click { button: TrayButton::Left, button_state: MouseButtonState::Up, .. } = ev {
                if self.visible { self.hide() } else { self.show() }
            }
        }
        while let Ok(ev) = MenuEvent::receiver().try_recv() {
            let Some(ids) = &self.ids else { continue };
            let id = ev.id;
            if id == *ids.show.id() {
                if self.visible { self.hide() } else { self.show() }
            } else if id == *ids.auto.id() {
                self.set.auto = ids.auto.is_checked();
                self.set.save();
            } else if id == *ids.mouse.id() {
                self.set.mouse = ids.mouse.is_checked();
                self.set.save();
            } else if id == *ids.settings.id() {
                self.show();
                self.open_settings();
            } else if id == *ids.full.id() {
                self.show();
                if !self.fullscreen {
                    self.toggle_fullscreen();
                }
            } else if id == *ids.ghost.id() {
                let on = ids.ghost.is_checked();
                self.set_ghost(on);
            } else if id == *ids.exit.id() {
                self.tray = None;
                el.exit();
            } else if let Some(i) = ids.looks.iter().position(|l| *l.id() == id) {
                self.show();
                self.set_look(i, true);
            }
        }
    }

    fn edge_dir(&self, x: f32, y: f32, w: f32, h: f32) -> Option<ResizeDirection> {
        if self.fullscreen {
            return None;
        }
        let b = 7.0 * self.scale();
        let (l, r, t, bt) = (x < b, x > w - b, y < b, y > h - b);
        Some(match (l, r, t, bt) {
            (true, _, true, _) => ResizeDirection::NorthWest,
            (_, true, true, _) => ResizeDirection::NorthEast,
            (true, _, _, true) => ResizeDirection::SouthWest,
            (_, true, _, true) => ResizeDirection::SouthEast,
            (true, ..) => ResizeDirection::West,
            (_, true, ..) => ResizeDirection::East,
            (_, _, true, _) => ResizeDirection::North,
            (_, _, _, true) => ResizeDirection::South,
            _ => return None,
        })
    }
}

impl ApplicationHandler for App {
    fn resumed(&mut self, el: &ActiveEventLoop) {
        if self.window.is_none() {
            self.init(el);
        }
    }

    fn window_event(&mut self, el: &ActiveEventLoop, _id: WindowId, event: WindowEvent) {
        let Some(window) = self.window.clone() else { return };
        let size = window.inner_size();
        let (w, h) = (size.width as f32, size.height as f32);
        match event {
            WindowEvent::CloseRequested => self.hide(),
            WindowEvent::Resized(s) => {
                self.reconfigure(s);
                if !self.fullscreen && self.enlarged.is_none() && self.visible {
                    if let Ok(p) = window.outer_position() {
                        self.set.bounds = Some((p.x, p.y, s.width, s.height));
                    }
                }
            }
            WindowEvent::Moved(_) => {
                if !self.fullscreen && self.visible {
                    self.last_move = Some(Instant::now());
                }
            }
            WindowEvent::RedrawRequested => {
                if self.visible {
                    self.frame();
                }
            }
            WindowEvent::CursorMoved { position, .. } => {
                let (x, y) = (position.x as f32, position.y as f32);
                if (x - self.cursor.0).abs() + (y - self.cursor.1).abs() > 2.0 {
                    self.idle = 0.0;
                    if self.cursor_hidden {
                        window.set_cursor_visible(true);
                        self.cursor_hidden = false;
                    }
                }
                self.cursor = (x, y);
                self.inside = true;
                self.hover = self.hit_button(x, y, w);
                self.hover_row = if self.settings_open {
                    self.row_rects.iter().position(|r| x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3]).map(|i| i as i32).unwrap_or(-1)
                } else {
                    -1
                };
                let icon = match self.edge_dir(x, y, w, h) {
                    Some(ResizeDirection::East | ResizeDirection::West) => CursorIcon::EwResize,
                    Some(ResizeDirection::North | ResizeDirection::South) => CursorIcon::NsResize,
                    Some(ResizeDirection::NorthWest | ResizeDirection::SouthEast) => CursorIcon::NwseResize,
                    Some(_) => CursorIcon::NeswResize,
                    None if self.hover >= 0 => CursorIcon::Pointer,
                    None => CursorIcon::Default,
                };
                window.set_cursor(icon);
            }
            WindowEvent::CursorLeft { .. } => {
                self.inside = false;
                self.hover = -1;
                self.hover_row = -1;
            }
            WindowEvent::MouseInput { state, button, .. } => {
                let (x, y) = self.cursor;
                match (button, state) {
                    (MouseButton::Left, ElementState::Pressed) => {
                        if self.settings_open {
                            return;
                        }
                        self.pressed = self.hit_button(x, y, w);
                        if self.pressed >= 0 {
                            return;
                        }
                        let double = self.last_press.elapsed() < Duration::from_millis(350);
                        self.last_press = Instant::now();
                        if double {
                            self.toggle_fullscreen();
                            return;
                        }
                        if let Some(dir) = self.edge_dir(x, y, w, h) {
                            let _ = window.drag_resize_window(dir);
                            self.set.size = -1;
                            return;
                        }
                        // with mouse control on, clicks play with the look; drag the top strip to move
                        let grab_strip = y < 26.0 * self.d();
                        if self.set.mouse && !grab_strip {
                            self.click_pos = (x / w, y / h);
                            self.click_time = self.time();
                        } else if !self.fullscreen {
                            let _ = window.drag_window();
                        }
                    }
                    (MouseButton::Left, ElementState::Released) => {
                        if self.settings_open {
                            let p = self.panel_rect;
                            let c = self.close_rect;
                            let inside = |r: [f32; 4]| x >= r[0] && x <= r[0] + r[2] && y >= r[1] && y <= r[1] + r[3];
                            if inside(c) || !inside(p) {
                                self.close_settings();
                            } else if let Some(i) = self.row_rects.iter().position(|r| inside(*r)) {
                                let r = self.row_rects[i];
                                let dir = if x > r[0] + r[2] - 16.0 * self.d() - self.row_val_w[i] / 2.0 { 1 } else { -1 };
                                self.change_row(i, dir);
                            }
                            return;
                        }
                        let b = self.hit_button(x, y, w);
                        let pressed = self.pressed;
                        self.pressed = -1;
                        if b < 0 || b != pressed {
                            return;
                        }
                        match b as usize {
                            B_PREV => self.set_look((self.set.look + LOOKS.len() - 1) % LOOKS.len(), true),
                            B_NEXT => self.set_look((self.set.look + 1) % LOOKS.len(), true),
                            B_MOUSE => {
                                self.set.mouse = !self.set.mouse;
                                self.hint(if self.set.mouse { "Mouse control on: move and click to play. Drag the top edge to move the window." } else { "Mouse control off" });
                                self.change_row(usize::MAX, 0);
                            }
                            B_SETTINGS => self.open_settings(),
                            B_FULL => self.toggle_fullscreen(),
                            B_HIDE => self.hide(),
                            _ => {}
                        }
                    }
                    (MouseButton::Right, ElementState::Released) => {
                        if let Some(menu) = &self.menu {
                            unsafe {
                                menu.show_context_menu_for_hwnd(self.hwnd(), None);
                            }
                        }
                    }
                    _ => {}
                }
            }
            WindowEvent::MouseWheel { delta, .. } => {
                let dy = match delta {
                    MouseScrollDelta::LineDelta(_, y) => y,
                    MouseScrollDelta::PixelDelta(p) => p.y as f32,
                };
                let dir = if dy < 0.0 { 1 } else { -1 };
                if self.settings_open {
                    if self.hover_row >= 0 && !self.rows()[self.hover_row as usize].2 {
                        self.change_row(self.hover_row as usize, dir);
                    }
                } else {
                    self.set_look((self.set.look as i32 + dir).rem_euclid(LOOKS.len() as i32) as usize, true);
                }
            }
            WindowEvent::KeyboardInput { event, .. } if event.state == ElementState::Pressed => match event.logical_key.as_ref() {
                Key::Named(NamedKey::Escape) => {
                    if self.settings_open {
                        self.close_settings()
                    } else if self.fullscreen {
                        self.toggle_fullscreen()
                    } else {
                        self.hide()
                    }
                }
                Key::Named(NamedKey::F11) => self.toggle_fullscreen(),
                Key::Named(NamedKey::ArrowRight) => self.set_look((self.set.look + 1) % LOOKS.len(), true),
                Key::Named(NamedKey::ArrowLeft) => self.set_look((self.set.look + LOOKS.len() - 1) % LOOKS.len(), true),
                Key::Character(c) => match c.to_ascii_lowercase().as_str() {
                    "f" => self.toggle_fullscreen(),
                    "s" => {
                        if self.settings_open { self.close_settings() } else { self.open_settings() }
                    }
                    "m" => {
                        self.set.mouse = !self.set.mouse;
                        self.change_row(usize::MAX, 0);
                        self.hint(if self.set.mouse { "Mouse control on" } else { "Mouse control off" });
                    }
                    _ => {}
                },
                _ => {}
            },
            _ => {}
        }
        let _ = el;
    }

    fn about_to_wait(&mut self, el: &ActiveEventLoop) {
        if self.probe && self.frames == 180 && self.visible {
            // exercise hide (GPU freed) -> show (GPU rebuilt)
            self.hide();
            std::thread::sleep(Duration::from_millis(500));
            log(&format!("probe: hidden, private {} MB", private_mb()));
            self.show();
            self.frames += 1;
        }
        if self.probe && (self.frames >= 360 || self.time() > 20.0) {
            log(&format!("probe done: {} frames in {:.1} s", self.frames, self.time()));
            el.exit();
            return;
        }
        self.poll_tray(el);
        if !self.visible {
            el.set_control_flow(ControlFlow::WaitUntil(Instant::now() + Duration::from_millis(60)));
            return;
        }
        let fps = FPS[self.set.fps];
        if fps == 0 {
            el.set_control_flow(ControlFlow::Poll);
            if let Some(w) = &self.window {
                w.request_redraw();
            }
        } else {
            let next = self.last_frame + Duration::from_secs_f32(1.0 / fps as f32);
            if Instant::now() >= next {
                if let Some(w) = &self.window {
                    w.request_redraw();
                }
                el.set_control_flow(ControlFlow::Poll);
            } else {
                el.set_control_flow(ControlFlow::WaitUntil(next));
            }
        }
    }
}

fn icon_rgba() -> Vec<u8> {
    let mut px = vec![0u8; 32 * 32 * 4];
    let hs = [12, 22, 30, 18, 26, 14];
    for (i, &bh) in hs.iter().enumerate() {
        let hue = 200.0 + i as f32 * 18.0;
        let (r, g, b) = hsv(hue, 0.7, 1.0);
        for y in 32 - bh..32 {
            for x in 1 + i * 5..5 + i * 5 {
                let o = (y * 32 + x) * 4;
                px[o..o + 4].copy_from_slice(&[r, g, b, 255]);
            }
        }
    }
    px
}

fn hsv(h: f32, s: f32, v: f32) -> (u8, u8, u8) {
    let c = v * s;
    let hp = (h % 360.0) / 60.0;
    let x = c * (1.0 - (hp % 2.0 - 1.0).abs());
    let (r, g, b) = match hp as i32 {
        0 => (c, x, 0.0),
        1 => (x, c, 0.0),
        2 => (0.0, c, x),
        3 => (0.0, x, c),
        4 => (x, 0.0, c),
        _ => (c, 0.0, x),
    };
    let m = v - c;
    (((r + m) * 255.0) as u8, ((g + m) * 255.0) as u8, ((b + m) * 255.0) as u8)
}

fn make_icon_tray() -> tray_icon::Icon {
    tray_icon::Icon::from_rgba(icon_rgba(), 32, 32).expect("icon")
}

fn make_icon_winit() -> winit::window::Icon {
    winit::window::Icon::from_rgba(icon_rgba(), 32, 32).expect("icon")
}


pub fn private_mb() -> u64 {
    use windows::Win32::System::ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS_EX};
    use windows::Win32::System::Threading::GetCurrentProcess;
    unsafe {
        let mut c = PROCESS_MEMORY_COUNTERS_EX::default();
        c.cb = std::mem::size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32;
        let _ = GetProcessMemoryInfo(GetCurrentProcess(), &mut c as *mut _ as *mut _, c.cb);
        (c.PrivateUsage / 1_048_576) as u64
    }
}


