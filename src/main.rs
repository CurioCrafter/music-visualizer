#![windows_subsystem = "windows"]
//! Music Visualizer 2: a GPU (wgpu / DirectX 12) music visualizer that lives in the Windows tray.

mod analyzer;
mod app;
mod capture;
mod looks;
mod media;
mod render;
mod settings;
mod shots;
mod state;
mod text;

use windows::core::PCWSTR;
use windows::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS};
use windows::Win32::System::Threading::{CreateMutexW, GetCurrentProcess, SetPriorityClass, BELOW_NORMAL_PRIORITY_CLASS};

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match args.first().map(|s| s.as_str()) {
        Some("--shots") => return { attach_console(); shots::run(&args[1..]) },
        Some("--stills") => return { attach_console(); shots::stills(&args[1..]) },
        Some("--reel") => return { attach_console(); shots::reel(&args[1..]) },
        _ => {}
    }
    unsafe {
        // one copy only
        let name: Vec<u16> = "MusicVisualizer2.Single\0".encode_utf16().collect();
        let _m = CreateMutexW(None, true, PCWSTR(name.as_ptr()));
        if GetLastError() == ERROR_ALREADY_EXISTS && !args.iter().any(|a| a == "--probe") {
            return;
        }
        // games and other apps come first; the visualizer takes what is left
        let _ = SetPriorityClass(GetCurrentProcess(), BELOW_NORMAL_PRIORITY_CLASS);
        std::mem::forget(_m);
    }
    let event_loop = winit::event_loop::EventLoop::new().expect("event loop");
    let probe = args.iter().any(|a| a == "--probe");
    let mut app = app::App::new(args.iter().any(|a| a == "--hidden"), probe);
    let _ = event_loop.run_app(&mut app);
}

/// The exe is a GUI app; when run from a terminal for --shots, print to that terminal.
fn attach_console() {
    unsafe {
        let _ = windows::Win32::System::Console::AttachConsole(windows::Win32::System::Console::ATTACH_PARENT_PROCESS);
    }
}
