//! What's playing (Spotify, YouTube in a browser, ...) via Windows media controls, plus the album
//! cover (96x96 RGBA) and three glowing colours taken from it. Polls on its own thread.

use std::sync::{Arc, Mutex};
use std::time::Duration;
use windows::Media::Control::GlobalSystemMediaTransportControlsSessionManager as Manager;
use windows::Storage::Streams::DataReader;

#[derive(Clone, Default)]
pub struct NowPlaying {
    pub title: String,
    pub artist: String,
    pub art: Option<Vec<u8>>,           // 96x96 RGBA
    pub palette: Option<[[f32; 4]; 3]>, // None for grey covers
    pub version: u32,
}

pub fn start() -> Arc<Mutex<NowPlaying>> {
    let shared = Arc::new(Mutex::new(NowPlaying::default()));
    let s = shared.clone();
    std::thread::Builder::new()
        .name("media".into())
        .spawn(move || {
            unsafe { let _ = windows::Win32::System::Com::CoInitializeEx(None, windows::Win32::System::Com::COINIT_MULTITHREADED); }
            let mut art_tries = 0;
            loop {
                let _ = poll(&s, &mut art_tries);
                std::thread::sleep(Duration::from_millis(1500));
            }
        })
        .unwrap();
    shared
}

fn poll(s: &Mutex<NowPlaying>, art_tries: &mut u32) -> windows::core::Result<()> {
    let mgr = Manager::RequestAsync()?.get()?;
    let Ok(ses) = mgr.GetCurrentSession() else {
        let mut g = s.lock().unwrap();
        if !g.title.is_empty() {
            *g = NowPlaying { version: g.version + 1, ..Default::default() };
        }
        return Ok(());
    };
    let p = ses.TryGetMediaPropertiesAsync()?.get()?;
    let title = p.Title()?.to_string();
    let artist = p.Artist()?.to_string();
    let (changed, need_art) = {
        let g = s.lock().unwrap();
        (g.title != title || g.artist != artist, g.art.is_none())
    };
    if changed {
        *art_tries = 0;
        let mut g = s.lock().unwrap();
        *g = NowPlaying { title, artist, version: g.version + 1, ..Default::default() };
    }
    // players often publish the cover a moment after the title
    if (changed || need_art) && *art_tries < 5 {
        *art_tries += 1;
        if let Ok(thumb) = p.Thumbnail() {
            let stream = thumb.OpenReadAsync()?.get()?;
            let size = stream.Size()? as u32;
            let reader = DataReader::CreateDataReader(&stream)?;
            reader.LoadAsync(size)?.get()?;
            let mut bytes = vec![0u8; size as usize];
            reader.ReadBytes(&mut bytes)?;
            if let Ok(img) = image::load_from_memory(&bytes) {
                let small = img.resize_exact(96, 96, image::imageops::FilterType::Triangle).to_rgba8().into_raw();
                let pal = extract_palette(&small);
                let mut g = s.lock().unwrap();
                g.art = Some(small);
                g.palette = pal;
                g.version += 1;
            }
        }
    }
    Ok(())
}

fn hsv_to_rgb(h: f32, s: f32, v: f32) -> [f32; 4] {
    let h = (h.rem_euclid(360.0)) / 60.0;
    let i = h.floor() as i32;
    let f = h - i as f32;
    let (p, q, t) = (v * (1.0 - s), v * (1.0 - s * f), v * (1.0 - s * (1.0 - f)));
    let (r, g, b) = match i {
        0 => (v, t, p),
        1 => (q, v, p),
        2 => (p, v, t),
        3 => (p, q, v),
        4 => (t, p, v),
        _ => (v, p, q),
    };
    [r, g, b, 1.0]
}

/// The 3 strongest, clearly different hues of the cover, pushed bright. Grey covers -> None.
fn extract_palette(rgba: &[u8]) -> Option<[[f32; 4]; 3]> {
    let mut w = [0f32; 24];
    let mut hx = [0f32; 24];
    let mut hy = [0f32; 24];
    let mut n = 0;
    for px in rgba.chunks(4).step_by(3) {
        let (r, g, b) = (px[0] as f32 / 255.0, px[1] as f32 / 255.0, px[2] as f32 / 255.0);
        let mx = r.max(g).max(b);
        let mn = r.min(g).min(b);
        let sat = if mx > 0.0 { (mx - mn) / mx } else { 0.0 };
        let d = mx - mn;
        let hue = if d < 1e-5 {
            0.0
        } else if mx == r {
            60.0 * ((g - b) / d).rem_euclid(6.0)
        } else if mx == g {
            60.0 * ((b - r) / d + 2.0)
        } else {
            60.0 * ((r - g) / d + 4.0)
        };
        let wt = sat * sat * mx;
        let bin = ((hue / 15.0) as usize) % 24;
        w[bin] += wt;
        hx[bin] += hue.to_radians().cos() * wt;
        hy[bin] += hue.to_radians().sin() * wt;
        n += 1;
    }
    if w.iter().sum::<f32>() / n as f32 > 0.03 {
        let mut picks: Vec<usize> = Vec::new();
        while picks.len() < 3 {
            let best = (0..24)
                .filter(|&i| w[i] > 0.0 && picks.iter().all(|&p: &usize| (p as i32 - i as i32).abs().min(24 - (p as i32 - i as i32).abs()) >= 3))
                .max_by(|&a, &b| w[a].partial_cmp(&w[b]).unwrap());
            match best {
                Some(b) if picks.is_empty() || w[b] > w[picks[0]] * 0.08 => picks.push(b),
                _ => break,
            }
        }
        let mut hues: Vec<f32> = picks.iter().map(|&i| hy[i].atan2(hx[i]).to_degrees()).collect();
        while hues.len() < 3 {
            let h = hues[0] + 40.0 * hues.len() as f32;
            hues.push(h);
        }
        return Some([hsv_to_rgb(hues[0], 0.75, 1.0), hsv_to_rgb(hues[1], 0.75, 1.0), hsv_to_rgb(hues[2], 0.75, 1.0)]);
    }
    None
}

