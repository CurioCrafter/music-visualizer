// Port of src/analyzer.rs + src/state.rs. FFTs come from Web Audio AnalyserNodes (getFloatFrequencyData, dB),
// so the maths below starts from dB instead of a raw FFT, but the signals and ranges are the same.
export const BANDS = 96, N = 2048, NN = 8192, HIST = 64;
const freqOf = (b) => 25 * Math.pow(640, b / (BANDS - 1));
const bandAt = (hz) => Math.trunc(Math.max(0, Math.min(BANDS - 1, Math.log(hz / 25) / Math.log(640) * (BANDS - 1))));
const avg = (v, a, b) => { let s = 0; for (let i = a; i <= b; i++) s += v[i]; return s / (b - a + 1); };
// AnalyserNode applies a Blackman window and divides by N, the Rust code a Hann window with *4/N:
// a full-scale sine reads ~0.21 vs 1.0, so add 20*log10(1/0.21) dB to land on the same scale.
const DB_FIX = 13.5;

class Onset {
  constructor() { this.prev = 0; this.mean = 0; this.v = 0; this.last = 0; this.env = 0; }
  update(e, now, refractory, min, decay, dt) {
    const flux = Math.max(e - this.prev, 0);
    this.prev = e;
    const hit = flux > this.mean + 1.6 * Math.sqrt(this.v) + min && now - this.last > refractory;
    this.mean = this.mean * 0.95 + flux * 0.05;
    this.v = this.v * 0.95 + (flux - this.mean) ** 2 * 0.05;
    if (hit) { this.last = now; this.env = 1; } else this.env *= Math.exp(-dt * decay);
    return hit;
  }
}

export class Analyzer {
  constructor() {
    this.rate = 48000; this.sensitivity = 1; this.wantNotes = false;
    this.an = null; this.ak = null;
    this.td = new Float32Array(N); this.fq = new Float32Array(N / 2).fill(-200); this.amp = new Float32Array(N / 2);
    this.fk = new Float32Array(NN / 2);
    this.raw = new Float32Array(BANDS); this.smooth = new Float32Array(BANDS); this.prevRaw = new Float32Array(BANDS);
    this.keys = new Float32Array(88); this.wave = new Float32Array(256);
    this.history = Array.from({ length: HIST }, () => new Float32Array(BANDS)); this.histHead = 0; this.histTimer = 0;
    this.bass = this.mid = this.high = this.vol = this.flux = this.centroid = this.energy = this.beatPhase = 0;
    this.beat = false; this.drop = false; this.bpm = 120;
    this.kickO = new Onset(); this.snareO = new Onset(); this.hatO = new Onset();
    this.peak = 0.5; this.bassAvg = 0; this.bassFast = 0;
    this.lastBeat = -10; this.lastBigBass = -10; this.lastDrop = -100; this.intervals = []; this.phaseOrigin = 0;
    this.volLong = 0; this.volPeak = 0.05;
    this.setup(48000);
  }
  /** Connects the analysers to an audio node (the analysers have no output, they only listen). */
  attach(ctx, src) {
    this.an = ctx.createAnalyser(); this.an.fftSize = N; this.an.smoothingTimeConstant = 0;
    this.ak = ctx.createAnalyser(); this.ak.fftSize = NN; this.ak.smoothingTimeConstant = 0;
    src.connect(this.an); src.connect(this.ak);
    this.setup(ctx.sampleRate);
  }
  setup(sr) {
    this.rate = sr;
    this.binLo = new Float32Array(BANDS); this.binHi = new Float32Array(BANDS); this.tilt = new Float32Array(BANDS);
    for (let b = 0; b < BANDS; b++) {
      this.binLo[b] = freqOf(b - 0.5) * N / sr;
      this.binHi[b] = freqOf(b + 0.5) * N / sr;
      this.tilt[b] = 3 * Math.log2(freqOf(b) / 1000); // +3 dB/oct so highs show
    }
  }
  get kick() { return this.kickO.env; }
  get snare() { return this.snareO.env; }
  get hat() { return this.hatO.env; }

  update(now, dt) {
    if (this.an) { this.an.getFloatTimeDomainData(this.td); this.an.getFloatFrequencyData(this.fq); }
    const s = this.td, H = N / 2;
    let sq = 0;
    for (let i = 0; i < N; i++) sq += s[i] * s[i];
    this.vol = Math.sqrt(sq / N);
    for (let i = 0; i < 256; i++) this.wave[i] = s[N - 512 + i * 2];
    for (let i = 0; i < H; i++) this.amp[i] = Math.pow(10, (Math.max(this.fq[i], -200) + DB_FIX) / 20);
    const mag = (i) => (i < H ? this.amp[i] : 0);

    let max = 0;
    for (let b = 0; b < BANDS; b++) {
      let m;
      if (this.binHi[b] - this.binLo[b] < 1) {
        const c = (this.binLo[b] + this.binHi[b]) / 2, i0 = Math.trunc(c), fr = c - i0;
        m = mag(i0) * (1 - fr) + mag(i0 + 1) * fr;
      } else {
        m = 0;
        for (let i = Math.trunc(this.binLo[b]); i <= Math.trunc(this.binHi[b]); i++) m = Math.max(m, mag(i));
      }
      const db = 20 * Math.log10(m + 1e-9) + this.tilt[b];
      this.raw[b] = Math.min(Math.max((db + 72) / 62, 0), 1);
      max = Math.max(max, this.raw[b]);
    }
    // slow auto-gain so quiet and loud songs both fill the screen
    this.peak = Math.max(max, 0.4, this.peak * Math.pow(0.996, dt * 60));
    const gain = 0.97 / this.peak * this.sensitivity;
    for (let b = 0; b < BANDS; b++) this.raw[b] = Math.pow(Math.min(this.raw[b] * gain, 1), 1.4);

    // smoothed spectrum: fast attack, gentle release
    const fa = 1 - Math.pow(1 - 0.65, dt * 60), fr = 1 - Math.pow(1 - 0.14, dt * 60);
    for (let b = 0; b < BANDS; b++) this.smooth[b] += (this.raw[b] - this.smooth[b]) * (this.raw[b] > this.smooth[b] ? fa : fr);

    this.bass = avg(this.raw, 0, bandAt(150));
    this.mid = avg(this.raw, bandAt(400), bandAt(2500));
    this.high = avg(this.raw, bandAt(4000), BANDS - 1);

    // spectral flux + centroid (brightness)
    let fl = 0, wsum = 0, sum = 0;
    for (let b = 0; b < BANDS; b++) {
      fl += Math.max(this.raw[b] - this.prevRaw[b], 0); wsum += this.raw[b] * b; sum += this.raw[b];
    }
    this.prevRaw.set(this.raw);
    this.flux += (Math.min(fl / 6, 1) - this.flux) * (1 - Math.exp(-dt * 12));
    const c = sum > 0.01 ? wsum / sum / (BANDS - 1) : 0;
    this.centroid += (c - this.centroid) * (1 - Math.exp(-dt * 4));

    // section energy: loudness over ~4 s relative to the loudest recent stretch
    this.volLong += (this.vol - this.volLong) * (1 - Math.exp(-dt / 4));
    this.volPeak = Math.max(this.volLong, this.volPeak * (1 - dt * 0.01), 0.02);
    this.energy = Math.min(Math.max(this.volLong / this.volPeak, 0), 1);

    // drum onsets
    const ke = avg(this.raw, bandAt(40), bandAt(120));
    const se = avg(this.raw, bandAt(1500), bandAt(5000)) * 0.6 + avg(this.raw, bandAt(180), bandAt(320)) * 0.4;
    const he = avg(this.raw, bandAt(7000), BANDS - 1);
    const kickHit = this.kickO.update(ke, now, 0.12, 0.04, 8, dt);
    this.snareO.update(se, now, 0.12, 0.03, 7, dt);
    this.hatO.update(he, now, 0.06, 0.02, 16, dt);

    // beat = kick onset, or a bass jump above its running average
    const bassJump = this.bass > this.bassAvg * 1.3 + 0.04 && this.bass > 0.35;
    this.beat = (kickHit || bassJump) && now - this.lastBeat > 0.2;
    if (this.beat) {
      const iv = now - this.lastBeat;
      if (iv >= 0.25 && iv < 1.5) {
        this.intervals.push(iv);
        if (this.intervals.length > 12) this.intervals.shift();
        const sorted = [...this.intervals].sort((a, b) => a - b);
        let bpm = 60 / sorted[Math.floor(sorted.length / 2)];
        while (bpm < 70) bpm *= 2;
        while (bpm > 180) bpm /= 2;
        this.bpm += (bpm - this.bpm) * 0.3;
      }
      this.lastBeat = now; this.phaseOrigin = now;
    }
    this.beatPhase = ((now - this.phaseOrigin) * this.bpm / 60) % 1;
    this.bassAvg += (this.bass - this.bassAvg) * (1 - Math.pow(0.93, dt * 60));

    // the drop: heavy bass slams back after being gone for a while
    this.bassFast = this.bassFast * 0.6 + this.bass * 0.4;
    this.drop = this.bassFast > 0.55 && now - this.lastBigBass > 1.8 && now - this.lastDrop > 8 && this.vol > 0.01;
    if (this.drop) this.lastDrop = now;
    if (this.bassFast > 0.4) this.lastBigBass = now;

    // history rows at 20 Hz
    this.histTimer += dt;
    if (this.histTimer >= 0.05) {
      this.histTimer = 0;
      this.histHead = (this.histHead + 1) % HIST;
      this.history[this.histHead].set(this.smooth);
    }

    if (this.wantNotes && this.ak) this.notes(dt);
    else for (let k = 0; k < 88; k++) this.keys[k] = Math.max(this.keys[k] - dt * 1.6, 0);
  }

  notes(dt) {
    this.ak.getFloatFrequencyData(this.fk);
    const lvl = new Float32Array(88);
    let max = 1e-9;
    for (let k = 0; k < 88; k++) {
      const i0 = Math.trunc(27.5 * Math.pow(2, k / 12) * NN / this.rate);
      if (i0 + 1 >= NN / 2) continue;
      lvl[k] = Math.pow(10, Math.max(this.fk[i0], this.fk[i0 + 1], -200) / 20);
      max = Math.max(max, lvl[k]);
    }
    for (let k = 0; k < 88; k++) {
      const on = this.vol > 0.002 && lvl[k] > max * 0.2 && (k === 0 || lvl[k] >= lvl[k - 1]) && (k === 87 || lvl[k] >= lvl[k + 1]);
      const target = on ? 0.4 + 0.6 * lvl[k] / max : 0;
      this.keys[k] = target > this.keys[k] ? target : Math.max(this.keys[k] - dt * 1.6, 0);
    }
  }

  /** Fills the 256 x 66 R32Float audio texture described in shaders/common.wgsl. */
  writeTexture(out) {
    out.fill(0);
    out.set(this.smooth, 0);
    out.set(this.keys, 96);
    out.set(this.wave, 256);
    for (let age = 0; age < HIST; age++) out.set(this.history[(this.histHead + HIST - age) % HIST], (2 + age) * 256);
  }
}

/** Envelopes and counters (state.rs Signals). */
export class Signals {
  constructor() { this.beat = 0; this.drop = 0; this.beatCount = 0; this.travel = 0; }
  step(an, dt) {
    if (an.beat) { this.beat = 1; this.beatCount += 1; }
    this.beat = Math.max(this.beat - dt * 3, 0);
    if (an.drop) this.drop = 1;
    this.drop = Math.max(this.drop - dt * 0.7, 0);
    // forward speed: idle drift + loudness + a surge on the drop
    this.travel += dt * (0.4 + 2.5 * an.bass + 1.5 * an.mid + 4 * this.drop);
  }
}
