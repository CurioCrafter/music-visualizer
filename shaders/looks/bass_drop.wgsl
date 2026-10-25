// name: Bass Drop
// palette: #ff1f8f #7a2cff #12e0ff
// A dubstep club: pumping woofer, mirrored LED bar wall, lasers through haze, moving heads,
// a jumping crowd with phones up, kick sparks, and a white-out shockwave on the drop.

fn bd_haze(p: vec2f) -> f32 {
    return fbm2(p * vec2f(1.4, 2.2) + vec2f(G.time * 0.06, -G.time * 0.11), 4);
}

// LED bar wall, mirrored out from the speaker. Returns colour.
fn bd_bars(p: vec2f, stage_y: f32, pulse: f32) -> vec3f {
    let ax = abs(p.x);
    let inner = 0.6;
    let bt = (ax - inner) / (G.aspect - inner);
    if (bt <= 0.0 || bt >= 1.0) { return vec3f(0.0); }
    let nb = 34.0;
    let bi = floor(bt * nb);
    let bc = (bi + 0.5) / nb;
    let bf = fract(bt * nb);
    let sx = pow(bc, 1.25) * 0.92;
    let v = spec(sx);
    let h = v * (1.25 - 0.35 * bc) * (0.88 + 0.22 * pulse) + 0.015;
    let y = p.y - stage_y;
    let colw = smoothstep(0.08, 0.16, bf) * smoothstep(0.92, 0.84, bf);
    let seg = smoothstep(0.15, 0.3, fract(y * 38.0));
    var c = vec3f(0.0);
    if (y > 0.0 && y < h) {
        let k = y / max(h, 1e-3);
        var bcol = pal(bc + k * 0.25) * (0.6 + 1.2 * k);
        bcol = mix(bcol, vec3f(1.6, 1.5, 1.7), smoothstep(h - 0.05, h, y) * (0.4 + G.high));
        c = bcol * seg * colw;
    }
    // peak-hold cap from a moment ago
    let pk = hist(sx, 0.12) * (1.25 - 0.35 * bc) + 0.03;
    c += pal(bc + 0.3) * 1.6 * colw * smoothstep(0.012, 0.0, abs(y - pk));
    // faint unlit LED grid
    c += pal(bc) * 0.025 * colw * seg * step(0.0, y) * step(y, 1.25);
    return c;
}

// woofer in a cabinet. q relative to speaker centre. rgb + coverage
fn bd_speaker(q: vec2f, px: f32, pump: f32, t: f32) -> vec4f {
    let cab = sd_round_box(q, vec2f(0.52, 0.52), 0.06);
    if (cab > px * 2.0) { return vec4f(0.0); }
    let Ld = normalize(vec3f(-0.45, 0.65, 0.62));
    let lc = mix(vec3f(1.0), pal(0.5), 0.35);
    // tolex cabinet
    var c = vec3f(0.03, 0.028, 0.034) * (0.55 + 0.9 * noise2(q * 140.0)) ;
    c += vec3f(0.18, 0.17, 0.2) * smoothstep(0.012, 0.0, abs(cab + 0.014)) * (0.35 + 0.65 * clamp(0.5 + q.y - q.x * 0.5, 0.0, 1.0));
    // corner bolts
    let bq = abs(q) - vec2f(0.445);
    let bolt = length(bq) - 0.02;
    c = mix(c, vec3f(0.5) * (0.4 + 0.6 * clamp(-bq.y * 30.0 + 0.5, 0.0, 1.0)), fill(bolt, px));
    let R = 0.42;
    let r = length(q) / R;
    let dir = q / max(length(q), 1e-4);
    let a = atan2(q.y, q.x);
    // frame ring 0.97..1.08 brushed metal with 8 bolts
    if (r > 0.97 && r < 1.1) {
        let x = (r - 1.035) / 0.065;
        let n = normalize(vec3f(dir * x * 0.8, 1.0));
        let dif = max(dot(n, Ld), 0.0);
        let brushed = 0.7 + 0.3 * noise2(vec2f(a * 120.0, r * 4.0));
        var m = vec3f(0.22, 0.22, 0.25) * dif * brushed + vec3f(1.2) * pow(max(dot(reflect(-Ld, n), vec3f(0.0, 0.0, 1.0)), 0.0), 30.0);
        let ba = (floor(a / TAU * 8.0) + 0.5) * TAU / 8.0;
        let bp = vec2f(cos(ba), sin(ba)) * 1.035 * R;
        m = mix(m, vec3f(0.05), fill(length(q - bp) - 0.016, px));
        m = mix(m, vec3f(0.6), fill(length(q - bp + vec2f(0.004, -0.004)) - 0.008, px));
        c = mix(c, m, smoothstep(0.97, 0.975, r) * smoothstep(1.1, 1.095, r));
    }
    // pumped geometry: centre comes forward
    let rr = r / (1.0 + pump * 0.07 * (1.0 - r));
    if (r <= 0.975) {
        var s = vec3f(0.0);
        if (rr > 0.85) {
            // rubber surround, half torus
            let x = clamp((rr - 0.91) / 0.065, -1.0, 1.0);
            let n = normalize(vec3f(dir * x, sqrt(max(1.0 - x * x, 0.0)) + 0.05));
            let dif = max(dot(n, Ld), 0.0);
            let sp = pow(max(dot(reflect(-Ld, n), vec3f(0.0, 0.0, 1.0)), 0.0), 18.0);
            s = vec3f(0.025) + vec3f(0.12) * dif * lc + lc * sp * 0.5 * (0.6 + pump);
        } else {
            let capR = 0.3 * (1.0 + 0.16 * pump);
            if (rr > capR) {
                // paper cone: tilts toward viewer more when pumped
                let slope = 0.45 + 0.9 * pump;
                let n = normalize(vec3f(-dir * slope, 1.0));
                let dif = max(dot(n, Ld), 0.0);
                let fib = 0.75 + 0.25 * noise2(vec2f(a * 40.0, rr * 6.0)) + 0.1 * noise2(q * 300.0);
                s = vec3f(0.045, 0.042, 0.05) * fib * (0.4 + 1.6 * dif);
                // ribs
                let rib = smoothstep(0.08, 0.0, abs(fract(rr * 11.0) - 0.5) - 0.38);
                s *= 1.0 - 0.45 * rib;
                s += lc * 0.04 * dif * smoothstep(0.42, 0.5, fract(rr * 11.0)) * smoothstep(0.58, 0.5, fract(rr * 11.0));
                // pressure waves running out on the sub
                s += pal(0.1) * 0.09 * pump * pow(0.5 + 0.5 * sin(rr * 34.0 - t * 26.0), 6.0);
                // stage colour bouncing off the cone
                s += pal(0.85) * 0.05 * max(dot(dir, vec2f(0.0, -1.0)), 0.0) * (1.0 - rr);
            } else {
                // glossy dust cap
                let cq = q / (capR * R);
                let z = sqrt(max(1.0 - dot(cq, cq), 0.0));
                let n = normalize(vec3f(cq, z * 1.2));
                let dif = max(dot(n, Ld), 0.0);
                let sp = pow(max(dot(reflect(-Ld, n), vec3f(0.0, 0.0, 1.0)), 0.0), 50.0);
                s = vec3f(0.02, 0.018, 0.025) + vec3f(0.08) * dif + vec3f(1.6) * sp;
                // printed logo ring
                s += pal(0.0) * 0.5 * smoothstep(0.03, 0.0, abs(length(cq) - 0.62)) * (0.4 + pump);
                s += pal(0.95) * 0.12 * pow(1.0 - z, 3.0);
            }
            // cone shadow under surround
            s *= 0.55 + 0.45 * smoothstep(0.85, 0.75, rr);
        }
        c = mix(c, s, smoothstep(0.975, 0.97, r));
    }
    return vec4f(c, fill(cab, px));
}

fn bd_crowd(p: vec2f, cw: f32, base: f32, sc: f32, seed: f32, bounce: f32, raise: f32) -> vec2f {
    var d = 1e3;
    var phone = 1e3;
    let id0 = floor(p.x / cw);
    for (var k = -1; k <= 1; k++) {
        let id = id0 + f32(k);
        let h = hash21(vec2f(id, seed));
        let h2 = hash21(vec2f(id, seed + 7.3));
        let h3 = hash21(vec2f(id, seed + 3.1));
        let cx = (id + 0.5) * cw + (h3 - 0.5) * cw * 0.45;
        let off = select(1.0, 0.55 + 0.45 * sin(G.time * 2.0 + id), h3 > 0.8);
        let hy = base + (h2 - 0.5) * 0.06 * sc + bounce * (0.5 + 0.9 * h2) * off;
        d = min(d, length((p - vec2f(cx, hy)) * vec2f(1.0, 0.88)) - 0.04 * sc);
        d = min(d, sd_round_box(p - vec2f(cx, hy - 0.08 * sc - 0.5), vec2f(0.075 * sc, 0.5), 0.04 * sc));
        let sway = sin(G.time * 2.4 + id * 1.7) * 0.025 * sc;
        if (h > 0.4) {
            let sh = vec2f(cx - 0.05 * sc, hy - 0.07 * sc);
            let el = sh + vec2f(-0.05 * sc + sway, 0.08 * sc);
            let ha = el + vec2f(0.01 * sc + sway, 0.09 * sc + raise * sc);
            d = min(d, sd_segment(p, sh, el) - 0.014 * sc);
            d = min(d, sd_segment(p, el, ha) - 0.012 * sc);
            d = min(d, length(p - ha) - 0.018 * sc);
        }
        if (h2 > 0.55) {
            let sh = vec2f(cx + 0.05 * sc, hy - 0.07 * sc);
            let el = sh + vec2f(0.055 * sc - sway, 0.07 * sc);
            let ha = el + vec2f(-0.005 * sc, 0.1 * sc + raise * sc * 0.7);
            d = min(d, sd_segment(p, sh, el) - 0.014 * sc);
            d = min(d, sd_segment(p, el, ha) - 0.012 * sc);
            if (h3 > 0.55) {
                phone = min(phone, length(p - ha - vec2f(0.0, 0.025 * sc)));
                d = min(d, sd_box(p - ha - vec2f(0.0, 0.02 * sc), vec2f(0.011, 0.019) * sc));
            }
        }
    }
    return vec2f(d, phone);
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let t = G.time;
    let asp = G.aspect;
    let bp = G.beat_phase;
    let pulse = pow(1.0 - bp, 3.0);
    let sub = band_avg(0, 5);
    let kick = G.kick;
    let drop = G.drop;
    let q = G.quality;

    // song sections (cross-fading weights)
    let wQ = sec(SEC_QUIET);
    let wV = sec(SEC_VERSE);
    let wB = sec(SEC_BUILD);
    let wC = sec(SEC_CHORUS);
    let wR = sec(SEC_BREAKDOWN);
    let wD = sec(SEC_DROP);
    let tens = wB * sec_progress(12.0);          // build-up tension 0..1
    // how "on" the show is: dim in intro, climbing in build, full in chorus, gone-soft in breakdown
    let en = clamp(G.energy * (1.0 - 0.7 * wQ - 0.45 * wR) + 0.55 * tens + 0.3 * wC + 0.15 * wD + 0.1 * wR, 0.0, 1.4);
    let drums = 1.0 - wR;                          // 0 in the breakdown: no kick-driven stuff

    // camera: kick punch-in + shake, drop slams harder; build creeps in and trembles,
    // chorus/breakdown pull back wide, drop rolls
    var p = centered(fc);
    let shake = (hash22(vec2f(floor(t * 45.0), 1.7)) - 0.5) * (0.02 * kick + 0.06 * drop * drop + 0.03 * tens * tens + 0.015 * wD);
    let zoom = (1.0 - 0.045 * kick - 0.1 * drop * drop - 0.16 * tens) * (1.0 + 0.07 * wC + 0.1 * wR + 0.04 * wQ);
    p = p * zoom + shake;
    p = rot(0.03 * wD * sin(t * 0.8) + 0.05 * wD * G.kick) * p;
    let px = 2.0 / G.res.y * zoom;

    let haze = bd_haze(p);
    let stage_y = -0.44;
    let S = vec2f(0.0, 0.0);

    // ---------- back wall / haze ----------
    var col = mix(vec3f(0.01, 0.004, 0.03), vec3f(0.03, 0.012, 0.012), G.centroid) * (0.5 + 1.0 * haze);
    col += pal(0.5) * 0.08 * exp(-1.6 * length(p - vec2f(0.0, 0.15))) * (0.4 + en + 0.5 * pulse);
    // hats: glitter in the haze
    let gl = hash21(floor(p * 160.0) + floor(t * 30.0));
    col += vec3f(0.9, 0.9, 1.0) * step(0.997, gl) * G.hat * 1.5 * haze;

    // ---------- moving heads from the truss ----------
    let truss_y = 0.87;
    let mpos = (G.mouse - 0.5) * vec2f(2.0 * asp, -2.0);
    let palstep = floor(G.beat_count / 4.0);
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let o = vec2f((fi - 2.0) * asp * 0.4, truss_y - 0.085);
        var aim = sin(t * 0.45 + fi * 1.9) * 0.5 + sin(t * 0.21 + fi) * 0.25;
        if (G.mouse_on > 0.5) {
            let to = mpos - o;
            aim = mix(aim, atan2(to.x, -to.y), 0.85);
        }
        // build: all heads converge on the woofer; chorus: fan up and open like a crown; breakdown: slow wide sweep
        let toS = vec2f(0.0, 0.1) - o;
        aim = mix(aim, atan2(toS.x, -toS.y), tens * 0.95);
        aim = mix(aim, PI + (fi - 2.0) * 0.38 + 0.12 * sin(t * 0.5 + fi), wC);
        aim = mix(aim, sin(t * 0.22 + fi * 1.3) * 0.8, wR * 0.8);
        let d = vec2f(sin(aim), -cos(aim));
        let v = p - o;
        let dist = length(v);
        let c = dot(v, d) / max(dist, 1e-4);
        let w = 0.1 + 0.05 * G.mid + 0.07 * wR + 0.04 * wC - 0.04 * tens;
        let cone = smoothstep(cos(w), 1.0, c);
        let core = pow(max(c, 0.0), 900.0);
        var hc = palc(fi * 0.21 + palstep * 0.17);
        hc = mix(hc, vec3f(1.0, 0.78, 0.4), 0.55 * wC);                  // chorus: warm gold
        hc = mix(hc, mix(pal(0.95), vec3f(1.0), 0.4), 0.6 * wR);         // breakdown: pale, airy
        hc = mix(hc, vec3f(1.0, 0.3, 0.12), 0.7 * tens);                 // build: heating up
        hc = mix(hc, hc.bgr, 0.5 * wD);                                  // drop: colour flip
        let on = 0.2 + 0.7 * en + 0.9 * G.snare * drums + 1.5 * drop + 0.5 * wC + 0.5 * wR;
        col += hc * (cone * 0.45 + core * 0.7 * (1.0 - 0.85 * wR)) * (0.3 + 1.1 * haze) * exp(-dist * 0.6) * on * 0.5;
    }

    // ---------- LED bar wall ----------
    col += bd_bars(p, stage_y, pulse) * (1.0 - 0.8 * wQ) * (1.0 + 0.5 * wC);

    // speaker back glow
    let sq = (p - S) / (1.0 + 0.035 * kick + 0.02 * pulse);
    let cabd = sd_round_box(sq, vec2f(0.52, 0.52), 0.06);
    col += pal(0.0) * glow(cabd, 0.04) * (0.08 + 0.5 * kick * drums + 0.8 * drop + 0.25 * wQ * (0.5 + 0.5 * sin(t * 0.8)));

    // ---------- speaker ----------
    let pump = clamp(sub * 0.9 + kick * 0.55 + 0.25 * pulse * en, 0.0, 1.6) * (1.0 - 0.7 * wR) + 0.04 * sin(t * 1.7) + 0.12 * tens * sin(t * 40.0);
    let spk = bd_speaker(sq, px, pump, t);
    col = mix(col, spk.rgb, spk.a);
    // LED ring around the woofer
    let ringd = abs(length(sq) - 0.475);
    col += mix(pal(0.0), vec3f(1.0), 0.3 * kick) * (smoothstep(0.006, 0.0, ringd) * 1.2 + glow(ringd, 0.012) * 0.25) * (0.25 + 1.6 * kick + 2.0 * drop + 0.4 * G.bass);
    // build: the ring charges up like a progress arc, with rings imploding onto the woofer
    {
        let ang01 = fract((atan2(sq.y, sq.x) + PI * 0.5) / TAU);
        let arc = smoothstep(tens + 0.01, tens - 0.01, ang01) * step(0.001, tens);
        col += mix(vec3f(1.0, 0.35, 0.12), vec3f(1.6, 1.4, 1.2), tens) * (smoothstep(0.012, 0.0, ringd) * 2.2 + glow(ringd, 0.02) * 0.6) * arc * wB;
        for (var k = 0; k < 3; k++) {
            let ph = fract(t * (0.5 + 1.6 * tens) + f32(k) / 3.0);
            col += pal(0.95) * exp(-abs(length(p - S) - (1.8 * (1.0 - ph) + 0.5)) * 30.0) * ph * tens * 0.9;
        }
    }

    // ---------- truss + fixtures ----------
    let tb = sd_box(p - vec2f(0.0, truss_y), vec2f(asp * 1.2, 0.03));
    if (tb < 0.0) {
        let lat = smoothstep(0.12, 0.0, abs(fract((p.x + (p.y - truss_y) * 1.0) * 16.0) - 0.5) - 0.38)
                + smoothstep(0.12, 0.0, abs(fract((p.x - (p.y - truss_y) * 1.0) * 16.0) - 0.5) - 0.38);
        let rail = smoothstep(0.008, 0.0, abs(abs(p.y - truss_y) - 0.024));
        col = vec3f(0.01) + vec3f(0.22, 0.22, 0.25) * clamp(lat * 0.5 + rail, 0.0, 1.0) * (0.4 + 0.6 * haze);
    }
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let o = vec2f((fi - 2.0) * asp * 0.4, truss_y - 0.085);
        let yoke = sd_round_box(p - o - vec2f(0.0, 0.035), vec2f(0.045, 0.03), 0.01);
        col = mix(col, vec3f(0.03, 0.03, 0.035), fill(yoke, px));
        let lens = length(p - o) - 0.026;
        let hc = palc(fi * 0.21 + palstep * 0.17);
        col = mix(col, hc * (1.5 + G.hat * 2.0) + 0.5, fill(lens, px));
        col += hc * glow(lens, 0.02) * 0.4;
    }
    // blinders on the truss flash on hats
    let bl = vec2f(fract(p.x * 3.0) - 0.5, p.y - truss_y);
    col += vec3f(1.0, 0.85, 0.6) * glow(length(bl / vec2f(3.0, 1.0)) - 0.006, 0.006) * (G.hat * 0.8 + drop) * 0.6;

    // ---------- stage floor with reflection ----------
    if (p.y < stage_y) {
        let fy = stage_y - p.y;
        let rip = noise2(vec2f(p.x * 30.0, fy * 120.0 - t * 2.0)) - 0.5;
        let rp = vec2f(p.x + rip * 0.01, stage_y + fy * 1.4 + rip * 0.01);
        col = vec3f(0.006, 0.004, 0.012) + bd_bars(rp, stage_y, pulse) * 0.35 * exp(-fy * 6.0);
        let rs = bd_speaker(vec2f(rp.x, rp.y) - S, px * 2.0, pump, t);
        col = mix(col, spk.rgb * 0.0 + rs.rgb * 0.3, rs.a * exp(-fy * 5.0));
        col += vec3f(0.3, 0.3, 0.35) * smoothstep(0.004, 0.0, fy) ;
    }

    // ---------- lasers from the stage lip ----------
    let strobe = (drop + 0.3 * wD) * step(0.5, fract(t * (13.0 + 8.0 * tens)));
    let lvis = (smoothstep(0.1, 0.55, en) * 0.85 + 0.15 + drop * 2.0 + 0.5 * wD + 0.7 * tens) * (1.0 - 0.9 * wQ) * (1.0 - wR) * (1.0 + 0.3 * wC);
    for (var e = 0; e < 4; e++) {
        let fe = f32(e);
        let o = vec2f((fe - 1.5) * asp * 0.52, stage_y - 0.03);
        var lc = mix(palc(fe * 0.33 + 0.55), vec3f(1.4), clamp(G.snare * 0.8 * drums + strobe, 0.0, 1.0));
        lc = mix(lc, mix(vec3f(1.0, 0.85, 0.5), pal(0.5), 0.3), 0.5 * wC);
        lc = mix(lc, lc.bgr, 0.5 * wD);
        var spread = 0.13 + 0.07 * sin(t * 0.3 + fe) + 0.06 * hash11(G.beat_count * 0.37 + fe);
        var sweep = sin(t * 0.9 + fe * 1.3) * (0.12 + 0.5 * G.mid) + (1.5 - fe) * 0.1;
        // build: beams tighten and converge on the woofer; chorus: wide open fan; drop: fast whipping sweep
        spread = spread * (1.0 - 0.85 * tens) * (1.0 + 0.55 * wC);
        sweep = mix(sweep, atan2(-o.x, 0.1 - o.y), tens);
        sweep += wD * sin(t * 4.0 + fe * 2.0) * 0.5;
        for (var j = 0; j < 7; j++) {
            let fj = f32(j) - 3.0;
            let act = step(hash21(vec2f(fe * 7.0 + f32(j), G.beat_count)), 0.25 + 0.75 * en + drop + 0.5 * tens);
            if (act < 0.5) { continue; }
            let ang = fj * spread + sweep;
            let d = vec2f(sin(ang), cos(ang));
            let v = p - o;
            let al = dot(v, d);
            if (al < 0.0) { continue; }
            let pr = abs(v.x * d.y - v.y * d.x);
            let w = 0.0018 + 0.0025 * al;
            let beam = exp(-pr * pr / (w * w)) + 0.18 * exp(-pr / (w * 5.0));
            col += lc * beam * (0.25 + 1.3 * haze) * exp(-al * 0.55) * lvis * 0.55;
        }
        col += lc * glow(length(p - o) - 0.005, 0.012) * lvis * 0.6;
    }

    // ---------- sparks on every beat (bigger on kicks / drop), plus the click ----------
    let blen = 60.0 / max(G.bpm, 60.0);
    let age = bp * blen;
    let sparkamt = (0.15 + 0.85 * en + 2.0 * drop + 0.4 * wD) * (1.0 - bp) * (1.0 - 0.9 * wR) * (1.0 - 0.85 * wQ);
    let ns = 18 + i32(q * 12.0);
    var sp = 0.0;
    for (var i = 0; i < ns; i++) {
        let fi = f32(i);
        let s = hash22(vec2f(fi * 1.31, G.beat_count * 0.71));
        let ang = s.x * TAU;
        let dir = vec2f(cos(ang), sin(ang));
        let vel = dir * (0.7 + 1.5 * s.y) * (1.0 + drop) + vec2f(0.0, 0.6);
        let o = S + dir * 0.47;
        let pos = o + vel * age + vec2f(0.0, -1.3) * age * age;
        let vn = vel + vec2f(0.0, -2.6) * age;
        let d = sd_segment(p, pos, pos - vn * 0.035);
        sp += 0.0018 / (d + 0.0018) * smoothstep(0.004, 0.0, d - 0.001) + 0.0006 / (d + 0.003);
    }
    if (G.click_age < 1.5) {
        for (var i = 0; i < 14; i++) {
            let fi = f32(i);
            let s = hash22(vec2f(fi, 9.1));
            let dir = vec2f(cos(s.x * TAU), sin(s.x * TAU));
            let cp = (G.click_pos - 0.5) * vec2f(2.0 * asp, -2.0);
            let vel = dir * (0.5 + 1.2 * s.y) + vec2f(0.0, 0.5);
            let a2 = G.click_age;
            let pos = cp + vel * a2 + vec2f(0.0, -1.3) * a2 * a2;
            let d = sd_segment(p, pos, pos - (vel + vec2f(0.0, -2.6) * a2) * 0.03);
            sp += (0.0018 / (d + 0.0018) * smoothstep(0.004, 0.0, d - 0.001) + 0.0006 / (d + 0.003)) * (1.0 - G.click_age / 1.5) * 1.5;
        }
    }
    col += mix(vec3f(1.0, 0.45, 0.12), vec3f(1.2, 1.1, 0.9), 0.4) * sp * max(sparkamt, select(0.0, 1.0, G.click_age < 1.5));

    // ---------- crowd ----------
    let bounce = (0.008 + 0.04 * en + 0.04 * drop + 0.03 * wC + 0.02 * wD) * sin(PI * bp) * (1.0 - 0.9 * wR) + 0.006 * wR * sin(t * 1.3);
    let raise = 0.03 * pulse * drums + 0.04 * drop + 0.05 * wC + 0.07 * wR;
    let cdown = 0.5 * wQ;   // intro: the crowd is still outside
    let back = bd_crowd(p, 0.105, -0.58 - cdown, 0.8, 1.0, bounce * 0.8, raise);
    let rim_c = mix(pal(0.5), pal(0.0), 0.5 + 0.5 * sin(t * 0.5));
    if (back.x < px) {
        col = mix(col, vec3f(0.012, 0.008, 0.02) + rim_c * 0.3 * smoothstep(-0.01, 0.0, back.x) * smoothstep(-0.64, -0.5, p.y) * (0.4 + en), fill(back.x, px));
    }
    col += vec3f(0.7, 0.85, 1.0) * (smoothstep(0.01, 0.0, back.y) * 1.5 + glow(back.y, 0.008) * 0.25) * (1.0 + 2.0 * wR);
    let front = bd_crowd(p + vec2f(0.07, 0.0), 0.15, -0.78 - cdown, 1.15, 2.0, bounce * 1.1, raise);
    if (front.x < px) {
        col = mix(col, vec3f(0.003) + rim_c * 0.45 * smoothstep(-0.008, 0.0, front.x) * smoothstep(-0.84, -0.7, p.y) * (0.4 + en + G.snare), fill(front.x, px));
    }
    col += vec3f(0.75, 0.9, 1.0) * (smoothstep(0.012, 0.0, front.y) * 1.8 + glow(front.y, 0.01) * 0.3) * (1.0 + 2.5 * wR);

    // ---------- chorus confetti / breakdown fireflies (floating, melody-driven) ----------
    if (wC + wR > 0.01) {
        let nf = 16 + i32(q * 10.0);
        var fl = vec3f(0.0);
        for (var i = 0; i < nf; i++) {
            let fi = f32(i);
            let h = hash22(vec2f(fi, 4.4));
            let h2 = hash11(fi * 1.7 + 2.0);
            // confetti: tumbling flakes falling
            let cy = 1.3 - fract(h.y + t * (0.07 + 0.08 * h2)) * 2.6;
            let cx = (h.x * 2.0 - 1.0) * asp * 1.05 + sin(t * (0.5 + h2) + fi) * 0.08;
            let cq = rot(t * (1.0 + 2.0 * h2) + fi) * (p - vec2f(cx, cy));
            let cf = fill(sd_box(cq * vec2f(1.0, 0.4 + 0.6 * abs(sin(t * 3.0 + fi))), vec2f(0.011, 0.007)), px);
            fl += palc(h2 * 1.3 + 0.1) * cf * 1.6 * wC;
            // firefly: rises slowly, size and glow from the spectrum band that belongs to it
            let fy2 = -0.9 + fract(h.x * 3.0 + t * 0.03 + h2) * 2.1;
            let fx2 = (h.y * 2.0 - 1.0) * asp + sin(t * 0.35 + fi * 2.1) * 0.12;
            let amp2 = spec(0.15 + 0.6 * h2) + 0.6 * key(30 + i * 2);
            let fd = length(p - vec2f(fx2, fy2));
            fl += mix(pal(h2), vec3f(1.0), 0.5) * (0.0035 / (fd + 0.004) * (0.5 + 2.5 * amp2) * (0.6 + 0.4 * sin(t * 2.0 + fi * 3.0))) * wR;
        }
        col += fl;
    }

    // ---------- kick pressure ring, drop shockwave + flash ----------
    let rd = length(p - S);
    col += pal(0.95) * exp(-abs(rd - (0.5 + bp * 1.1)) * 40.0) * pulse * (0.1 + 0.5 * kick) * (0.3 + en);
    let shock = (1.0 - drop) * 2.6;
    col += mix(vec3f(1.0), pal(0.2), 0.4) * exp(-abs(rd - shock) * 14.0) * drop * 2.0;
    col += vec3f(1.0, 0.95, 1.0) * (pow(drop, 4.0) * 1.2 + strobe * 0.25);
    col += vec3f(1.0, 0.8, 0.7) * G.snare * wB * (0.2 + 0.5 * tens);          // build: snare rolls flash the room
    // drop only: a rotating sunburst of rays from the woofer, and the colours flip on every kick
    if (wD > 0.01) {
        let ra = atan2(p.y - S.y, p.x - S.x);
        let rays = pow(abs(sin(ra * 9.0 + t * 0.7)), 10.0) + 0.6 * pow(abs(sin(ra * 23.0 - t * 1.3)), 24.0);
        col += mix(pal(0.2), vec3f(1.0), 0.5) * rays * exp(-rd * 0.9) * wD * (0.35 + 1.1 * kick) * (0.4 + haze);
        col = mix(col, vec3f(1.0) - min(col, vec3f(1.0)), 0.3 * wD * kick);
    }
    // quiet: a slow breathing halo, the only light on
    col += pal(0.5) * 0.12 * wQ * exp(-rd * 2.2) * (0.6 + 0.4 * sin(t * 0.9));

    // ---------- feedback: light trails drift upward like smoke ----------
    let pv = prev(uv + vec2f(0.0, 0.0035)) * (0.78 + 0.13 * wR + 0.05 * wQ + 0.04 * wC);
    col = max(col, pv * vec3f(0.98, 0.95, 1.0));

    col *= 1.0 - 0.3 * wQ;
    // vignette + grain
    col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.35, 2.5);
    col += (hash21(fc + fract(t) * 91.0) - 0.5) * 0.012;
    return vec4f(col, 1.0);
}
