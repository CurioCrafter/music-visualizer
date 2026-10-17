//! Off-screen rendering with a built-in synthetic 128 BPM song. Nothing opens on screen.
//!
//!   --shots <dir> [look.wgsl ...]   per look, a PNG strip: groove | breakdown | right after the drop (+mouse)
//!   --stills <dir>                  one 1280x720 PNG per look, just after the drop
//!   --reel <out.mp4> [seconds]      every look in turn (default 4 s each, around the drop) piped into ffmpeg

use crate::analyzer::{synth, Analyzer, NN};
use crate::looks;
use crate::render::{self, Globals, Renderer, Ui};
use crate::state::Signals;
use std::io::Write;

const FPS: f32 = 60.0;

/// Steps one look through the synthetic song frame by frame; `capture(frame)` decides which frames
/// get read back, `sink` receives them.
fn simulate(r: &mut Renderer, view: &wgpu::TextureView, tex: &wgpu::Texture, src: &str, (w, h): (u32, u32), frames: u32, capture: impl Fn(u32) -> bool, mut sink: impl FnMut(u32, Vec<u8>)) {
    let mut an = Analyzer::new();
    an.want_notes = true;
    let mut sig = Signals::default();
    let mut ring = vec![0f32; NN];
    let mut rng = 12345u32;
    let mut sample_t = 0u64;
    let mut audio_tex = vec![0f32; (render::AUDIO_W * render::AUDIO_H) as usize];
    let pal = looks::palette(src);
    let per_frame = (48000.0 / FPS) as usize;
    for frame in 0..frames {
        ring.drain(..per_frame);
        for _ in 0..per_frame {
            ring.push(synth(sample_t as f64 / 48000.0, &mut rng));
            sample_t += 1;
        }
        let now = frame as f64 / FPS as f64;
        an.update(&ring, 48000, now, 1.0 / FPS);
        sig.step(&an, 1.0 / FPS);
        an.write_texture(&mut audio_tex);
        r.upload_audio(&audio_tex);
        let mut g = Globals::default();
        // a lazy simulated mouse after 6.7 s, and a click at 7.4 s
        if now > 6.7 {
            let a = now as f32 * 1.3;
            g.mouse = [0.5 + 0.3 * a.cos(), 0.5 + 0.25 * a.sin()];
            g.mouse_on = 1.0;
            g.click_pos = [0.35, 0.6];
            g.click_age = (now as f32 - 7.4).max(0.0);
        }
        sig.fill(&mut g, &an, now as f32, 1.0 / FPS, (w, h), now as f32, 2.0);
        g.pal0 = pal[0];
        g.pal1 = pal[1];
        g.pal2 = pal[2];
        let mut ui = Ui::default();
        ui.screen = [w as f32, h as f32];
        ui.fx = [0.9, 0.35, 0.0, 0.0];
        r.render(view, &g, &ui);
        if capture(frame) {
            sink(frame, render::read_rgba(&r.device, &r.queue, tex, w, h));
        }
    }
}

fn setup(w: u32, h: u32) -> (Renderer, wgpu::Texture, wgpu::TextureView) {
    let (device, queue) = render::headless();
    let (tex, view) = render::offscreen(&device, w, h);
    let mut r = Renderer::new(device, queue, wgpu::TextureFormat::Rgba8Unorm);
    r.resize((w, h), (w, h));
    (r, tex, view)
}

fn stem(file: &str) -> String {
    std::path::Path::new(file).file_stem().unwrap().to_string_lossy().to_string()
}

pub fn run(args: &[String]) {
    let out_dir = std::path::PathBuf::from(&args[0]);
    std::fs::create_dir_all(&out_dir).ok();
    let (w, h) = (960u32, 540u32);
    let files: Vec<(String, String)> = if args.len() > 1 {
        args[1..].iter().map(|p| (p.clone(), std::fs::read_to_string(p).unwrap_or_else(|e| panic!("{p}: {e}")))).collect()
    } else {
        looks::LOOKS.iter().map(|l| (l.file.to_string(), l.src.to_string())).collect()
    };
    let (mut r, tex, view) = setup(w, h);
    let mut failed = 0;
    for (path, src) in &files {
        if let Err(e) = r.set_look(src) {
            eprintln!("SHADER ERROR in {path}:\n{e}");
            failed += 1;
            continue;
        }
        let shots_at = [120u32, 390, 480];
        let mut strip = vec![0u8; (w * 3 * h * 4) as usize];
        let started = std::time::Instant::now();
        simulate(&mut r, &view, &tex, src, (w, h), 481, |f| shots_at.contains(&f), |f, px| {
            let slot = shots_at.iter().position(|&s| s == f).unwrap();
            for y in 0..h as usize {
                let o = (y * w as usize * 3 + slot * w as usize) * 4;
                strip[o..o + w as usize * 4].copy_from_slice(&px[y * w as usize * 4..(y + 1) * w as usize * 4]);
            }
        });
        let ms = started.elapsed().as_secs_f32() * 1000.0 / 481.0;
        let out = out_dir.join(format!("{}.png", stem(path)));
        image::save_buffer(&out, &strip, w * 3, h, image::ColorType::Rgba8).expect("save png");
        println!("{}: ok  ({ms:.2} ms/frame incl. readback)  -> {}", stem(path), out.display());
    }
    if failed > 0 {
        std::process::exit(1);
    }
}

pub fn stills(args: &[String]) {
    let out_dir = std::path::PathBuf::from(&args[0]);
    std::fs::create_dir_all(&out_dir).ok();
    let (w, h) = (1280u32, 720u32);
    let (mut r, tex, view) = setup(w, h);
    for l in looks::LOOKS {
        r.set_look(l.src).expect("look compiles");
        let target = 486u32; // ~0.4 s after the drop
        simulate(&mut r, &view, &tex, l.src, (w, h), target + 1, |f| f == target, |_, px| {
            let out = out_dir.join(format!("{}.png", stem(l.file)));
            image::save_buffer(&out, &px, w, h, image::ColorType::Rgba8).expect("save png");
            println!("{}", out.display());
        });
    }
}

pub fn reel(args: &[String]) {
    let out = &args[0];
    let secs: f32 = args.get(1).and_then(|s| s.parse().ok()).unwrap_or(4.0);
    let (w, h) = (1280u32, 720u32);
    let (mut r, tex, view) = setup(w, h);
    let mut ff = std::process::Command::new("ffmpeg")
        .args(["-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgba", "-s", &format!("{w}x{h}"), "-r", "30", "-i", "-"])
        .args(["-c:v", "libx264", "-preset", "slow", "-crf", "21", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out])
        .stdin(std::process::Stdio::piped())
        .spawn()
        .expect("ffmpeg not found");
    let mut pipe = ff.stdin.take().unwrap();
    // each look: from just before the breakdown ends through the drop (synthetic song drops at ~7.5 s)
    let end = (8.6 * FPS) as u32;
    let start = end - (secs * FPS) as u32;
    for l in looks::LOOKS {
        r.set_look(l.src).expect("look compiles");
        simulate(&mut r, &view, &tex, l.src, (w, h), end, |f| f >= start && (f - start) % 2 == 0, |_, px| {
            pipe.write_all(&px).expect("ffmpeg pipe");
        });
        println!("{} done", looks::name(l.src));
    }
    drop(pipe);
    ff.wait().ok();
    println!("-> {out}");
}
