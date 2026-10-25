// name: Classic Bars
// palette: #22ff66 #ffd21a #ff2a1a
// A premium rack-mount spectrum analyser: LED bars with falling peak-hold, analogue VU meters,
// phosphor scope, brushed-metal rack ears, glass front, glossy floor reflection.
// pal0 -> pal1 -> pal2 = LED colour from the bottom of a bar to the top.

const CB_N: f32 = 32.0;     // bars
const CB_S: f32 = 24.0;     // LED segments per bar

// section weights (sum to 1); bp = build-up progress 0..1 over ~12 s
struct CbS { q: f32, v: f32, b: f32, c: f32, k: f32, d: f32, bp: f32 }
fn cb_secs() -> CbS {
    var s: CbS;
    s.q = sec(SEC_QUIET); s.v = sec(SEC_VERSE); s.b = sec(SEC_BUILD);
    s.c = sec(SEC_CHORUS); s.k = sec(SEC_BREAKDOWN); s.d = sec(SEC_DROP);
    s.bp = s.b * sec_progress(12.0);
    return s;
}

// 3x5 pixel font: five rows of 3 bits (octal digits)
fn cb_g(a: u32, b: u32, c: u32, d: u32, e: u32) -> u32 { return (a << 12u) | (b << 9u) | (c << 6u) | (d << 3u) | e; }
fn cb_glyph(ch: i32) -> u32 {
    switch ch {
        case 0: { return cb_g(2u, 5u, 7u, 5u, 5u); }   // A
        case 1: { return cb_g(6u, 5u, 6u, 5u, 6u); }   // B
        case 2: { return cb_g(3u, 4u, 4u, 4u, 3u); }   // C
        case 3: { return cb_g(6u, 5u, 5u, 5u, 6u); }   // D
        case 4: { return cb_g(7u, 4u, 6u, 4u, 7u); }   // E
        case 5: { return cb_g(5u, 5u, 7u, 5u, 5u); }   // H
        case 6: { return cb_g(7u, 2u, 2u, 2u, 7u); }   // I
        case 7: { return cb_g(5u, 5u, 6u, 5u, 5u); }   // K
        case 8: { return cb_g(4u, 4u, 4u, 4u, 7u); }   // L
        case 9: { return cb_g(5u, 7u, 7u, 7u, 5u); }   // N
        case 10: { return cb_g(2u, 5u, 5u, 5u, 2u); }  // O
        case 11: { return cb_g(6u, 5u, 6u, 4u, 4u); }  // P
        case 12: { return cb_g(2u, 5u, 5u, 6u, 3u); }  // Q
        case 13: { return cb_g(6u, 5u, 6u, 5u, 5u); }  // R
        case 14: { return cb_g(3u, 4u, 2u, 1u, 6u); }  // S
        case 15: { return cb_g(7u, 2u, 2u, 2u, 2u); }  // T
        case 16: { return cb_g(5u, 5u, 5u, 5u, 7u); }  // U
        case 17: { return cb_g(5u, 5u, 5u, 5u, 2u); }  // V
        case 18: { return cb_g(5u, 5u, 7u, 7u, 5u); }  // W
        case 19: { return cb_g(0u, 0u, 7u, 0u, 0u); }  // -
        default: { return 0u; }
    }
}
fn cb_name_len(s: i32) -> i32 {
    switch s { case 0: { return 5; } case 1: { return 5; } case 2: { return 8; } case 3: { return 6; } case 4: { return 9; } default: { return 4; } }
}
fn cb_name_ch(s: i32, i: i32) -> i32 {
    var a = array<i32, 9>(12, 16, 6, 4, 15, 0, 0, 0, 0);          // QUIET
    if (s == 1) { a = array<i32, 9>(17, 4, 13, 14, 4, 0, 0, 0, 0); }                 // VERSE
    if (s == 2) { a = array<i32, 9>(1, 16, 6, 8, 3, 19, 16, 11, 0); }                // BUILD-UP
    if (s == 3) { a = array<i32, 9>(2, 5, 10, 13, 16, 14, 0, 0, 0); }                // CHORUS
    if (s == 4) { a = array<i32, 9>(1, 13, 4, 0, 7, 3, 10, 18, 9); }                 // BREAKDOWN
    if (s == 5) { a = array<i32, 9>(3, 13, 10, 11, 0, 0, 0, 0, 0); }                 // DROP
    return a[clamp(i, 0, 8)];
}
// dot-matrix section name. p in font cells, origin top-left, y down. returns 0..1 lit dot
fn cb_text(p: vec2f, s: i32) -> f32 {
    let n = cb_name_len(s);
    if (p.x < 0.0 || p.y < 0.0 || p.y >= 5.0 || p.x >= f32(n) * 4.0) { return 0.0; }
    let ci = i32(floor(p.x / 4.0));
    let gx = i32(floor(p.x - f32(ci) * 4.0));
    let gy = i32(floor(p.y));
    if (gx > 2) { return 0.0; }
    let bits = cb_glyph(cb_name_ch(s, ci));
    let on = f32((bits >> u32(14 - gy * 3 - gx)) & 1u);
    let f = fract(p) - vec2f(0.5);
    return on * fill(sd_round_box(f, vec2f(0.36), 0.12), 0.25);
}

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
    let S = cb_secs();
    let sid = i32(G.section);
    let sfade = sec(G.section);
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
            let gain = 0.55 * S.q + S.v + S.b + 1.05 * S.c + 0.9 * S.k + 1.1 * S.d;
            // display modes: drop = mirrored from the centre line, others from the bottom
            let lyc = mix(ly, abs(ly - 0.5) * 2.0, S.d);
            let si = floor(lyc * CB_S);
            let fs = fract(lyc * CB_S);
            var v = clamp(pow(spec(bx * 0.97), 0.85) * 1.12 * gain, 0.0, 1.0);
            // build-up: a rising tide of lit segments with ragged bar heights
            v = max(v, S.bp * (0.15 + 0.5 * S.bp) * (0.6 + 0.4 * hash21(vec2f(bi, 3.0))));
            // peak hold: highest recent level minus gravity (hold 0.35 s, then fall)
            var pk = 0.0;
            for (var j = 0; j < 14; j++) {
                let ag = f32(j) / 13.0 * 0.6;
                let ts = max(ag * 3.2 - 0.35, 0.0);
                pk = max(pk, clamp(pow(hist(bx * 0.97, ag), 0.85) * 1.12 * gain, 0.0, 1.0) - 0.9 * ts * ts);
            }
            pk = max(pk, v);
            // drop: peak-hold storm, the caps jump around near the top
            pk = max(pk, (0.6 + 0.4 * hash21(vec2f(bi, floor(G.time * 14.0)))) * S.d * step(0.35, hash21(vec2f(bi + 9.0, floor(G.time * 7.0)))));
            // chorus: fat solid segments; breakdown: slimmer dots
            let led = sd_round_box(vec2f(fb - 0.5, (fs - 0.5) * 0.45), vec2f(0.36 + 0.1 * S.c - 0.12 * S.k, 0.15 + 0.07 * S.c - 0.05 * S.k), 0.04);
            let lm = fill(led, 0.06);
            let tc = si / (CB_S - 1.0);
            let tb = mix(tc, 0.35 + 0.65 * tc, S.bp);
            let lc = 0.7 * S.q * pal(tc * 0.25) + S.v * pal(tc) + S.b * pal(tb)
                + S.c * palc(bx * 0.9 + G.time * 0.05 + tc * 0.15) + S.k * pal(0.55 + 0.45 * tc) + S.d * pal(1.0 - tc);
            let lit = step(si + 0.5, v * CB_S) * (1.0 - 0.85 * S.k);
            let pseg = floor(pk * CB_S - 0.001);
            let pdist = select(abs(si - pseg), min(abs(si - pseg), abs(si - (CB_S - 1.0 - pseg))), S.d > 0.5);
            let ispk = max(step(pdist, 0.4), 0.35 * S.k * step(pdist, 1.4)) * step(0.04, pk);
            let bright = (1.25 + 0.6 * G.drop + 0.25 * G.kick * step(si, 6.0)) * (0.6 * S.q + S.v + (1.0 + 0.35 * S.bp) * S.b + 1.2 * S.c + 0.85 * S.k + 1.3 * S.d);
            g += lc * lm * (0.045 + lit * bright + ispk * (1.6 + G.drop));
            g += vec3f(1.0) * lm * lit * G.snare * S.b * 0.25;
            // inner LED highlight
            g += vec3f(1.0) * lm * (lit + ispk) * 0.25 * smoothstep(0.2, 0.0, abs(fs - 0.62));
            // light spill onto the black mask
            g += lc * (lit * 0.06 + ispk * 0.05) * (1.0 - lm);
        }
        // glass: diagonal reflection, mouse spotlight, edge darkening
        g += vec3f(0.9, 0.95, 1.0) * 0.05 * smoothstep(0.08, 0.0, abs((q.x - gc.x) * 0.35 + (q.y - gc.y) - 0.18));
        g += vec3f(0.8, 0.9, 1.0) * 0.035 * smoothstep(0.03, 0.0, abs((q.x - gc.x) * 0.35 + (q.y - gc.y) - 0.3));
        g += vec3f(0.9, 0.95, 1.0) * spot * 0.22;
        g += pal(0.5) * 0.03 * S.c + vec3f(1.0) * 0.06 * G.drop * S.d;
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

    // ---------------- section row: lamps, name, build-up meter ----------------
    let lx0 = vx0 + 0.04;
    for (var i = 0; i < 6; i++) {
        let lp = q - vec2f(lx0 + f32(i) * 0.07, -0.19);
        var w = S.q;
        var lcol = vec3f(0.5, 0.7, 1.0);
        if (i == 1) { w = S.v; lcol = pal(0.0); }
        if (i == 2) { w = S.b * (0.5 + 0.5 * step(0.5, fract(G.time * (2.0 + 6.0 * S.bp)))); lcol = pal(0.5); }
        if (i == 3) { w = S.c; lcol = vec3f(1.0, 0.8, 0.35); }
        if (i == 4) { w = S.k; lcol = pal(0.8); }
        if (i == 5) { w = S.d * (0.6 + 0.4 * G.kick); lcol = pal(1.0); }
        let ld = length(lp) - 0.016;
        c = mix(c, lcol * (0.08 + 1.8 * w) + vec3f(1.0) * 0.4 * w * smoothstep(0.012, 0.0, length(lp - vec2f(-0.004, 0.004))), fill(ld, px));
        c += lcol * w * 0.3 * exp(-max(ld, 0.0) / 0.025);
        c += vec3f(0.5) * cb_ln(abs(ld - 0.004), px * 1.5) * 0.5;
    }
    // name in dot-matrix
    let cell = 0.0125;
    let tp = (q - vec2f(lx0 - 0.015, -0.255 + 2.5 * cell)) / cell * vec2f(1.0, -1.0);
    let tcol = mix(vec3f(0.6, 0.8, 1.0), mix(pal(0.0), pal(1.0), S.d), clamp(S.v + S.b + S.c + S.k + S.d, 0.0, 1.0));
    let tx = cb_text(tp, sid);
    c += tcol * (tx * (0.25 + 1.4 * sfade) + 0.03 * step(abs(tp.y - 2.5), 2.5) * step(0.0, tp.x) * step(tp.x, 36.0) * (1.0 - step(0.5, tx)));
    // build-up meter: 20 segments fill with tension
    let bmx = (q.x - lx0 + 0.015) / 0.43;
    if (abs(q.y + 0.33) < 0.012 && bmx > 0.0 && bmx < 1.0) {
        let bs = floor(bmx * 20.0);
        let on = step((bs + 0.5) / 20.0, S.bp);
        let flash = 1.0 + 1.5 * G.snare * S.b;
        c = mix(c, pal(bs / 19.0) * (0.06 + 1.5 * on * flash), step(0.12, fract(bmx * 20.0)) * step(fract(bmx * 20.0), 0.88));
    }

    // rack light strip along the top edge
    if (abs(q.y - (y1 - 0.022)) < 0.007 && abs(q.x) < x1 - 0.1) {
        let u = (q.x / (x1 - 0.1)) * 0.5 + 0.5;
        let k = floor(u * 40.0);
        let ph = fract(u * 40.0);
        let hs = hash21(vec2f(k, floor(G.time * 16.0)));
        var l = 0.0;
        var scol = vec3f(1.0, 0.7, 0.35);
        l += S.q * 0.12;
        l += S.v * 0.5;
        l += S.b * step(u, S.bp) * (0.6 + 1.5 * G.snare);
        l += S.c * (0.8 + 0.5 * sin(u * 12.0 - G.time * 2.0));
        l += S.k * (0.25 + 0.25 * sin(G.time * 0.8));
        l += S.d * step(0.5, hs) * 2.0;
        scol = mix(scol, vec3f(0.5, 0.7, 1.0), S.k + 0.4 * S.q);
        scol = mix(scol, pal(0.5), S.b);
        scol = mix(scol, vec3f(1.0, 0.9, 0.6), S.c);
        scol = mix(scol, mix(pal(1.0), vec3f(1.0), 0.5 * step(0.5, fract(k * 0.5))), S.d);
        c = mix(c, scol * l, step(0.1, ph) * step(ph, 0.9) * 0.95);
    }

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

    // room lighting behind the rack, per section
    let S = cb_secs();
    let rc = p - vec2f(0.0, 0.1);
    let rr = length(rc);
    let rang = atan2(rc.y, rc.x);
    col *= 1.0 - 0.5 * S.q;
    // build-up: two spotlight shafts close in from the corners, snares flash them
    for (var i = 0; i < 2; i++) {
        let sx = select(-1.0, 1.0, i == 1);
        let bx = sx * a * (0.9 - 0.75 * S.bp);
        let beam = exp(-pow((p.x - bx) * 3.0, 2.0)) * smoothstep(-0.6, 0.0, p.y);
        col += mix(pal(0.5), pal(1.0), S.bp) * beam * S.bp * (0.1 + 0.3 * G.snare);
    }
    col += pal(0.5) * G.snare * S.b * 0.05 * exp(-rr);
    // chorus: warm open sunburst of soft rays behind the rack
    col += mix(vec3f(1.0, 0.75, 0.4), pal(0.5), 0.35) * pow(0.5 + 0.5 * sin(rang * 8.0 + G.time * 0.25), 2.0) * exp(-rr * 0.55) * S.c * (0.1 + 0.06 * G.beat);
    col += vec3f(1.0, 0.8, 0.5) * 0.05 * S.c * exp(-rr * 0.8);
    // breakdown: cool dark room, slow bokeh lights float up, notes make them glow
    col = mix(col, col * vec3f(0.6, 0.7, 1.0), 0.5 * S.k);
    if (S.k > 0.001) {
        for (var j = 0; j < 8; j++) {
            let fj = f32(j);
            let h = hash11(fj * 2.3 + 1.0);
            let bp2 = vec2f((hash11(fj * 5.1) * 2.0 - 1.0) * a * 0.95, -0.7 + fract(G.time * (0.015 + 0.01 * h) + h) * 2.0);
            let bd = length(p - bp2);
            col += mix(pal(0.6 + 0.4 * h), vec3f(1.0), 0.3) * smoothstep(0.09 + 0.05 * h, 0.04, bd) * (0.03 + 0.12 * key(30 + j * 4) + 0.04 * G.mid) * S.k;
        }
    }
    // drop only: laser fan sweeping out from behind the rack, strobing room
    if (S.d > 0.001) {
        for (var j = 0; j < 5; j++) {
            let ta = (f32(j) - 2.0) * 0.5 + sin(G.time * 1.3 + f32(j)) * 0.35 + 1.5708;
            let ln = exp(-pow((rang - ta) * 18.0, 2.0)) * exp(-rr * 0.3);
            col += pal(1.0 - 0.25 * f32(j % 3)) * ln * S.d * (0.2 + 0.4 * G.kick);
        }
        col += pal(0.9) * 0.03 * S.d * step(0.5, fract(G.beat_phase * 2.0));
    }
    // drop: whole room flashes with the LED colours
    col += pal(0.9) * 0.06 * G.drop;
    let vq = uv - 0.5;
    col *= 1.0 - dot(vq, vq) * 0.7;
    col += (hash21(fc + fract(G.time) * 61.0) - 0.5) * 0.01;
    return vec4f(col, 1.0);
}
