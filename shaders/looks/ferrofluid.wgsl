// name: Ferrofluid
// palette: #ff3a6e #8a3cff #19d6ff
// Glossy black magnetic liquid on a mirror floor in a studio. Spikes grow from the spectrum,
// kicks stab them out, the sub swells the blob, iron filings line up on the floor, dashed field
// lines orbit, chrome droplets circle and get flung off. The magnet follows the mouse.

fn ff_smin(a: f32, b: f32, k: f32) -> f32 {
    let h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// signed distance of the blob + spikes
fn ff_sdf(p: vec2f, M: vec2f, R: f32, amp: f32, mdir: vec2f, mpull: f32) -> f32 {
    let q = p - M;
    let a = atan2(q.y, q.x);
    let wob = 0.025 * sin(a * 5.0 + G.time * 2.0) * (0.3 + 2.5 * G.snare) + 0.01 * sin(a * 9.0 - G.time * 3.1);
    var d = length(q * vec2f(0.9, 1.08)) - R * (1.0 + wob);
    let N = 30.0;
    let c0 = floor(a / TAU * N);
    for (var k = -1; k <= 1; k++) {
        let ci = c0 + f32(k) + 0.5;
        let ac = ci / N * TAU + 0.05 * sin(G.time * 0.8 + ci * 1.7);
        let dir = vec2f(cos(ac), sin(ac));
        let fromtop = abs(atan2(dir.x, dir.y)) / PI;   // 0 = straight up .. 1 = down
        let sv = spec(clamp(fromtop * 1.5, 0.0, 1.0) * 0.8);
        let lean = 1.0 + mpull * max(dot(dir, mdir), 0.0);
        let L = (0.04 + sv * 0.5) * amp * lean * (0.8 + 0.4 * hash11(ci + 3.0)) * smoothstep(0.85, 0.55, fromtop);
        let B = M + dir * R * 0.75;
        let ba = dir * (R * 0.25 + L);
        let h = clamp(dot(p - B, ba) / dot(ba, ba), 0.0, 1.0);
        let w = (0.04 + 0.02 * sv) * pow(1.0 - h, 1.5) + 0.0012;
        d = ff_smin(d, length(p - B - ba * h) - w, 0.05);
    }
    return d;
}

// studio environment seen in a reflection direction
fn ff_env(rv: vec3f) -> vec3f {
    var c = vec3f(0.004, 0.004, 0.007);
    let warm = mix(vec3f(0.8, 0.9, 1.2), vec3f(1.25, 1.05, 0.85), G.centroid);
    c += warm * 1.6 * smoothstep(0.5, 0.8, rv.y) * smoothstep(0.7, 0.35, abs(rv.x)) * (0.5 + 0.5 * G.energy + 0.6 * G.drop);
    c += pal(0.0) * 2.2 * smoothstep(0.4, 0.85, -rv.x) * smoothstep(-0.6, 0.2, rv.y) * (0.45 + 1.8 * G.snare + G.drop);
    c += pal(1.0) * 2.2 * smoothstep(0.4, 0.85, rv.x) * smoothstep(-0.6, 0.2, rv.y) * (0.45 + 1.2 * G.hat + 0.6 * G.mid + G.drop);
    c += pal(0.5) * 0.12 * smoothstep(0.1, 0.8, -rv.y);
    c += vec3f(0.25) * exp(-abs(rv.y + 0.05) * 14.0) * (0.3 + 0.7 * G.energy);
    return c;
}

// shaded blob: rgb + coverage
fn ff_blob(p: vec2f, M: vec2f, R: f32, amp: f32, mdir: vec2f, mpull: f32, px: f32, lp: vec2f) -> vec4f {
    if (length(p - M) > R * 1.15 + (0.05 + 0.6 * amp) * (1.0 + mpull)) { return vec4f(0.0); }
    let d = ff_sdf(p, M, R, amp, mdir, mpull);
    if (d > px * 2.0) { return vec4f(0.0, 0.0, 0.0, 0.0); }
    let e = 0.004;
    let gx = ff_sdf(p + vec2f(e, 0.0), M, R, amp, mdir, mpull) - d;
    let gy = ff_sdf(p + vec2f(0.0, e), M, R, amp, mdir, mpull) - d;
    let g = normalize(vec2f(gx, gy) + 1e-6);
    let di = max(-d, 0.0);
    let hz = sqrt(clamp(di / 0.28, 0.0, 1.0));
    var n = normalize(vec3f(g * (1.0 - hz) * 1.4, hz * 0.9 + 0.08));
    // snare ripples sliding over the skin
    let rq = p - M;
    n = normalize(n + vec3f(sin(length(rq) * 70.0 - G.time * 12.0) * 0.08 * G.snare * hz, 0.0, 0.0));
    let rv = reflect(vec3f(0.0, 0.0, -1.0), n);
    let fres = 0.06 + 0.94 * pow(1.0 - clamp(n.z, 0.0, 1.0), 4.0);
    var c = ff_env(rv) * (0.15 + fres) + vec3f(0.006, 0.005, 0.009);
    // mouse light (the magnet's work lamp)
    let L = normalize(vec3f(lp - p, 0.7));
    let sp = pow(max(dot(reflect(-L, n), vec3f(0.0, 0.0, 1.0)), 0.0), 70.0);
    c += vec3f(1.5, 1.45, 1.4) * sp * (0.5 + 0.8 * G.energy);
    // hats: sparkle on spike tips
    c += vec3f(1.2, 1.2, 1.4) * G.hat * step(0.985, hash21(floor(p * 220.0))) * (1.0 - hz);
    return vec4f(c, fill(d, px));
}

// chrome droplets orbiting the magnet. front = 1 draws the half in front of the blob
fn ff_drops(p: vec2f, M: vec2f, front: bool, px: f32, fling: f32) -> vec4f {
    var acc = vec4f(0.0);
    let cnt = 8 + i32(G.quality * 4.0);
    for (var i = 0; i < cnt; i++) {
        let fi = f32(i);
        let h = hash11(fi * 3.7 + 1.0);
        let ph = G.time * (0.35 + 0.35 * h) * select(1.0, -1.0, i % 3 == 0) + fi * 2.39 + G.travel * 0.05;
        let depth = sin(ph);
        if ((depth < 0.0) != front) { continue; }
        let rho = 0.48 + 0.3 * h + fling * (0.5 + h);
        let c = M + vec2f(cos(ph) * rho * G.aspect * 0.55, 0.12 + 0.18 * hash11(fi + 9.0) + depth * rho * 0.18 + 0.05 * sin(G.time * 1.3 + fi));
        let rad = (0.01 + 0.016 * hash11(fi + 4.0)) * (1.0 - 0.3 * depth) * (1.0 + 0.4 * G.kick);
        let q = (p - c) / rad;
        let l2 = dot(q, q);
        if (l2 > 1.6) { continue; }
        let n = normalize(vec3f(q, sqrt(max(1.0 - l2, 0.0))));
        let rv = reflect(vec3f(0.0, 0.0, -1.0), n);
        var col = ff_env(rv) * 0.9 + vec3f(0.03);
        col += vec3f(1.6) * pow(max(dot(n, normalize(vec3f(-0.4, 0.6, 0.7))), 0.0), 40.0);
        let cov = fill(length(p - c) - rad, px);
        acc = vec4f(mix(acc.rgb, col, cov), max(acc.a, cov));
    }
    return acc;
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let t = G.time;
    let asp = G.aspect;
    let pulse = pow(1.0 - G.beat_phase, 2.5);
    var p = centered(fc);
    p = p * (1.0 - 0.025 * G.kick - 0.05 * G.drop);
    let px = 2.0 / G.res.y;

    let H = 0.14;          // horizon
    let fy = -0.32;        // contact line of the blob on the floor
    let sub = band_avg(0, 5);
    let R = 0.38 * (1.0 + 0.2 * sub + 0.04 * pulse + 0.02 * sin(t * 1.1));
    let mpos = (G.mouse - 0.5) * vec2f(2.0 * asp, -2.0);
    let M = vec2f(clamp(mpos.x * 0.18, -0.3, 0.3), fy + R * 0.5);
    let tom = mpos - M;
    let mdir = tom / max(length(tom), 1e-3);
    let clickp = (G.click_pos - 0.5) * vec2f(2.0 * asp, -2.0);
    let clickb = exp(-G.click_age * 3.0);
    let mpull = G.mouse_on * 0.7 + clickb * 1.5;
    let amp = 0.7 + 0.5 * G.energy + 1.3 * G.kick + 0.4 * pulse * G.energy + 1.4 * G.drop;
    let lp = select(vec2f(-0.6, 0.9), mpos, G.mouse_on > 0.5);
    let fling = G.drop * 1.3 + G.kick * 0.06;

    // ---------- studio backdrop ----------
    var col = vec3f(0.006, 0.006, 0.01) + vec3f(0.02, 0.018, 0.03) * smoothstep(-0.2, 1.0, p.y);
    let haze = fbm2(p * 1.8 + vec2f(t * 0.04, 0.0), 4);
    col += pal(0.0) * 0.12 * exp(-abs(p.x + asp) * 1.6) * (0.5 + haze) * (0.6 + 1.5 * G.snare);
    col += pal(1.0) * 0.12 * exp(-abs(p.x - asp) * 1.6) * (0.5 + haze) * (0.6 + 1.2 * G.hat);
    // light panels at the sides
    let lpan = sd_round_box(vec2f(abs(p.x) - asp * 0.9, p.y - 0.35), vec2f(0.05, 0.45), 0.02);
    let pcol = select(pal(1.0) * (0.8 + 1.2 * G.hat), pal(0.0) * (0.8 + 1.8 * G.snare), p.x < 0.0);
    col += pcol * (fill(lpan, px) * 1.2 + glow(lpan, 0.05) * 0.3) * (0.6 + 0.6 * G.energy);
    // top softbox
    let sb = sd_round_box(p - vec2f(0.0, 0.92), vec2f(0.7, 0.04), 0.02);
    col += vec3f(1.2, 1.15, 1.1) * (fill(sb, px) + glow(sb, 0.04) * 0.25) * (0.5 + 0.5 * G.energy + G.drop);
    // dust motes in the light
    let dm = hash21(floor((p + vec2f(0.0, t * 0.02)) * 90.0));
    col += vec3f(0.6) * step(0.996, dm) * (0.3 + G.high) * smoothstep(-0.3, 0.6, p.y);

    // ---------- floor: mirror + iron filings ----------
    if (p.y < H) {
        let dy = H - p.y;
        let Z = 0.6 / dy;
        let X = p.x * Z;
        let Zm = 0.6 / (H - fy);
        let fm = vec2f(M.x * Zm, Zm);
        let fp = vec2f(X, Z);
        var fl = vec3f(0.004, 0.004, 0.007) + pal(0.5) * 0.03 * exp(-length(fp - fm) * 0.8);
        // click ripple on the floor
        let cdy = max(H - clickp.y, 0.05);
        let cf = vec2f(clickp.x * 0.6 / cdy, 0.6 / cdy);
        let rip = sin(length(fp - cf) * 25.0 - G.click_age * 18.0) * exp(-G.click_age * 1.5) * exp(-length(fp - cf) * 1.2);
        let wav = sin(length(fp - fm) * 30.0 - t * 8.0) * 0.004 * (0.3 + G.bass) + rip * 0.02;
        // mirror reflection of blob + drops
        if (p.y < fy) {
            let rp = vec2f(p.x + wav, 2.0 * fy - p.y + wav);
            let rb = ff_blob(rp, M, R, amp, mdir, mpull, px * 1.5, lp);
            let rd = ff_drops(rp, M, true, px * 1.5, fling);
            var refl = mix(vec3f(0.0), rb.rgb, rb.a);
            refl = mix(refl, rd.rgb, rd.a);
            fl += refl * 0.55 * exp(-(fy - p.y) * 2.5);
        }
        // reflections of the side panels and softbox
        fl += pcol * 0.12 * exp(-abs(abs(p.x) - asp * 0.9) * 20.0) * exp(-dy * 3.0);
        // iron filings line up with the field
        let cs = 0.05;
        let cid = floor(fp / cs);
        let jit = hash22(cid);
        let cc = (cid + 0.25 + 0.5 * jit) * cs;
        let rel = cc - fm;
        let dist = length(rel);
        let ang = atan2(rel.y, rel.x) + 0.6 * G.mid * sin(t * 0.7) / (1.0 + dist) + (jit.x - 0.5) * (0.25 + 2.5 * G.kick / (1.0 + dist * 2.0));
        let lq = rot(-ang) * (fp - cc);
        let len = cs * (0.25 + 0.35 / (1.0 + dist * 1.5)) * (1.0 + 0.6 * G.kick);
        let fd = sd_box(lq, vec2f(len, cs * 0.05));
        let fpx = px * 0.6 / (dy * dy);
        let fcov = fill(fd, fpx) * smoothstep(9.0, 3.0, Z) * step(0.25, jit.y);
        let glint = pow(abs(sin(ang * 2.0 + p.x * 3.0 + t * 0.3)), 8.0);
        fl = mix(fl, vec3f(0.05, 0.05, 0.06) + mix(pal(0.0), pal(1.0), step(0.0, rel.x)) * glint * 0.7 * (0.4 + G.energy), fcov * 0.85);
        // horizon sheen
        fl += vec3f(0.12, 0.12, 0.15) * exp(-dy * 25.0);
        col = fl;
    }

    // ---------- dashed field lines around the magnet ----------
    let fq = (p - M) / 1.0;
    let rr = length(fq);
    let s2 = (fq.x * fq.x) / max(rr * rr, 1e-4);
    let fval = log(max(rr / max(s2, 1e-3), 1e-3));
    let lv = fval * 2.6 - G.beat_count * 0.0;
    let fw = fwidth(lv);
    let lid = floor(lv + 0.5);
    let line = smoothstep(fw * 1.8, fw * 0.3, abs(fract(lv + 0.5) - 0.5));
    let th = atan2(fq.x, fq.y);
    let dash = step(0.45, fract(th * 16.0 * sign(fq.x) - t * (0.3 + 1.5 * G.mid) - lid * 0.37));
    let fvis = line * dash * smoothstep(0.25, 0.45, rr) * exp(-rr * 0.9) * step(fy, p.y) * step(lid, 3.5) * step(-0.5, lid);
    col += palc(lid * 0.3 + 0.1) * fvis * (0.25 + 0.9 * G.energy + 0.8 * pulse * G.energy);

    // ---------- drops behind, blob, drops in front ----------
    if (p.y > fy - px) {
        let db = ff_drops(p, M, false, px, fling);
        col = mix(col, db.rgb, db.a);
        // contact shadow / glow under the blob
        let b = ff_blob(p, M, R, amp, mdir, mpull, px, lp);
        col = mix(col, b.rgb, b.a * smoothstep(fy - px, fy + px, p.y));
        let df = ff_drops(p, M, true, px, fling);
        col = mix(col, df.rgb, df.a);
    }
    col += pal(0.5) * 0.25 * exp(-abs(p.y - fy) * 60.0) * exp(-abs(p.x - M.x) * 2.5) * (0.3 + G.bass);

    // ---------- drop: flash ----------
    col += vec3f(1.0, 0.97, 1.0) * pow(G.drop, 4.0) * 0.8;
    col += pal(0.5) * exp(-abs(length(p - M) - (1.0 - G.drop) * 2.4) * 12.0) * G.drop * 1.2;

    // light trails for the droplets
    col = max(col, prev(uv) * 0.55);

    col *= 1.0 - 0.4 * pow(length(uv - 0.5) * 1.3, 2.5);
    col += (hash21(fc + fract(t) * 37.0) - 0.5) * 0.01;
    return vec4f(col, 1.0);
}
