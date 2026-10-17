//! Turns raw samples into everything the looks react to: 96 log bands, beats, kick/snare/hat
//! onsets, tempo + beat phase, the drop, brightness, section energy, piano keys and history.

use rustfft::{num_complex::Complex, Fft, FftPlanner};
use std::sync::Arc;

pub const BANDS: usize = 96;
pub const N: usize = 2048; // main FFT (~43 ms at 48 kHz)
pub const NN: usize = 8192; // note FFT, fine enough to tell piano keys apart
pub const HIST: usize = 64;

fn freq_of(b: f32) -> f32 {
    25.0 * 640f32.powf(b / (BANDS as f32 - 1.0))
}
fn band_at(hz: f32) -> usize {
    ((hz / 25.0).ln() / 640f32.ln() * (BANDS as f32 - 1.0)).clamp(0.0, BANDS as f32 - 1.0) as usize
}

/// Onset detector for one frequency region: positive change vs. an adaptive threshold.
#[derive(Default)]
struct Onset {
    prev: f32,
    mean: f32,
    var: f32,
    last: f64,
    pub env: f32,
}
impl Onset {
    fn update(&mut self, e: f32, now: f64, refractory: f64, min: f32, decay: f32, dt: f32) -> bool {
        let flux = (e - self.prev).max(0.0);
        self.prev = e;
        let hit = flux > self.mean + 1.6 * self.var.sqrt() + min && now - self.last > refractory;
        self.mean = self.mean * 0.95 + flux * 0.05;
        self.var = self.var * 0.95 + (flux - self.mean).powi(2) * 0.05;
        if hit {
            self.last = now;
            self.env = 1.0;
        } else {
            self.env *= (-dt * decay).exp();
        }
        hit
    }
}

pub struct Analyzer {
    fft: Arc<dyn Fft<f32>>,
    fft_big: Arc<dyn Fft<f32>>,
    win: Vec<f32>,
    nwin: Vec<f32>,
    buf: Vec<Complex<f32>>,
    nbuf: Vec<Complex<f32>>,
    bin_lo: [f32; BANDS],
    bin_hi: [f32; BANDS],
    tilt: [f32; BANDS],
    rate: u32,
    pub sensitivity: f32,
    pub want_notes: bool,

    pub raw: [f32; BANDS],
    pub smooth: [f32; BANDS],
    pub keys: [f32; 88],
    pub wave: [f32; 256],
    pub history: Vec<[f32; BANDS]>,
    pub hist_head: usize,
    hist_timer: f32,

    pub bass: f32,
    pub mid: f32,
    pub high: f32,
    pub vol: f32,
    pub beat: bool,
    pub drop: bool,
    pub flux: f32,
    pub centroid: f32,
    pub energy: f32,
    pub bpm: f32,
    pub beat_phase: f32,
    kick: Onset,
    snare: Onset,
    hat: Onset,

    peak: f32,
    bass_avg: f32,
    bass_fast: f32,
    last_beat: f64,
    last_big_bass: f64,
    last_drop: f64,
    intervals: Vec<f32>,
    phase_origin: f64,
    prev_raw: [f32; BANDS],
    vol_long: f32,
    vol_peak: f32,
}

impl Analyzer {
    pub fn new() -> Self {
        let mut planner = FftPlanner::new();
        let hann = |n: usize| (0..n).map(|i| 0.5 * (1.0 - (2.0 * std::f32::consts::PI * i as f32 / (n - 1) as f32).cos())).collect::<Vec<_>>();
        let mut a = Analyzer {
            fft: planner.plan_fft_forward(N),
            fft_big: planner.plan_fft_forward(NN),
            win: hann(N),
            nwin: hann(NN),
            buf: vec![Complex::default(); N],
            nbuf: vec![Complex::default(); NN],
            bin_lo: [0.0; BANDS],
            bin_hi: [0.0; BANDS],
            tilt: [0.0; BANDS],
            rate: 0,
            sensitivity: 1.0,
            want_notes: false,
            raw: [0.0; BANDS],
            smooth: [0.0; BANDS],
            keys: [0.0; 88],
            wave: [0.0; 256],
            history: vec![[0.0; BANDS]; HIST],
            hist_head: 0,
            hist_timer: 0.0,
            bass: 0.0,
            mid: 0.0,
            high: 0.0,
            vol: 0.0,
            beat: false,
            drop: false,
            flux: 0.0,
            centroid: 0.0,
            energy: 0.0,
            bpm: 120.0,
            beat_phase: 0.0,
            kick: Onset::default(),
            snare: Onset::default(),
            hat: Onset::default(),
            peak: 0.5,
            bass_avg: 0.0,
            bass_fast: 0.0,
            last_beat: -10.0,
            last_big_bass: -10.0,
            last_drop: -100.0,
            intervals: Vec::new(),
            phase_origin: 0.0,
            prev_raw: [0.0; BANDS],
            vol_long: 0.0,
            vol_peak: 0.05,
        };
        a.setup(48000);
        a
    }

    fn setup(&mut self, sr: u32) {
        self.rate = sr;
        for b in 0..BANDS {
            self.bin_lo[b] = freq_of(b as f32 - 0.5) * N as f32 / sr as f32;
            self.bin_hi[b] = freq_of(b as f32 + 0.5) * N as f32 / sr as f32;
            self.tilt[b] = 3.0 * (freq_of(b as f32) / 1000.0).log2(); // +3 dB/oct so highs show
        }
    }

    pub fn kick(&self) -> f32 { self.kick.env }
    pub fn snare(&self) -> f32 { self.snare.env }
    pub fn hat(&self) -> f32 { self.hat.env }

    fn avg(v: &[f32], a: usize, b: usize) -> f32 {
        v[a..=b].iter().sum::<f32>() / (b - a + 1) as f32
    }

    /// `samples` = newest NN samples (mono). `now` = seconds, `dt` = seconds since last call.
    pub fn update(&mut self, samples: &[f32], rate: u32, now: f64, dt: f32) {
        if rate != self.rate && rate > 0 {
            self.setup(rate);
        }
        let s = &samples[samples.len() - N..];
        let mut sq = 0.0f64;
        for i in 0..N {
            self.buf[i] = Complex::new(s[i] * self.win[i], 0.0);
            sq += (s[i] * s[i]) as f64;
        }
        self.vol = (sq / N as f64).sqrt() as f32;
        for i in 0..256 {
            self.wave[i] = s[N - 512 + i * 2];
        }
        self.fft.process(&mut self.buf);
        let mag = |buf: &Vec<Complex<f32>>, i: usize| if i < N / 2 { buf[i].norm() } else { 0.0 };

        let mut max = 0.0f32;
        for b in 0..BANDS {
            let m = if self.bin_hi[b] - self.bin_lo[b] < 1.0 {
                let c = (self.bin_lo[b] + self.bin_hi[b]) / 2.0;
                let i0 = c as usize;
                let fr = c - i0 as f32;
                mag(&self.buf, i0) * (1.0 - fr) + mag(&self.buf, i0 + 1) * fr
            } else {
                let mut m = 0.0f32;
                for i in self.bin_lo[b] as usize..=self.bin_hi[b] as usize {
                    m = m.max(mag(&self.buf, i));
                }
                m
            };
            let db = 20.0 * (m * 4.0 / N as f32 + 1e-9).log10() + self.tilt[b];
            self.raw[b] = ((db + 72.0) / 62.0).clamp(0.0, 1.0);
            max = max.max(self.raw[b]);
        }
        // slow auto-gain so quiet and loud songs both fill the screen
        self.peak = max.max(0.4).max(self.peak * 0.996f32.powf(dt * 60.0));
        let gain = 0.97 / self.peak * self.sensitivity;
        for b in 0..BANDS {
            self.raw[b] = (self.raw[b] * gain).min(1.0).powf(1.4);
        }

        // smoothed spectrum: fast attack, gentle release
        let fa = 1.0 - (1.0f32 - 0.65).powf(dt * 60.0);
        let fr = 1.0 - (1.0f32 - 0.14).powf(dt * 60.0);
        for b in 0..BANDS {
            let v = self.raw[b];
            let k = if v > self.smooth[b] { fa } else { fr };
            self.smooth[b] += (v - self.smooth[b]) * k;
        }

        self.bass = Self::avg(&self.raw, 0, band_at(150.0));
        self.mid = Self::avg(&self.raw, band_at(400.0), band_at(2500.0));
        self.high = Self::avg(&self.raw, band_at(4000.0), BANDS - 1);

        // spectral flux + centroid (brightness)
        let mut fl = 0.0;
        let (mut wsum, mut sum) = (0.0, 0.0);
        for b in 0..BANDS {
            fl += (self.raw[b] - self.prev_raw[b]).max(0.0);
            wsum += self.raw[b] * b as f32;
            sum += self.raw[b];
        }
        self.prev_raw = self.raw;
        self.flux += ((fl / 6.0).min(1.0) - self.flux) * (1.0 - (-dt * 12.0).exp());
        let c = if sum > 0.01 { wsum / sum / (BANDS as f32 - 1.0) } else { 0.0 };
        self.centroid += (c - self.centroid) * (1.0 - (-dt * 4.0).exp());

        // section energy: loudness over ~4 s relative to the loudest recent stretch
        self.vol_long += (self.vol - self.vol_long) * (1.0 - (-dt / 4.0).exp());
        self.vol_peak = self.vol_long.max(self.vol_peak * (1.0 - dt * 0.01)).max(0.02);
        self.energy = (self.vol_long / self.vol_peak).clamp(0.0, 1.0);

        // drum onsets
        let ke = Self::avg(&self.raw, band_at(40.0), band_at(120.0));
        let se = Self::avg(&self.raw, band_at(1500.0), band_at(5000.0)) * 0.6 + Self::avg(&self.raw, band_at(180.0), band_at(320.0)) * 0.4;
        let he = Self::avg(&self.raw, band_at(7000.0), BANDS - 1);
        let kick_hit = self.kick.update(ke, now, 0.12, 0.04, 8.0, dt);
        self.snare.update(se, now, 0.12, 0.03, 7.0, dt);
        self.hat.update(he, now, 0.06, 0.02, 16.0, dt);

        // beat = kick onset, or a bass jump above its running average
        let bass_jump = self.bass > self.bass_avg * 1.3 + 0.04 && self.bass > 0.35;
        self.beat = (kick_hit || bass_jump) && now - self.last_beat > 0.2;
        if self.beat {
            let iv = (now - self.last_beat) as f32;
            if (0.25..1.5).contains(&iv) {
                self.intervals.push(iv);
                if self.intervals.len() > 12 {
                    self.intervals.remove(0);
                }
                let mut sorted = self.intervals.clone();
                sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
                let mut bpm = 60.0 / sorted[sorted.len() / 2];
                while bpm < 70.0 { bpm *= 2.0; }
                while bpm > 180.0 { bpm /= 2.0; }
                self.bpm += (bpm - self.bpm) * 0.3;
            }
            self.last_beat = now;
            self.phase_origin = now;
        }
        self.beat_phase = (((now - self.phase_origin) * self.bpm as f64 / 60.0) % 1.0) as f32;
        self.bass_avg += (self.bass - self.bass_avg) * (1.0 - 0.93f32.powf(dt * 60.0));

        // the drop: heavy bass slams back after being gone for a while
        self.bass_fast = self.bass_fast * 0.6 + self.bass * 0.4;
        self.drop = self.bass_fast > 0.5 && now - self.last_big_bass > 1.5 && now - self.last_drop > 8.0 && self.vol > 0.01;
        if self.drop {
            self.last_drop = now;
        }
        if self.bass_fast > 0.4 {
            self.last_big_bass = now;
        }

        // history rows at 20 Hz
        self.hist_timer += dt;
        if self.hist_timer >= 0.05 {
            self.hist_timer = 0.0;
            self.hist_head = (self.hist_head + 1) % HIST;
            self.history[self.hist_head] = self.smooth;
        }

        if self.want_notes {
            self.notes(samples, dt);
        } else {
            for k in self.keys.iter_mut() {
                *k = (*k - dt * 1.6).max(0.0);
            }
        }
    }

    fn notes(&mut self, samples: &[f32], dt: f32) {
        let s = &samples[samples.len() - NN..];
        for i in 0..NN {
            self.nbuf[i] = Complex::new(s[i] * self.nwin[i], 0.0);
        }
        self.fft_big.process(&mut self.nbuf);
        let mut lvl = [0.0f32; 88];
        let mut max = 1e-9f32;
        for k in 0..88 {
            let c = 27.5 * 2f32.powf(k as f32 / 12.0) * NN as f32 / self.rate as f32;
            let i0 = c as usize;
            if i0 + 1 >= NN / 2 {
                continue;
            }
            lvl[k] = self.nbuf[i0].norm().max(self.nbuf[i0 + 1].norm());
            max = max.max(lvl[k]);
        }
        for k in 0..88 {
            let on = self.vol > 0.002 && lvl[k] > max * 0.2 && (k == 0 || lvl[k] >= lvl[k - 1]) && (k == 87 || lvl[k] >= lvl[k + 1]);
            let target = if on { 0.4 + 0.6 * lvl[k] / max } else { 0.0 };
            self.keys[k] = if target > self.keys[k] { target } else { (self.keys[k] - dt * 1.6).max(0.0) };
        }
    }

    /// Fills the 256 x 66 R32Float audio texture described in shaders/common.wgsl.
    pub fn write_texture(&self, out: &mut [f32]) {
        out.fill(0.0);
        out[..BANDS].copy_from_slice(&self.smooth);
        out[96..96 + 88].copy_from_slice(&self.keys);
        out[256..512].copy_from_slice(&self.wave);
        for age in 0..HIST {
            let row = &self.history[(self.hist_head + HIST - age) % HIST];
            let o = (2 + age) * 256;
            out[o..o + BANDS].copy_from_slice(row);
        }
    }
}

/// Synthetic 128 BPM test song: kick, wobbling sub, chords, piano notes, hats; a breakdown every
/// 16 beats so the drop fires. Used by `--shots`.
pub fn synth(time: f64, rng: &mut u32) -> f32 {
    use std::f64::consts::PI;
    let beat = 60.0 / 128.0;
    let tb = time % beat;
    let section = (time / beat) as u64 % 16;
    let breakdown = section >= 12; // last 4 beats of every 16: no drums, no sub
    let kick_f = 45.0 + 90.0 * (-tb * 30.0).exp();
    let kick = if breakdown { 0.0 } else { (2.0 * PI * kick_f * tb).sin() * (-tb * 9.0).exp() * 0.8 };
    let duck = 1.0 - (-tb * 8.0).exp();
    let sub = if breakdown { 0.0 } else { (2.0 * PI * 55.0 * time + (2.0 * PI * 4.0 * time).sin() * 2.0).sin() * 0.3 * duck };
    let chord = ((2.0 * PI * 220.0 * time).sin() + (2.0 * PI * 277.2 * time).sin() + (2.0 * PI * 329.6 * time).sin()) * 0.05;
    const SCALE: [f64; 7] = [440.0, 494.0, 554.0, 659.0, 740.0, 880.0, 988.0];
    let note = SCALE[((time / (beat / 2.0)) as usize * 7) % 7];
    let tn = time % (beat / 2.0);
    let piano = ((2.0 * PI * note * time).sin() + 0.4 * (4.0 * PI * note * time).sin()) * (-tn * 5.0).exp() * 0.2;
    *rng = rng.wrapping_mul(1664525).wrapping_add(1013904223);
    let noise = (*rng >> 8) as f64 / (1u32 << 24) as f64 * 2.0 - 1.0;
    let th = time % (beat / 2.0);
    let hat = noise * (-th * 70.0).exp() * 0.12;
    let snare = if breakdown || ((time / beat) as u64 % 2 == 0) { 0.0 } else { noise * (-tb * 18.0).exp() * 0.35 };
    (kick + sub + chord + piano + hat + snare) as f32
}
