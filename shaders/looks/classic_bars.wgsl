// name: Classic Bars
// palette: #22ff66 #ffd21a #ff2a1a
// A premium rack-mount spectrum analyser: LED bars with falling peak-hold, analogue VU meters,
// phosphor scope, brushed-metal rack ears, glass front, glossy floor reflection.
// pal0 -> pal1 -> pal2 = LED colour from the bottom of a bar to the top.

const CB_N: f32 = 32.0;     // bars
const CB_S: f32 = 24.0;     // LED segments per bar

fn cb_ln(d: f32, w: f32) -> f32 { return clamp(1.0 - d / w, 0.0, 1.0); }

fn cb_seg7(p: vec2f, dg: i32) -> f32 {
    var m = array<u32, 10>(0x3Fu, 0x06u, 0x5Bu, 0x4Fu, 0x66u, 0x6Du, 0x7Du, 0x07u, 0x7Fu, 0x6Fu);
    let bits = m[clamp(dg, 0, 9)];
    let w = 0.5; let h = 1.0; let g = 0.14;
    var d = 1e5;
    if ((bits & 1u) != 0u) { d = min(d, sd_segment(p, vec2f(-w + g, h), vec2f(w - g, h))); }
    if ((bits & 2u) != 0u) { d = min(d, sd_segment(p, vec2f(w, h - g), vec2f(w, g))); }
    if ((bits & 4u) != 0u) { d = min(d, sd_segment(p, vec2f(w, -g), vec2f(w, -h + g))); }
    if ((bits & 8u) != 0u) { d = min(d, sd_segment(p, vec2f(-w + g, -h), vec2f(w - g, -h))); }
    if ((bits & 16u) != 0u) { d = min(d, sd_segment(p, vec2f(-w, -g), vec2f(-w, -h + g))); }
    if ((bits & 32u) != 0u) { d = min(d, sd_segment(p, vec2f(-w, h - g), vec2f(-w, g))); }
    if ((bits & 64u) != 0u) { d = min(d, sd_segment(p, vec2f(-w + g, 0.0), vec2f(w - g, 0.0))); }
    return d;
}
// all 7 segments (for the unlit ghost of an LED digit)
fn cb_seg8(p: vec2f) -> f32 { return cb_seg7(p, 8); }

// a frequency label: value in Hz drawn as digits, with a 'k' glyph when >= 1000. p: digit units, centred
fn cb_label(p: vec2f, hz: f32) -> f32 {
    let kilo = hz >= 1000.0;
    let v = select(hz, hz / 1000.0, kilo);
    let nd = select(select(1, 2, v >= 10.0), 3, v >= 100.0);
    let total = f32(nd) * 1.5 + select(0.0, 1.3, kilo);
    let q = p + vec2f(total * 0.5, 0.0);
    var d = 1e5;
    for (var i = 0; i < nd; i++) {
        let dg = i32(floor(v / pow(10.0, f32(nd - 1 - i))) % 10.0);
        d = min(d, cb_seg7(q - vec2f(0.5 + f32(i) * 1.5, 0.0), dg));
    }
    if (kilo) {
        let kq = q - vec2f(f32(nd) * 1.5 + 0.3, 0.0);
        d = min(d, sd_segment(kq, vec2f(0.0, 1.0), vec2f(0.0, -1.0)));
        d = min(d, sd_segment(kq, vec2f(0.0, -0.2), vec2f(0.7, 0.4)));
        d = min(d, sd_segment(kq, vec2f(0.25, 0.0), vec2f(0.7, -1.0)));
    }
    return d;
}

fn cb_screw(q: vec2f, r: f32, a: f32, px: f32) -> vec3f {
    let d = length(q) - r;
    var c = vec3f(0.55, 0.56, 0.58) * (0.6 + 0.6 * clamp(dot(normalize(q + vec2f(1e-4)), vec2f(-0.5, 0.7)), -0.5, 1.0) * length(q) / r);
    let sq = (rot(a) * q);
    let slot = min(sd_box(sq, vec2f(r * 0.75, r * 0.12)), sd_box(sq, vec2f(r * 0.12, r * 0.75)));
    c = mix(c, vec3f(0.06), fill(slot, px));
    c *= 0.6 + 0.4 * smoothstep(0.0, -r * 0.4, d);
    return c * fill(d, px);
}

// analogue VU meter, q local (face spans x -0.21..0.21, y -0.15..0.15)
fn cb_vu(q: vec2f, level: f32, px: f32, spot: f32) -> vec3f {
    let face = sd_round_box(q, vec2f(0.21, 0.15), 0.015);
    let warm = mix(vec3f(1.0, 0.78, 0.45), vec3f(1.0, 0.92, 0.75), G.centroid);
    var c = warm * (0.55 + 0.25 * G.energy + 0.25 * spot) * (1.0 - 0.35 * length(q / vec2f(0.25, 0.2)));
    let piv = vec2f(0.0, -0.2);
    let v = q - piv;
    let r = length(v);
    let a = atan2(v.x, v.y);                       // 0 = straight up
    let amax = 0.8;
    // scale arc, red zone, ticks
    let onarc = step(abs(a), amax);
    c = mix(c, vec3f(0.08), cb_ln(abs(r - 0.27), px * 1.2) * onarc);
    let redz = step(0.45, a) * step(a, amax);
    c = mix(c, vec3f(0.85, 0.08, 0.05), step(abs(r - 0.285), 0.012) * redz);
    let tk = abs(fract(a / (amax * 2.0) * 10.0 + 0.5) - 0.5) * (amax * 2.0) / 10.0 * r;
    let mt = abs(fract(a / (amax * 2.0) * 20.0 + 0.5) - 0.5) * (amax * 2.0) / 20.0 * r;
    c = mix(c, select(vec3f(0.08), vec3f(0.75, 0.06, 0.04), a > 0.45), cb_ln(tk, px * 1.3) * step(abs(r - 0.3), 0.025) * onarc);
    c = mix(c, vec3f(0.1), cb_ln(mt, px) * step(abs(r - 0.29), 0.012) * onarc);
    // needle + shadow
    let na = mix(-amax, amax, clamp(level, -0.05, 1.08));
    let tip = piv + vec2f(sin(na), cos(na)) * 0.33;
    let sh = sd_segment(q - vec2f(0.006, -0.008), piv, tip);
    c *= 1.0 - 0.35 * smoothstep(0.012, 0.0, sh);
    let nd = sd_segment(q, piv, tip);
    c = mix(c, vec3f(0.06, 0.02, 0.02), fill(nd - px * 0.6, px));
    // pivot cover
    c = mix(c, vec3f(0.12), fill(sd_round_box(q - vec2f(0.0, -0.15), vec2f(0.21, 0.03), 0.01), px));
    // glass sheen
    c += vec3f(1.0) * 0.12 * smoothstep(0.02, 0.0, abs(q.x * 0.6 + q.y - 0.08)) ;
    var outc = mix(vec3f(0.02), c, fill(face, px));
    // bezel
    outc += vec3f(0.5) * cb_ln(abs(face), px * 2.0) * (0.4 + 0.3 * q.y / 0.15);
    return outc;
}

// the whole device front, q in centred coords. mirror = 1 when drawing the floor reflection
fn cb_device(q: vec2f, px: f32, a: f32, m: vec2f) -> vec3f {
    let x0 = -a + 0.06; let x1 = a - 0.06;
    let y0 = -0.52; let y1 = 0.64;
    let box = sd_box(q - vec2f(0.0, (y0 + y1) * 0.5), vec2f((x1 - x0) * 0.5, (y1 - y0) * 0.5));
    if (box > px * 2.0) { return vec3f(-1.0); }
    let spotd = q - m;
    let spot = exp(-dot(spotd, spotd) / 0.06);
    // brushed aluminium
    let brush = noise2(vec2f(q.x * 3.0, q.y * 700.0)) * 0.6 + hash21(vec2f(floor(q.y * 900.0), 1.0)) * 0.4;
    let aniso = exp(-spotd.x * spotd.x * 6.0 - spotd.y * spotd.y * 30.0);
    let earw = 0.17;
    let inEar = abs(q.x) > a - 0.06 - earw;
    var c = vec3f(0.0);
    if (inEar) {
        c = vec3f(0.33, 0.34, 0.36) * (0.75 + 0.35 * brush) + vec3f(0.5) * aniso * 0.5;
        let ex = sign(q.x) * (a - 0.06 - earw * 0.5);
        // rack slots + screws
        for (var i = 0; i < 2; i++) {
            let sy = select(-0.38, 0.5, i == 1);
            let sq = q - vec2f(ex, sy);
            let slot = sd_round_box(sq, vec2f(0.035, 0.022), 0.02);
            c = mix(c, vec3f(0.03), fill(slot, px));
            c = mix(c, cb_screw(sq, 0.024, 0.6 + f32(i) + ex, px), fill(length(sq) - 0.024, px));
        }
        // handle
        let hq = q - vec2f(ex + sign(q.x) * 0.0, 0.06);
        let hd = sd_round_box(hq, vec2f(0.03, 0.26), 0.03);
        c = mix(c * (1.0 - 0.5 * smoothstep(0.03, 0.0, hd - 0.01)), vec3f(0.62, 0.63, 0.66) * (0.7 + 0.5 * smoothstep(0.03, -0.03, hq.x * sign(q.x))) + aniso * 0.4, fill(hd, px));
        // edge between ear and panel
        c *= 1.0 - 0.6 * cb_ln(abs(abs(q.x) - (a - 0.06 - earw)), px * 2.0);
    } else {
        c = vec3f(0.09, 0.095, 0.1) * (0.8 + 0.4 * brush) + vec3f(0.35) * aniso * 0.35;
    }
    // top/bottom panel bevels
    c += vec3f(0.35) * cb_ln(abs(q.y - y1 + 0.006), px * 2.5) - vec3f(0.06) * cb_ln(abs(q.y - y0 - 0.006), px * 2.5);

    // ---------------- analyser window ----------------
    let gx0 = -a + 0.34; let gx1 = a * 0.3;
    let gy0 = -0.06; let gy1 = 0.53;
    let gc = vec2f((gx0 + gx1) * 0.5, (gy0 + gy1) * 0.5);
    let gh = vec2f((gx1 - gx0) * 0.5, (gy1 - gy0) * 0.5);
    let gd = sd_round_box(q - gc, gh, 0.012);
    if (gd < 0.0) {
        var g = vec3f(0.005, 0.006, 0.008);
        let lx = (q.x - gx0 - 0.02) / (gx1 - gx0 - 0.04);
        let ly = (q.y - gy0 - 0.03) / (gy1 - gy0 - 0.05);
        if (lx > 0.0 && lx < 1.0 && ly > 0.0 && ly < 1.0) {
            let bi = floor(lx * CB_N);
            let bx = (bi + 0.5) / CB_N;
            let fb = fract(lx * CB_N);
            let si = floor(ly * CB_S);
            let fs = fract(ly * CB_S);
            let v = clamp(pow(spec(bx * 0.97), 0.85) * 1.12, 0.0, 1.0);
            // peak hold: highest recent level minus gravity (hold 0.35 s, then fall)
            var pk = 0.0;
            for (var j = 0; j < 14; j++) {
                let ag = f32(j) / 13.0 * 0.6;
                let ts = max(ag * 3.2 - 0.35, 0.0);
                pk = max(pk, clamp(pow(hist(bx * 0.97, ag), 0.85) * 1.12, 0.0, 1.0) - 0.9 * ts * ts);
            }
            pk = max(pk, v);
            let led = sd_round_box(vec2f(fb - 0.5, (fs - 0.5) * 0.45), vec2f(0.36, 0.15), 0.04);
            let lm = fill(led, 0.06);
            let lc = pal(si / (CB_S - 1.0));
            let lit = step(si + 0.5, v * CB_S);
            let pseg = floor(pk * CB_S - 0.001);
            let ispk = step(abs(si - pseg), 0.4) * step(0.04, pk);
            let bright = 1.25 + 0.6 * G.drop + 0.25 * G.kick * step(si, 6.0);
            g += lc * lm * (0.045 + lit * bright + ispk * (1.6 + G.drop));
            // inner LED highlight
            g += vec3f(1.0) * lm * (lit + ispk) * 0.25 * smoothstep(0.2, 0.0, abs(fs - 0.62));
            // light spill onto the black mask
            g += lc * (lit * 0.06 + ispk * 0.05) * (1.0 - lm);
        }
        // glass: diagonal reflection, mouse spotlight, edge darkening
        g += vec3f(0.9, 0.95, 1.0) * 0.05 * smoothstep(0.08, 0.0, abs((q.x - gc.x) * 0.35 + (q.y - gc.y) - 0.18));
        g += vec3f(0.8, 0.9, 1.0) * 0.035 * smoothstep(0.03, 0.0, abs((q.x - gc.x) * 0.35 + (q.y - gc.y) - 0.3));
        g += vec3f(0.9, 0.95, 1.0) * spot * 0.22;
        g += vec3f(1.0) * 0.5 * exp(-dot(spotd, spotd) / 0.0012);
        g *= 0.75 + 0.25 * smoothstep(0.0, -0.05, gd);
        c = g;
    }
    c += vec3f(0.45) * cb_ln(abs(gd), px * 2.0) * (0.5 + 0.5 * sign(q.y - gc.y));
    c -= vec3f(0.05) * cb_ln(abs(gd - 0.008), px * 3.0);

    // ---------------- frequency scale ----------------
    let fsy = -0.105;
    if (abs(q.y - fsy) < 0.025 && q.x > gx0 && q.x < gx1) {
        var labs = array<f32, 9>(31.0, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0);
        var dmin = 1e5;
        for (var i = 0; i < 9; i++) {
            let hz = labs[i];
            let bnd = 95.0 * log(hz / 25.0) / log(640.0);
            let lx = bnd / 95.0 / 0.97;
            let xx = gx0 + 0.02 + lx * (gx1 - gx0 - 0.04);
            let s = 0.012;
            dmin = min(dmin, cb_label((q - vec2f(xx, fsy)) / s, hz) * s);
        }
        c = mix(c, vec3f(0.78, 0.8, 0.82), cb_ln(dmin, px * 1.3) * 0.9);
    }

    // ---------------- phosphor scope strip ----------------
    let sc = vec2f(gc.x, -0.31);
    let shh = vec2f(gh.x, 0.13);
    let sd = sd_round_box(q - sc, shh, 0.012);
    if (sd < 0.0) {
        let lq = (q - sc) / shh;
        var s = vec3f(0.01, 0.03, 0.02);
        let grid = max(cb_ln(abs(fract(lq.x * 5.0 + 0.5) - 0.5) / 5.0 * shh.x, px), cb_ln(abs(fract(lq.y * 2.0 + 0.5) - 0.5) / 2.0 * shh.y, px));
        s += vec3f(0.1, 0.35, 0.2) * grid * 0.35;
        let wv = wave(lq.x * 0.5 + 0.5) * 0.8;
        let d = abs(lq.y - wv) * shh.y;
        let ph = mix(vec3f(0.3, 1.0, 0.55), pal(0.0), 0.3);
        s += ph * (cb_ln(d, px * 1.6) * 1.4 + 0.25 * exp(-d / 0.012));
        s += vec3f(0.8, 0.9, 1.0) * spot * 0.15;
        c = s;
    }
    c += vec3f(0.4) * cb_ln(abs(sd), px * 2.0) * (0.5 + 0.5 * sign(q.y - sc.y));

    // ---------------- VU meters ----------------
    let vx0 = gx1 + 0.06; let vx1 = a - 0.27;
    let vw = (vx1 - vx0) * 0.5;
    let vs = min(vw / 0.46, 1.0);
    let lvlL = clamp(G.vol * 2.4 + 0.18 * G.kick + 0.1 * G.bass, 0.0, 1.1);
    let lvlR = clamp(G.vol * 2.2 + 0.12 * G.snare + 0.12 * G.mid + 0.05 * G.hat, 0.0, 1.1);
    for (var i = 0; i < 2; i++) {
        let cx = vx0 + vw * (f32(i) + 0.5);
        let vq = (q - vec2f(cx, 0.36)) / vs;
        if (abs(vq.x) < 0.24 && abs(vq.y) < 0.18) {
            let lv = select(lvlL, lvlR, i == 1);
            c = cb_vu(vq, lv, px / vs, spot);
        }
    }
    // red LED readout: tempo, plus beat/clip/hat lamps
    let dc = vec2f((vx0 + vx1) * 0.5, 0.06);
    let dw = sd_round_box(q - dc, vec2f(0.17, 0.065), 0.008);
    if (dw < 0.0) {
        var dcol = vec3f(0.03, 0.005, 0.005);
        let s = 0.036;
        let lq = (q - dc + vec2f(0.12, 0.0)) / s;
        let bpm = round(G.bpm);
        var dd = 1e5;
        var gd8 = 1e5;
        for (var i = 0; i < 3; i++) {
            let dg = i32(floor(bpm / pow(10.0, f32(2 - i))) % 10.0);
            let pq = lq - vec2f(0.5 + f32(i) * 1.6, 0.0);
            let skew = vec2f(pq.x - pq.y * 0.12, pq.y);
            dd = min(dd, cb_seg7(skew, dg));
            gd8 = min(gd8, cb_seg8(skew));
        }
        dcol += vec3f(1.0, 0.1, 0.06) * (cb_ln(gd8 * s - 0.004, px * 1.5) * 0.08 + cb_ln(dd * s - 0.004, px * 1.5) * 1.6);
        c = dcol + vec3f(1.0) * spot * 0.1;
    }
    c += vec3f(0.35) * cb_ln(abs(dw), px * 2.0);
    // lamps: beat (on the tempo grid), snare/clip, hat
    for (var i = 0; i < 3; i++) {
        let lp = q - vec2f(vx0 + 0.04 + f32(i) * 0.07, -0.08);
        var on = 1.0 - G.beat_phase;
        var lcol = pal(0.0);
        if (i == 1) { on = G.snare; lcol = pal(1.0); }
        if (i == 2) { on = G.hat; lcol = pal(0.5); }
        let ld = length(lp) - 0.014;
        c = mix(c, lcol * (0.12 + 1.6 * on) + vec3f(1.0) * 0.4 * on * smoothstep(0.01, 0.0, length(lp - vec2f(-0.004, 0.004))), fill(ld, px));
        c += lcol * on * 0.25 * exp(-max(ld, 0.0) / 0.02);
        c += vec3f(0.5) * cb_ln(abs(ld - 0.004), px * 1.5) * 0.5;
    }
    // big gain knob: turns with the section energy, notch glows on the drop
    let kp = q - vec2f(vx1 - 0.13, -0.3);
    let kr = 0.11;
    let kd = length(kp) - kr;
    let ka = -2.3 + 4.6 * clamp(G.energy, 0.0, 1.0);
    let kang = atan2(kp.x, kp.y);
    let knurl = 0.5 + 0.5 * sin(kang * 60.0);
    var kc = vec3f(0.16) * (0.7 + 0.3 * knurl * step(kr * 0.8, length(kp))) + vec3f(0.6) * 0.25 * clamp(dot(normalize(kp + vec2f(1e-4)), normalize(m - q + vec2f(1e-4))), 0.0, 1.0);
    kc += vec3f(0.35) * smoothstep(kr * 0.7, 0.0, length(kp - vec2f(-0.02, 0.03))) * 0.4;
    let notch = sd_segment(kp, vec2f(sin(ka), cos(ka)) * kr * 0.35, vec2f(sin(ka), cos(ka)) * kr * 0.85);
    kc = mix(kc, pal(0.0) * (1.0 + 2.0 * G.drop) + 0.2, fill(notch - 0.006, px));
    c = mix(c, vec3f(0.01), smoothstep(0.03, 0.0, kd - 0.01) * 0.6);
    c = mix(c, kc, fill(kd, px));
    // scale dots around the knob
    let kdots = abs(fract((kang + 2.3) / 4.6 * 10.0 + 0.5) - 0.5);
    c += vec3f(0.7) * step(abs(length(kp) - kr - 0.025), 0.005) * step(kdots, 0.12) * step(abs(kang), 2.35);

    // outline
    c *= fill(box, px);
    return c;
}

fn look(fc: vec2f) -> vec4f {
    let res = G.res;
    let uv = fc / res;
    let p = centered(fc);
    let a = G.aspect;
    let px = 2.0 / res.y;
    let m = (G.mouse - vec2f(0.5)) * vec2f(2.0 * a, -2.0);

    // studio wall
    var col = mix(vec3f(0.035, 0.035, 0.045), vec3f(0.012, 0.012, 0.016), clamp(p.y, 0.0, 1.0));
    col += pal(0.5) * 0.04 * (0.4 + G.energy) * exp(-dot(p - vec2f(0.0, 0.1), p - vec2f(0.0, 0.1)) * 0.8);
    col += vec3f(0.8, 0.85, 1.0) * 0.05 * exp(-dot(p - m, p - m) * 2.0);
    // the bars light the wall above the rack
    let wx = clamp((p.x + a - 0.36) / (a * 1.3 - 0.4), 0.0, 1.0);
    col += pal(spec(wx) * 0.8) * spec(wx) * 0.12 * exp(-max(p.y - 0.64, 0.0) * 3.0) * step(0.64, p.y);
    let floorY = -0.6;
    if (p.y < floorY) {
        // glossy floor with the device reflected in it
        let fd = floorY - p.y;
        col = vec3f(0.012, 0.012, 0.015) + vec3f(0.6, 0.65, 0.8) * 0.05 * exp(-dot(p - vec2f(m.x, floorY - 0.15), p - vec2f(m.x, floorY - 0.15)) * 3.0);
        let rc = cb_device(vec2f(p.x, 2.0 * floorY - p.y + 0.08), px, a, vec2f(m.x, 2.0 * floorY - m.y));
        if (rc.x >= 0.0) { col += rc * 0.45 * exp(-fd * 3.0); }
        // shadow line under the device
        col *= 1.0 - 0.6 * exp(-fd * 25.0);
    }
    let dev = cb_device(p, px, a, m);
    if (dev.x >= 0.0) {
        col = dev;
    } else {
        // soft drop shadow around the rack
        let sb = sd_box(p - vec2f(0.0, 0.03), vec2f(a - 0.06, 0.58));
        col *= 0.5 + 0.5 * smoothstep(0.0, 0.08, sb);
    }

    // drop: whole room flashes with the LED colours
    col += pal(0.9) * 0.06 * G.drop;
    let vq = uv - 0.5;
    col *= 1.0 - dot(vq, vq) * 0.7;
    col += (hash21(fc + fract(G.time) * 61.0) - 0.5) * 0.01;
    return vec4f(col, 1.0);
}
