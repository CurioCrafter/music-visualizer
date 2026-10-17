// name: Pulse Ring
// palette: #1ee0ff #8b3dff #ff2d7a
// A reactor core in a nebula: spectrum spike crown, live oscilloscope ring, segmented arc rings
// spinning on different bands, kick shockwaves, orbiting satellites with trails, a particle vortex
// spiralling into the core and an anamorphic flare on the beat. Mouse tilts the reactor.

fn pr_ring(r: f32, rad: f32, w: f32) -> f32 {
    let d = abs(r - rad);
    return smoothstep(w, 0.0, d);
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let t = G.time;
    let asp = G.aspect;
    let bp = G.beat_phase;
    let pulse = pow(1.0 - bp, 3.0);
    let kick = G.kick;
    let drop = G.drop;
    let en = G.energy;
    let sub = band_avg(0, 5);
    let p0 = centered(fc);
    let p = p0 * (1.0 - 0.03 * kick - 0.06 * drop);
    let px = 2.0 / G.res.y;

    // ---------- reactor frame (mouse tilts and offsets it) ----------
    let mpos = (G.mouse - 0.5) * vec2f(2.0 * asp, -2.0);
    let mon = G.mouse_on;
    let C = mpos * 0.18 * mon;
    let tilt = 0.82 + 0.06 * sin(t * 0.3) - 0.3 * mon * (G.mouse.y - 0.5);
    let roll = 0.08 * sin(t * 0.21) + 0.25 * mon * (G.mouse.x - 0.5);
    var q = rot(roll) * (p - C);
    q.y = q.y / tilt;
    let r = length(q);
    let a = atan2(q.y, q.x);
    let am = abs(atan2(q.x, q.y)) / PI;   // 0 at top .. 1 at bottom, mirrored, no seam

    // ---------- nebula + stars (screen space) ----------
    let np = rot(t * 0.015) * p0;
    let n1 = fbm2(np * 1.3 + vec2f(t * 0.02, 0.0), 5);
    let n2 = fbm2(np * 2.7 - vec2f(0.0, t * 0.03) + n1 * 1.5, 4);
    let neb = pow(n2, 2.0) * (0.35 + 0.9 * en + 0.3 * pulse * en);
    var col = vec3f(0.005, 0.004, 0.012);
    col += mix(pal(0.0), pal(1.0) * 0.6, n1) * neb * 0.55 * mix(1.0, 0.6, G.centroid);
    col += pal(0.5) * pow(n1, 4.0) * 0.6 * (0.3 + en) * G.centroid;
    col += pal(0.0) * 0.06 * exp(-length(p0) * 1.4);
    let sc = floor(p0 * 120.0);
    let sh = hash21(sc);
    let tw = 0.5 + 0.5 * sin(t * (2.0 + sh * 5.0) + sh * 40.0);
    col += vec3f(0.9, 0.95, 1.0) * step(0.993, sh) * (0.25 + 0.6 * tw + 1.5 * G.hat * step(0.5, fract(sh * 77.0))) * smoothstep(0.5, 0.0, length(fract(p0 * 120.0) - 0.5));

    // ---------- particle vortex spiralling in (bends toward cursor) ----------
    let tom = mpos - C;
    let bend = mon * 0.25 * smoothstep(0.1, 0.9, r);
    let qv = q - rot(roll) * tom * bend;
    let rv = max(length(qv), 1e-3);
    let av = atan2(qv.y, qv.x);
    let lr = log(rv);
    let flow = t * (0.25 + 0.9 * G.flux) + G.travel * 0.15;
    let arms = pow(0.5 + 0.5 * sin((av + lr * 2.2 + flow * 1.3) * 3.0), 3.0);
    let swirl = fbm2(vec2f(av * 3.0 + lr * 6.6, lr * 3.0 + flow), 4);
    let vmask = smoothstep(0.08, 0.2, rv) * exp(-rv * 1.6);
    col += mix(pal(0.0), pal(0.5), swirl) * arms * swirl * vmask * (0.25 + 0.7 * en);
    // particles riding the spiral inward
    let nlay = 2 + i32(G.quality);
    for (var l = 0; l < nlay; l++) {
        let fl = f32(l);
        let sp = vec2f(lr * 7.0 + flow * (2.0 + fl) , (av + lr * (1.6 + fl * 0.4)) / TAU * (60.0 + fl * 20.0));
        let cid = floor(sp);
        let h = hash22(cid + fl * 17.0);
        let f = fract(sp) - 0.5 - (h - 0.5) * 0.6;
        let dd = length(f * vec2f(1.0, 0.6));
        let on = step(1.0 - (0.15 + 0.45 * en + 0.3 * G.flux), h.x);
        col += mix(vec3f(1.0), pal(h.y), 0.5) * on * smoothstep(0.12, 0.0, dd) * smoothstep(0.06, 0.25, rv) * smoothstep(1.6, 0.4, rv) * 0.8;
    }

    // ---------- core ----------
    let coreR = 0.07 * (1.0 + 0.6 * sub + 0.5 * kick + drop);
    let plasma = fbm2(vec2f(a * 2.0 + t * 3.0, r * 20.0 - t * 5.0), 3);
    col += pal(0.5) * glow(r - coreR, 0.05) * (0.5 + 1.2 * kick + 0.4 * sub);
    col += vec3f(1.4, 1.3, 1.2) * smoothstep(coreR, coreR * 0.3, r) * (0.8 + plasma);
    col += pal(0.0) * glow(r - coreR * 1.8, 0.12) * 0.3 * (0.4 + en);

    // ---------- segmented arc rings, each on its own band ----------
    let sigs = array<f32, 5>(sub, band_avg(12, 24), G.mid, G.high, G.snare);
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let rad = 0.17 + fi * 0.075;
        let s = sigs[i];
        let dirn = select(1.0, -1.0, i % 2 == 1);
        let ang = a + dirn * (t * (0.15 + fi * 0.08) + G.travel * (0.05 + fi * 0.03) + s * 0.5);
        let nseg = 6.0 + fi * 8.0;
        let sf = fract(ang / TAU * nseg);
        let si = floor(ang / TAU * nseg);
        let lit = hash11(si + fi * 13.0 + floor(G.beat_count / 2.0) * 0.0);
        let gap = 0.12 + 0.25 * step(0.7, lit);
        let segm = smoothstep(gap, gap + 0.02, sf) * smoothstep(1.0 - 0.02, 1.0 - 0.04, sf);
        let w = 0.006 + 0.004 * s;
        let ring = pr_ring(r, rad, w) * segm;
        let br = 0.25 + 2.2 * s * (0.5 + lit);
        let rc = mix(palc(fi * 0.23 + 0.1), vec3f(1.2), 0.25 * s);
        col += rc * ring * br + rc * glow(abs(r - rad) - w, 0.01) * 0.12 * br * segm;
        // fine tick marks between rings
        col += vec3f(0.4) * pr_ring(r, rad + 0.03, 0.0015) * step(0.8, fract(ang / TAU * 120.0)) * 0.3;
    }

    // ---------- oscilloscope ring of the real waveform ----------
    let wr = 0.6 + wave(am) * 0.06 * (0.6 + 4.0 * G.vol) * sin(am * PI * 0.999 + 0.001);
    let wd = abs(r - wr);
    let wc = mix(pal(0.5), vec3f(1.3), 0.5 * G.snare + 0.2);
    col += wc * (smoothstep(0.004, 0.0, wd) * 1.3 + glow(wd, 0.008) * 0.35) * (0.5 + en + G.snare);

    // ---------- outer spectrum spike crown ----------
    let nb = 96.0;
    let bi = floor(am * nb);
    let bc = (bi + 0.5) / nb;
    let bf = fract(am * nb);
    let sv = spec(bc * 0.95);
    let r0 = 0.7;
    let len = 0.015 + sv * 0.3 * (1.0 + 0.4 * pulse) + 0.1 * drop;
    let inbar = step(r0, r) * step(r, r0 + len) * smoothstep(0.25, 0.4, bf) * smoothstep(0.75, 0.6, bf);
    let k = clamp((r - r0) / max(len, 1e-3), 0.0, 1.0);
    var bcol = pal(bc * 0.8 + k * 0.2) * (0.25 + 0.8 * k);
    bcol = mix(bcol, vec3f(1.8, 1.7, 1.6), smoothstep(0.75, 1.0, k) * (0.4 + G.high + G.hat));
    col += bcol * inbar;
    let pk = hist(bc * 0.95, 0.1) * 0.3 + 0.03;
    col += pal(bc + 0.2) * smoothstep(0.005, 0.0, abs(r - r0 - pk)) * smoothstep(0.15, 0.3, bf) * smoothstep(0.85, 0.7, bf);
    col += pal(0.2) * pr_ring(r, r0 - 0.012, 0.003) * (0.4 + en);

    // ---------- satellites with light trails ----------
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        let rho = 1.0 + fi * 0.13;
        let ph = t * (0.5 - fi * 0.08) * select(1.0, -1.0, i == 2) + fi * 1.7 + G.travel * 0.08;
        let dirn = select(1.0, -1.0, i == 2);
        var da = (ph - a) * dirn;
        da = da - floor(da / TAU) * TAU;
        let trail = exp(-da * 2.2) * smoothstep(0.012, 0.0, abs(r - rho) - 0.001 * da);
        let scol = palc(fi * 0.3 + 0.2);
        col += scol * trail * (0.6 + en + 1.2 * kick);
        let spos = vec2f(cos(ph), sin(ph)) * rho;
        let sd = length(q - spos);
        col += mix(scol, vec3f(1.0), 0.6) * (smoothstep(0.012, 0.0, sd) * 2.0 + glow(sd, 0.015) * 0.5) * (0.7 + G.hat);
        col += vec3f(0.25) * pr_ring(r, rho, 0.0012) * 0.25;
    }

    // ---------- shockwaves: every beat from the core, the drop, and the click ----------
    let swr = 0.12 + bp * 1.7;
    col += mix(pal(0.5), vec3f(1.0), 0.4) * exp(-abs(r - swr) * 45.0) * pulse * (0.2 + 0.8 * kick + 0.4 * en);
    let dr = (1.0 - drop) * 3.0;
    col += mix(vec3f(1.2), pal(0.0), 0.3) * exp(-abs(r - dr) * 10.0) * drop * 2.0;
    let cp = (G.click_pos - 0.5) * vec2f(2.0 * asp, -2.0);
    let cr = length(p - cp);
    let cfade = exp(-G.click_age * 1.8);
    col += pal(1.0) * (exp(-abs(cr - G.click_age * 1.3) * 40.0) * 1.5 + exp(-abs(cr - G.click_age * 0.8) * 60.0) * 0.6) * cfade;

    // ---------- anamorphic flare on the beat ----------
    let fq = p - C;
    let fl = pulse * (0.3 + 0.7 * en) + kick * 0.6 + drop * 2.0;
    col += vec3f(0.35, 0.6, 1.3) * exp(-abs(fq.y) * 90.0) * exp(-abs(fq.x) * 0.9) * fl;
    col += vec3f(0.6, 0.8, 1.3) * exp(-abs(fq.y) * 400.0) * exp(-abs(fq.x) * 0.35) * fl * 0.6;
    col += vec3f(1.0) * pow(drop, 4.0) * 0.9;

    // ---------- feedback: trails swirl into the core ----------
    let cuv = vec2f(0.5) + C * vec2f(0.5 / asp, -0.5);
    let fuv = cuv + rot(0.006) * (uv - cuv) * vec2f(asp, 1.0) * 1.006 / vec2f(asp, 1.0);
    col = max(col, prev(fuv) * 0.62);

    col *= 1.0 - 0.4 * pow(length(uv - 0.5) * 1.3, 2.5);
    return vec4f(col, 1.0);
}
