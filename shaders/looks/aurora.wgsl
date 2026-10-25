// name: Aurora
// palette: #3dff8f #1fc9d6 #a45cff
// Northern lights over snowy mountains and a mirror-still lake. Three aurora curtains (green -> teal -> violet
// along pal()), each driven by its own band; Milky Way, shooting stars on beats, a cabin with a warm window and
// chimney smoke, pines on the shore, a wolf on a rock that howls on the drop, snowfall.

fn au_sq(x: f32) -> f32 { return x * x; }
const AU_H: f32 = -0.30;   // horizon / shoreline (centred coords, y up)

// section weights (all add up to 1); bp = build-up tension 0..1 over ~12 s
struct AuS { q: f32, v: f32, b: f32, c: f32, k: f32, d: f32, bp: f32 }
fn au_secs() -> AuS {
    var s: AuS;
    s.q = sec(SEC_QUIET); s.v = sec(SEC_VERSE); s.b = sec(SEC_BUILD);
    s.c = sec(SEC_CHORUS); s.k = sec(SEC_BREAKDOWN); s.d = sec(SEC_DROP);
    s.bp = s.b * sec_progress(12.0);
    return s;
}

fn au_cp(v: vec2f) -> vec2f { return vec2f((v.x * 2.0 - 1.0) * G.aspect, 1.0 - v.y * 2.0); }

// ridged 1D noise for mountain silhouettes
fn au_ridge(x: f32, seed: f32) -> f32 {
    var s = 0.0;
    var a = 0.5;
    var f = 1.0;
    for (var i = 0; i < 5; i++) {
        let n = 1.0 - abs(noise2(vec2f(x * f, seed + f32(i) * 3.7)) * 2.0 - 1.0);
        s += a * n * n;
        f *= 2.1;
        a *= 0.48;
    }
    return s;
}

// sin-free value noise: common noise2()'s sin(dot*43758) hash loses precision for big arguments (late in the song),
// so the same lattice point can hash differently on the two sides of a cell border -> a hard vertical step.
fn au_h(p: vec2f) -> f32 {
    var p3 = fract(vec3f(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
fn au_n(p: vec2f) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(au_h(i), au_h(i + vec2f(1.0, 0.0)), u.x), mix(au_h(i + vec2f(0.0, 1.0)), au_h(i + vec2f(1.0, 1.0)), u.x), u.y);
}
fn au_fbm(p0: vec2f) -> f32 {
    var p = p0; var a = 0.5; var s = 0.0;
    for (var i = 0; i < 3; i++) { s += a * au_n(p); p = p * 2.03 + vec2f(1.7, 9.2); a *= 0.5; }
    return s;
}

// one aurora curtain; drive = the band that feeds it, lo/hi = spectrum range that lights it along x
fn au_curtain(q: vec2f, i: f32, drive0: f32, lo: f32, hi: f32) -> vec3f {
    let t = G.time;
    let A = G.aspect;
    let S = au_secs();
    // breakdown: the curtains follow the melody instead of the drums
    let drive = mix(drive0, 0.25 + 0.9 * G.mid, S.k);
    // the curtains flow toward the cursor
    let m = au_cp(G.mouse);
    var x = q.x;
    let near = exp(-au_sq((q.x - m.x) * 1.3)) * G.mouse_on;
    x += (m.x - q.x) * 0.25 * G.mouse_on * exp(-abs(q.x - m.x) * 0.8);
    let speed = 0.035 + 0.10 * G.flux;
    let fold = au_fbm(vec2f(x * 0.55 + i * 7.3, t * speed + i * 3.0));
    let s = clamp(q.x / A * 0.5 + 0.5, 0.0, 1.0);
    var yb = AU_H + 0.42 + 0.17 * i + (fold - 0.5) * 0.55
        + hist(mix(lo, hi, s) / 95.0, 0.15 + 0.2 * i) * 0.07
        + wave(1.0 - abs(1.0 - 2.0 * fract(s + i * 0.31))) * 0.012 * (1.0 + G.flux * 2.0);
    yb += (fold - 0.5) * 0.25 * S.d;                                   // drop: curtains whip harder
    yb = mix(yb, AU_H + 0.58 + 0.05 * i, 0.6 * S.bp);                  // build-up: all curtains converge into one band
    yb -= 0.16 * near * (0.5 + 0.5 * clamp(m.y - AU_H, 0.0, 1.0));
    let hm = 0.5 * S.q + S.v + (1.0 + 0.8 * S.bp) * S.b + 1.45 * S.c + 1.2 * S.k + 1.5 * S.d;
    let hgt = (0.20 + 0.30 * drive + 0.08 * i) * hm + 0.25 * G.drop;
    let dy = q.y - yb;
    if (dy < -0.08 || dy > hgt * 4.0) { return vec3f(0.0); }
    // vertical ray structure following the folds, shimmering faster when the music is busy
    let rx = x * 13.0 + fold * 10.0 + i * 40.0;
    let rt = t * (0.25 + 0.9 * G.flux);
    let rays0 = 0.25 + 0.75 * pow(noise2(vec2f(rx, rt + i)), 1.6) + 0.45 * pow(noise2(vec2f(rx * 3.3, rt * 1.7 - dy * 2.0)), 3.0);
    var rays = rays0 + S.bp * 0.6 * pow(noise2(vec2f(rx * 7.0, t * 6.0 + i)), 3.0);   // build-up: charged crackle
    rays = mix(rays, 0.85, 0.55 * S.k + 0.3 * S.c);                                    // breakdown / chorus: smooth silk
    let dyp = max(dy, 0.0);
    let prof = smoothstep(-0.05, 0.01, dy) * exp(-dyp / hgt);
    let fringe = smoothstep(-0.02, 0.0, dy) * exp(-dyp * 30.0) * 0.9;
    // a pulse climbing the rays on every beat
    let pulse = exp(-au_sq((dyp / hgt - G.beat_phase * 2.0) * 3.0)) * (0.25 + 0.6 * G.beat) * 0.6;
    let local = 0.45 + 1.4 * spec_range(s, lo, hi);
    let lm = 0.4 * S.q + S.v + (1.0 + 0.9 * S.bp) * S.b + 1.35 * S.c + 0.7 * S.k + 0.85 * S.d;
    let level = (0.35 + 1.1 * drive) * (0.55 + 0.7 * G.energy) * (1.0 + 1.0 * G.drop) * (1.0 + 0.8 * near) * lm;
    // colour: green fringe -> teal -> violet tops, pushed to violet when the sound is bright
    let ct = clamp(dyp / (hgt * 1.8) + 0.15 * G.centroid + 0.08 * i, 0.0, 1.0);
    // colour: drop flips the palette upside down; build-up heats toward the last palette colour
    var cc = mix(pal(ct), mix(pal(1.0 - ct), vec3f(1.0, 0.9, 0.95), 0.2), S.d);
    cc = mix(cc, pal(1.0) * 1.2 + 0.1, 0.5 * S.bp);
    cc = mix(cc, pal(0.15 + 0.7 * ct) * 0.7 + vec3f(0.12, 0.1, 0.06), 0.35 * S.c);       // chorus: warmer, pastel
    let topfade = smoothstep(hgt * 4.0, hgt * 2.2, dy);   // light ends before the early-out line
    return cc * (prof * (1.0 + pulse) * topfade + fringe) * rays * local * level * 0.55;
}

fn au_wolf(l: vec2f, howl: f32) -> f32 {
    // l in wolf units (body ~0.13 long), facing +x
    var d = sd_round_box(l - vec2f(0.0, 0.055), vec2f(0.055, 0.017), 0.016);
    d = min(d, sd_segment(l, vec2f(0.04, 0.045), vec2f(0.046, 0.0)) - 0.008);
    d = min(d, sd_segment(l, vec2f(0.025, 0.045), vec2f(0.02, 0.0)) - 0.007);
    d = min(d, sd_segment(l, vec2f(-0.04, 0.05), vec2f(-0.05, 0.0)) - 0.008);
    d = min(d, sd_segment(l, vec2f(-0.03, 0.045), vec2f(-0.025, 0.0)) - 0.007);
    d = min(d, sd_segment(l, vec2f(-0.055, 0.065), vec2f(-0.095, 0.035)) - mix(0.009, 0.004, clamp((-l.x - 0.055) / 0.04, 0.0, 1.0)));
    let head = mix(vec2f(0.075, 0.085), vec2f(0.068, 0.112), howl);
    d = min(d, sd_segment(l, vec2f(0.04, 0.065), head) - 0.014);
    d = min(d, sd_circle(l - head, 0.017));
    let sdir = normalize(mix(vec2f(1.0, -0.35), vec2f(0.45, 1.0), howl));
    d = min(d, sd_segment(l, head, head + sdir * 0.032) - 0.007);
    let up = vec2f(-sdir.y, sdir.x);
    d = min(d, sd_segment(l, head - sdir * 0.006 + up * 0.01, head - sdir * 0.012 + up * 0.03) - 0.004);
    return d;
}

// everything above the horizon; also sampled mirrored for the lake
fn au_scene(q: vec2f) -> vec3f {
    let t = G.time;
    let A = G.aspect;
    let px = 2.0 / G.res.y;
    let hh = q.y - AU_H;
    let S = au_secs();

    var col = mix(vec3f(0.012, 0.030, 0.055), vec3f(0.003, 0.006, 0.020), smoothstep(0.0, 1.2, hh));
    col += G.pal1.rgb * 0.03 * exp(-hh * 5.0);
    col += vec3f(0.35, 0.2, 0.3) * 0.12 * S.c * exp(-hh * 2.5);            // chorus: warm dawn glow on the horizon
    col += vec3f(0.01, 0.015, 0.03) * S.k;

    // Milky Way: a diagonal band of dust and dense stars with dark lanes
    let mwd = normalize(vec2f(1.0, 0.42));
    let mwn = vec2f(-mwd.y, mwd.x);
    let v = dot(q - vec2f(0.0, 0.45), mwn);
    let band = exp(-v * v * 9.0);
    var mw = 0.0;
    if (band > 0.02) {
        let dust = fbm2(q * 3.0 + vec2f(3.0, 1.0), 4);
        let lanes = smoothstep(0.45, 0.7, fbm2(q * 6.0 + vec2f(9.0, 2.0), 3)) * exp(-v * v * 40.0);
        mw = band * (0.5 + dust) * (1.0 - 0.7 * lanes);
        col += mix(vec3f(0.08, 0.07, 0.10), vec3f(0.10, 0.12, 0.18), dust) * mw * 0.45 * (1.0 + 1.3 * S.q + 0.6 * S.k);
    }

    // stars: twinkle on the hats, extra-dense inside the Milky Way
    let sg = q * 40.0;
    let sc = floor(sg);
    let sh = hash21(sc);
    let sd = length(fract(sg) - (hash22(sc) * 0.4 + 0.3));
    let tw = 0.6 + 0.4 * sin(t * (1.0 + 4.0 * hash21(sc + 7.0)) + sh * 60.0) + G.hat * 0.8 * step(0.6, hash21(sc + 3.0));
    var stars = smoothstep(0.8 - 0.35 * mw, 1.0, sh) * tw * exp(-sd * sd * 170.0) * 1.3;
    let bg = q * 8.0;
    let bc = floor(bg);
    let bo = fract(bg) - (hash22(bc + 5.0) * 0.6 + 0.2);
    let bh = hash21(bc + 31.0);
    stars += step(0.85, bh) * (0.7 + 0.3 * sin(t * 1.3 + bh * 40.0) + 0.5 * G.snare) * (exp(-dot(bo, bo) * 1500.0) * 2.0
        + (exp(-abs(bo.x) * 120.0) * exp(-abs(bo.y) * 12.0) * smoothstep(0.2, 0.08, abs(bo.y)) + exp(-abs(bo.y) * 120.0) * exp(-abs(bo.x) * 12.0) * smoothstep(0.2, 0.08, abs(bo.x))) * 0.3);
    col += vec3f(0.85, 0.92, 1.0) * stars * smoothstep(0.05, 0.3, hh) * (1.0 + 0.8 * S.q + 0.4 * S.k - 0.4 * S.d);

    // aurora curtains: back (treble) -> mid -> front (bass)
    var aur = vec3f(0.0);
    aur += au_curtain(q, 2.0, G.high, 60.0, 92.0);
    aur += au_curtain(q, 1.0, G.mid, 30.0, 62.0);
    aur += au_curtain(q, 0.0, G.bass, 2.0, 34.0);
    if (S.c > 0.01) { aur += au_curtain(q, 3.0, 0.3 + 0.6 * G.mid, 20.0, 80.0) * S.c; }   // chorus: a fourth, high curtain
    col += aur / (1.0 + 0.4 * luma(aur));
    let aglow = G.pal0.rgb * (0.4 + 0.8 * G.energy + G.drop) * 0.06;   // aurora light on the scene
    col += aglow * exp(-hh * 2.5);

    // build-up: a column of light climbs from the horizon, narrows and brightens; snares flash the sky
    if (S.b > 0.001) {
        let w2 = 0.0015 + 0.04 * (1.0 - S.bp);
        col += mix(pal(0.7), vec3f(1.0), 0.4 * S.bp) * exp(-q.x * q.x / w2) * smoothstep(0.0, 0.05, hh) * exp(-hh * 0.7)
            * S.bp * (0.5 + 0.8 * G.snare + 0.3 * G.beat) * 0.9;
        col += pal(0.8) * G.snare * S.b * (0.04 + 0.12 * S.bp) * exp(-hh * 0.6);
    }
    // chorus: wide soft sunburst fanning up from behind the mountains
    if (S.c > 0.001) {
        let cr = q - vec2f(0.0, AU_H - 0.1);
        let ang = atan2(cr.y, cr.x);
        let fan = pow(0.5 + 0.5 * sin(ang * 9.0 + t * 0.15), 2.0) * smoothstep(0.0, 0.3, hh);
        col += mix(pal(0.3), vec3f(1.0, 0.85, 0.8), 0.4) * fan * exp(-length(cr) * 0.9) * S.c * (0.12 + 0.1 * G.beat);
    }
    // drop only: a hard-rayed corona at the zenith that spins, plus a shockwave ring on every kick
    if (S.d > 0.001) {
        let dc = q - vec2f(0.0, 0.62);
        let dr = length(dc);
        let ang = atan2(dc.y, dc.x);
        let rays = pow(abs(sin(ang * 14.0 + t * 1.6)), 8.0) * exp(-dr * 1.4);
        let ring = exp(-au_sq((dr - (1.0 - G.kick) * 1.6) * 12.0)) * G.kick;
        col += mix(pal(1.0), vec3f(1.0), 0.35) * (rays * (0.15 + 0.3 * G.drop + 0.2 * G.bass) + ring * 0.4 + exp(-dr * 6.0) * 0.2 * (0.3 + G.kick)) * S.d * smoothstep(-0.05, 0.1, hh);
    }
    // breakdown: spirit lights drift up, each one a note (key glow)
    if (S.k > 0.001) {
        let no = 7 + 3 * i32(G.quality);
        for (var j = 0; j < no; j++) {
            let fj = f32(j);
            let h1 = hash11(fj * 3.7 + 1.0);
            let kk = key(28 + (j * 5) % 40);
            let ox = (hash11(fj * 1.9 + 4.0) * 2.0 - 1.0) * A * 0.9 + sin(t * 0.3 + fj) * 0.06;
            let oy = AU_H + 0.1 + fract(t * (0.012 + 0.01 * h1) + h1) * 1.0;
            let od = length(q - vec2f(ox, oy));
            col += mix(pal(h1), vec3f(1.0), 0.4) * (0.0008 / (od * od + 0.0006) * (0.25 + 1.6 * kk + 0.6 * G.mid)) * S.k * smoothstep(0.0, 0.08, hh);
        }
    }

    // shooting stars: one on some beats, and one from every click
    let bseed = G.beat_count;
    if (hash11(bseed * 1.7) > 0.4 + 0.5 * S.q + 0.3 * S.k && G.beat > 0.01) {
        let pr = 1.0 - G.beat;
        let s0 = vec2f((hash11(bseed) * 1.6 - 0.6) * A, 0.55 + 0.4 * hash11(bseed + 3.0));
        let sdir = normalize(vec2f(-1.0, -0.35 - 0.3 * hash11(bseed + 9.0)));
        let head = s0 + sdir * pr * 0.9;
        let ds = sd_segment(q, head, head - sdir * 0.3 * (0.3 + pr));
        col += vec3f(0.85, 1.0, 0.95) * (exp(-ds * ds * 150000.0) * 1.6 + 0.0015 / (ds + 0.004))
            * clamp(1.0 - length(q - head) * 3.0, 0.0, 1.0) * G.beat;
    }
    if (G.click_age < 2.5) {
        let cp = au_cp(G.click_pos);
        let ca = G.click_age;
        let dc = length(q - cp);
        // burst: flash, expanding ring, rays
        let ang = atan2(q.y - cp.y, q.x - cp.x);
        let rays = pow(abs(sin(ang * 6.0 + ca)), 30.0) * exp(-dc * 6.0);
        col += mix(G.pal0.rgb, vec3f(1.0), 0.5) * (exp(-dc * 30.0) * 2.0 * exp(-ca * 4.0) + rays * exp(-ca * 2.0)
            + exp(-au_sq((dc - ca * 0.5) * 40.0)) * exp(-ca * 1.5));
        let sdir = normalize(vec2f(1.0, -0.5));
        let head = cp + sdir * ca * 0.8;
        let ds = sd_segment(q, head, cp + sdir * max(ca * 0.8 - 0.35, 0.0));
        col += vec3f(0.9, 1.0, 0.95) * (exp(-ds * ds * 100000.0) + 0.002 / (ds + 0.004)) * clamp(1.5 - ca, 0.0, 1.0);
    }

    if (hh < 1.05) {
        // far mountain range: ridged peaks, snow, rim light from the aurora
        let rf = AU_H + 0.9 * au_ridge(q.x * 0.75 + 2.0, 1.0) - 0.12;
        let inm = smoothstep(rf + px, rf - px, q.y);
        if (inm > 0.0) {
            let depth = rf - q.y;
            // fake face normal: sample the ridge sideways along a diagonal so faces and gullies slope down
            let xs = q.x * 0.75 + 2.0 + depth * 0.9 * (0.6 + 0.4 * noise2(q * 9.0));
            let slope = (au_ridge(xs + 0.01, 1.0) - au_ridge(xs, 1.0)) / 0.01;
            let snowl = AU_H + 0.17 + 0.08 * noise2(vec2f(q.x * 6.0, 2.0));
            let snow = smoothstep(snowl - 0.01, snowl + 0.03, q.y) * (0.6 + 0.4 * noise2(q * vec2f(30.0, 60.0)));
            let lit = clamp(0.5 - slope * 0.35, 0.0, 1.0);
            let rock = vec3f(0.018, 0.025, 0.045);
            let snc = vec3f(0.30, 0.38, 0.50) * (0.35 + 0.65 * lit) + G.pal0.rgb * 0.10 * (0.5 + G.energy);
            var mc = mix(rock, snc * (0.5 + 0.5 * exp(-depth * 3.0)), snow);
            mc += G.pal0.rgb * exp(-depth / (px * 4.0)) * (0.25 + 0.6 * G.energy + G.drop) * 0.6;   // rim light
            mc = mix(mc, col * 0.6 + vec3f(0.02, 0.04, 0.07), 0.25 * smoothstep(0.2, 0.0, hh));     // haze at the foot
            col = mix(col, mc, inm);
        }
        // near range, darker
        let rn = AU_H + 0.42 * au_ridge(q.x * 1.1 + 9.0, 7.0) - 0.07;
        let inn = smoothstep(rn + px, rn - px, q.y);
        if (inn > 0.0) {
            let depth = rn - q.y;
            let snow = smoothstep(AU_H + 0.09, AU_H + 0.13, q.y + 0.02 * noise2(vec2f(q.x * 12.0, 5.0))) * (0.5 + 0.5 * noise2(q * vec2f(40.0, 80.0)));
            var mc = mix(vec3f(0.010, 0.014, 0.026), vec3f(0.16, 0.21, 0.30) + G.pal0.rgb * 0.06, snow * 0.8);
            mc += G.pal0.rgb * exp(-depth / (px * 3.0)) * (0.2 + 0.5 * G.energy) * 0.5;
            col = mix(col, mc, inn);
        }

        // snowy shore strip
        let shore = AU_H + 0.012 + 0.006 * noise2(vec2f(q.x * 8.0, 1.0));
        col = mix(col, vec3f(0.16, 0.20, 0.27) + aglow * 2.0, smoothstep(shore + px, shore - px, q.y));

        // cabin with a warm flickering window and chimney smoke
        let cx = -0.52 * A;
        let cb = vec2f(cx, AU_H + 0.012);
        let cl = q - cb;
        let fl = 0.75 + 0.15 * noise2(vec2f(t * 7.0, 1.0)) + 0.1 * sin(t * 17.0) + 0.35 * G.mid;
        let warm = vec3f(1.0, 0.55, 0.2);
        // smoke (behind the cabin)
        let ch = vec2f(0.035, 0.105);
        let sl = cl - ch;
        if (sl.y > 0.0 && sl.y < 0.5) {
            let sx = sl.x - sl.y * sl.y * 0.9 - sin(sl.y * 9.0 - t * 0.8) * 0.012 * sl.y * 4.0;
            let w = 0.008 + sl.y * 0.12;
            let dens = fbm2(vec2f(sx * 18.0, sl.y * 9.0 - t * 0.9), 3);
            let sm = exp(-sx * sx / (w * w)) * smoothstep(0.5, 0.05, sl.y) * smoothstep(0.0, 0.02, sl.y) * (0.4 + dens);
            col = mix(col, vec3f(0.10, 0.13, 0.17) + aglow * 1.5, clamp(sm * 0.55, 0.0, 1.0));
        }
        let body = sd_box(cl - vec2f(0.0, 0.03), vec2f(0.06, 0.03));
        let rp = cl - vec2f(0.0, 0.06);
        let roof = max(abs(rp.x) * 0.62 + rp.y - 0.045, -rp.y);
        let chim = sd_box(cl - vec2f(0.035, 0.088), vec2f(0.007, 0.018));
        let cab = min(min(body, roof), chim);
        let rsnow = smoothstep(-0.012, -0.004, roof) * step(0.0, rp.y);
        var cc = vec3f(0.025, 0.017, 0.014) + vec3f(0.02, 0.012, 0.008) * step(0.5, fract(cl.y * 120.0));
        cc = mix(cc, vec3f(0.35, 0.42, 0.52) + aglow * 2.0, rsnow);
        let win = sd_box(cl - vec2f(-0.022, 0.028), vec2f(0.011, 0.01));
        let winm = fill(win, px);
        let mull = step(abs(cl.x + 0.022), 0.0012) + step(abs(cl.y - 0.028), 0.0012);
        cc = mix(cc, warm * 1.6 * fl * (1.0 - 0.7 * clamp(mull, 0.0, 1.0)), winm);
        col = mix(col, cc, fill(cab, px));
        col += warm * fl * 0.012 / (max(win, 0.0) + 0.012) * 0.35 * (1.0 - winm);
        // window light on the snow in front of the cabin
        col += warm * fl * 0.25 * exp(-au_sq((q.x - cx + 0.022) * 12.0)) * exp(-abs(q.y - AU_H - 0.005) * 120.0);

        // pines on the shore (tiered silhouettes), cleared around the cabin and the rock
        let tx = q.x * 26.0;
        let tc = floor(tx);
        for (var j = -1; j <= 1; j++) {
            let c = tc + f32(j);
            let hsh = hash11(c * 1.31);
            let ctr = (c + 0.5 + (hash11(c + 2.0) - 0.5) * 0.6) / 26.0;
            let clear = smoothstep(0.08, 0.12, abs(ctr - cx)) * smoothstep(0.08, 0.13, abs(ctr - 0.62 * A));
            if (hsh > 0.25 && clear > 0.5) {
                let th = (0.05 + 0.08 * hash11(c + 5.0)) * (0.7 + 0.3 * smoothstep(0.0, 0.6, abs(ctr)));
                let ty = (q.y - AU_H - 0.008) / th;
                if (ty > -0.05 && ty < 1.0) {
                    let tier = fract(ty * 4.0);
                    let wdt = (1.0 - ty) * 0.022 * (0.6 + 0.4 * tier) + 0.002;
                    let dd = abs(q.x - ctr) - wdt;
                    let tm = fill(dd, px);
                    let tsnow = smoothstep(0.75, 0.95, tier) * 0.6;
                    col = mix(col, vec3f(0.006, 0.012, 0.016) + vec3f(0.16, 0.2, 0.26) * tsnow + G.pal0.rgb * 0.06 * exp(min(dd, 0.0) / (px * 2.0)), tm);
                }
            }
        }

        // the wolf on its rock: howls (head up, sound rings) on the drop, and now and then by itself
        let wx = 0.62 * A;
        let rk = q - vec2f(wx, AU_H);
        let rock = length(rk * vec2f(1.0, 1.5)) - 0.09 + 0.012 * noise2(rk * 40.0);
        let rkm = fill(rock, px);
        col = mix(col, vec3f(0.02, 0.025, 0.04) + vec3f(0.2, 0.25, 0.33) * smoothstep(0.03, 0.045, rk.y) * 0.6 + G.pal0.rgb * 0.15 * exp(min(rock, 0.0) / (px * 3.0)) * step(0.0, rk.y), rkm);
        let idle = smoothstep(0.0, 0.1, sin(t * 0.25)) * smoothstep(0.98, 0.9, fract(t * 0.25 / TAU)) * step(0.85, fract(t * 0.25 / TAU));
        let howl = clamp(max(max(G.drop * 1.6, idle), S.bp * 0.7 + S.d * 0.3 * step(0.3, G.energy)), 0.0, 1.0);
        let wl = (q - vec2f(wx - 0.01, AU_H + 0.055)) / 1.2;
        let wd = au_wolf(wl, howl) * 1.2;
        col = mix(col, vec3f(0.008, 0.01, 0.016) + G.pal0.rgb * 0.35 * exp(min(wd, 0.0) / px) * (0.3 + G.energy) * step(0.06, q.y - AU_H - 0.02 + 0.0), fill(wd, px));
        let mouth = vec2f(wx - 0.01, AU_H + 0.055) + vec2f(0.09, 0.115) * 1.2 + vec2f(0.0, 0.03) * howl;
        let mr = length(q - mouth);
        for (var j = 0; j < 3; j++) {
            let rr = fract(t * 0.7 + f32(j) / 3.0) * 0.35;
            col += G.pal2.rgb * exp(-au_sq((mr - rr) * 120.0)) * (1.0 - rr / 0.35) * howl * 0.5 * smoothstep(-0.25, -0.05, q.y - mouth.y);
        }
    }
    return col;
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let q = centered(fc);
    let t = G.time;
    let A = G.aspect;
    let px = 2.0 / G.res.y;
    var col = vec3f(0.0);

    if (q.y >= AU_H) {
        col = au_scene(q);
    } else {
        // mirror-still lake: gentle ripples (stronger on kicks), a click drops a ripple
        let d = AU_H - q.y;
        let wz = 1.0 / (d + 0.04);
        let wp = vec2f(q.x * wz * 0.5, wz);
        let rn = noise2(vec2f(wp.x * 1.5, wp.y * 2.5 - t * 0.3)) - 0.5;
        let rn2 = noise2(vec2f(wp.x * 4.0 + 3.0, wp.y * 7.0 - t * 0.5)) - 0.5;
        var dist = vec2f(rn2 * 0.4, rn + rn2) * (0.003 + 0.004 * d) * (1.0 + 2.5 * G.kick + G.bass);
        var rip = 0.0;
        let cp = au_cp(G.click_pos);
        if (G.click_age < 6.0 && cp.y < AU_H) {
            let rel = vec2f(q.x - cp.x, (q.y - cp.y) * 3.5);
            let rl = length(rel) + 1e-4;
            for (var j = 0; j < 3; j++) {
                let rd = rl - max(G.click_age * 0.3 - f32(j) * 0.07, 0.0);
                let ring = exp(-rd * rd * 2000.0) * exp(-G.click_age * 0.8) * step(f32(j) * 0.07, G.click_age * 0.3);
                rip += ring;
                dist += rel / rl * ring * 0.02;
            }
        }
        let rq = vec2f(q.x + dist.x, AU_H + d + dist.y + 0.002);
        let refl = au_scene(rq);
        let fres = mix(0.8, 0.5, smoothstep(0.0, 0.6, d));
        col = vec3f(0.004, 0.010, 0.020) + refl * fres * vec3f(0.85, 0.95, 1.0);
        col += G.pal1.rgb * rip * 0.3;
        // thin ice line along the shore
        col += vec3f(0.3, 0.38, 0.45) * exp(-d / px * 0.6) * 0.4;
        // faint ice sheen in the foreground
        col += vec3f(0.05, 0.07, 0.09) * smoothstep(0.35, 0.7, d) * (0.5 + 0.5 * noise2(wp * vec2f(3.0, 1.0)));
    }

    // snowfall: three depth layers, wind from the mouse, flakes glint on the hats
    let wind = 0.15 + 0.6 * (G.mouse.x - 0.5) * G.mouse_on + 0.15 * sin(t * 0.2);
    let S = au_secs();
    let nl = 2 + i32(G.quality > 0.5);
    for (var j = 0; j < nl; j++) {
        let fj = f32(j);
        let sc = 9.0 + fj * 9.0;
        let sp = (0.12 + 0.06 / (fj + 1.0)) * (1.0 + 0.6 * G.energy);
        let p = q * sc + vec2f(wind * t * sc * 0.25 + sin(q.y * 3.0 + t + fj) * 0.3, t * sp * sc);
        let c = floor(p);
        let h = hash21(c + fj * 17.0);
        if (h > 0.55 + 0.15 * S.q + 0.25 * S.k - 0.1 * S.d) {
            let o = hash22(c + fj * 5.0) * 0.6 + 0.2;
            let dd = length(fract(p) - o) / sc;
            let r = (0.007 - fj * 0.002) * (0.6 + 0.6 * h);
            let br = (0.35 - fj * 0.08) * (1.0 + 1.5 * G.hat * step(0.85, h) + 1.5 * S.c * step(0.8, h) + 2.0 * S.d * step(0.7, h)) * (1.0 - 0.4 * S.q);
            col += vec3f(0.85, 0.9, 1.0) * br * smoothstep(r, r * 0.3, dd);
        }
    }

    let vg = 1.0 - 0.35 * pow(length(uv - 0.5) * 1.3, 2.5);
    col *= vg;
    col += (hash21(fc + fract(t) * 91.0) - 0.5) * 0.012;
    return vec4f(col, 1.0);
}
