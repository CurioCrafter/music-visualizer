//! Envelopes and counters shared by the app and `--shots`, and filling the shader Globals.

use crate::analyzer::Analyzer;
use crate::render::Globals;

#[derive(Default)]
pub struct Signals {
    pub beat: f32,
    pub drop: f32,
    pub beat_count: f32,
    pub travel: f32,
}

impl Signals {
    pub fn step(&mut self, an: &Analyzer, dt: f32) {
        if an.beat {
            self.beat = 1.0;
            self.beat_count += 1.0;
        }
        self.beat = (self.beat - dt * 3.0).max(0.0);
        if an.drop {
            self.drop = 1.0;
        }
        self.drop = (self.drop - dt * 0.7).max(0.0);
        // forward speed: idle drift + loudness + a surge on the drop
        self.travel += dt * (0.4 + 2.5 * an.bass + 1.5 * an.mid + 4.0 * self.drop);
    }

    #[allow(clippy::too_many_arguments)]
    pub fn fill(&self, g: &mut Globals, an: &Analyzer, time: f32, dt: f32, res: (u32, u32), look_time: f32, quality: f32) {
        g.res = [res.0 as f32, res.1 as f32];
        g.time = time;
        g.dt = dt;
        g.aspect = res.0 as f32 / res.1.max(1) as f32;
        g.bass = an.bass;
        g.mid = an.mid;
        g.high = an.high;
        g.vol = an.vol;
        g.beat = self.beat;
        g.drop = self.drop;
        g.beat_count = self.beat_count;
        g.travel = self.travel;
        g.quality = quality;
        g.kick = an.kick();
        g.snare = an.snare();
        g.hat = an.hat();
        g.flux = an.flux;
        g.centroid = an.centroid;
        g.energy = an.energy;
        g.beat_phase = an.beat_phase;
        g.bpm = an.bpm;
        g.look_time = look_time;
        if g.mouse_on == 0.0 {
            g.mouse = [0.5, 0.5];
        }
        if g.click_age == 0.0 {
            g.click_age = 999.0;
        }
    }
}
