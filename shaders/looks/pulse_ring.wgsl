// name: Pulse Ring
// palette: #1ee0ff #8b3dff #ff2d7a
// A reactor core in a nebula: spectrum spike crown, live oscilloscope ring, segmented arc rings
// spinning on different bands, kick shockwaves, orbiting satellites with trails, a particle vortex
// spiralling into the core and an anamorphic flare on the beat. Mouse tilts the reactor.

fn pr_ring(r: f32, rad: f32, w: f32) -> f32 {
    let d = abs(r - rad);
    return smoothstep(w, 0.0, d);
}

var<private> pr_f: f32;   // drop colour flip 0..1
fn pr_p(x: f32) -> vec3f { return pal(mix(x, 1.0 - x, pr_f)); }
fn pr_pc(x: f32) -> vec3f { return palc(x + 0.5 * pr_f); }

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let t = G.time;
    let asp = G.aspect;
    let bp = G.beat_phase;
    let pulse = pow(1.0 - bp, 3.0);
    let kick = G.kick;
    let drop = G.drop;
    let en = G.energy;
    // ---- song sections ----
    let wq = sec(SEC_QUIET); let wv = sec(SEC_VERSE); let wb = sec(SEC_BUILD);
    let wc = sec(SEC_CHORUS); let wk = sec(SEC_BREAKDOWN); let wdr = sec(SEC_DROP);
    let bprog = select(1.0, sec_progress(12.0), G.section == SEC_BUILD) * wb;
    pr_f = wdr;
    let ringK = wq * 0.3 + wv + wb + wc * 1.2 + wk * 0.12 + wdr * 1.3;
    let rs = wq + wv + wb * (1.0 - 0.45 * bprog) + wc * 1.15 + wk * 1.3 + wdr;
    let crownK = wq * 0.1 + wv + wb * (0.5 + 0.9 * bprog) + wc * 1.3 + wk * 0.2 + wdr * 1.7;
    let satK = wq * 0.25 + wv + wb + wc * 1.3 + wk * 0.5 + wdr;
    let vorK = wq * 0.3 + wv + wb * (1.0 + 1.5 * bprog) + wc + wk * 0.5 + wdr * 1.5;
    let nebK = wq * 0.5 + wv + wb + wc * 1.4 + wk * 1.8 + wdr;
    let coreK = wq * 0.7 + wv + wb * (1.0 + 0.9 * bprog) + wc * 1.1 + wk * 0.8 + wdr * 1.5;
    let beatK = 1.0 - 0.8 * wk - 0.4 * wq;   // breakdown has no drums: calm the beat flashes
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
    let neb = pow(n2, 2.0) * (0.35 + 0.9 * en + 0.3 * pulse * en * beatK) * nebK;
    var col = vec3f(0.005, 0.004, 0.012);
    col += mix(pr_p(0.0), pr_p(1.0) * 0.6, n1) * neb * 0.55 * mix(1.0, 0.6, G.centroid);
    col += pr_p(0.5) * pow(n1, 4.0) * 0.6 * (0.3 + en) * G.centroid;
    col += pr_p(0.0) * 0.06 * exp(-length(p0) * 1.4);
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
    col += mix(pr_p(0.0), pr_p(0.5), swirl) * arms * swirl * vmask * (0.25 + 0.7 * en) * vorK;
    // particles riding the spiral inward
    let nlay = max(1, i32(f32(2 + i32(G.quality)) * clamp(vorK, 0.4, 1.0)));
    for (var l = 0; l < nlay; l++) {
        let fl = f32(l);
        let sp = vec2f(lr * 7.0 + flow * (2.0 + fl) , (av + lr * (1.6 + fl * 0.4)) / TAU * (60.0 + fl * 20.0));
        let cid = floor(sp);
        let h = hash22(cid + fl * 17.0);
        let f = fract(sp) - 0.5 - (h - 0.5) * 0.6;
        let dd = length(f * vec2f(1.0, 0.6));
        let on = step(1.0 - (0.15 + 0.45 * en + 0.3 * G.flux), h.x);
        col += mix(vec3f(1.0), pr_p(h.y), 0.5) * on * smoothstep(0.12, 0.0, dd) * smoothstep(0.06, 0.25, rv) * smoothstep(1.6, 0.4, rv) * 0.8;
    }

    // ---------- core ----------
    let coreR = 0.07 * coreK * (1.0 + 0.6 * sub + 0.5 * kick + drop);
    let plasma = fbm2(vec2f(a * 2.0 + t * 3.0, r * 20.0 - t * 5.0), 3);
    col += pr_p(0.5) * glow(r - coreR, 0.05) * (0.5 + 1.2 * kick + 0.4 * sub);
    col += vec3f(1.4, 1.3, 1.2) * smoothstep(coreR, coreR * 0.3, r) * (0.8 + plasma);
    col += pr_p(0.0) * glow(r - coreR * 1.8, 0.12) * 0.3 * (0.4 + en);

    // ---------- segmented arc rings, each on its own band ----------
    let sigs = array<f32, 5>(sub, band_avg(12, 24), G.mid, G.high, G.snare);
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let rad = (0.17 + fi * 0.075) * rs;
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
        let rc = mix(pr_pc(fi * 0.23 + 0.1), vec3f(1.2), 0.25 * s);
        col += (rc * ring * br + rc * glow(abs(r - rad) - w, 0.01) * 0.12 * br * segm) * ringK;
        // fine tick marks between rings
        col += vec3f(0.4) * pr_ring(r, rad + 0.03, 0.0015) * step(0.8, fract(ang / TAU * 120.0)) * 0.3 * ringK;
    }

    // ---------- oscilloscope ring of the real waveform ----------
    let wr = 0.6 * (1.0 + 0.15 * wk - 0.1 * bprog) + wave(am) * 0.06 * (0.6 + 4.0 * G.vol) * sin(am * PI * 0.999 + 0.001);
    let owd = abs(r - wr);
    let owc = mix(pr_p(0.5), vec3f(1.3), 0.5 * G.snare + 0.2);
    col += owc * (smoothstep(0.004, 0.0, owd) * 1.3 + glow(owd, 0.008) * 0.35) * (0.5 + en + G.snare);

    // ---------- outer spectrum spike crown ----------
    let nb = 96.0;
    let bi = floor(am * nb);
    let bc = (bi + 0.5) / nb;
    let bf = fract(am * nb);
    let sv = spec(bc * 0.95);
    let r0 = 0.7;
    let len = 0.015 + (sv * 0.3 * (1.0 + 0.4 * pulse * beatK) + 0.1 * drop) * crownK;
    let inbar = step(r0, r) * step(r, r0 + len) * smoothstep(0.25, 0.4, bf) * smoothstep(0.75, 0.6, bf);
    let k = clamp((r - r0) / max(len, 1e-3), 0.0, 1.0);
    var bcol = pr_p(bc * 0.8 + k * 0.2) * (0.25 + 0.8 * k);
    bcol = mix(bcol, vec3f(1.8, 1.7, 1.6), smoothstep(0.75, 1.0, k) * (0.4 + G.high + G.hat));
    col += bcol * inbar;
    let pk = hist(bc * 0.95, 0.1) * 0.3 + 0.03;
    col += crownK * pr_p(bc + 0.2) * smoothstep(0.005, 0.0, abs(r - r0 - pk)) * smoothstep(0.15, 0.3, bf) * smoothstep(0.85, 0.7, bf);
    col += pr_p(0.2) * pr_ring(r, r0 - 0.012, 0.003) * (0.4 + en);

    // ---------- satellites with light trails ----------
    for (var i = 0; i < 4; i++) {
        let fi = f32(i);
        let rho = 1.0 + fi * 0.13;
        let ph = t * (0.5 - fi * 0.08) * select(1.0, -1.0, i == 2) + fi * 1.7 + G.travel * 0.08;
        let dirn = select(1.0, -1.0, i == 2);
        var da = (ph - a) * dirn;
        da = da - floor(da / TAU) * TAU;
        let trail = exp(-da * 2.2) * smoothstep(0.012, 0.0, abs(r - rho) - 0.001 * da);
        let scol = pr_pc(fi * 0.3 + 0.2);
        col += satK * scol * trail * (0.6 + en + 1.2 * kick);
        let spos = vec2f(cos(ph), sin(ph)) * rho;
        let sd = length(q - spos);
        col += satK * mix(scol, vec3f(1.0), 0.6) * (smoothstep(0.012, 0.0, sd) * 2.0 + glow(sd, 0.015) * 0.5) * (0.7 + G.hat);
        col += satK * vec3f(0.25) * pr_ring(r, rho, 0.0012) * 0.25;
    }

    // ---------- shockwaves: every beat from the core, the drop, and the click ----------
    let swr = 0.12 + bp * 1.7;
    col += mix(pr_p(0.5), vec3f(1.0), 0.4) * exp(-abs(r - swr) * 45.0) * pulse * (0.2 + 0.8 * kick + 0.4 * en) * beatK * (1.0 + 0.8 * wdr);
    let dr = (1.0 - drop) * 3.0;
    col += mix(vec3f(1.2), pr_p(0.0), 0.3) * exp(-abs(r - dr) * 10.0) * drop * 2.0;
    let cp = (G.click_pos - 0.5) * vec2f(2.0 * asp, -2.0);
    let cr = length(p - cp);
    let cfade = exp(-G.click_age * 1.8);
    col += pr_p(1.0) * (exp(-abs(cr - G.click_age * 1.3) * 40.0) * 1.5 + exp(-abs(cr - G.click_age * 0.8) * 60.0) * 0.6) * cfade;

    // ---------- build-up: rings collapse inward, charge arc fills ----------
    if (bprog > 0.01) {
        let cs = fract(t * (0.4 + 1.2 * bprog));
        col += mix(pr_p(0.0), vec3f(1.0), bprog) * exp(-abs(r - (1.4 - 1.3 * cs * cs)) * 28.0) * (0.3 + 0.9 * bprog) * wb;
        let chg = fract(0.25 - a / TAU);
        col += mix(pr_p(0.5), vec3f(1.3), bprog) * pr_ring(r, 0.5 * rs + 0.04, 0.008) * step(chg, bprog) * (0.8 + 2.0 * G.snare) * wb;
        col += vec3f(0.8, 0.9, 1.2) * G.snare * 0.12 * bprog * exp(-r * 1.5);
    }
    // ---------- drop only: burst spokes + a second ring thrown out on each beat ----------
    if (wdr > 0.01) {
        let sp = pow(abs(sin(a * 10.0 + t * 0.4)), 18.0) + 0.6 * pow(abs(sin(a * 23.0 - t * 0.7)), 40.0);
        col += mix(vec3f(1.2), pr_p(0.5), 0.4) * sp * exp(-r * 0.9) * wdr * (0.15 + 0.7 * kick + 0.3 * pulse);
        col += vec3f(1.2) * exp(-abs(r - (0.1 + bp * 2.2)) * 18.0) * wdr * 0.5 * (0.4 + kick);
    }
    // ---------- chorus only: slow soft light rays, open and warm ----------
    if (wc > 0.01) {
        let ry = pow(0.5 + 0.5 * sin(a * 6.0 + t * 0.25), 2.0) * pow(0.5 + 0.5 * sin(a * 9.0 - t * 0.17), 2.0);
        col += mix(pr_p(0.2), vec3f(1.0), 0.45) * ry * exp(-r * 0.7) * wc * (0.12 + 0.2 * en);
        col += pr_p(0.8) * pr_ring(r, 1.12 + 0.03 * pulse, 0.012) * wc * 0.5 * (0.5 + en);
    }
    // ---------- breakdown only: floating melody lights, one big soft breathing ring ----------
    if (wk > 0.01) {
        for (var i = 0; i < 8; i++) {
            let fi = f32(i);
            let hh = hash11(fi * 3.7 + 1.0);
            let oc = vec2f((hash11(fi * 9.1) - 0.5) * 2.0 * asp * 0.9 + 0.1 * sin(t * 0.3 + fi), fract(hh + t * 0.02 * (1.0 + hh)) * 2.4 - 1.2);
            let kv = key(28 + i * 7) + 0.6 * spec(0.12 + 0.1 * fi);
            col += mix(pr_p(fi * 0.15), vec3f(1.0), 0.4) * glow(length(p - oc), 0.012 + 0.03 * kv) * (0.12 + 1.0 * kv) * wk * 0.6;
        }
        col += pr_p(0.3) * exp(-abs(r - (0.75 + 0.1 * G.mid)) * 12.0) * wk * (0.1 + 0.8 * G.mid);
    }
    // ---------- anamorphic flare on the beat ----------
    let fq = p - C;
    let fl = (pulse * (0.3 + 0.7 * en) + kick * 0.6) * beatK + drop * 2.0 + 0.4 * wdr * pulse;
    col += vec3f(0.35, 0.6, 1.3) * exp(-abs(fq.y) * 90.0) * exp(-abs(fq.x) * 0.9) * fl;
    col += vec3f(0.6, 0.8, 1.3) * exp(-abs(fq.y) * 400.0) * exp(-abs(fq.x) * 0.35) * fl * 0.6;
    col += vec3f(1.0) * pow(drop, 4.0) * 0.9;

    // ---------- feedback: trails swirl into the core ----------
    let cuv = vec2f(0.5) + C * vec2f(0.5 / asp, -0.5);
    let fuv = cuv + rot(0.006) * (uv - cuv) * vec2f(asp, 1.0) * 1.006 / vec2f(asp, 1.0);
    col = max(col, prev(fuv) * (0.62 + 0.2 * wk - 0.06 * wdr));

    col *= 1.0 - 0.25 * wq;
    col *= 1.0 - 0.4 * pow(length(uv - 0.5) * 1.3, 2.5);
    return vec4f(col, 1.0);
}
