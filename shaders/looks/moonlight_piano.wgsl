// name: Moonlight Piano
// palette: #2c3f8f #ffc35c #dbe9ff
// Night lake under a big moon. A golden melody line (spectrum + fading echoes from history) floats over the
// hills, the notes being played light a piano keyboard along the bottom, send beams up and ripples across
// the lake, and join stars into constellations. pal0 = night tint, pal1 = gold (melody, lit keys),
// pal2 = moonlight.

fn mp_sq(x: f32) -> f32 { return x * x; }
// build-up tension 0..1 (stays 1 while the build fades out into the drop)
fn mp_bprog() -> f32 { return select(1.0, sec_progress(12.0), G.section == SEC_BUILD) * sec(SEC_BUILD); }
const MP_H: f32 = -0.12;   // horizon (centred coords, y up)
const MP_KB: f32 = -0.80;  // top edge of the keyboard

fn mmask0(md: f32) -> f32 { return smoothstep(0.125, 0.11, md); }
fn mp_cp(v: vec2f) -> vec2f { return vec2f((v.x * 2.0 - 1.0) * G.aspect, 1.0 - v.y * 2.0); }

fn mp_moon() -> vec2f {
    let def = vec2f(0.40 * G.aspect, 0.50 + 0.02 * sin(G.time * 0.05));
    let m = vec2f((G.mouse.x * 2.0 - 1.0) * G.aspect, mix(0.92, MP_H + 0.14, G.mouse.y));
    return mix(def, m, G.mouse_on);
}

// keyboard layout: 36 white keys C2..C7 spread over the width
fn mp_fw(x: f32) -> f32 { return ((x / G.aspect * 0.5 + 0.5 - 0.03) / 0.94) * 36.0; }
fn mp_wkey(w: i32) -> i32 {
    let j = w % 7;
    return 15 + 12 * (w / 7) + j * 2 - select(0, 1, j >= 3);
}
// black key between white keys w and w+1, -1 if none
fn mp_bkey(w: i32) -> i32 {
    if (w < 0 || w >= 35) { return -1; }
    let j = w % 7;
    if (j == 2 || j == 6) { return -1; }
    return mp_wkey(w) + 1;
}
fn mp_keyx(k: i32) -> f32 {
    let r = k - 15;
    let sm = f32(r % 12);
    let fw = f32(r / 12) * 7.0 + sm * 0.5 + select(0.5, 1.0, sm >= 5.0);
    return ((fw / 36.0) * 0.94 + 0.03 - 0.5) * 2.0 * G.aspect;
}

fn mp_lantern(lp: vec2f, sz: f32, fl: f32, px: f32) -> vec3f {
    // paper lantern: slightly wider at the top, bright at the bottom where the flame is
    let p = vec2f(lp.x * (1.0 - 0.18 * lp.y / sz), lp.y);
    let d = sd_round_box(p, vec2f(sz * 0.62, sz), sz * 0.35);
    let warm = mix(G.pal1.rgb, vec3f(1.0, 0.42, 0.12), 0.45);
    let inner = 1.0 + 1.2 * smoothstep(sz, -sz, lp.y);
    return warm * fl * (fill(d, px) * 1.3 * inner + (glow(d, sz * 1.2) * 0.22 + exp(-dot(lp, lp) / (sz * sz * 30.0)) * 0.12) * smoothstep(0.12, 0.05, max(abs(lp.x), abs(lp.y))));
}

// everything above the horizon; also sampled mirrored for the lake reflection
fn mp_sky(q: vec2f, moon: vec2f) -> vec3f {
    let t = G.time;
    let A = G.aspect;
    let px = 2.0 / G.res.y;
    let hh = q.y - MP_H;
    let sQ = sec(SEC_QUIET);
    let sB = sec(SEC_BUILD);
    let sC = sec(SEC_CHORUS);
    let sK = sec(SEC_BREAKDOWN);
    let sD = sec(SEC_DROP);
    let bp = mp_bprog();

    // gradient, warmer when the sound is bright (centroid)
    let top = mix(vec3f(0.004, 0.008, 0.030), vec3f(0.014, 0.008, 0.030), G.centroid);
    let low = mix(vec3f(0.030, 0.055, 0.140), vec3f(0.090, 0.065, 0.130), G.centroid);
    var col = mix(low, top, smoothstep(0.0, 1.0, hh));
    col *= 1.0 - 0.35 * sQ - 0.4 * sK - 0.2 * bp;                                           // quiet/breakdown: darker sky so the rest glows
    col += mix(vec3f(0.30, 0.13, 0.07), G.pal1.rgb * 0.25, 0.4) * sC * exp(-max(hh, 0.0) * 2.2);   // chorus: golden dawn glow on the horizon
    col += G.pal0.rgb * 0.07 * exp(-max(hh, 0.0) * 4.0);
    let md = length(q - moon);
    col += G.pal2.rgb * (0.06 * exp(-md * 2.0) + 0.10 * exp(-md * 6.5)) * (1.0 - mmask0(md)) * (0.8 + 0.5 * G.bass);

    // thin drifting clouds lit by the moon
    let cl = fbm2(vec2f(q.x * 1.1 + t * 0.012, q.y * 3.5 - 0.3), 3);
    let cloud = smoothstep(0.52, 0.80, cl) * smoothstep(0.05, 0.30, hh) * (1.0 - smoothstep(0.6, 1.1, hh)) * 0.75;

    // stars (small field + big twinkling ones), twinkle on hats and high end
    let sg = q * 34.0;
    let sc = floor(sg);
    let sh = hash21(sc);
    let sd = length(fract(sg) - (hash22(sc) * 0.5 + 0.25));
    let tw = 0.55 + 0.45 * sin(t * (1.0 + 4.0 * hash21(sc + 7.0)) + sh * 60.0) + G.hat * G.high * 1.2 * step(0.6, hash21(sc + 3.0));
    var stars = smoothstep(0.72, 1.0, sh) * tw * exp(-sd * sd * 160.0) * 1.4;
    let bg = q * 9.0;
    let bc = floor(bg);
    let bh = hash21(bc + 31.0);
    let bo = fract(bg) - (hash22(bc + 5.0) * 0.3 + 0.35);
    let btw = 0.6 + 0.4 * sin(t * (0.7 + 2.0 * hash21(bc)) + bh * 30.0) + G.high * 0.6;
    let spike = exp(-abs(bo.x) * 90.0) * exp(-abs(bo.y) * 9.0) * smoothstep(0.35, 0.15, abs(bo.y)) + exp(-abs(bo.y) * 90.0) * exp(-abs(bo.x) * 9.0) * smoothstep(0.35, 0.15, abs(bo.x));
    stars += step(0.86, bh) * btw * (exp(-dot(bo, bo) * 1200.0) * 2.5 + spike * 0.35) * (0.7 + 0.6 * G.energy);
    stars *= smoothstep(0.02, 0.35, hh) * (1.0 - cloud) * smoothstep(0.14, 0.3, md) * (1.0 - 0.6 * sQ + 0.7 * sK + 0.8 * bp);
    col += vec3f(0.85, 0.9, 1.0) * stars;

    // constellation: one star per pitch class, lines light up between notes being played
    var con = 0.0;
    if (hh > 0.42) {
    var pn = vec2f(0.0);
    var pg = 0.0;
    for (var i = 0; i < 12; i++) {
        let fi = f32(i);
        var g = 0.0;
        for (var o = 0; o < 5; o++) { g = max(g, key(15 + i + 12 * o)); }
        let n = vec2f((-0.86 + 1.72 * (fi + 0.5) / 12.0) * A + (hash11(fi + 3.1) - 0.5) * 0.2,
                      MP_H + 0.62 + 0.36 * hash11(fi * 1.7 + 0.4));
        let dn = length(q - n);
        con += (0.35 + 2.0 * g) * exp(-dn * dn * 30000.0) + g * 0.006 / (dn + 0.01);
        if (i > 0) {
            let ds = sd_segment(q, pn, n);
            let lg = 0.05 + 1.2 * min(g, pg) + 0.4 * max(g, pg);
            con += lg * (exp(-ds * ds * 250000.0) * 0.7 + 0.0012 / (ds + 0.004));
        }
        pn = n;
        pg = g;
    }
    con *= smoothstep(0.42, 0.52, hh) * (1.0 - 0.7 * sQ + 1.2 * bp + 0.4 * sC);   // build: the whole constellation charges up
    }
    col += mix(G.pal2.rgb, G.pal1.rgb, 0.35) * con * smoothstep(0.1, 0.3, hh) * (1.0 - 0.6 * cloud);

    // cloud layer (in front of stars)
    let ccol = mix(vec3f(0.03, 0.045, 0.09), G.pal2.rgb * 0.55, exp(-md * 2.2)) + G.pal0.rgb * 0.03;
    col = mix(col, ccol, cloud);

    // the moon: craters, maria, limb darkening, halo; halo ring on the beat, flare on the drop
    let r = 0.115 * (1.0 + 0.02 * G.bass) * (1.0 + 0.5 * bp + 0.22 * sC - 0.2 * sK);   // build: the moon swells; chorus: big; breakdown: small and distant
    let mq = (q - moon) / r;
    let ml = length(mq);
    let sph = sqrt(max(0.0, 1.0 - ml * ml));
    var maria = 0.0;
    var mfb = 0.5;
    if (ml < 1.05) { maria = smoothstep(0.42, 0.62, fbm2(mq * 1.6 + 2.0, 4)); mfb = fbm2(mq * 6.0, 3); }
    let cgp = mq * 5.0;
    let ci = floor(cgp);
    let cdist = length(fract(cgp) - (hash22(ci) * 0.5 + 0.25));
    let crr = 0.12 + 0.18 * hash21(ci + 9.0);
    let hasc = step(0.45, hash21(ci + 1.3));
    let crater = hasc * (smoothstep(crr, crr * 0.6, cdist) * 0.14 - smoothstep(0.06, 0.0, abs(cdist - crr)) * 0.1 * sign(fract(cgp).x - 0.5));
    let mtex = (0.88 + 0.25 * mfb) * (1.0 - 0.32 * maria) * (1.0 - crater);
    var mcol = G.pal2.rgb * 1.2 * (0.62 + 0.38 * sph) * mtex;
    mcol = mix(mcol, mcol * vec3f(1.5, 0.8, 0.55), 0.7 * bp);   // build: the moon heats up red
    let mmask = smoothstep(1.0, 1.0 - 2.0 * px / r, ml);
    let edge = max(md - r, 0.0);
    col = mix(col, mcol, mmask);
    col += (1.0 - mmask) * G.pal2.rgb * (0.30 * exp(-edge * 16.0) + 0.14 * exp(-edge * 4.0)) * (0.75 + 0.5 * G.bass + 1.5 * G.drop + 2.5 * bp + 0.8 * sC);
    let ringr = r * (1.25 + 1.6 * G.beat_phase);
    col += G.pal2.rgb * exp(-abs(md - ringr) * 70.0) * (1.0 - G.beat_phase) * (0.12 + 0.3 * G.energy) * (1.0 - 0.8 * sK);
    // build: rings of light contract onto the moon, faster and brighter as the tension climbs
    let cr = (1.0 - fract(t * (0.4 + 1.2 * bp))) * 1.6;
    col += mix(G.pal2.rgb, vec3f(1.0, 0.5, 0.3), 0.5) * exp(-abs(md - cr) * 22.0) * bp * 0.5;
    col += G.pal2.rgb * G.snare * sB * 0.12 * exp(-md * 1.5);
    // DROP ONLY: aurora curtains across the sky and rays bursting out of the moon
    if (sD > 0.01) {
        let av = noise2(vec2f(q.x * 2.0 + t * 0.2, t * 0.1));
        let ab = exp(-mp_sq((hh - 0.5 - 0.25 * av - 0.08 * sin(q.x * 4.0 + t)) * 4.5));
        let ast = 0.5 + 0.5 * noise2(vec2f(q.x * 30.0, t * 0.5));
        col += mix(vec3f(0.1, 1.0, 0.5), vec3f(0.9, 0.2, 0.95), smoothstep(0.2, 0.9, hh + 0.2 * av)) * ab * ast * smoothstep(0.08, 0.3, hh) * sD * (0.7 + 1.2 * G.kick);
        let ra = atan2(q.y - moon.y, q.x - moon.x);
        col += G.pal2.rgb * pow(abs(sin(ra * 8.0 + t * 0.3)), 14.0) * exp(-md * 1.6) * sD * (0.4 + 1.2 * G.kick) * (1.0 - mmask);
    }

    // shooting stars: a slow idle one, and a big one on the drop
    let mp = t / 9.0;
    let mph = fract(mp);
    let ms = floor(mp);
    let m0 = vec2f((hash11(ms) * 1.6 - 0.8) * A, 0.55 + 0.35 * hash11(ms + 2.0));
    let mdir = normalize(vec2f(-0.8 + 0.4 * hash11(ms + 5.0), -0.45));
    let mhead = m0 + mdir * mph * 6.0;
    let mds = sd_segment(q, mhead, mhead - mdir * 0.25);
    col += vec3f(0.9, 0.95, 1.0) * exp(-mds * mds * 200000.0) * smoothstep(0.12, 0.0, mph) * smoothstep(0.0, 0.02, mph)
        * clamp(1.0 - length(q - mhead) * 4.0, 0.0, 1.0) * 2.0;
    if (G.drop > 0.01) {
        let dhead = vec2f(0.8 * A, 0.9) + vec2f(-1.6 * A, -0.6) * (1.0 - G.drop);
        let ddir = normalize(vec2f(-1.6 * A, -0.6));
        let dds = sd_segment(q, dhead, dhead - ddir * 0.6);
        col += mix(G.pal1.rgb, vec3f(1.0), 0.5) * (exp(-dds * dds * 60000.0) * 2.5 + 0.004 / (dds + 0.004))
            * clamp(1.0 - length(q - dhead) * 1.6, 0.0, 1.0) * G.drop;
    }

    // golden melody line from the spectrum, with echoes of the last moment drifting up and fading
    let s = clamp(q.x / A * 0.5 + 0.5, 0.0, 1.0);
    let bx = mix(18.0, 84.0, s) / 95.0;
    let bx2 = mix(18.0, 84.0, s + 0.004) / 95.0;
    let base = MP_H + 0.24;
    var mel = vec3f(0.0);
    if (hh > 0.04 && hh < 1.1) {
    for (var e = 0; e < 6; e++) {
        let fe = f32(e);
        var v = spec(bx);
        var v2 = spec(bx2);
        if (e > 0) { v = hist(bx, fe * 0.12); v2 = hist(bx2, fe * 0.12); }
        let slope = (v2 - v) * 0.42 / (0.008 * A);
        let yl = base + v * 0.42 * (1.0 + 0.6 * bp + 0.25 * sC) + fe * 0.03;
        let dy = abs(q.y - yl) / sqrt(1.0 + slope * slope);
        let w = 1.0 - fe / 6.0;
        let lc = mix(G.pal1.rgb, mix(G.pal1.rgb, G.pal0.rgb * 2.0, 0.5), fe / 5.0);
        mel += lc * w * w * (exp(-dy * dy / (px * px * 1.2)) * 1.1 + 0.0008 / (dy + 0.004)) * (0.5 + 0.6 * G.mid + G.drop) * (1.0 - 0.9 * sQ - 0.65 * sK + 1.2 * bp + 0.6 * sC + 0.4 * sD);
    }
    }
    col += mel * smoothstep(0.0, 0.06, hh);

    // far hills (misty, rim-lit by the moon) and near hills with a pine line
    if (hh < 0.5) {
    let rf = MP_H + 0.04 + 0.6 * max(fbm2(vec2f(q.x * 0.8 + 3.0, 0.5), 4) - 0.3, 0.0);
    let farc = mix(vec3f(0.055, 0.075, 0.15), low, 0.3) + G.pal0.rgb * 0.03 + vec3f(0.02, 0.03, 0.05) * smoothstep(0.0, -0.08, q.y - rf);
    let rim = exp(-max(rf - q.y, 0.0) * 160.0) * exp(-abs(q.x - moon.x) * 1.1) * 0.35;
    col = mix(col, farc + G.pal2.rgb * rim, smoothstep(rf + px, rf - px, q.y));
    let tx = q.x * 55.0;
    let th = step(0.35, hash11(floor(tx))) * (1.0 - abs(fract(tx) - 0.5) * 2.0) * (0.02 + 0.025 * hash11(floor(tx) + 4.0));
    let rn = MP_H + 0.012 + 0.22 * max(fbm2(vec2f(q.x * 1.6 + 11.0, 1.5), 4) - 0.38, 0.0) + th;
    let nearc = vec3f(0.006, 0.010, 0.022);
    let rim2 = exp(-max(rn - q.y, 0.0) * 300.0) * exp(-abs(q.x - moon.x) * 1.5) * 0.18;
    col = mix(col, nearc + G.pal2.rgb * rim2, smoothstep(rn + px, rn - px, q.y));
    }

    // sky lanterns rising (more when the section is big), flicker with the mids, one more from each click
    var lan = vec3f(0.0);
    let nl = min(i32((6.0 + 8.0 * G.energy + 3.0 * G.quality + 9.0 * sC + 5.0 * sK) * (1.0 - 0.85 * sQ)), 30);
    for (var i = 0; i < nl; i++) {
        let fi = f32(i);
        let P = 18.0 + 10.0 * hash11(fi * 3.3);
        let ph = fract(t / P + hash11(fi * 7.7));
        let lx = (hash11(fi * 1.9) * 2.0 - 1.0) * A * 0.92 + 0.05 * sin(t * 0.3 + fi * 2.0) + ph * 0.15;
        let ly = MP_H + 0.03 + ph * 1.15;
        let sz = 0.018 * (1.0 - 0.6 * ph) * (0.8 + 0.4 * hash11(fi * 5.1));
        if (abs(q.x - lx) > 0.12 || abs(q.y - ly) > 0.12) { continue; }
        let fl = (0.75 + 0.15 * sin(t * 11.0 + fi * 5.0) + 0.5 * G.mid + 1.2 * G.drop) * smoothstep(0.0, 0.06, ph) * smoothstep(1.0, 0.6, ph);
        lan += mp_lantern(q - vec2f(lx, ly), sz, fl, px);
    }
    if (G.click_age < 25.0) {
        let cp = mp_cp(G.click_pos);
        let lp = vec2f(cp.x + 0.03 * sin(G.click_age * 0.8), max(cp.y, MP_H + 0.02) + G.click_age * 0.06);
        lan += mp_lantern(q - lp, 0.022, (1.1 + 0.4 * G.mid) * smoothstep(25.0, 18.0, G.click_age), px);
    }
    col += lan;
    return col;
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let sQ = sec(SEC_QUIET);
    let sB = sec(SEC_BUILD);
    let sC = sec(SEC_CHORUS);
    let sK = sec(SEC_BREAKDOWN);
    let sD = sec(SEC_DROP);
    let bp = mp_bprog();
    let t = G.time;
    let shk = (vec2f(noise2(vec2f(t * 25.0, 1.0)), noise2(vec2f(t * 25.0, 9.0))) - 0.5) * (0.006 * bp + 0.014 * sD * G.kick);
    let q = centered(fc) + shk;
    let A = G.aspect;
    let px = 2.0 / G.res.y;
    let moon = mp_moon();
    var col = vec3f(0.0);

    if (q.y >= MP_H) {
        col = mp_sky(q, moon);
    } else if (q.y > MP_KB) {
        // ---- the lake ----
        let d = MP_H - q.y;
        let wz = 1.0 / (d + 0.03);
        let wp = vec2f(q.x * wz * 0.5, wz);
        let wt = t * (0.35 + 0.4 * G.energy);
        let e = 0.04;
        let h0 = noise2(vec2f(wp.x * 2.0, wp.y * 3.0 - wt)) + 0.5 * noise2(vec2f(wp.x * 5.0 + wt * 0.3, wp.y * 8.0));
        let hx = noise2(vec2f((wp.x + e) * 2.0, wp.y * 3.0 - wt)) + 0.5 * noise2(vec2f((wp.x + e) * 5.0 + wt * 0.3, wp.y * 8.0));
        let hy = noise2(vec2f(wp.x * 2.0, (wp.y + e) * 3.0 - wt)) + 0.5 * noise2(vec2f(wp.x * 5.0 + wt * 0.3, (wp.y + e) * 8.0));
        let amp = 0.010 * (0.25 + 1.6 * d) * (0.7 + 0.8 * G.bass + 0.9 * G.kick);
        var dist = vec2f(hx - h0, hy - h0) / e * amp;

        // each struck note sends a ring across the water (ring grows as the key's glow fades)
        var rip = 0.0;
        for (var k = 15; k <= 75; k++) {
            let g = key(k);
            if (g < 0.03) { continue; }
            let kc = vec2f(mp_keyx(k), MP_KB + 0.06 + 0.3 * hash11(f32(k) * 1.37));
            let rel = vec2f(q.x - kc.x, (q.y - kc.y) * 3.5);
            let rl = length(rel) + 1e-4;
            let rr = (1.0 - g) * 0.55 + 0.015;
            let rd = rl - rr;
            let ring = (exp(-rd * rd * 2500.0) + 0.5 * exp(-(rd + 0.05) * (rd + 0.05) * 2500.0)) * g;
            rip += ring;
            dist += rel / rl * ring * 0.02 * sin(rd * 120.0);
        }
        // click ripple
        let cp = mp_cp(G.click_pos);
        if (G.click_age < 6.0 && cp.y < MP_H) {
            let rel = vec2f(q.x - cp.x, (q.y - cp.y) * 3.5);
            let rl = length(rel) + 1e-4;
            for (var j = 0; j < 3; j++) {
                let rd = rl - max(G.click_age * 0.3 - f32(j) * 0.07, 0.0);
                let ring = exp(-rd * rd * 2000.0) * exp(-G.click_age * 0.8) * step(f32(j) * 0.07, G.click_age * 0.3);
                rip += ring * 1.5;
                dist += rel / rl * ring * 0.02;
            }
        }

        // reflection of the whole sky (moon, stars, hills, melody, lanterns), stretched vertically
        let rq = vec2f(q.x + dist.x, MP_H + d + dist.y * 2.5 + 0.004);
        let refl = mp_sky(rq, moon);
        let fres = mix(0.85, 0.42, smoothstep(0.0, 0.55, d));
        col = vec3f(0.004, 0.010, 0.026) + G.pal0.rgb * 0.02 + refl * fres * vec3f(0.80, 0.90, 1.0);

        // moon's light path: widening glitter, edges wobbling with the waveform, glints on the high end
        let above = smoothstep(MP_H, MP_H + 0.1, moon.y);
        let pw = 0.025 + d * 0.42;
        let wob = wave(fract(d * 1.3 + t * 0.03)) * 0.04 * (0.3 + d);
        let path = exp(-mp_sq((q.x - moon.x - wob) / pw));
        let gl = noise2(vec2f(wp.x * 16.0, wp.y * 26.0 - wt * 4.0));
        let glint = pow(gl, 9.0) * 10.0;
        col += G.pal2.rgb * path * (0.06 + glint * (0.45 + 1.4 * G.high)) * above;

        col += mix(G.pal2.rgb, G.pal1.rgb, 0.45) * rip * (0.55 + 0.7 * sK);

        // shoreline glint that traces the waveform
        let sl = MP_H - 0.006 + wave(clamp(q.x / A * 0.5 + 0.5, 0.0, 1.0)) * 0.006;
        col += G.pal2.rgb * exp(-abs(q.y - sl) / px * 0.7) * 0.25 * (0.4 + G.vol * 2.0);

        // a small boat with a lamp drifting along the lake, bobbing on the beat
        let bx = sin(t * 0.021) * 0.75 * A;
        let by = MP_H - 0.085 + 0.003 * sin(t * 1.3) + 0.005 * (1.0 - G.beat_phase) * G.beat;
        let l = (q - vec2f(bx, by)) / 1.6;
        let hull = max(abs(l.x) - (0.075 + l.y * 1.4), max(l.y, -l.y - 0.016));
        let mast = sd_box(l - vec2f(-0.01, 0.045), vec2f(0.0018, 0.045));
        let boat = min(hull, mast);
        let lampp = vec2f(0.035, 0.03);
        let lfl = 0.85 + 0.15 * sin(t * 9.0) + 0.4 * G.mid;
        // the boat's reflection (dark) and lamp streak on the water
        let lr = vec2f(l.x, -l.y - 0.032);
        let hullr = max(abs(lr.x) - (0.075 + lr.y * 1.4), max(lr.y, -lr.y - 0.016));
        col *= 1.0 - 0.7 * fill(hullr + 0.002, px * 3.0);
        let lsd = l - lampp;
        col += mix(G.pal1.rgb, vec3f(1.0, 0.5, 0.15), 0.4) * lfl * exp(-abs(lsd.x + dist.x * 2.0) * 90.0) * exp(-max(-lsd.y, 0.0) * 6.0) * step(lsd.y, -0.035) * 0.6;
        col = mix(col, vec3f(0.006, 0.008, 0.016) + G.pal2.rgb * 0.06 * smoothstep(-0.01, 0.0, l.y), fill(boat, px));
        col += mix(G.pal1.rgb, vec3f(1.0, 0.5, 0.15), 0.4) * lfl * (exp(-dot(lsd, lsd) * 40000.0) * 2.0 + 0.004 / (length(lsd) + 0.008));
    } else {
        // ---- the keyboard ----
        let fw = mp_fw(q.x);
        let ky = (MP_KB - q.y) / (1.0 + MP_KB);   // 0 top .. 1 bottom
        col = vec3f(0.018, 0.012, 0.014) + vec3f(0.03, 0.02, 0.015) * fbm2(q * vec2f(3.0, 40.0), 3);
        if (fw >= 0.0 && fw < 36.0) {
            let w = i32(floor(fw));
            let f = fract(fw);
            let gw = min(key(mp_wkey(w)) * (1.0 + 0.8 * sK), 1.0);
            let gap = smoothstep(0.0, 0.05, f) * smoothstep(1.0, 0.95, f);
            var c = vec3f(0.30, 0.31, 0.36) * (0.75 + 0.25 * smoothstep(0.0, 0.3, ky)) * (1.0 - 0.45 * smoothstep(0.88, 0.95, ky));
            c += G.pal2.rgb * 0.15 * exp(-abs(q.x - moon.x) * 2.0) * smoothstep(0.35, 0.1, ky);  // moon sheen
            c = mix(c, G.pal1.rgb * 2.4 * (1.0 - 0.4 * ky), gw);
            c *= gap;
            var bk = -1;
            var be = 0.0;
            if (f > 0.66) { bk = mp_bkey(w); be = (f - 0.66) / 0.34; }
            else if (f < 0.34) { bk = mp_bkey(w - 1); be = (0.34 - f) / 0.34; }
            if (bk >= 0 && ky < 0.62) {
                let gb = key(bk);
                var b = vec3f(0.012, 0.012, 0.018) + vec3f(0.06, 0.065, 0.08) * smoothstep(0.5, 0.58, ky) + vec3f(0.03) * smoothstep(0.8, 1.0, be);
                b = mix(b, mix(G.pal1.rgb, G.pal0.rgb * 3.0, 0.45) * 1.8, gb);
                c = mix(c, b, smoothstep(0.62, 0.6, ky) * smoothstep(0.98, 0.9, be));
            } else if (bk >= 0 && ky < 0.66) {
                c *= 0.5; // shadow under the black key
            }
            col = c;
            // glow spilling out of lit keys
            col += G.pal1.rgb * gw * (0.3 + 0.9 * sK) * exp(-ky * 3.0);
        }
        // felt strip and a gold edge breathing with the energy
        col = mix(col, vec3f(0.12, 0.02, 0.03), smoothstep(0.045, 0.035, ky));
        col += G.pal1.rgb * exp(-abs(ky - 0.045) * 250.0) * (0.25 + 0.6 * G.energy);
    }

    // light beams rising from lit keys (over water and sky)
    if (q.y > MP_KB) {
        let fw = mp_fw(q.x);
        let hy = q.y - MP_KB;
        let bh = 0.45 + 0.9 * G.energy + 0.8 * G.drop + 1.5 * sK + 0.5 * sC;   // breakdown: the keys' beams soar high into the sky
        let shim = 0.7 + 0.3 * noise2(vec2f(fw * 3.0, q.y * 7.0 - t * 2.5));
        var beam = vec3f(0.0);
        for (var dw = -1; dw <= 1; dw++) {   // neighbours too, so the beam is not cut at the key border
            let ww = i32(floor(fw)) + dw;
            if (ww >= 0 && ww < 36) {
                beam += G.pal1.rgb * key(mp_wkey(ww)) * exp(-mp_sq((fw - f32(ww) - 0.5) * 3.2));
            }
        }
        if (fw >= 0.0 && fw < 36.0) {
            let b = i32(round(fw));
            let bk = mp_bkey(b - 1);
            if (bk >= 0) {
                beam += mix(G.pal1.rgb, G.pal0.rgb * 2.5, 0.5) * key(bk) * exp(-mp_sq((fw - f32(b)) * 5.0));
            }
        }
        col += beam * shim * exp(-hy / bh) * (0.8 + 0.4 * G.beat * (1.0 - sK)) * 0.7 * (1.0 + 1.8 * sK + 0.3 * sC - 0.4 * sQ);
    }

    // fireflies over the shore and the water: more and faster when the music is busy (flux)
    let nf = i32((10.0 + (14.0 + 10.0 * G.quality) * G.flux) * (1.0 - 0.8 * sQ - 0.6 * sK + 0.5 * sC));
    var ff = 0.0;
    for (var i = 0; i < nf; i++) {
        let fi = f32(i);
        let sp = 0.25 + 0.5 * G.flux;
        let fp = vec2f((hash11(fi * 2.1) * 2.0 - 1.0) * A * 0.95, MP_H - 0.2 + 0.32 * hash11(fi * 4.7))
            + vec2f(sin(t * sp * (0.6 + hash11(fi)) + fi * 3.0), cos(t * sp * (0.5 + hash11(fi + 1.0)) + fi * 5.0)) * vec2f(0.12, 0.05);
        let blink = pow(0.5 + 0.5 * sin(t * (1.2 + 2.0 * hash11(fi * 9.0)) + fi * 40.0), 3.0);
        let dd = length(q - fp);
        ff += blink * (exp(-dd * dd * 60000.0) * 1.8 + 0.0015 / (dd + 0.006));
    }
    col += vec3f(0.75, 1.0, 0.45) * ff * 0.7;

    // soft trails above the keyboard (moon dragged by the mouse, fireflies)
    if (q.y > MP_KB) { col = max(col, prev(uv) * 0.6); }

    // colour treatment per section
    col = mix(col, vec3f(luma(col)) * vec3f(0.8, 0.95, 1.2), 0.3 * sQ);
    col *= mix(vec3f(1.0), vec3f(1.12, 1.03, 0.88), sC);
    col *= mix(vec3f(1.0), vec3f(1.15, 0.85, 1.3), 0.5 * sD);
    col += vec3f(0.9, 0.2, 0.1) * 0.12 * bp * pow(length(uv - 0.5) * 1.3, 2.0) * (0.5 + 0.5 * (1.0 - G.beat_phase));
    col += G.pal2.rgb * G.snare * sB * 0.06;

    // vignette + grain
    let vg = 1.0 - 0.35 * pow(length(uv - 0.5) * 1.3, 2.5);
    col *= vg;
    col += (hash21(fc + fract(t) * 91.0) - 0.5) * 0.012;
    return vec4f(col, 1.0);
}
