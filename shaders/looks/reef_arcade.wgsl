// name: Reef Arcade
// palette: #ff4a2e #ffd23c #20d8ff
// Pixel-art arcade reef: a diver hunts invasive lionfish over a spectrum reef.
// Everything is drawn on a ~160 px tall virtual screen, then quantised with ordered dithering.

const RH_VH: f32 = 160.0;
const RH_INK: vec3f = vec3f(0.03, 0.04, 0.10);
const RH_CREAM: vec3f = vec3f(1.0, 0.92, 0.78);

// ---------- 3x5 pixel font: 0-9, 10 S, 11 C, 12 O, 13 R, 14 E, 15 M, 16 B, 17 x, 18 + ----------
fn rh_glyph(c: i32) -> u32 {
    switch (c) {
        case 0: { return 31599u; }
        case 1: { return 11415u; }
        case 2: { return 29671u; }
        case 3: { return 29647u; }
        case 4: { return 23497u; }
        case 5: { return 31183u; }
        case 6: { return 31215u; }
        case 7: { return 29330u; }
        case 8: { return 31727u; }
        case 9: { return 31695u; }
        case 10: { return 31183u; }
        case 11: { return 31015u; }
        case 12: { return 31599u; }
        case 13: { return 27565u; }
        case 14: { return 31143u; }
        case 15: { return 24557u; }
        case 16: { return 27566u; }
        case 17: { return 2728u; }
        case 18: { return 1488u; }
        default: { return 0u; }
    }
}
fn rh_gpx(q: vec2f, c: i32) -> f32 {
    if (q.x < 0.0 || q.y < 0.0 || q.x >= 3.0 || q.y >= 5.0) { return 0.0; }
    let row = (rh_glyph(c) >> ((4u - u32(q.y)) * 3u)) & 7u;
    return f32((row >> (2u - u32(q.x))) & 1u);
}
fn rh_num(q: vec2f, v: f32, n: i32) -> f32 {
    if (q.x < 0.0 || q.x >= f32(n) * 4.0) { return 0.0; }
    let ci = floor(q.x / 4.0);
    var div = 1u;
    for (var k = 0; k < n - 1 - i32(ci); k++) { div *= 10u; }
    let d = (u32(max(v, 0.0)) / div) % 10u;
    return rh_gpx(vec2f(q.x - ci * 4.0, q.y), i32(d));
}
fn rh_word(q: vec2f, a: i32, b: i32, c: i32, d: i32, e: i32) -> f32 {
    if (q.x < 0.0 || q.x >= 20.0) { return 0.0; }
    let ci = i32(floor(q.x / 4.0));
    var g = a;
    if (ci == 1) { g = b; } else if (ci == 2) { g = c; } else if (ci == 3) { g = d; } else if (ci == 4) { g = e; }
    if (g < 0) { return 0.0; }
    return rh_gpx(vec2f(q.x - f32(ci) * 4.0, q.y), g);
}
fn rh_bayer(p: vec2f) -> f32 {
    let x = u32(p.x) & 3u;
    let y = u32(p.y) & 3u;
    let xy = x ^ y;
    let m = ((xy & 1u) << 3u) | ((y & 1u) << 2u) | (xy & 2u) | ((y & 2u) >> 1u);
    return (f32(m) + 0.5) / 16.0;
}

// ---------- sprite helpers ----------
fn rh_lay(c: vec4f, d: f32, k: vec3f) -> vec4f { return select(c, vec4f(k, 1.0), d < 0.0); }
fn rh_ink(c: vec4f, d: f32) -> vec4f { return select(c, vec4f(RH_INK, 1.0), c.a < 0.5 && d < 1.0); }
fn rh_floor(x: f32) -> f32 { return 146.0 + 2.0 * sin(x * 0.045) + floor(noise2(vec2f(x * 0.1, 1.0)) * 2.0); }

// lionfish, q in px (x forward, y down), s = pixels per unit (body is 10 units long)
fn rh_lion(q: vec2f, s: f32, flare: f32, t: f32) -> vec4f {
    let red = G.pal0.rgb;
    let p = q / s;
    var c = vec4f(0.0);
    // tail fan
    if (p.x < -4.3 && p.x > -8.0 && abs(p.y) < (-4.3 - p.x) * 0.75 + 0.6) {
        c = vec4f(select(RH_CREAM, red, fract(p.x * 0.8) < 0.5) * 0.85, 1.0);
    }
    // feathery pectoral fans, flaring with the bass
    let fq = p - vec2f(1.0, 0.6);
    let fr = length(fq);
    let fa = atan2(fq.y, -fq.x);
    let flen = 6.0 * (1.0 + 0.5 * flare) + sin(t * 3.0 + fa * 4.0) * 0.4;
    if (fr < flen && fa > -0.35 && fa < 1.5) {
        if (fract(fa * 5.5) < 0.42) { c = vec4f(select(RH_CREAM, red, fract(fr * 0.55) < 0.5), 1.0); }
        else if (c.a < 0.5 && fr > 1.5) { c = vec4f(mix(red, RH_CREAM, 0.4) * 0.5, 1.0); }
    }
    // venomous dorsal spines, leaning back
    let sb = p.x - 0.5 * p.y;
    let sh = 2.0 + (3.5 + 1.5 * sin(sb * 1.7 + 1.0)) * (0.75 + 0.6 * flare);
    if (p.y < -0.8 && -p.y < sh && sb > -4.5 && sb < 3.0 && fract(sb / 1.25) < 0.34) {
        c = vec4f(select(RH_CREAM, red, fract(p.y * 0.8) < 0.5), 1.0);
    }
    // striped body
    let be = (length(vec2f(p.x / 5.0, p.y / 2.3)) - 1.0) * 2.3 * s;
    if (be < 0.0) {
        var bc = select(RH_CREAM, red, fract((p.x + p.y * 0.35) / 1.5) < 0.55);
        if (p.y > 1.2) { bc = mix(bc, RH_CREAM, 0.5); }
        if (length(p - vec2f(3.4, -0.5)) < 0.7) { bc = RH_INK; }
        c = vec4f(bc, 1.0);
    } else if (be < 1.0 && c.a < 0.5) { c = vec4f(RH_INK, 1.0); }
    return c;
}

// diver hero facing +x, q in px
fn rh_diver(q: vec2f, t: f32) -> vec4f {
    let kk = sin(t * 6.0 + G.beat_phase * TAU) * (1.0 + G.energy * 1.2);
    let hip = vec2f(-6.0, 0.5);
    let fu = vec2f(-13.0, -1.2 + kk);
    let fd = vec2f(-13.0, 1.8 - kk);
    var c = vec4f(0.0);
    let dfin = min(sd_segment(q, fu, fu + vec2f(-5.0, -0.5 + kk * 0.6)), sd_segment(q, fd, fd + vec2f(-5.0, 0.5 - kk * 0.6))) - 1.1;
    c = rh_lay(c, dfin, G.pal1.rgb);
    let dleg = min(sd_segment(q, hip, fu), sd_segment(q, hip, fd)) - 1.4;
    c = rh_lay(c, dleg, vec3f(0.07, 0.09, 0.17));
    let dtank = sd_segment(q, vec2f(-5.0, -3.3), vec2f(2.0, -3.3)) - 1.6;
    c = rh_lay(c, dtank, select(vec3f(0.95, 0.75, 0.15), vec3f(1.0, 0.95, 0.6), q.y < -4.0));
    let dtor = sd_segment(q, hip, vec2f(4.0, 0.0)) - 2.6;
    let suit = select(vec3f(0.08, 0.1, 0.2), G.pal2.rgb, abs(q.y - 0.4) < 0.7);
    c = rh_lay(c, dtor, suit);
    let dhead = length(q - vec2f(7.0, -0.8)) - 2.7;
    c = rh_lay(c, dhead, vec3f(0.06, 0.07, 0.12));
    let dmask = sd_box(q - vec2f(8.7, -1.3), vec2f(1.3, 1.0));
    c = rh_lay(c, dmask, select(vec3f(0.45, 0.85, 1.0), vec3f(1.3), abs(q.x - 9.0) < 0.5 && abs(q.y + 1.8) < 0.5));
    let dgun = sd_segment(q, vec2f(6.0, 2.8), vec2f(16.0, 2.8)) - 0.7;
    c = rh_lay(c, dgun, vec3f(0.55, 0.6, 0.66));
    let darm = sd_segment(q, vec2f(2.0, 1.0), vec2f(7.5, 2.8)) - 1.1;
    c = rh_lay(c, darm, vec3f(0.1, 0.12, 0.24));
    let dm = min(min(min(dfin, dleg), min(dtank, dtor)), min(min(dhead, dmask), min(dgun, darm)));
    return rh_ink(c, dm);
}

fn rh_fish(q: vec2f, k: vec3f) -> vec4f {
    let be = (length(vec2f(q.x / 2.6, q.y / 1.3)) - 1.0) * 1.3;
    let dt = select(1e3, abs(q.y) - ((-2.0 - q.x) * 0.9 + 0.4), q.x < -2.0 && q.x > -4.2);
    var c = rh_lay(vec4f(0.0), min(be, dt), k);
    if (abs(q.x - 1.5) < 0.5 && abs(q.y + 0.5) < 0.5) { c = vec4f(RH_INK, 1.0); }
    return c;
}

fn rh_clown(q: vec2f) -> vec4f {
    let be = (length(vec2f(q.x / 3.4, q.y / 1.9)) - 1.0) * 1.9;
    let dt = select(1e3, abs(q.y) - ((-2.8 - q.x) * 0.9 + 0.5), q.x < -2.8 && q.x > -5.0);
    var k = vec3f(1.0, 0.45, 0.05);
    if (abs(q.x - 1.3) < 0.6 || abs(q.x + 1.3) < 0.6) { k = vec3f(1.1); }
    var c = rh_lay(vec4f(0.0), min(be, dt), k);
    if (abs(q.x - 2.2) < 0.5 && abs(q.y + 0.5) < 0.5) { c = vec4f(RH_INK, 1.0); }
    return rh_ink(c, min(be, dt));
}

fn rh_turtle(q: vec2f, t: f32) -> vec4f {
    var c = vec4f(0.0);
    let fa = sin(t * 1.4) * 0.7;
    let fv = rot(fa) * vec2f(-0.55, 1.0);
    let df = sd_segment(q, vec2f(3.0, 2.5), vec2f(3.0, 2.5) + fv * 10.0) - 1.7;
    let dr = sd_segment(q, vec2f(-6.5, 2.5), vec2f(-6.5, 2.5) + rot(-fa * 0.6) * vec2f(-1.0, 0.7) * 5.0) - 1.3;
    let skin = vec3f(0.5, 0.62, 0.38);
    c = rh_lay(c, dr, skin * 0.8);
    let dn = min(sd_segment(q, vec2f(6.0, 0.5), vec2f(10.5, 0.0)) - 1.7, length(q - vec2f(11.5, 0.0)) - 2.6);
    c = rh_lay(c, dn, select(skin, skin * 0.75, fract(q.x * 0.6 + q.y * 0.4) < 0.3));
    let ds = (length(vec2f(q.x / 9.0, q.y / 5.5)) - 1.0) * 5.5;
    if (ds < 0.0) {
        let g = vec2f(q.x / 3.6 + 0.5 * floor(q.y / 3.2 + 0.5), q.y / 3.2 + 0.5);
        var sc = mix(vec3f(0.42, 0.3, 0.12), vec3f(0.72, 0.56, 0.22), noise2(q * 0.4));
        if (fract(g.x) < 0.2 || fract(g.y) < 0.2) { sc *= 0.6; }
        if (ds > -1.2) { sc = vec3f(0.8, 0.68, 0.36); }
        c = vec4f(sc, 1.0);
    }
    c = rh_lay(c, df, skin);
    if (length(q - vec2f(12.5, -0.8)) < 0.7) { c = vec4f(RH_INK, 1.0); }
    return rh_ink(c, min(min(df, dr), min(dn, ds)));
}

fn rh_crab(q: vec2f, mv: f32, snap: f32) -> vec4f {
    let shell = vec3f(0.95, 0.35, 0.18);
    var c = vec4f(0.0);
    let m = vec2f(abs(q.x), q.y);
    let sd = select(-1.0, 1.0, q.x > 0.0);
    var dl = 1e3;
    for (var k = 0; k < 3; k++) {
        let fk = f32(k);
        let w = sin(mv * TAU + fk * 2.1) * 1.2 * sd;
        dl = min(dl, sd_segment(m, vec2f(2.5 + fk, 0.5), vec2f(7.5 + fk * 0.8, 3.5 + w)));
    }
    dl -= 0.6;
    c = rh_lay(c, dl, shell * 0.75);
    let cy = -3.5 - snap * 2.5;
    let darm = sd_segment(m, vec2f(3.5, -1.0), vec2f(6.5, cy)) - 0.8;
    c = rh_lay(c, darm, shell * 0.85);
    let qc = m - vec2f(7.0, cy - 1.0);
    var dcl = length(qc) - 2.4;
    if (qc.y < 0.0 && abs(qc.x) < 0.5 + snap * 1.2) { dcl = 2.0; }
    c = rh_lay(c, dcl, shell * 1.1);
    let db = (length(vec2f(q.x / 5.0, q.y / 3.0)) - 1.0) * 3.0;
    c = rh_lay(c, db, select(shell, shell * 1.25, q.y < -1.0));
    let deye = min(length(m - vec2f(1.5, -4.3)) - 1.0, sd_segment(m, vec2f(1.5, -2.5), vec2f(1.5, -4.0)) - 0.4);
    c = rh_lay(c, deye, vec3f(1.0));
    if (length(m - vec2f(1.5, -4.5)) < 0.5) { c = vec4f(RH_INK, 1.0); }
    return rh_ink(c, min(min(dl, darm), min(min(dcl, db), deye)));
}

fn rh_chest(q: vec2f, open: f32) -> vec4f {
    // q: origin bottom-centre of the chest, y down
    let wood = vec3f(0.55, 0.3, 0.12);
    let gold = G.pal1.rgb;
    var c = vec4f(0.0);
    let lq = rot(open * 1.9) * (q - vec2f(-8.0, -8.0));
    let dlid = sd_round_box(lq - vec2f(8.0, -2.2), vec2f(8.0, 2.6), 2.0);
    c = rh_lay(c, dlid, select(wood * 1.15, gold, abs(lq.x - 3.0) < 0.6 || abs(lq.x - 13.0) < 0.6));
    let dbox = sd_box(q - vec2f(0.0, -4.0), vec2f(8.0, 4.0));
    var bc = select(wood, wood * 0.8, fract(q.y / 2.5) < 0.25);
    if (abs(abs(q.x) - 5.0) < 0.6) { bc = gold; }
    if (open > 0.1 && q.y < -6.5) { bc = select(gold * 1.5, vec3f(2.0), hash21(floor(q) + floor(G.time * 10.0)) > 0.8); }
    if (sd_box(q - vec2f(0.0, -6.8), vec2f(1.2, 1.2)) < 0.0 && open < 0.1) { bc = gold * 1.3; }
    c = rh_lay(c, dbox, bc);
    return rh_ink(c, min(dlid, dbox));
}

// lionfish k: xy = position, z = facing. Respawns at a new spot the beat after it was speared.
fn rh_lpos(k: i32, t: f32, bc: f32, W: f32) -> vec3f {
    let fk = f32(k);
    let gen = floor((bc - fk + 2.0) / 3.0);
    let sd = hash11(fk * 13.1 + gen * 7.7);
    let dir = select(-1.0, 1.0, sd > 0.5);
    let u = fract(t * 0.02 * (0.7 + sd) + sd * 3.1) * (W + 50.0);
    let x = select(W + 25.0 - u, u - 25.0, dir > 0.0);
    let y = 40.0 + fk * 24.0 + sd * 14.0 + sin(t * 0.8 + fk * 2.0) * 5.0;
    return vec3f(x, y, dir);
}

fn look(fc: vec2f) -> vec4f {
    let ps = max(G.res.y / RH_VH, 1.0);
    let W = floor(G.res.x / ps);
    let pix = floor(fc / ps);
    let t = G.time;
    let bc = floor(G.beat_count);
    let ph = G.beat_phase;
    let act = smoothstep(0.02, 0.08, G.energy);
    // song-section weights, build-up tension 0..1 over ~12 s
    let nq = sec(SEC_QUIET); let nb = sec(SEC_BUILD); let nc = sec(SEC_CHORUS);
    let nd = sec(SEC_BREAKDOWN); let np = sec(SEC_DROP);
    let bpg = sec_progress(12.0) * nb;
    let hunt = act * clamp(1.0 - nq - nd, 0.0, 1.0);     // spear hunting only while the drums are in
    let bayer = rh_bayer(floor(fc / ps));
    let bossOn = G.drop > 0.03 || np > 0.4;
    let shk = floor((hash22(vec2f(floor(t * 24.0), 3.0)) - 0.5) * 5.0 * G.drop) + vec2f(0.0, floor(G.kick * 1.6));
    let v = pix + 0.5 + shk;
    let dep = clamp(v.y / RH_VH, 0.0, 1.0);

    // ---- water: colour temperature follows the centroid, brightness the section energy ----
    var col = mix(vec3f(0.16, 0.6, 0.85), vec3f(0.02, 0.09, 0.28), pow(dep, 0.75));
    col *= mix(vec3f(0.85, 1.0, 1.12), vec3f(1.12, 1.02, 0.85), G.centroid);
    col *= 0.78 + 0.3 * G.energy;
    let deep = pow(dep, 0.8);
    col = mix(col, col * vec3f(0.45, 0.55, 0.8), 0.7 * nq);                                                  // quiet: dark, still
    col = mix(col, mix(vec3f(0.55, 0.92, 1.0), vec3f(0.12, 0.42, 0.62), deep), 0.75 * nd);                   // breakdown: pale, airy
    col = mix(col, mix(vec3f(0.3, 0.88, 0.95), vec3f(0.05, 0.38, 0.62), deep) * 1.15, 0.65 * nc);            // chorus: bright turquoise
    col = mix(col, col * vec3f(1.0, 0.5, 0.6) * 0.85, 0.75 * bpg);                                           // build-up: danger red
    col = mix(col, mix(vec3f(0.55, 0.1, 0.38), vec3f(0.1, 0.0, 0.18), pow(dep, 0.7)), 0.8 * np);             // drop: magenta storm

    // ---- light shafts fanning from the sun, breathing with the sub ----
    let sunx = W * 0.66 + sin(t * 0.07) * 25.0;
    let ray = (v.x - sunx) / (v.y + 25.0);
    let shaft = smoothstep(0.5, 0.85, noise2(vec2f(ray * 7.0, t * 0.18))) * smoothstep(0.2, 0.6, noise2(vec2f(ray * 2.5 + 5.0, t * 0.11)));
    col += vec3f(0.45, 0.85, 0.9) * shaft * pow(1.0 - dep, 1.3) * (0.22 + 0.45 * G.bass + 0.2 * G.beat) * (1.0 + 1.3 * nc + 1.6 * nd - 0.7 * nq);

    // ---- surface: waves shaped by the waveform, sun glints sparkle on hats ----
    let sy = 9.0 + 2.0 * sin(v.x * 0.07 + t * 1.3) + 1.2 * sin(v.x * 0.19 - t * 2.1) + wave(v.x / W) * 4.0;
    if (v.y < sy) {
        var sc = mix(vec3f(0.6, 0.95, 1.0), vec3f(0.3, 0.75, 0.95), v.y / max(sy, 1.0));
        if (fract(v.x * 0.05 + sin(v.y * 0.9 + t) * 0.3) < 0.15) { sc *= 1.12; }
        let gl = hash21(vec2f(floor(v.x / 2.0), floor(t * 8.0) + floor(v.y / 2.0) * 7.0));
        if (gl > 0.95 - G.hat * 0.15) { sc = vec3f(1.7); }
        col = sc;
    } else if (v.y < sy + 1.0) { col = vec3f(0.9, 1.0, 1.0); }
    col += vec3f(1.0, 0.95, 0.7) * 0.9 * exp(-length((v - vec2f(sunx, 0.0)) * vec2f(1.0, 1.6)) / (14.0 + 18.0 * nc + 10.0 * nd));

    // ---- far reef silhouette: an echo of the spectrum 1.6 s ago ----
    let fh = 30.0 + 18.0 * fbm2(vec2f(v.x * 0.03 + G.travel * 0.03, 2.0), 3) + 18.0 * hist(v.x / W, 0.5);
    if (v.y > RH_VH - fh) { col = mix(col, vec3f(0.04, 0.2, 0.34) * (0.8 + 0.3 * G.energy), 0.6); }

    // ---- sea turtle cruising by ----
    let tpos = vec2f(fract(t * 0.011 + 0.35) * (W + 90.0) - 45.0, 30.0 + sin(t * 0.4) * 6.0);
    let tq = v - floor(tpos);
    if (abs(tq.x) < 20.0 && abs(tq.y) < 16.0) {
        let tc = rh_turtle(tq, t);
        if (tc.a > 0.5) { col = mix(tc.rgb, col, 0.12); }
    }

    let fy = rh_floor(v.x);

    // ---- seaweed swaying with the mids ----
    for (var i = 0; i < 7; i++) {
        let fi = f32(i);
        let sx = (fi + 0.5) / 7.0 * W + (hash11(fi * 4.3) - 0.5) * 30.0;
        let hgt = 35.0 + hash11(fi * 2.9) * 45.0;
        let up2 = fy - v.y;
        if (up2 > 0.0 && up2 < hgt) {
            let k = up2 / hgt;
            let cx = sx + sin(up2 * 0.12 - t * 1.6 + fi) * k * (3.0 + 6.0 * G.mid) + sin(t * 0.5 + fi) * k * 3.0;
            if (abs(v.x - cx) < 1.8 - k * 0.8) {
                col = select(vec3f(0.2, 0.62, 0.3), vec3f(0.12, 0.42, 0.22), fract(up2 / 5.0) < 0.25) * (0.8 + 0.3 * G.energy);
            }
        }
    }

    // ---- reef fish school: more fish in big sections, scatter on snares ----
    let scen = vec2f(W * 0.55 + sin(t * 0.17) * W * 0.25, 54.0 + sin(t * 0.29) * 14.0);
    let nf = i32((10.0 + G.energy * 14.0) * clamp(1.0 - 0.75 * nq - 0.9 * nd, 0.0, 1.0) + 8.0 * nc);
    for (var i = 0; i < 24; i++) {
        if (i >= nf) { break; }
        let fi = f32(i);
        let hs = hash11(fi * 1.37 + 0.5);
        let a = t * (0.5 + hs * 0.5) + fi * 2.39 + G.travel * 0.08;
        let rad = (7.0 + hash11(fi * 3.3) * 18.0 + G.snare * 10.0) * (1.0 - 0.65 * bpg) * (1.0 + 0.35 * nc);
        let fp = floor(scen + vec2f(cos(a) * rad, sin(a) * rad * 0.45));
        let fd = select(1.0, -1.0, sin(a) > 0.0);
        let fq = (v - fp - 0.5) * vec2f(fd, 1.0);
        if (abs(fq.x) < 5.0 && abs(fq.y) < 3.0) {
            let fcol = rh_fish(fq, select(vec3f(1.0, 0.85, 0.15), vec3f(0.2, 0.5, 1.0), i % 3 == 0));
            if (fcol.a > 0.5) { col = fcol.rgb; }
        }
    }

    // ---- breakdown only: jellyfish drifting up, pulsing with the melody ----
    if (nd > 0.03) {
        for (var i = 0; i < 4; i++) {
            let fi = f32(i);
            let jp = floor(vec2f(W * (0.14 + 0.24 * fi) + sin(t * 0.3 + fi * 2.0) * 10.0, 150.0 - fract(t * 0.012 + fi * 0.27) * 150.0));
            let jq = v - jp;
            let kv = key(30 + i * 12);
            let pul = 1.0 + 0.15 * sin(t * 2.2 + fi) + 0.3 * kv;
            var jc = vec3f(0.0);
            var hit_j = false;
            if (jq.y < 1.0 && jq.y > -9.0 * pul && length(vec2f(jq.x / (9.0 * pul), jq.y / (7.0 * pul))) < 1.0) {
                jc = mix(vec3f(1.0, 0.7, 0.95), G.pal2.rgb, 0.5 + 0.5 * sin(fi + jq.y * 0.2)) * (0.9 + 0.8 * kv);
                hit_j = true;
            } else if (jq.y >= 1.0 && jq.y < 16.0 && abs(jq.x) < 8.0) {
                let tx = jq.x - sin(jq.y * 0.35 - t * 2.0 + fi) * 1.5;
                if (abs(tx - floor(tx / 3.0) * 3.0 - 1.0) < 0.6) { jc = vec3f(0.9, 0.75, 1.0) * (0.6 + 0.8 * kv); hit_j = true; }
            }
            if (hit_j && bayer < nd) { col = jc; }
        }
    }

    // ---- the spectrum reef: one coral per column, height = its band ----
    let CW = 10.0;
    let ncol = ceil(W / CW);
    let ci = floor(v.x / CW);
    let lx = v.x - ci * CW;
    let bx = ci / max(ncol - 1.0, 1.0);
    let sv = spec(0.03 + bx * 0.78);
    let ch = 12.0 + sv * 58.0 + hash11(ci * 3.1) * 8.0 + G.kick * 6.0 * (1.0 - bx);
    let up = fy - v.y;
    let u = up / ch;
    let ty = i32(hash11(ci * 7.31 + 2.0) * 4.0);
    let cp = vec2f(lx, up);
    var dc = 1e3;
    var ccol = vec3f(0.0);
    if (ty == 0) {          // staghorn
        let w0 = sin(u * 5.0 + ci) * 1.0;
        dc = sd_segment(cp, vec2f(5.0, 0.0), vec2f(5.0 + w0, ch)) - 1.3;
        dc = min(dc, sd_segment(cp, vec2f(5.0, ch * 0.3), vec2f(1.6, ch * 0.72)) - 1.0);
        dc = min(dc, sd_segment(cp, vec2f(5.0, ch * 0.5), vec2f(8.4, ch * 0.9)) - 1.0);
        ccol = mix(vec3f(0.95, 0.6, 0.35), vec3f(0.9, 0.55, 1.0), hash11(ci));
    } else if (ty == 1) {   // pillar / brain coral
        dc = sd_round_box(cp - vec2f(5.0, ch * 0.5), vec2f(4.3, ch * 0.5), 3.5);
        let g = sin(lx * 1.9 + sin(up * 0.8 + ci) * 2.5);
        ccol = select(vec3f(0.82, 0.85, 0.38), vec3f(0.5, 0.58, 0.22), g > 0.3);
    } else if (ty == 2) {   // tube sponges
        let ti = clamp(floor(lx / 3.4), 0.0, 2.0);
        let tcx = 1.7 + ti * 3.3;
        let th = ch * (0.65 + 0.35 * hash11(ci * 5.0 + ti));
        dc = sd_box(cp - vec2f(tcx, th * 0.5), vec2f(1.4, th * 0.5));
        ccol = hsv(0.74 + hash11(ci) * 0.14, 0.65, 0.85);
        if (up > th - 2.0 && abs(lx - tcx) < 0.6) { ccol = vec3f(0.1, 0.03, 0.15); }
    } else {                // sea fan lattice
        let fq = cp - vec2f(5.0, 0.0);
        let fr = length(fq);
        let fa = atan2(fq.x, fq.y);
        dc = max(fr - ch, abs(fa) - 1.0);
        if (fr > 4.0 && !(fract(fa * 6.0) < 0.3 || fract(fr / 3.5) < 0.3)) { dc = 2.0; }
        if (fr < 4.0 && abs(fq.x) < 1.0) { dc = -1.0; }
        ccol = mix(vec3f(0.95, 0.25, 0.45), vec3f(1.0, 0.55, 0.15), hash11(ci + 0.3));
    }
    if (up > -0.5 && dc < 1.0) {
        if (dc < 0.0) {
            var cc = ccol * (0.6 + 0.5 * clamp(u, 0.0, 1.0));
            cc += ccol * smoothstep(0.75, 1.0, u) * sv * 1.6;
            if (hash21(floor(v) + floor(t * 15.0)) > 0.985 - G.hat * 0.04) { cc += vec3f(1.2); }
            col = cc * (0.75 + 0.3 * G.energy);
        } else { col = RH_INK; }
    }

    // ---- sand with dancing caustics ----
    if (v.y > fy) {
        var sc = mix(vec3f(0.88, 0.77, 0.5), vec3f(0.6, 0.48, 0.3), clamp((v.y - fy) / 14.0, 0.0, 1.0));
        sc *= 0.9 + 0.2 * hash21(floor(v * 0.5));
        let cz = noise2(v * 0.12 + vec2f(t * 0.6, t * 0.3)) + noise2(v * 0.17 - vec2f(t * 0.4, -t * 0.5));
        if (abs(cz - 1.0) < 0.06 + 0.05 * G.hat) { sc *= 1.35; }
        col = sc * (0.75 + 0.3 * G.energy);
    }

    // ---- treasure chest: rattles on kicks, bursts open on the drop ----
    let chx = floor(W * 0.13);
    let cfy = floor(rh_floor(chx));
    let open = smoothstep(0.0, 0.08, G.drop);
    if (open > 0.0) {
        let gq = v - vec2f(chx, cfy - 8.0);
        let cone_w = -gq.y * 0.45 + 6.0;
        if (gq.y < 0.0 && abs(gq.x) < cone_w) {
            col += G.pal1.rgb * 0.6 * open * exp(gq.y / 22.0) * smoothstep(1.0, 0.6, abs(gq.x) / cone_w) * step(0.5, fract(atan2(gq.x, -gq.y) * 3.0 + t * 2.0));
        }
    }
    let chq = v - vec2f(chx + floor(sin(t * 50.0) * G.kick * 1.5) * (1.0 - open), cfy);
    if (abs(chq.x) < 18.0 && chq.y > -24.0 && chq.y < 1.0) {
        let cc2 = rh_chest(chq, open);
        if (cc2.a > 0.5) { col = cc2.rgb; }
    }

    // ---- anemone + clownfish ----
    let ab = vec2f(floor(W * 0.76), floor(rh_floor(W * 0.76)) - 2.0);
    let aq = v - ab;
    if (abs(aq.x) < 24.0 && aq.y < 5.0 && aq.y > -26.0) {
        let ar = length(aq);
        let aa = atan2(aq.x, -aq.y);
        if (abs(aa) < 1.45 && aq.y < 0.0) {
            let sw = sin(t * 1.7 + ar * 0.22) * 0.22 * (ar / 16.0) * (1.0 + G.mid);
            let a2 = (aa - sw) * 5.5;
            let ti = floor(a2 + 0.5);
            let len = 13.0 + 4.0 * hash11(ti * 3.3) + 4.0 * G.beat * act + 2.0 * sin(t * 2.0 + ti);
            let wd = abs(a2 - ti) / 5.5 * ar;
            if (ar < len && wd < 1.1) {
                var tc = mix(vec3f(0.75, 0.45, 0.85), vec3f(1.0, 0.55, 0.85), ar / len);
                if (ar > len - 2.5) { tc = vec3f(0.6, 1.0, 0.7) * (1.0 + G.hat); }
                col = tc;
            }
        }
        let dmound = (length(vec2f(aq.x / 9.0, aq.y / 4.0)) - 1.0) * 4.0;
        if (dmound < 0.0) { col = vec3f(0.45, 0.2, 0.55); } else if (dmound < 1.0) { col = RH_INK; }
    }
    for (var j = 0; j < 2; j++) {
        let fj = f32(j);
        let ca = t * 1.1 + fj * PI;
        let cpos = floor(ab + vec2f(cos(ca) * 12.0, -12.0 + sin(t * 1.9 + fj * 2.0) * 4.0 - G.beat * 3.0 * act));
        let cq = (v - cpos - 0.5) * vec2f(select(1.0, -1.0, sin(ca) > 0.0), 1.0);
        if (abs(cq.x) < 7.0 && abs(cq.y) < 4.0) {
            let k2 = rh_clown(cq);
            if (k2.a > 0.5) { col = k2.rgb; }
        }
    }

    // ---- crabs side-stepping on every beat, snapping on snares ----
    for (var j = 0; j < 2; j++) {
        let fj = f32(j);
        let mv = bc + smoothstep(0.0, 0.3, ph) + t * 0.15;
        let cxp = W * (0.42 + fj * 0.48) + sin(mv * 0.9 + fj * 2.0) * 12.0;
        let cpos = vec2f(floor(cxp), floor(rh_floor(cxp)) - 4.0);
        let cq = v - cpos;
        if (abs(cq.x) < 12.0 && abs(cq.y) < 10.0) {
            let k2 = rh_crab(cq, mv, G.snare);
            if (k2.a > 0.5) { col = k2.rgb; }
        }
    }

    // ---- diver (follows the cursor), spear target = this beat's lionfish ----
    let idle = vec2f(W * 0.3 + sin(t * 0.21) * W * 0.12, 80.0 + sin(t * 0.33) * 14.0);
    let dpos = floor(mix(idle, G.mouse * vec2f(W, RH_VH), G.mouse_on));
    let tk = i32(bc) % 3;
    let tl = rh_lpos(tk, t, bc, W);
    let ddir = select(-1.0, 1.0, tl.x >= dpos.x);
    let gtip = dpos + vec2f(16.0 * ddir, 2.8);
    let hit = step(0.28, ph) * hunt * step(8.0, tl.x) * step(tl.x, W - 8.0);

    // lionfish, fins flaring with sub + kick
    let flare = G.bass * 0.7 + G.kick * 0.7;
    for (var k = 0; k < 3; k++) {
        let lp = rh_lpos(k, t, bc, W);
        let lq = (v - floor(lp.xy) - 0.5) * vec2f(lp.z, 1.0);
        if (abs(lq.x) < 20.0 && abs(lq.y) < 18.0) {
            var lc = rh_lion(lq, 1.6, flare, t + f32(k));
            if (k == tk && hit > 0.5) {
                if (ph > 0.75) { lc.a = 0.0; }
                else if (fract(ph * 14.0) < 0.5) { lc = vec4f(vec3f(1.8), lc.a); }
            }
            if (lc.a > 0.5 && bayer >= nq + nd) { col = lc.rgb; }
        }
    }

    // build-up: a huge lionfish shadow slides in from the right as tension climbs
    if (bpg > 0.03) {
        let sbs = 2.2 + 2.0 * bpg;
        let sp = floor(vec2f(W + 40.0 - bpg * W * 0.3, 74.0 + sin(t * 1.1) * 6.0));
        let sq3 = (v - sp) * vec2f(-1.0, 1.0);
        if (abs(sq3.x) < 15.0 * sbs && abs(sq3.y) < 12.5 * sbs) {
            let sc3 = rh_lion(sq3, sbs, 0.4 + G.snare, t);
            if (sc3.a > 0.5 && bayer < bpg * 1.6) { col = RH_INK * 1.6 + vec3f(0.45, 0.02, 0.05) * (0.3 + G.snare + 0.4 * G.beat); }
            if (length(sq3 / sbs - vec2f(3.4, -0.5)) < 0.75 && bayer < bpg * 1.6) { col = vec3f(2.0, 0.2, 0.1); }
        }
    }

    // boss lionfish on the drop: huge, flashes on every kick, health drains as the drop fades
    if (bossOn) {
        let bs = 4.2;
        let bpos = floor(vec2f(W * 0.7 + pow(G.drop, 4.0) * 90.0 + sin(t * 1.3) * 6.0, 72.0 + sin(t * 0.9) * 10.0));
        let bq = (v - bpos) * vec2f(-1.0, 1.0);
        if (abs(bq.x) < 62.0 && abs(bq.y) < 52.0) {
            var bcl = rh_lion(bq, bs, G.bass + G.kick + 0.4, t);
            bcl = vec4f(mix(bcl.rgb * vec3f(0.85, 0.7, 0.8), vec3f(1.8), G.kick * 0.7), bcl.a);
            if (length(bq / bs - vec2f(3.4, -0.5)) < 0.75) { bcl = vec4f(2.2, 0.25, 0.1, 1.0); }
            if (G.drop < 0.15 && np < 0.4 && fract(t * 12.0) < 0.5) { bcl.a = 0.0; }
            if (bcl.a > 0.5) { col = bcl.rgb; }
        }
    }

    // diver sprite
    let dq = (v - dpos - 0.5) * vec2f(ddir, 1.0);
    if (abs(dq.x) < 22.0 && abs(dq.y) < 9.0) {
        let dcl = rh_diver(dq, t);
        if (dcl.a > 0.5) { col = dcl.rgb; }
    }

    // spear flight + rope, burst, +100 popup
    let onscr = step(8.0, tl.x) * step(tl.x, W - 8.0);
    if (hunt * onscr > 0.5 && ph < 0.75) {
        let prog = smoothstep(0.0, 0.28, ph);
        let tgt = floor(tl.xy) + 0.5;
        let sdir = normalize(tgt - gtip + vec2f(1e-4, 0.0));
        let head = mix(gtip, tgt, prog);
        let ds = sd_segment(v, head - sdir * 9.0, head);
        if (ds < 0.6) { col = select(vec3f(0.85, 0.9, 0.95), vec3f(1.6), length(v - head) < 1.5); }
        let rope = sd_segment(v, gtip, head - sdir * 9.0);
        if (rope < 0.5 && fract(dot(v - gtip, sdir) / 3.0) < 0.5) { col = vec3f(0.9, 0.9, 0.75); }
    }
    if (hit > 0.5) {
        let age = ph - 0.28;
        for (var i = 0; i < 8; i++) {
            let an = f32(i) * TAU / 8.0 + 0.3;
            let bp = floor(tl.xy + vec2f(cos(an), sin(an)) * age * 45.0);
            if (all(floor(v) == bp)) { col = select(G.pal1.rgb * 1.6, vec3f(2.0), i % 2 == 0); }
        }
        let pq = floor(v) - floor(tl.xy + vec2f(-8.0, -14.0 - age * 18.0));
        if (rh_word(pq + vec2f(-1.0, -1.0), 18, 1, 0, 0, -1) > 0.5) { col = RH_INK; }
        if (rh_word(pq, 18, 1, 0, 0, -1) > 0.5) { col = select(G.pal1.rgb * 1.5, vec3f(1.8), fract(ph * 10.0) < 0.5); }
    }

    // ---- coins bursting from the chest on the drop ----
    if (G.drop > 0.005) {
        let age = (1.0 - G.drop) * 1.4;
        for (var i = 0; i < 18; i++) {
            let fi = f32(i);
            let vel = vec2f((hash11(fi * 7.1) - 0.5) * 80.0, -(45.0 + hash11(fi * 3.9) * 50.0));
            var cpos = vec2f(chx, cfy - 8.0) + vel * age + vec2f(0.0, 70.0 * age * age);
            cpos.y = min(cpos.y, cfy - 1.0);
            let spin = abs(sin(age * 9.0 + fi));
            let cq = abs(v - floor(cpos) - 0.5);
            if (cq.x < 0.5 + spin && cq.y < 1.5) {
                col = select(G.pal1.rgb * 1.6, vec3f(2.2), cq.x < 0.5 && cq.y < 0.5 && spin > 0.8);
            }
        }
    }

    // ---- drop only: lightning bolts crack down from the surface ----
    if (np > 0.4) {
        for (var i = 0; i < 3; i++) {
            let fi = f32(i);
            let sd2 = floor(t * 5.0) + fi * 9.0;
            let bx = hash11(sd2) * W + sin(v.y * 0.3 + fi * 3.0) * 6.0 + sin(v.y * 0.9) * 2.0;
            if (abs(v.x - bx) < 0.8 && v.y < 120.0 && hash11(sd2 + 4.0) > 0.35 && fract(t * 5.0) < 0.45 + G.kick * 0.3) { col = vec3f(2.0, 1.9, 2.2); }
        }
    }
    // ---- chorus only: rainbow confetti drifting up ----
    if (nc > 0.03) {
        for (var i = 0; i < 22; i++) {
            let fi = f32(i);
            let cp2 = floor(vec2f(hash11(fi * 6.1) * W + sin(t * 0.8 + fi) * 4.0, RH_VH - fract(t * (0.06 + 0.05 * hash11(fi * 2.7)) + hash11(fi * 8.3)) * RH_VH));
            let dq2 = abs(v - cp2 - 0.5);
            if (dq2.x < 1.2 && dq2.y < 1.2 && bayer < nc) { col = hsv(hash11(fi * 1.9) + t * 0.05, 0.55, 1.6); }
        }
    }

    // ---- bubbles: ambient (faster with flux), regulator, click burst ----
    for (var i = 0; i < 28; i++) {
        if (i >= 14 && bayer >= nd) { break; }
        let fi = f32(i);
        let bp = vec2f(hash11(fi * 3.7) * W + sin(t * 1.5 + fi) * 2.0,
                       RH_VH - fract(t * (0.05 + hash11(fi * 5.1) * 0.06) + G.travel * 0.01 + hash11(fi * 9.3)) * 175.0);
        let r = 1.0 + step(0.6, hash11(fi * 2.2));
        let d = length(v - floor(bp) - 0.5);
        if (abs(d - r) < 0.6) { col = mix(col, vec3f(0.85, 1.0, 1.0), 0.8); }
    }
    for (var i = 0; i < 5; i++) {
        let fi = f32(i);
        let a = fract(t * 0.8 + fi * 0.2);
        let bp = dpos + vec2f(7.0 * ddir + sin(t * 4.0 + fi * 2.0) * 1.5, -5.0 - a * 34.0);
        if (length(v - floor(bp) - 0.5) < 0.9 + a) { col = mix(col, vec3f(0.9, 1.0, 1.0), 0.7); }
    }
    if (G.click_age < 1.5) {
        let ca = G.click_age;
        let cpp = G.click_pos * vec2f(W, RH_VH);
        if (abs(length(v - cpp) - ca * 70.0) < 1.0 && ca < 0.5) { col = vec3f(1.5); }
        for (var i = 0; i < 12; i++) {
            let fi = f32(i);
            let an = fi * TAU / 12.0 + hash11(fi) * 0.4;
            let bp = cpp + vec2f(cos(an), sin(an)) * ca * (30.0 + hash11(fi * 4.0) * 20.0) * (1.0 - ca * 0.3) - vec2f(0.0, ca * ca * 20.0);
            if (abs(length(v - floor(bp) - 0.5) - 1.5) < 0.6) { col = vec3f(0.9, 1.0, 1.0); }
        }
        if (ca < 0.5) {
            let head = cpp + vec2f(ddir * ca * 260.0, 0.0);
            if (sd_segment(v, head - vec2f(ddir * 10.0, 0.0), head) < 0.6) { col = vec3f(1.6); }
        }
    }

    // ---- HUD: SCORE / COMBO in the pixel font, BOSS health bar on the drop ----
    let score = bc * 100.0 + floor(G.travel) * 10.0;
    let combo = f32(1 + i32(bc) % 32);
    let hud_c = vec3f(1.3);
    let hud_on = bayer < clamp(1.0 - nq - nd, 0.0, 1.0) * 1.001;
    let sq = pix - vec2f(4.0, 3.0);
    let s_sh = rh_word(sq - 1.0, 10, 11, 12, 13, 14) + rh_num(sq - vec2f(23.0, 1.0), score, 7);
    let s_on = rh_word(sq, 10, 11, 12, 13, 14) + rh_num(sq - vec2f(22.0, 0.0), score, 7);
    if (s_sh > 0.5 && hud_on) { col = RH_INK; }
    if (s_on > 0.5 && hud_on) { col = select(hud_c, G.pal1.rgb * 1.4, sq.x >= 22.0); }
    let cq2 = pix - vec2f(W - 40.0, 3.0);
    let c_sh = rh_word(cq2 - 1.0, 11, 12, 15, 16, 12) + rh_word(cq2 - vec2f(23.0, 1.0), 17, -1, -1, -1, -1) + rh_num(cq2 - vec2f(27.0, 1.0), combo, 2);
    let c_on = rh_word(cq2, 11, 12, 15, 16, 12) + rh_word(cq2 - vec2f(22.0, 0.0), 17, -1, -1, -1, -1) + rh_num(cq2 - vec2f(26.0, 0.0), combo, 2);
    if (c_sh > 0.5 && hud_on) { col = RH_INK; }
    if (c_on > 0.5 && hud_on) { col = select(hud_c, mix(G.pal2.rgb * 1.4, G.pal1.rgb * 1.8, G.kick), cq2.x >= 22.0); }
    if (bpg > 0.3 && fract(t * (1.0 + 4.0 * bpg)) < 0.5) {
        let wq2 = pix - vec2f(floor(W * 0.5) - 8.0, 13.0);
        if (rh_word(wq2, 16, 12, 10, 10, -1) > 0.5) { col = vec3f(1.8, 0.3, 0.2); }
    }
    if (bossOn) {
        let bq2 = pix - vec2f(floor(W * 0.5) - 34.0, 13.0);
        if (rh_word(bq2, 16, 12, 10, 10, -1) > 0.5) { col = select(vec3f(1.8, 0.3, 0.2), vec3f(1.8), fract(t * 6.0) < 0.5); }
        let hp = max(smoothstep(0.05, 0.9, G.drop), np * max(0.12, 0.95 - G.section_age * 0.02));
        let hx = bq2.x - 18.0;
        if (hx >= 0.0 && hx < 50.0 && bq2.y >= 0.0 && bq2.y < 5.0) {
            let edge = hx < 1.0 || hx >= 49.0 || bq2.y < 1.0 || bq2.y >= 4.0;
            col = select(select(vec3f(0.15, 0.02, 0.05), mix(vec3f(1.6, 0.2, 0.1), vec3f(1.8, 1.4, 0.2), step(0.5, hp)), (hx - 1.0) / 48.0 < hp), vec3f(1.2), edge);
        }
    }

    // ---- drop flash, vignette, palette quantisation with ordered dither ----
    col += G.pal1.rgb * G.drop * 0.12;
    col += vec3f(0.35, 0.04, 0.05) * G.snare * nb;
    col = mix(col, col * vec3f(1.2, 0.45, 0.5), bpg * clamp(dot(fc / G.res - 0.5, fc / G.res - 0.5) * 3.5, 0.0, 1.0));
    let uv = fc / G.res;
    col *= 1.0 - 0.3 * dot(uv - 0.5, uv - 0.5) * 2.0;
    let L = 7.0;
    col = floor(max(col, vec3f(0.0)) * L + rh_bayer(pix)) / L;
    return vec4f(col, 1.0);
}
