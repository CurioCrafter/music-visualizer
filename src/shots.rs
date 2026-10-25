//! Off-screen rendering with a built-in synthetic 128 BPM song. Nothing opens on screen.
//!
//!   --shots <dir> [look.wgsl ...]   per look, a 4x2 PNG grid, one tile per song section:
//!                                   intro | verse | build-up | drop  /  breakdown | chorus | outro | drop + mouse & click
//!   --stills <dir>                  one 1280x720 PNG per look, just after the drop
//!   --sections <song.mp3|wav>       run a real song (decoded by ffmpeg) through the analyzer, print the sections it finds
//!   --reel <out.mp4> [seconds]      every look in turn (default 4 s each, around the drop) piped into ffmpeg

use crate::analyzer::{synth, Analyzer, NN, SONG, SONG_BEAT, SONG_BEATS};
use crate::looks;
use crate::render::{self, Globals, Renderer, Ui};
use crate::state::Signals;
use std::io::Write;

const FPS: f32 = 60.0;
const SECTION_NAMES: [&str; 6] = ["Quiet", "Verse", "Build-up", "Chorus", "Breakdown", "Drop"];

fn frame_at_beat(b: f64) -> u32 {
    (b * SONG_BEAT * FPS as f64) as u32
}
/// The frames `--shots` keeps: the middle of each part (late in the build-up, just after the drop), then the drop with the mouse.
fn shot_frames() -> [u32; 8] {
    [10.0, 36.0, 63.6, 66.0, 110.0, 150.0, 172.0, 80.0].map(frame_at_beat)
}

/// Steps one look through the synthetic song frame by frame; `capture(frame)` decides which frames
/// get read back, `sink` receives them.
#[allow(clippy::too_many_arguments)]
fn simulate(r: &mut Renderer, view: &wgpu::TextureView, tex: &wgpu::Texture, src: &str, (w, h): (u32, u32), frames: u32, verbose: bool, capture: impl Fn(u32) -> bool, mut sink: impl FnMut(u32, Vec<u8>)) {
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
        let before = an.section;
        an.update(&ring, 48000, now, 1.0 / FPS);
        if verbose && an.section != before {
            let b = now / SONG_BEAT % SONG_BEATS;
            let part = SONG.iter().find(|p| b >= p.1 && b < p.2).map_or("?", |p| p.0);
            println!("  {now:5.1} s  -> {:<9}  (song is in its {part} at beat {b:.0})", SECTION_NAMES[an.section as usize]);
        }
        if verbose && std::env::var("MV_DEBUG").is_ok() && an.drop {
            println!("    drop event at {now:.2} s, section {} age {:.1}", an.section, an.section_age);
        }
        if verbose && std::env::var("MV_DEBUG").is_ok() && frame % 30 == 0 {
            let d = an.dbg;
            println!("    {now:5.1} b{:5.1} loud {:.2} kick {:.2} snare {:.2} bass {:.2} rise {:+.2} rms {:.3}", now / SONG_BEAT % SONG_BEATS, d[0], d[1], d[2], d[3], d[4], d[5]);
        }
        sig.step(&an, 1.0 / FPS);
        an.write_texture(&mut audio_tex);
        r.upload_audio(&audio_tex);
        let mut g = Globals::default();
        // a lazy simulated mouse during beats 76..84 of the drop, and a click at beat 79
        let b = now / SONG_BEAT % SONG_BEATS;
        if (76.0..84.0).contains(&b) {
            let a = now as f32 * 1.3;
            g.mouse = [0.5 + 0.3 * a.cos(), 0.5 + 0.25 * a.sin()];
            g.mouse_on = 1.0;
            g.click_pos = [0.35, 0.6];
            g.click_age = ((b - 79.0) * SONG_BEAT).max(0.0) as f32;
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
    let (w, h) = (640u32, 360u32);
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
        let shots_at = shot_frames();
        let last = *shots_at.iter().max().unwrap() + 1;
        let mut grid = vec![0u8; (w * 4 * h * 2 * 4) as usize];
        let started = std::time::Instant::now();
        let verbose = std::ptr::eq(path, &files[0].0);
        if verbose {
            println!("sections found in the test song:");
        }
        simulate(&mut r, &view, &tex, src, (w, h), last, verbose, |f| shots_at.contains(&f), |f, px| {
            let slot = shots_at.iter().position(|&s| s == f).unwrap();
            let (cx, cy) = (slot % 4, slot / 4);
            for y in 0..h as usize {
                let o = (((cy * h as usize + y) * w as usize * 4) + cx * w as usize) * 4;
                grid[o..o + w as usize * 4].copy_from_slice(&px[y * w as usize * 4..(y + 1) * w as usize * 4]);
            }
        });
        let ms = started.elapsed().as_secs_f32() * 1000.0 / last as f32;
        let strip = grid;
        let out = out_dir.join(format!("{}.png", stem(path)));
        image::save_buffer(&out, &strip, w * 4, h * 2, image::ColorType::Rgba8).expect("save png");
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
        let target = frame_at_beat(65.0); // ~0.5 s after the drop
        simulate(&mut r, &view, &tex, l.src, (w, h), target + 1, false, |f| f == target, |_, px| {
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
    // each look: the end of the build-up through the drop
    let end = frame_at_beat(66.5);
    let start = end - (secs * FPS) as u32;
    for l in looks::LOOKS {
        r.set_look(l.src).expect("look compiles");
        simulate(&mut r, &view, &tex, l.src, (w, h), end, false, |f| f >= start && (f - start) % 2 == 0, |_, px| {
            pipe.write_all(&px).expect("ffmpeg pipe");
        });
        println!("{} done", looks::name(l.src));
    }
    drop(pipe);
    ff.wait().ok();
    println!("-> {out}");
}

pub fn sections(args: &[String]) {
    let path = &args[0];
    let out = std::process::Command::new("ffmpeg")
        .args(["-loglevel", "error", "-i", path, "-ac", "1", "-ar", "48000", "-f", "f32le", "-"])
        .output()
        .expect("ffmpeg not found");
    let pcm: Vec<f32> = out.stdout.chunks_exact(4).map(|c| f32::from_le_bytes([c[0], c[1], c[2], c[3]])).collect();
    let mut an = Analyzer::new();
    let mut ring = vec![0f32; NN];
    let per_frame = (48000.0 / FPS) as usize;
    let mut now = 0.0f64;
    for chunk in pcm.chunks(per_frame) {
        ring.drain(..chunk.len());
        ring.extend_from_slice(chunk);
        let before = an.section;
        an.update(&ring, 48000, now, 1.0 / FPS);
        if an.section != before {
            println!("{:>2}:{:04.1}  {}", (now / 60.0) as u32, now % 60.0, SECTION_NAMES[an.section as usize]);
        }
        if std::env::var("MV_DEBUG").is_ok() && (now * FPS as f64) as u64 % 120 == 0 {
            let d = an.dbg;
            println!("    {:>2}:{:04.1} loud {:.2} kick {:.2} snare {:.2} bass {:.2} rise {:+.2} rms {:.3} drop {}", (now / 60.0) as u32, now % 60.0, d[0], d[1], d[2], d[3], d[4], d[5], an.drop);
        }
        now += 1.0 / FPS as f64;
    }
    println!("end {:>2}:{:04.1}  ({:.0} BPM)", (now / 60.0) as u32, now % 60.0, an.bpm);
}
