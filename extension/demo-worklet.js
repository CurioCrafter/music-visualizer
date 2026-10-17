// Built-in demo song (port of analyzer::synth in the Windows app): 128 BPM kick, wobbling sub, chords,
// piano notes, hats, snare; the last 4 beats of every 16 are a breakdown so the drop fires.
const SCALE = [440, 494, 554, 659, 740, 880, 988];
const BEAT = 60 / 128;
class Demo extends AudioWorkletProcessor {
  constructor() { super(); this.rng = 1; }
  sample(time) {
    const TAU = 2 * Math.PI;
    const tb = time % BEAT;
    const breakdown = Math.floor(time / BEAT) % 16 >= 12;
    const kickF = 45 + 90 * Math.exp(-tb * 30);
    const kick = breakdown ? 0 : Math.sin(TAU * kickF * tb) * Math.exp(-tb * 9) * 0.8;
    const duck = 1 - Math.exp(-tb * 8);
    const sub = breakdown ? 0 : Math.sin(TAU * 55 * time + Math.sin(TAU * 4 * time) * 2) * 0.3 * duck;
    const chord = (Math.sin(TAU * 220 * time) + Math.sin(TAU * 277.2 * time) + Math.sin(TAU * 329.6 * time)) * 0.05;
    const note = SCALE[(Math.floor(time / (BEAT / 2)) * 7) % 7];
    const tn = time % (BEAT / 2);
    const piano = (Math.sin(TAU * note * time) + 0.4 * Math.sin(2 * TAU * note * time)) * Math.exp(-tn * 5) * 0.2;
    this.rng = (Math.imul(this.rng, 1664525) + 1013904223) >>> 0;
    const noise = (this.rng >>> 8) / 16777216 * 2 - 1;
    const hat = noise * Math.exp(-tn * 70) * 0.12;
    const snare = breakdown || Math.floor(time / BEAT) % 2 === 0 ? 0 : noise * Math.exp(-tb * 18) * 0.35;
    return Math.tanh((kick + sub + chord + piano + hat + snare) * 0.9) * 0.7;
  }
  process(_in, outs) {
    const o = outs[0][0];
    for (let i = 0; i < o.length; i++) o[i] = this.sample((currentFrame + i) / sampleRate);
    return true;
  }
}
registerProcessor('demo-synth', Demo);
