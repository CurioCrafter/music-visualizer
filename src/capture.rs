//! Captures whatever the PC is playing: WASAPI loopback on the default output device.
//! Runs on its own thread; follows the default device when it changes (speakers -> headphones).

use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use windows::core::Interface;
use windows::Win32::Media::Audio::*;
use windows::Win32::System::Com::*;

use crate::analyzer::NN;

pub struct Shared {
    pub ring: Mutex<(Vec<f32>, usize, Instant)>, // samples, write pos, last packet time
    pub rate: AtomicU32,
    pub active: AtomicBool,
}

impl Shared {
    /// Newest NN samples in order (silence if nothing has played for a moment).
    pub fn latest(&self, out: &mut Vec<f32>) {
        out.resize(NN, 0.0);
        let g = self.ring.lock().unwrap();
        if g.2.elapsed() > Duration::from_millis(150) {
            out.fill(0.0);
            return;
        }
        let (ring, pos) = (&g.0, g.1);
        for i in 0..NN {
            out[i] = ring[(pos + i) % NN];
        }
    }
}

pub fn start() -> Arc<Shared> {
    let shared = Arc::new(Shared {
        ring: Mutex::new((vec![0.0; NN], 0, Instant::now() - Duration::from_secs(10))),
        rate: AtomicU32::new(48000),
        active: AtomicBool::new(false),
    });
    let s = shared.clone();
    std::thread::Builder::new()
        .name("loopback".into())
        .spawn(move || unsafe {
            let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
            loop {
                if s.active.load(Ordering::Relaxed) {
                    let _ = capture(&s);
                    std::thread::sleep(Duration::from_millis(500));
                } else {
                    std::thread::sleep(Duration::from_millis(200));
                }
            }
        })
        .unwrap();
    shared
}

unsafe fn device_id(en: &IMMDeviceEnumerator) -> windows::core::Result<String> {
    let dev = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
    let id = dev.GetId()?;
    let s = id.to_string().unwrap_or_default();
    CoTaskMemFree(Some(id.0 as _));
    Ok(s)
}

unsafe fn capture(s: &Shared) -> windows::core::Result<()> {
    let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let dev = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
    let id = device_id(&en)?;
    let client: IAudioClient = dev.Activate(CLSCTX_ALL, None)?;
    let fmt = client.GetMixFormat()?;
    let f = &*fmt;
    let ch = f.nChannels as usize;
    let bits = f.wBitsPerSample;
    let tag = f.wFormatTag as u32;
    let is_float = tag == 3 || (tag == 0xFFFE && {
        let ext = &*(fmt as *const WAVEFORMATEXTENSIBLE);
        let sub = ext.SubFormat;
        sub.data1 == 3
    });
    s.rate.store(f.nSamplesPerSec, Ordering::Relaxed);
    client.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2_000_000, 0, fmt, None)?;
    CoTaskMemFree(Some(fmt as _));
    let cap: IAudioCaptureClient = client.GetService()?;
    client.Start()?;
    let mut next_check = Instant::now() + Duration::from_secs(2);
    let r = if ch > 1 { 1 } else { 0 };
    while s.active.load(Ordering::Relaxed) {
        std::thread::sleep(Duration::from_millis(5));
        loop {
            let packet = cap.GetNextPacketSize()?;
            if packet == 0 {
                break;
            }
            let mut data = std::ptr::null_mut();
            let mut frames = 0u32;
            let mut flags = 0u32;
            cap.GetBuffer(&mut data, &mut frames, &mut flags, None, None)?;
            let silent = flags & (AUDCLNT_BUFFERFLAGS_SILENT.0 as u32) != 0;
            {
                let mut g = s.ring.lock().unwrap();
                g.2 = Instant::now();
                for fi in 0..frames as usize {
                    let v = if silent {
                        0.0
                    } else if is_float {
                        let p = data as *const f32;
                        (*p.add(fi * ch) + *p.add(fi * ch + r)) * 0.5
                    } else if bits == 16 {
                        let p = data as *const i16;
                        (*p.add(fi * ch) as f32 + *p.add(fi * ch + r) as f32) / 65536.0
                    } else {
                        let p = data as *const i32;
                        (*p.add(fi * ch) as f32 + *p.add(fi * ch + r) as f32) / 4294967296.0
                    };
                    let pos = g.1;
                    g.0[pos] = v;
                    g.1 = (pos + 1) % NN;
                }
            }
            cap.ReleaseBuffer(frames)?;
        }
        if Instant::now() > next_check {
            next_check = Instant::now() + Duration::from_secs(2);
            if device_id(&en)? != id {
                break;
            }
        }
    }
    let _ = client.Stop();
    let _ = cap.cast::<windows::core::IUnknown>();
    Ok(())
}
