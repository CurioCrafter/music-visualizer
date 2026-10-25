// name: Deep Wreck
// palette: #ff6a3c #ffc861 #3cf0ff
// A dive on a listing ocean-liner wreck: god rays, torch beam, sonar, whale in the haze.

fn sw_caustic(p: vec2f, t: f32) -> f32 {
    let w = vec2f(noise2(p * 3.0 + vec2f(t * 0.4, 0.0)), noise2(p * 3.0 - vec2f(0.0, t * 0.3) + 7.0));
    let n1 = noise2(p * 4.0 + w * 1.6 + t * 0.2);
    let n2 = noise2(p * 6.3 - w * 1.2 - t * 0.17 + 3.0);
    return pow(1.0 - abs(2.0 * n1 - 1.0), 7.0) + 0.6 * pow(1.0 - abs(2.0 * n2 - 1.0), 9.0);
}

// humpback, local units, head toward +x, y up
fn sw_whale(q: vec2f, t: f32) -> f32 {
    let x = q.x;
    let bend = sin(x * 2.5 - t * 0.8) * 0.035 * smoothstep(0.2, -0.9, x);
    let y = q.y - bend;
    let u = clamp((x + 0.9) / 1.75, 0.0, 1.0);
    let th = 0.15 * pow(max(sin(u * PI * 0.92 + 0.08), 0.0), 0.7) * mix(0.3, 1.0, smoothstep(0.0, 0.55, u));
    var d = max(abs(y + 0.03 * u) - th, abs(x + 0.025) - 0.875);
    let flap = sin(t * 0.8) * 0.05;
    let fq = vec2f(x + 0.9, y - bend);
    d = min(d, sd_segment(fq, vec2f(0.0), vec2f(-0.13, 0.13 + flap)) - 0.022);
    d = min(d, sd_segment(fq, vec2f(0.0), vec2f(-0.13, -0.13 + flap)) - 0.022);
    let pa = vec2f(0.38, -0.07);
    let pb = pa + rot(sin(t * 0.5) * 0.25) * vec2f(-0.22, -0.26);
    let pd = sd_segment(q, pa, pb);
    d = min(d, pd - 0.03 * (1.0 - 0.6 * clamp(length(q - pa) / 0.34, 0.0, 1.0)));
    return d;
}

// 7-segment digit, q: x 0..1, y 0..2 (y up). x = lit distance, y = unlit distance
fn sw_digit(q: vec2f, dg: i32) -> vec2f {
    var m = 0u;
    switch (dg) {
        case 0: { m = 63u; } case 1: { m = 6u; } case 2: { m = 91u; } case 3: { m = 79u; } case 4: { m = 102u; }
        case 5: { m = 109u; } case 6: { m = 125u; } case 7: { m = 7u; } case 8: { m = 127u; } case 9: { m = 111u; }
        default: { m = 0u; }
    }
    var dl = 1e3;
    var du = 1e3;
    for (var s = 0u; s < 7u; s++) {
        var a = vec2f(0.0);
        var b = vec2f(0.0);
        switch (s) {
            case 0u: { a = vec2f(0.18, 2.0); b = vec2f(0.82, 2.0); }
            case 1u: { a = vec2f(1.0, 1.18); b = vec2f(1.0, 1.82); }
            case 2u: { a = vec2f(1.0, 0.18); b = vec2f(1.0, 0.82); }
            case 3u: { a = vec2f(0.18, 0.0); b = vec2f(0.82, 0.0); }
            case 4u: { a = vec2f(0.0, 0.18); b = vec2f(0.0, 0.82); }
            case 5u: { a = vec2f(0.0, 1.18); b = vec2f(0.0, 1.82); }
            default: { a = vec2f(0.18, 1.0); b = vec2f(0.82, 1.0); }
        }
        let d = sd_segment(q, a, b);
        if (((m >> s) & 1u) == 1u) { dl = min(dl, d); } else { du = min(du, d); }
    }
    return vec2f(dl, du);
}

fn sw_floor(x: f32) -> f32 { return -0.66 + 0.07 * fbm2(vec2f(x * 1.2, 0.5), 3) + 0.025 * sin(x * 2.1) + 0.07 * exp(-pow((x - 0.25) / 1.1, 2.0)); }

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let p0 = centered(fc);
    let px = 2.0 / G.res.y;
    let t = G.time;
    // song sections: Quiet / Verse / Build / Chorus / Breakdown / Drop
    let sQ = sec(SEC_QUIET);
    let sB = sec(SEC_BUILD);
    let sC = sec(SEC_CHORUS);
    let sK = sec(SEC_BREAKDOWN);
    let sD = sec(SEC_DROP);
    let bprog = select(1.0, sec_progress(12.0), G.section == SEC_BUILD) * sB;   // build-up tension 0..1
    // camera: pushes in during the build-up, pulls wide in the chorus, punches on drop kicks
    let zoom = 1.0 + 0.2 * bprog - 0.08 * sC - 0.04 * sK + 0.05 * G.kick * sD;
    let shk = (vec2f(noise2(vec2f(t * 25.0, 1.0)), noise2(vec2f(t * 25.0, 9.0))) - 0.5) * (0.012 * bprog + 0.02 * sD * G.kick);
    let p = p0 / zoom + shk;
    let A = G.aspect;
    let ph = G.beat_phase;
    let bc = floor(G.beat_count);
    let act = smoothstep(0.02, 0.08, G.energy);
    let vis = clamp(0.55 + 0.45 * G.energy - 0.3 * sQ + 0.35 * sC + 0.2 * sK, 0.2, 1.2);   // visibility: big sections clear the haze

    // ---- water column, colour temperature from the centroid ----
    let deep = vec3f(0.0, 0.025, 0.07);
    let shallow = mix(vec3f(0.03, 0.22, 0.36), vec3f(0.06, 0.3, 0.34), G.centroid);
    var water = mix(deep, shallow, smoothstep(-1.1, 1.2, p.y));
    water *= 1.0 - 0.45 * sQ;
    water += vec3f(0.02, 0.15, 0.15) * sC * smoothstep(-0.6, 1.2, p.y);                       // chorus: sunlit turquoise
    water += G.pal0.rgb * (0.06 * bprog) * (0.5 + 0.5 * sin(t * (3.0 + 8.0 * bprog)));        // build: red alarm pulse
    var col = water;

    // surface shimmer, rippled by the waveform
    let sh = smoothstep(0.78, 1.0, p.y + wave(uv.x) * 0.04 + 0.03 * sin(p.x * 6.0 + t));
    col += vec3f(0.15, 0.35, 0.4) * sh * (0.6 + 0.6 * noise2(vec2f(p.x * 9.0 + t * 0.5, t * 0.7)));

    // ---- god rays breathing with the sub ----
    let ro = vec2f(-0.3 + 0.35 * sin(t * 0.05), 1.7);
    let rd = p - ro;
    let ang = atan2(rd.x, -rd.y);
    let rn = noise2(vec2f(ang * 9.0, t * 0.15)) * noise2(vec2f(ang * 23.0 + 3.0, t * 0.25));
    let rays = smoothstep(0.12, 0.55, rn) * smoothstep(-1.1, 1.0, p.y);
    let breathe = (0.25 + 0.65 * G.bass + 0.25 * G.beat + 0.6 * G.drop) * (1.0 - 0.6 * sQ - 0.3 * sB) + 0.9 * sC + 0.45 * sK;
    let raywide = rays + sC * smoothstep(0.05, 0.4, rn) * 0.6;
    let raycol = mix(vec3f(0.2, 0.5, 0.55), G.pal1.rgb * 0.8, 0.55 * sC + 0.2 * sK);
    col += raycol * raywide * breathe * 0.6;

    // ---- humpback whale gliding in the haze ----
    let wc = vec2f(A + 1.3 - fract(t * 0.008 + 0.55) * (2.0 * A + 2.6), 0.5 + sin(t * 0.1) * 0.05);
    let wsc = 0.95 + 0.5 * sK + 0.2 * sC + 0.25 * sQ;
    let wq = vec2f(-(p.x - wc.x), p.y - wc.y) / wsc;
    if (abs(wq.x) < 1.2 && abs(wq.y) < 0.5) {
        let wd = sw_whale(wq, t);
        let wf = fill(wd, px / wsc * 3.0);
        var wcol = water * 0.62 + vec3f(0.03, 0.07, 0.09) * smoothstep(-0.1, 0.12, wq.y);
        wcol += vec3f(0.12, 0.25, 0.28) * exp(-abs(wd) / 0.006) * step(0.0, wq.y) * 0.6;
        col = mix(col, wcol, wf * (0.3 + 0.3 * vis + 0.3 * sK + 0.2 * sQ));
    }

    // ---- sonar sources: the diver on every beat, and any click ----
    let dpos = vec2f(-A * 0.62 + 0.08 * sin(t * 0.13), 0.1 + 0.06 * sin(t * 0.21));
    let phs = mix(ph, fract(ph * (1.0 + 3.0 * bprog)), sB);   // build: sonar pings faster and faster
    let s1r = phs * 3.4;
    let s1a = (1.0 - phs) * act * (1.0 - 0.6 * sQ - 0.8 * sK + 0.6 * bprog);
    let cpos = vec2f((G.click_pos.x - 0.5) * A * 2.0, (0.5 - G.click_pos.y) * 2.0);
    let s2r = G.click_age * 2.4;
    let s2a = max(1.0 - G.click_age / 1.6, 0.0);
    let ring1 = exp(-abs(length(p - dpos) - s1r) * 22.0) * s1a;
    let ring2 = exp(-abs(length(p - cpos) - s2r) * 22.0) * s2a;
    let sonar = ring1 + ring2 * 1.3;
    let sonc = G.pal2.rgb;
    col += sonc * sonar * 0.07;

    // ---- torch: aims at the cursor, otherwise sweeps the hull; snares make it flare ----
    let tp = dpos + vec2f(0.15, -0.02);
    let wcen = vec2f(0.25, -0.4);
    var sweep = wcen + vec2f(sin(t * 0.23) * 0.95 + sin(t * 3.1) * 0.35 * sD, 0.12 + 0.12 * sin(t * 0.37));
    sweep = mix(sweep, wcen + vec2f(0.0, 0.1), 0.9 * bprog);   // build: the beam locks onto the wreck
    let mp = vec2f((G.mouse.x - 0.5) * A * 2.0, (0.5 - G.mouse.y) * 2.0);
    let ad = normalize(mix(sweep, mp, G.mouse_on) - tp + vec2f(1e-4, 0.0));
    let rel = p - tp;
    let al = dot(rel, ad);
    let pr = length(rel - ad * al);
    let cw = 1.0 - 0.45 * bprog + 0.35 * sC;
    let cone = smoothstep((0.2 * al + 0.02) * cw, (0.09 * al + 0.004) * cw, pr) * step(0.0, al) * exp(-al * 0.55);
    let tflick = 1.0 + bprog * (0.5 * sin(t * 37.0) + 1.2 * G.snare);
    let tpow = (0.8 + 0.9 * G.snare + 0.3 * G.mid) * tflick * (1.0 - 0.85 * sQ - 0.85 * sK) * (1.0 + 0.5 * sD + 0.2 * sC);
    let torchc = vec3f(1.0, 0.92, 0.75);

    // ---- the wreck: a listing ocean liner ----
    let ws = 1.3;
    let wp = (rot(0.07) * (p - wcen)) / ws;
    let wpx = px / ws;
    var wr = 1e3;
    if (abs(wp.x) < 1.05 && wp.y > -0.3 && wp.y < 0.62) {
        let hb = sd_round_box(wp - vec2f(-0.02, -0.06), vec2f(0.9, 0.16), 0.05);
        let bow = (wp.x - 0.78 - (wp.y + 0.22) * 0.45) * 0.9;
        let hull = max(hb, bow);
        let s1 = sd_box(wp - vec2f(-0.12, 0.14), vec2f(0.55, 0.05));
        let s2 = sd_box(wp - vec2f(-0.1, 0.22), vec2f(0.42, 0.035));
        let s3 = sd_box(wp - vec2f(0.24, 0.28), vec2f(0.09, 0.03));
        let sup = min(s1, min(s2, s3)) + (fbm2(wp * 18.0, 3) - 0.45) * 0.03;
        var fun = 1e3;
        var fy = 0.0;
        for (var k = 0; k < 2; k++) {
            let fq = wp - vec2f(-0.36 + f32(k) * 0.3, 0.25);
            let sx = fq.x - fq.y * 0.3;
            let fd = sd_round_box(vec2f(sx, fq.y - 0.13), vec2f(0.07, 0.13), 0.025);
            if (fd < fun) { fun = fd; fy = fq.y; }
        }
        let mast = min(min(sd_segment(wp, vec2f(0.62, 0.1), vec2f(0.65, 0.4)) - 0.01,
                           sd_segment(wp, vec2f(0.65, 0.4), vec2f(0.88, 0.13)) - 0.008),
                       sd_segment(wp, vec2f(-0.72, 0.1), vec2f(-0.72, 0.24)) - 0.01);
        let rail = min(abs(wp.y - 0.135) - 0.002, max(abs(wp.y - 0.118) - 0.017, abs(fract(wp.x * 40.0) - 0.5) / 40.0 - 0.0015));
        wr = min(min(hull, sup), min(fun, mast));
        let wf = fill(wr, wpx);
        if (wf > 0.0) {
            let alg = fbm2(wp * 7.0, 4);
            var base = mix(vec3f(0.2, 0.1, 0.06), vec3f(0.07, 0.13, 0.08), smoothstep(0.35, 0.7, alg));
            if (hull < 0.0) {
                if (abs(fract(wp.y * 24.0) - 0.5) > 0.44 || fract(wp.x * 11.0) < 0.03) { base *= 0.7; }
                base *= 0.7 + 0.5 * smoothstep(-0.2, 0.1, wp.y);
                if (fbm2(wp * 4.0 + 11.0, 3) > 0.66) { base *= 0.15; }    // torn breaches
            } else if (sup < 0.0) {
                base = mix(vec3f(0.34, 0.38, 0.36), base, 0.6);
                if (abs(wp.y - 0.145) < 0.012 && fract(wp.x * 30.0) < 0.55) { base *= 0.25; }
                if (abs(wp.y - 0.225) < 0.01 && fract(wp.x * 26.0) < 0.5) { base *= 0.3; }
            } else if (fun < 0.0) {
                var fcol = vec3f(0.55, 0.55, 0.52);
                if (fy > 0.19) { fcol = vec3f(0.55, 0.08, 0.06); }
                else if (fy < 0.06) { fcol = vec3f(0.06, 0.12, 0.35); }
                fcol *= 0.55 + 0.45 * smoothstep(0.3, 0.65, noise2(wp * vec2f(60.0, 6.0)));
                base = mix(fcol * 0.75, base, 0.5);
            } else { base = vec3f(0.12, 0.1, 0.08); }
            // light: ambient haze + caustics on the upper surfaces + the torch
            let topl = smoothstep(-0.15, 0.4, wp.y);
            var wl = base * (0.35 + 0.35 * G.energy);
            wl += base * sw_caustic(p * 1.4, t) * topl * (0.6 + 1.2 * G.hat + 0.6 * G.high);
            wl += base * torchc * cone * tpow * 3.0;
            // portholes as spectrum bars: lower row = now, upper row = 0.6 s ago
            if (hull < 0.0) {
                let pidx = floor((wp.x + 0.82) / 0.045);
                if (pidx >= 0.0 && pidx < 35.0) {
                    let pcx = -0.82 + (pidx + 0.5) * 0.045;
                    let b = pidx / 35.0;
                    let r1 = length(wp - vec2f(pcx, -0.02));
                    let r2 = length(wp - vec2f(pcx, 0.045));
                    let v1 = pow(spec(0.02 + b * 0.8), 1.3);
                    let v2 = pow(hist(0.02 + b * 0.8, 0.19), 1.3);
                    if (r1 < 0.016) { wl = mix(vec3f(0.35, 0.25, 0.12), vec3f(1.0, 0.72, 0.32) * (0.1 + 3.0 * v1 * (1.0 + 1.5 * sD + 0.6 * sC)), step(r1, 0.011)); }
                    if (r2 < 0.014) { wl = mix(vec3f(0.35, 0.25, 0.12), G.pal1.rgb * (0.05 + 2.5 * v2), step(r2, 0.0095)); }
                    wl += vec3f(1.0, 0.7, 0.3) * v1 * 0.25 * glow(r1 - 0.011, 0.01);
                }
            }
            // octopus on the foredeck: colour jumps on every beat, flashes on kicks
            let op = (wp - vec2f(0.46, 0.1)) / 1.7;
            if (abs(op.x) < 0.16 && op.y > -0.02 && op.y < 0.14) {
                var od = (length((op - vec2f(-0.01, 0.068)) / vec2f(0.042, 0.055)) - 1.0) * 0.042;
                for (var k = 0; k < 6; k++) {
                    let fk = f32(k);
                    let sdir = select(-1.0, 1.0, k % 2 == 0);
                    let L = 0.07 + 0.05 * hash11(fk * 5.0);
                    let xx = op.x * sdir;
                    if (xx > 0.0 && xx < L) {
                        let s = xx / L;
                        let cy = 0.01 + 0.03 * s * s * sin(s * 6.0 + t * 1.5 + fk * 1.7) + fk * 0.002;
                        od = min(od, abs(op.y - cy) - 0.011 * (1.0 - s * 0.85));
                    }
                }
                let ofl = fill(od, wpx / 1.7);
                if (ofl > 0.0) {
                    let hue = fract(0.02 + bc * 0.29);
                    var oc = hsv(hue, 0.8, 0.55 + 0.9 * G.kick);
                    oc *= 0.7 + 0.5 * noise2(op * 120.0);
                    if (length(op - vec2f(0.02, 0.085)) < 0.007) { oc = vec3f(0.9, 0.85, 0.5); }
                    oc += oc * cone * tpow * 4.0;
                    wl = mix(wl, oc, ofl);
                }
            }
            // build: breaches glow red-hot; drop: the whole hull lights up
            let hotb = smoothstep(0.55, 0.7, fbm2(wp * 4.0 + 11.0, 3)) * step(hull, 0.0);
            wl += vec3f(1.0, 0.18, 0.06) * hotb * bprog * (0.6 + 1.5 * G.snare) + G.pal0.rgb * base * sD * (1.5 + 2.5 * G.kick);
            wl = mix(wl, water * 0.9, 0.3 * (1.0 - vis * 0.6));
            col = mix(col, wl, wf);
        }
        // sonar paints the outline as it passes; the torch also rim-lights it
        let edge = exp(-abs(wr) / (wpx * 3.0));
        col += sonc * edge * sonar * 2.2;
        col += sonc * edge * 0.04;
        let rl = fill(rail, wpx) * step(-0.85, wp.x) * step(wp.x, 0.75);
        col = mix(col, vec3f(0.12, 0.1, 0.08), rl * 0.8);
    }

    // ---- DROP ONLY: the wreck erupts, rotating light shafts and a shockwave on every beat ----
    if (sD > 0.01) {
        let dr = p - wcen;
        let dl = length(dr);
        let a2 = atan2(dr.y, dr.x);
        let shafts = pow(max(sin(a2 * 5.0 + t * 0.9 + G.travel * 0.1), 0.0), 10.0) * exp(-dl * 0.6) * (0.5 + 0.5 * noise2(vec2f(a2 * 6.0, t)));
        let shock = exp(-abs(dl - ph * 3.0) * 12.0) * (1.0 - ph);
        col += mix(G.pal0.rgb, G.pal1.rgb, 0.5 + 0.5 * sin(t)) * (shafts * (0.7 + 1.2 * G.kick) + shock * 0.8) * sD;
    }

    // ---- seafloor with dancing caustics ----
    let fl = sw_floor(p.x);
    if (p.y < fl + px) {
        let depthf = clamp((fl - p.y) / 0.4, 0.0, 1.0);
        var sc = mix(vec3f(0.32, 0.33, 0.27), vec3f(0.1, 0.12, 0.13), depthf);
        sc *= 0.85 + 0.25 * sin(p.x * 38.0 + fbm2(p * 3.0, 3) * 7.0);
        sc *= 0.8 + 0.4 * fbm2(p * 9.0, 3);
        var sl = sc * (0.45 + 0.35 * G.energy);
        sl += sc * sw_caustic(p * vec2f(1.0, 2.2), t) * (0.5 + 1.0 * G.hat + 0.5 * G.high) * (1.0 - depthf * 0.6);
        sl += sc * torchc * cone * tpow * 4.0;
        sl = mix(sl, water, 0.2 * (1.0 - vis));
        col = mix(col, sl, fill(p.y - fl, px));
        col += sonc * exp(-abs(p.y - fl) / (px * 2.0)) * sonar * 1.2;
    }

    // ---- volumetric torch beam ----
    let beam = cone * (0.55 + 0.45 * noise2(p * 7.0 + vec2f(t * 0.3, -t * 0.2)));
    col += torchc * beam * tpow * 0.16;
    col += torchc * glow(length(rel), 0.012) * 0.35 * tpow;

    // ---- diver silhouette ----
    let dq = (p - dpos) / 0.14;
    if (abs(dq.x) < 2.2 && abs(dq.y) < 1.0) {
        let kk = sin(t * 3.0) * 0.18;
        let hip = vec2f(-0.6, 0.0);
        var dd = sd_segment(dq, hip, vec2f(0.45, 0.02)) - 0.24;
        dd = min(dd, length(dq - vec2f(0.72, 0.08)) - 0.2);
        dd = min(dd, sd_segment(dq, vec2f(-0.5, 0.28), vec2f(0.2, 0.3)) - 0.13);
        dd = min(dd, sd_segment(dq, hip, vec2f(-1.3, 0.12 + kk)) - 0.11);
        dd = min(dd, sd_segment(dq, hip, vec2f(-1.3, -0.12 - kk)) - 0.11);
        dd = min(dd, sd_segment(dq, vec2f(-1.3, 0.12 + kk), vec2f(-1.85, 0.2 + kk * 1.6)) - 0.07);
        dd = min(dd, sd_segment(dq, vec2f(-1.3, -0.12 - kk), vec2f(-1.85, -0.2 - kk * 1.6)) - 0.07);
        dd = min(dd, sd_segment(dq, vec2f(0.3, -0.05), vec2f(0.3, -0.05) + ad * 0.85) - 0.08);
        let df = fill(dd, px / 0.14);
        var dc = vec3f(0.015, 0.03, 0.045);
        dc += vec3f(0.1, 0.25, 0.3) * exp(-abs(dd) / 0.05) * smoothstep(-0.2, 0.4, dq.y) * 0.6;
        col = mix(col, dc, df);
    }

    // ---- bioluminescent jellyfish: pulse on kicks, thrust upward on every beat ----
    let thrust = bc + smoothstep(0.0, 0.35, ph) * act;
    let con = pow(1.0 - ph, 3.0) * act;
    for (var i = 0; i < 6; i++) {
        let fi = f32(i);
        let sd = hash11(fi * 3.1 + 1.0);
        let s = (0.045 + sd * 0.04) * (1.0 + 0.7 * sK + 0.2 * sC);
        let lift = thrust * 0.035 + t * 0.012 + sd * 7.0 + fi * 0.37;
        let jp = vec2f((hash11(fi * 7.7) * 2.0 - 1.0) * A * 0.85 + sin(t * 0.2 + fi) * 0.1, -1.35 + fract(lift / 2.7) * 2.7);
        let jq = p - jp;
        if (abs(jq.x) > s * 2.2 || jq.y > s * 1.6 || jq.y < -s * 5.0) { continue; }
        let bw = s * (1.0 - 0.25 * con);
        let bh = s * (0.75 + 0.3 * con);
        let bd = max((length(vec2f(jq.x / bw, jq.y / bh)) - 1.0) * bh, -jq.y - bh * 0.1);
        let jc = select(G.pal0.rgb, G.pal2.rgb, sd > 0.45);
        let pulse = 0.6 + (1.3 * G.kick + 0.3 * G.beat) * (1.0 - sK) + sK * (0.5 + 1.8 * G.mid + 1.5 * spec(0.2 + 0.1 * fi)) + 0.5 * sC;
        let jw = select(1.0 - 0.9 * sQ, 1.0, i < 2);   // quiet: only two jellyfish drift by
        var jl = fill(bd, px) * (0.25 + 0.3 * noise2(jq * 90.0 + t)) + exp(-abs(bd) / 0.004) * 0.7 + glow(bd, 0.025) * 0.2;
        if (jq.y < 0.0) {
            for (var k = 0; k < 4; k++) {
                let fk = f32(k);
                let tx = (fk / 3.0 - 0.5) * bw * 1.4 + sin(jq.y * 35.0 + t * 3.0 + fk + fi) * 0.014 * (-jq.y / s);
                jl += 0.45 * exp(-abs(jq.x - tx) / 0.0022) * smoothstep(-s * 4.8, 0.0, jq.y);
            }
            jl += 0.5 * exp(-abs(jq.x - sin(jq.y * 20.0 + t * 2.0 + fi) * 0.01) / 0.006) * smoothstep(-s * 2.5, 0.0, jq.y);
        }
        col += mix(jc, G.pal2.rgb, 0.4 * sK) * jl * pulse * jw * (0.7 + 0.3 * vis);
    }

    // ---- fish school: circles calmly, bursts apart on the drop ----
    let scen = vec2f(-0.35 + 0.55 * sin(t * 0.07), 0.48 + 0.12 * sin(t * 0.11));
    let burst = (1.0 - 0.55 * bprog + 0.5 * sC) + G.drop * 5.0;   // build: school tightens; chorus: wide spiral
    if (length((p - scen) * vec2f(0.6, 1.0)) < 0.35 * burst + 0.08) {
        let nf = i32(f32(24 + i32(G.quality) * 12) * (1.0 - 0.7 * sQ - 0.4 * sK));
        for (var i = 0; i < 48; i++) {
            if (i >= nf) { break; }
            let fi = f32(i);
            let hs = hash11(fi * 1.37 + 0.5);
            let a = t * 0.35 * (1.0 + hs * 0.4) + fi * 2.39 + G.travel * 0.02 + bprog * t * 0.7;
            let rad = (0.06 + hash11(fi * 3.3) * 0.28) * burst;
            let fp = scen + vec2f(cos(a) * rad * 1.6, sin(a) * rad * 0.42 + sin(fi + t) * 0.02);
            let fq = (p - fp) * vec2f(select(1.0, -1.0, sin(a) > 0.0), 1.0);
            if (abs(fq.x) > 0.04 || abs(fq.y) > 0.015) { continue; }
            var fd = (length(fq / vec2f(0.026, 0.0085)) - 1.0) * 0.0085;
            fd = min(fd, max(abs(fq.y) - (-0.022 - fq.x) * 0.7 - 0.001, abs(fq.x + 0.031) - 0.009));
            let glint = 0.5 + 0.5 * sin(t * 4.0 + fi * 3.0) + G.hat * hs;
            let fcol = vec3f(0.45, 0.6, 0.65) * (0.35 + 0.5 * glint) + torchc * cone * 1.5;
            col = mix(col, fcol, fill(fd, px) * (0.6 + 0.4 * vis));
        }
    }

    // ---- bubbles: from the diver, from the wreck, more when the music is busy ----
    let nb = min(i32((8.0 + G.flux * 12.0 + 12.0 * bprog + 6.0 * sC) * (1.0 - 0.5 * sQ)), 20);
    for (var i = 0; i < 20; i++) {
        if (i >= nb) { break; }
        let fi = f32(i);
        let hs = hash11(fi * 4.7);
        var src = dpos + vec2f(0.08, 0.04);
        if (i % 3 == 1) { src = wcen + vec2f((hash11(fi * 2.3) - 0.5) * 1.6, 0.1); }
        let life = fract(t * (0.12 + hs * 0.1) + hash11(fi * 9.1));
        let bp = src + vec2f(sin(life * 12.0 + fi) * 0.02, life * 2.2);
        let r = 0.004 + hs * 0.008;
        let d = length(p - bp);
        col += vec3f(0.55, 0.8, 0.9) * (exp(-abs(d - r) / 0.0018) * 0.5 + step(length(p - bp - vec2f(-0.3, 0.3) * r), r * 0.3) * 0.6) * (1.0 - life * 0.5);
    }

    // ---- marine snow, glinting on hats and in the torch beam ----
    for (var l = 0; l < 2; l++) {
        let fl2 = f32(l);
        let scl = 9.0 + fl2 * 8.0;
        let q = p * scl + vec2f(sin(t * 0.1 + fl2) * 1.5, t * (0.2 + fl2 * 0.15));
        let cell = floor(q);
        let f = fract(q) - 0.5;
        let h = hash22(cell + fl2 * 17.0);
        let dd = length(f - (h - 0.5) * 0.8);
        let flake = smoothstep(0.06 + fl2 * 0.01, 0.0, dd) * step(0.45, hash21(cell + 3.0 + fl2));
        col += vec3f(0.6, 0.75, 0.8) * flake * (0.12 + 0.35 * G.hat * h.x + cone * tpow * 1.2);
    }

    // ---- BREAKDOWN: drifting glowing plankton, each mote lit by its own part of the melody ----
    if (sK > 0.01) {
        let nm = 16 + i32(G.quality) * 8;
        for (var i = 0; i < 32; i++) {
            if (i >= nm) { break; }
            let fi = f32(i);
            let hs = hash11(fi * 2.9 + 0.3);
            let mx = (hash11(fi * 5.3) * 2.0 - 1.0) * A + 0.12 * sin(t * 0.25 + fi);
            let my = fract(t * (0.02 + 0.03 * hs) + hash11(fi * 8.1)) * 2.8 - 1.4;
            let md = length(p - vec2f(mx, my));
            let mb = 0.15 + 3.0 * spec(0.04 + 0.5 * hs) + 1.2 * G.mid;
            col += mix(G.pal2.rgb, G.pal1.rgb, hs) * (exp(-md * md * 9000.0) * 1.5 + 0.0012 / (md + 0.01)) * mb * sK;
        }
    }

    // ---- kelp forest framing the shot, swaying with the mids ----
    for (var k = 0; k < 6; k++) {
        let fk = f32(k);
        let side = select(-1.0, 1.0, k >= 3);
        let kk = f32(k % 3);
        let bx = side * (A - 0.05 - kk * 0.13 - hash11(fk * 3.3) * 0.05);
        let h = p.y - sw_floor(bx) + 0.12;
        let height = 1.3 + hash11(fk * 1.9) * 0.6;
        if (h < 0.0 || h > height || abs(p.x - bx) > 0.25) { continue; }
        let s = h / height;
        let cx = bx + sin(h * 2.5 - t * 1.2 + fk) * 0.05 * s + sin(t * 0.4 + fk) * 0.07 * s * s * (1.0 + 1.5 * G.mid) - side * 0.06 * s;
        var kd = abs(p.x - cx) - 0.007;
        let li = floor(h / 0.085);
        let ly = h - (li + 0.5) * 0.085;
        let ldir = select(-1.0, 1.0, (i32(li) + k) % 2 == 0);
        let lx = (p.x - cx) * ldir;
        if (lx > 0.0 && lx < 0.14 && s > 0.15) {
            kd = min(kd, abs(ly - lx * 0.3 - sin(t * 1.5 + li) * 0.012) - 0.028 * sqrt(max(1.0 - lx / 0.14, 0.0)) * smoothstep(0.0, 0.02, lx) - 0.002);
        }
        let kf = fill(kd, px);
        let kc = mix(vec3f(0.015, 0.03, 0.015), vec3f(0.22, 0.25, 0.06), smoothstep(0.0, 1.0, s) * (0.4 + 0.6 * G.energy)) * (0.8 + 0.4 * noise2(p * vec2f(30.0, 8.0)));
        col = mix(col, kc + torchc * cone * 0.3, kf * 0.95);
    }

    // drop: a flash of surface light from above
    col += vec3f(0.3, 0.5, 0.55) * G.drop * 0.25 * smoothstep(-1.0, 1.0, p.y);

    // colour treatment per section: quiet = cold and dim, chorus = warm and golden, drop = hot flip, build = red edges
    col = mix(col, vec3f(luma(col)) * vec3f(0.7, 0.9, 1.1), 0.4 * sQ);
    col = col * mix(vec3f(1.0), vec3f(1.06, 1.1, 1.0), sC) + G.pal1.rgb * 0.025 * sC;
    col = mix(col, col * vec3f(1.4, 0.88, 0.7) + G.pal0.rgb * 0.04, 0.65 * sD);
    col += G.pal0.rgb * 0.18 * bprog * pow(length(uv - 0.5) * 1.3, 2.0) * (0.4 + 0.6 * (1.0 - ph));

    // vignette (depth darkness at the edges)
    col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.3, 2.0);

    // ---- dive computer HUD: depth + dive time in 7-segment digits ----
    let hc = vec2f(A - 0.36, -0.8);
    let hq = p0 - hc;
    let pd = sd_round_box(hq, vec2f(0.3, 0.135), 0.03);
    if (pd < 0.01) {
        col = mix(col, vec3f(0.01, 0.02, 0.025), fill(pd, px) * 0.8);
        col += sonc * exp(-abs(pd) / 0.003) * 0.5;
        let depth = 31.0 + 4.0 * sin(t * 0.03) + G.energy * 2.0 + 0.3 * sin(t * 0.7);
        let secs = floor(G.look_time);
        var lit = 1e3;
        var unl = 1e3;
        let dsz = 0.032;
        for (var i = 0; i < 7; i++) {
            var dg = 0;
            var org = vec2f(0.0);
            if (i < 3) {
                org = vec2f(-0.26 + f32(i) * 0.06 + select(0.0, 0.02, i == 2), 0.0);
                let dv = floor(depth * 10.0);
                if (i == 0) { dg = i32(floor(dv / 100.0)) % 10; } else if (i == 1) { dg = i32(floor(dv / 10.0)) % 10; } else { dg = i32(dv) % 10; }
            } else {
                let j = i - 3;
                org = vec2f(0.03 + f32(j) * 0.06 + select(0.0, 0.025, j >= 2), 0.0);
                let mm = floor(secs / 60.0) % 100.0;
                let ss = secs % 60.0;
                if (j == 0) { dg = i32(floor(mm / 10.0)); } else if (j == 1) { dg = i32(mm) % 10; } else if (j == 2) { dg = i32(floor(ss / 10.0)); } else { dg = i32(ss) % 10; }
            }
            let dq2 = (hq - org - vec2f(0.0, -0.045)) / dsz;
            if (dq2.x > -0.5 && dq2.x < 1.5 && dq2.y > -0.5 && dq2.y < 2.5) {
                let r = sw_digit(dq2, dg);
                lit = min(lit, r.x * dsz);
                unl = min(unl, r.y * dsz);
            }
        }
        // decimal point and colon
        lit = min(lit, length(hq - vec2f(-0.143, -0.043)) - 0.006);
        lit = min(lit, min(length(hq - vec2f(0.158, -0.02)) - 0.005, length(hq - vec2f(0.158, 0.0)) - 0.005));
        let segc = mix(vec3f(0.3, 1.0, 0.8), G.pal2.rgb, 0.5);
        col += segc * fill(lit - 0.0045, px) * 1.3;
        col += segc * fill(unl - 0.0045, px) * 0.06;
        // energy gauge + beat dot
        let gx = (hq.x + 0.26) / 0.52;
        if (gx > 0.0 && gx < 1.0 && abs(hq.y - 0.085) < 0.012) {
            let seg = fract(gx * 16.0);
            col += segc * step(0.2, seg) * select(0.08, 1.0, gx < G.energy * 0.8 + G.bass * 0.2) * 0.9;
        }
        col += G.pal0.rgb * fill(length(hq - vec2f(0.255, -0.105)) - 0.01, px) * (0.2 + 1.5 * (1.0 - ph) * act);
        // little "m" mark after the depth
        let mq = hq - vec2f(-0.07, -0.045);
        let md = min(min(sd_segment(mq, vec2f(0.0), vec2f(0.0, 0.03)), sd_segment(mq, vec2f(0.012, 0.0), vec2f(0.012, 0.025))),
                     min(sd_segment(mq, vec2f(0.024, 0.0), vec2f(0.024, 0.025)), sd_segment(mq, vec2f(0.0, 0.03), vec2f(0.024, 0.03))));
        col += segc * fill(md - 0.003, px) * 0.8;
    }

    return vec4f(col, 1.0);
}
