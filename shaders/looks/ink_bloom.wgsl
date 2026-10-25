// name: Ink Bloom
// palette: #1f4fd6 #e0306a #f2b21c
// Ink and paint blooming in water. The picture is a fluid-like feedback loop: last frame is advected along a
// curl-noise flow (plus vortices, bursts and the mouse), then relaxed toward the section's background, and
// fresh ink is mixed in. Everything is a convex mix of bounded colours, so it never burns to white or dies.
// Quiet: one thin ink thread curling. Verse: two-colour blooms on kicks. Build-up: a tightening vortex pulls
// ink to the centre. Drop: radial burst of saturated splashes. Breakdown: slow pastel diffusion with fine
// melody filaments. Chorus: many-colour marbling on bright paper. Mouse stirs, a click drops ink.

fn ib_sq(x: f32) -> f32 { return x * x; }

// centred coords (y up, height 2) -> uv
fn ib_uv(c: vec2f) -> vec2f { return vec2f(c.x / G.aspect * 0.5 + 0.5, 0.5 - c.y * 0.5); }

// stream function for the curl flow
fn ib_psi(p: vec2f, t: f32) -> f32 {
    return noise2(p * 1.3 + vec2f(t * 0.07, -t * 0.05)) + 0.5 * noise2(p * 2.9 - vec2f(t * 0.11, t * 0.04) + 7.0);
}

fn ib_curl(p: vec2f, t: f32) -> vec2f {
    let e = 0.02;
    let a = ib_psi(p + vec2f(0.0, e), t) - ib_psi(p - vec2f(0.0, e), t);
    let b = ib_psi(p + vec2f(e, 0.0), t) - ib_psi(p - vec2f(e, 0.0), t);
    return vec2f(a, -b) / (2.0 * e);
}

// where kick bloom number k sits
fn ib_bloom_pos(k: f32) -> vec2f {
    return vec2f((hash11(k * 3.1 + 0.7) - 0.5) * 1.5 * G.aspect, (hash11(k * 5.3 + 2.1) - 0.5) * 1.4);
}

// the curling pen of the quiet thread / breakdown filaments
fn ib_pen(t: f32, s: f32) -> vec2f {
    return vec2f(sin(t * 0.23 + s) * 0.9 + 0.35 * sin(t * 0.71 + s * 2.0), cos(t * 0.31 + s * 1.7) * 0.6 + 0.25 * sin(t * 0.53 + s)) * vec2f(G.aspect * 0.7, 1.0);
}

// paint ink colour c over x with amount a (convex: stays bounded)
fn ib_ink(x: vec3f, c: vec3f, a: f32) -> vec3f { return mix(x, c, clamp(a, 0.0, 1.0)); }

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let p = centered(fc);
    let t = G.time;
    let A = G.aspect;
    let px = 2.0 / G.res.y;
    let dt = clamp(G.dt, 0.0, 1.0 / 20.0);

    let wq = sec(SEC_QUIET);
    let wv = sec(SEC_VERSE);
    let wb = sec(SEC_BUILD);
    let wd = sec(SEC_DROP);
    let wk = sec(SEC_BREAKDOWN);
    let wc = sec(SEC_CHORUS);
    let bprog = select(1.0, sec_progress(12.0), G.section == SEC_BUILD);
    let r = length(p) + 1e-4;
    let rd = p / r;
    let tg = vec2f(-rd.y, rd.x);

    // ---------- velocity field (centred units / s) ----------
    let flowAmp = wq * 0.10 + wv * 0.22 + wb * 0.15 + wd * 0.35 + wk * 0.06 + wc * 0.30;
    var vel = ib_curl(p * (1.0 + wc * 0.6), t * (0.6 + G.flux)) * flowAmp;
    vel += vec2f(0.12, 0.03) * wc * sin(p.y * 2.5 + t * 0.2);                       // marbling shear
    // build-up vortex: spins faster and pulls harder as it ramps
    let vs = wb * (0.25 + 1.6 * bprog * bprog);
    vel += tg * vs * 0.5 / (r + 0.25) - rd * vs * 0.25 * smoothstep(0.02, 0.3, r);
    // kicks push blooms outward from their seed
    let bk = floor(G.beat_count);
    let bc = ib_bloom_pos(bk);
    let bvec = p - bc;
    let bl = length(bvec) + 1e-3;
    vel += bvec / bl * G.kick * exp(-bl * 3.0) * 1.2 * (wv + 0.5 * wc);
    // drop: radial blast
    vel += rd * (G.drop * 2.2 + G.kick * 0.5) * wd * smoothstep(0.0, 0.15, r);
    // mouse stirs a little whirlpool, a click pushes outward
    let mp = (G.mouse - 0.5) * vec2f(2.0 * A, -2.0);
    let md = p - mp;
    let ml = length(md) + 1e-3;
    vel += vec2f(-md.y, md.x) / ml * G.mouse_on * 0.9 * exp(-ml * 4.0);
    let cp = (G.click_pos - 0.5) * vec2f(2.0 * A, -2.0);
    let cd = p - cp;
    let cl = length(cd) + 1e-3;
    vel += cd / cl * exp(-G.click_age * 3.0) * exp(-cl * 5.0) * 1.5 * step(G.click_age, 2.0);

    // ---------- advect last frame, with section-dependent diffusion ----------
    let src = p - vel * dt;
    let blur = (0.3 + 0.4 * wk) * px;
    var c = prev(ib_uv(src + vec2f(blur, 0.0))) + prev(ib_uv(src - vec2f(blur, 0.0)))
          + prev(ib_uv(src + vec2f(0.0, blur))) + prev(ib_uv(src - vec2f(0.0, blur)));
    c *= 0.25;
    c = clamp(c, vec3f(0.0), vec3f(1.0));

    // ---------- background each section relaxes toward ----------
    let grain = noise2(fc * 0.35) * 0.5 + noise2(fc * 0.07) * 0.5;
    let water = vec3f(0.020, 0.030, 0.055) + vec3f(0.01, 0.02, 0.03) * fbm2(p * 1.5 + t * 0.02, 3);
    let paper = vec3f(0.96, 0.94, 0.90) - vec3f(0.05, 0.05, 0.06) * grain;
    let mist = vec3f(0.80, 0.78, 0.86) - vec3f(0.06) * fbm2(p * 1.2 - t * 0.01, 3);
    let bg = water * (wq + wv + wb) + vec3f(0.005, 0.004, 0.012) * wd + mist * wk + paper * wc;
    let rate = wq * 0.08 + wv * 0.35 + wb * 0.30 + wd * 0.5 + wk * 0.15 + wc * 0.45
        + 1.6 * (1.0 - wq) * (1.0 - smoothstep(0.0, 3.0, G.section_age));   // a new section clears quickly
    c = mix(c, bg, 1.0 - exp(-clamp(G.dt, 0.0, 0.5) * rate));   // real dt: stays balanced at any frame rate
    // stale foreign content (look just switched on) fades fast
    c = mix(c, bg, select(0.0, 0.15, G.look_time < 1.5));

    // ink colours: luminous on dark water, rich and deep on paper
    let k0 = G.pal0.rgb;
    let k1 = G.pal1.rgb;
    let k2 = G.pal2.rgb;

    // ---------- Quiet (and faintly everywhere dark): the curling thread ----------
    let thr = wq + 0.35 * wv + 0.2 * wb;
    if (thr > 0.004) {
        let a = ib_pen(t * 2.5, 0.0);
        let b = ib_pen((t - dt * 1.5) * 2.5, 0.0);
        let d = sd_segment(p, a, b);
        let wid = 0.006 + 0.004 * G.vol;
        c = ib_ink(c, mix(k0, vec3f(0.85, 0.9, 1.0), 0.45), smoothstep(wid, wid * 0.2, d) * thr);
        c = ib_ink(c, k0 * 0.6, smoothstep(wid * 5.0, wid, d) * thr * 0.08);   // halo bleeding into the water
    }

    // ---------- Verse: blooms on kicks, alternating two colours ----------
    let vw = wv + 0.6 * wc;
    if (vw > 0.004 && G.kick > 0.05) {
        let par = bk - 2.0 * floor(bk * 0.5);
        let col = select(k0, k1, par > 0.5);
        let rad = 0.04 + 0.22 * (1.0 - G.kick) * (0.6 + 0.8 * hash11(bk));
        let ang = atan2(bvec.y, bvec.x);
        let edge = rad * (0.8 + 0.45 * fbm2(vec2f(ang * 3.0, bk), 3));
        let ring = smoothstep(px * 6.0, 0.0, abs(bl - edge)) + smoothstep(edge, edge * 0.5, bl) * 0.35;
        c = ib_ink(c, col * (0.9 + 0.2 * G.bass), ring * G.kick * 0.55 * vw);
        // tendrils
        let ten = pow(noise2(vec2f(ang * 9.0 + bk, bl * 6.0 - t)), 6.0) * smoothstep(edge * 1.8, edge, bl);
        c = ib_ink(c, col, ten * G.kick * 0.8 * vw);
    }
    // snare: a fine third-colour spatter
    if (G.snare > 0.3 && (wv + wb + wc) > 0.1) {
        let sg = floor(p * 28.0);
        let sh = hash21(sg + floor(G.beat_count * 2.0));
        let so = length(fract(p * 28.0) - hash22(sg) * 0.6 - 0.2);
        c = ib_ink(c, k2, step(0.996, sh) * smoothstep(0.25, 0.1, so) * G.snare * (wv + wb + wc));
    }

    // ---------- Build-up: ink fed in from the rim, sucked into the vortex ----------
    if (wb > 0.004) {
        let an = atan2(p.y, p.x);
        let arms = pow(0.5 + 0.5 * sin(an * 3.0 + log(r) * 6.0 - t * (1.0 + 4.0 * bprog)), 18.0);
        let rim = smoothstep(0.75, 1.1, r) * arms;
        c = ib_ink(c, mix(k1, k0, 0.5 + 0.5 * sin(an)), rim * wb * 0.25);
        // charged core heats up
        c = ib_ink(c, mix(k2, vec3f(1.0), 0.3), exp(-r * r * 220.0) * bprog * wb * 0.25);
        c = ib_ink(c, vec3f(1.0, 0.95, 0.9), arms * G.snare * bprog * smoothstep(0.1, 0.5, r) * smoothstep(1.2, 0.6, r) * wb * 0.3);
    }

    // ---------- Drop: radial burst of saturated splashes ----------
    if (wd > 0.004) {
        let an = atan2(p.y, p.x);
        let front = (1.0 - G.drop) * 1.6 + 0.05;
        let spikes = pow(noise2(vec2f(an * 12.0, floor(G.beat_count * 0.25) * 7.0)), 2.0);
        let burst = smoothstep(0.08, 0.0, abs(r - front * (0.6 + 0.6 * spikes))) * smoothstep(0.0, 0.2, G.drop);
        let bcol = palc(an / TAU + 0.5 * spikes + t * 0.05) * 1.1;
        c = ib_ink(c, bcol, burst * wd);
        // a splash on every kick: blob with droplets
        let sp = ib_bloom_pos(bk * 1.37 + 11.0) * 0.8;
        let sd = length(p - sp);
        let blob = smoothstep(0.10 + 0.16 * G.kick, 0.04, sd + 0.04 * noise2(p * 12.0));
        let dg = p * 30.0;
        let di = floor(dg);
        let drops = step(0.85, hash21(di + bk)) * smoothstep(0.3, 0.1, length(fract(dg) - 0.5)) * smoothstep(0.45, 0.1, sd);
        c = ib_ink(c, palc(hash11(bk) + 0.1) * 1.15, (blob + drops) * G.kick * wd);
        // the core flashes white on the hit
        c = ib_ink(c, vec3f(1.0), exp(-r * r * 120.0) * G.drop * wd * 0.4);
    }

    // ---------- Breakdown: pastel washes and melody filaments ----------
    if (wk > 0.004) {
        for (var i = 0; i < 4; i++) {
            let fi = f32(i);
            let mel = max(spec(0.32 + 0.1 * fi), key(40 + i * 5));
            let a = ib_pen(t * 1.4, fi * 1.9 + 1.0) * 0.9;
            let b = ib_pen((t - dt * 1.5) * 1.4, fi * 1.9 + 1.0) * 0.9;
            let d = sd_segment(p, a, b);
            let fcol = mix(palc(fi * 0.27), vec3f(0.2, 0.15, 0.3), 0.3);
            c = ib_ink(c, fcol, smoothstep(0.004, 0.001, d) * (0.4 + 1.2 * mel) * wk);
        }
        let wash = smoothstep(0.55, 0.75, fbm2(p * 0.9 + vec2f(t * 0.02, 0.0), 3));
        c = ib_ink(c, mix(palc(fbm2(p * 0.5, 2) + t * 0.01), vec3f(1.0), 0.25), wash * 0.06 * wk);
    }

    // ---------- Chorus: marbling many colours across the paper ----------
    if (wc > 0.004) {
        let wp = p + 0.4 * vec2f(fbm2(p * 1.4 + t * 0.05, 3), fbm2(p * 1.4 + 5.0 - t * 0.04, 3));
        let bands = fract(wp.y * 2.2 + 0.3 * sin(wp.x * 3.0 + t * 0.1));
        let stripe = smoothstep(0.0, 0.04, bands) * smoothstep(0.22, 0.17, bands);
        let mc = palc(floor(wp.y * 2.2) * 0.37 + 0.1 * floor(wp.x * 1.5)) * 0.85;
        c = ib_ink(c, mc, stripe * 0.035 * (0.6 + G.energy) * wc);
        // classic marbling drops: concentric rings on the beat
        let dk = ib_bloom_pos(bk * 2.1 + 3.0);
        let dl = length(p - dk);
        let rings = smoothstep(0.35, 0.5, abs(sin(dl * 40.0)));
        c = ib_ink(c, palc(hash11(bk * 0.7) ), rings * smoothstep(0.12 + 0.1 * (1.0 - G.beat), 0.08, dl) * G.beat * 0.5 * wc);
        // hats flick fine dark speckles
        c = ib_ink(c, vec3f(0.08, 0.06, 0.12), step(0.995, hash21(floor(fc * 0.5) + floor(t * 20.0))) * G.hat * wc * 0.6);
    }

    // ---------- mouse pen and click drop ----------
    if (G.mouse_on > 0.5) {
        c = ib_ink(c, palc(t * 0.05), smoothstep(0.012, 0.004, length(p - mp)) * 0.6);
    }
    if (G.click_age < 0.6) {
        c = ib_ink(c, palc(hash11(floor(G.click_pos.x * 97.0)) + 0.2) * 1.05, smoothstep(0.09, 0.05, cl + 0.02 * noise2(p * 20.0)) * (1.0 - G.click_age / 0.6));
    }

    // tiny zero-mean dither (does not drift the feedback)
    c += (hash21(fc + fract(t) * 53.0) - 0.5) * 0.004;
    return vec4f(clamp(c, vec3f(0.0), vec3f(1.0)), 1.0);
}
