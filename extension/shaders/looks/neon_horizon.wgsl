// name: Neon Horizon
// palette: #ff2a9d #7b2cff #ffcf3a
// Synthwave drive: striped sun, spectrum mountains, racing grid, skyline, palms, a car, VHS tape.
// pal0 = neon pink (grid, glow), pal1 = violet (sky, mountains), pal2 = sun gold.

const NH_CAMH: f32 = 1.0;
const NH_CYAN: vec3f = vec3f(0.18, 0.88, 1.0);

fn nh_ln(d: f32, w: f32) -> f32 { return clamp(1.0 - d / w, 0.0, 1.0) + 0.3 * exp(-d / (w * 5.0)); }

fn nh_seg7(p: vec2f, dg: i32) -> f32 {
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

// tape counter H:MM:SS, p in digit units (y up), origin left-middle
fn nh_counter(p: vec2f, secs: f32) -> f32 {
    // slots: H : M M : S S  -> x positions
    var d = 1e5;
    let hh = floor(secs / 3600.0) % 10.0;
    let mm = floor(secs / 60.0) % 60.0;
    let ss = floor(secs) % 60.0;
    var xs = array<f32, 5>(0.5, 2.6, 4.1, 6.2, 7.7);
    var vs = array<f32, 5>(hh, floor(mm / 10.0), mm % 10.0, floor(ss / 10.0), ss % 10.0);
    for (var i = 0; i < 5; i++) {
        d = min(d, nh_seg7(p - vec2f(xs[i], 0.0), i32(vs[i])));
    }
    // colons
    d = min(d, length(abs(p - vec2f(1.55, 0.0)) - vec2f(0.0, 0.45)) - 0.08);
    d = min(d, length(abs(p - vec2f(5.15, 0.0)) - vec2f(0.0, 0.45)) - 0.08);
    return d;
}

// palm tree silhouette distance; q relative to the trunk base, s = height
fn nh_palm(q0: vec2f, s: f32, lean: f32, sway: f32) -> f32 {
    let q = q0 / s;
    // trunk: curved, tapering
    let ty = clamp(q.y, 0.0, 1.0);
    let tx = lean * ty * ty + sway * ty * ty * ty;
    var d = max(abs(q.x - tx) - mix(0.035, 0.018, ty), max(-q.y, q.y - 1.0));
    // trunk rings (notches)
    let crown = vec2f(lean + sway, 1.0);
    // fronds: 7 drooping arcs
    for (var i = 0; i < 8; i++) {
        let fi = f32(i);
        let a = mix(-0.35, PI + 0.35, fi / 7.0) + sway * 0.6;
        let len = 0.5 + 0.1 * sin(fi * 2.3);
        let dir = vec2f(cos(a), sin(a) * 0.55);
        let p1 = crown + dir * len * 0.35 + vec2f(0.0, 0.05);
        let p2 = crown + dir * len * 0.7 + vec2f(0.0, 0.02);
        let p3 = crown + dir * len + vec2f(0.0, -0.08 - 0.06 * abs(dir.x));
        d = min(d, sd_segment(q, crown, p1) - 0.022);
        d = min(d, sd_segment(q, p1, p2) - 0.016);
        d = min(d, sd_segment(q, p2, p3) - 0.006);
    }
    d = min(d, length(q - crown) - 0.035);
    return d * s;
}

fn look(fc0: vec2f) -> vec4f {
    let res = G.res;
    let pxs = 2.0 / res.y;
    // VHS tracking band: a drifting strip of horizontal tearing
    let tb = fract(G.time * 0.06) * 1.3 - 0.15;
    let uvy = fc0.y / res.y;
    let inband = smoothstep(0.035, 0.0, abs(uvy - tb));
    let jit = (hash21(vec2f(floor(fc0.y * 0.5), floor(G.time * 30.0))) - 0.5) * (inband * 0.02 + 0.0015 * G.snare + 0.01 * G.drop);
    let fc = fc0 + vec2f(jit * res.x, 0.0);
    let uv = fc0 / res;
    let p = centered(fc);

    let mo = G.mouse - vec2f(0.5);
    let pan = mo.x * 0.7 + sin(G.time * 0.1) * 0.05;
    let yh = 0.04 + mo.y * 0.35;               // horizon line (mouse tilts the camera)
    let cpink = G.pal0.rgb;
    let cviol = G.pal1.rgb;
    let csun = G.pal2.rgb;
    let speed = G.travel * 3.0;

    var col = vec3f(0.0);
    let above = p.y - yh;

    if (above > 0.0) {
        // ---------------- sky ----------------
        let warm = G.centroid;
        col = mix(cviol * 0.35 + cpink * 0.08 * (0.5 + warm), vec3f(0.01, 0.0, 0.04), smoothstep(0.0, 0.9, above));
        col += cpink * 0.35 * exp(-above * 9.0) * (0.6 + 0.6 * G.energy);
        // stars
        let sg = (p + vec2f(pan * 0.15, 0.0)) * 60.0;
        let sc = floor(sg);
        let sh = hash21(sc);
        if (sh > 0.86) {
            let so = hash22(sc) * 0.8 + 0.1;
            let tw = 0.5 + 0.5 * sin(G.time * (2.0 + 6.0 * sh) + sh * 40.0) + G.hat * step(0.95, sh) * 2.0;
            col += vec3f(0.85, 0.85, 1.0) * smoothstep(0.08, 0.0, length(fract(sg) - so)) * tw * smoothstep(0.05, 0.4, above) * (sh - 0.86) * 8.0;
        }
        // shooting stars: one per beat (two when busy)
        for (var k = 0; k < 2; k++) {
            let bid = floor(G.beat_count) + f32(k) * 17.0;
            if (k == 1 && G.flux < 0.3) { continue; }
            let st = G.beat_phase;
            let s0 = vec2f((hash11(bid * 1.7) - 0.5) * 3.0, yh + 0.45 + 0.4 * hash11(bid * 3.1));
            let dir = normalize(vec2f(select(-1.0, 1.0, hash11(bid) > 0.5), -0.35));
            let head = s0 + dir * st * 1.4;
            let tail = head - dir * (0.25 + 0.3 * G.energy);
            let d = sd_segment(p, tail, head);
            let along = clamp(dot(p - tail, dir) / length(head - tail), 0.0, 1.0);
            col += mix(cpink, vec3f(1.0), along) * nh_ln(d, pxs * 1.5) * along * (1.0 - st) * 1.5 * step(0.05, G.energy);
        }
        // ---------------- striped sun ----------------
        let sc0 = vec2f(-pan * 0.35, yh + 0.27);
        let sr = 0.36 * (1.0 + 0.03 * G.bass + 0.04 * G.drop);
        let sq = p - sc0;
        let sd = length(sq) - sr;
        let sy = sq.y / sr;                               // -1 bottom .. 1 top
        // stripes in the lower half scroll down on the beat, gaps widen downward
        let stripe = fract(sy * 7.0 + G.beat_phase);
        let gap = clamp((0.35 - sy) * 0.5, 0.0, 0.75);
        let cut = smoothstep(gap - 0.04, gap, stripe) * 0.0 + step(stripe, gap) * step(sy, 0.35);
        let sunc = mix(cpink * 1.05, csun * 1.05, smoothstep(-0.8, 0.7, sy));
        col = mix(col, sunc * (1.0 + 0.4 * G.kick), fill(sd, pxs) * (1.0 - cut));
        col += mix(cpink, csun, 0.3) * 0.3 * exp(-max(sd, 0.0) * 6.0) * (0.4 + 0.4 * G.energy + 0.6 * G.kick + G.drop) * step(0.0, sd);
        // ---------------- skyline: windows flicker to the highs ----------------
        let bxs = (p.x + pan * 0.6) / 0.03;
        let bc = floor(bxs);
        let bh0 = hash11(bc * 0.71);
        let skyl = smoothstep(1.6, 0.2, abs(p.x + pan * 0.6 + 0.5 * sin(bc * 0.01)));
        let bhgt = (0.02 + 0.17 * bh0 * bh0 * bh0 + 0.04 * hash11(bc + 3.0)) * (0.3 + 0.7 * skyl);
        if (above < bhgt) {
            col = vec3f(0.01, 0.0, 0.03) + cviol * 0.04;
            let wq = vec2f(fract(bxs) * 0.03, above);
            let wg = vec2f(floor(fract(bxs) * 4.0), floor(above / 0.006));
            let wl = fract(vec2f(fract(bxs) * 4.0, above / 0.006));
            let lit = step(hash21(wg + bc * 13.0 + floor(G.time * (0.5 + 4.0 * G.hat))), 0.1 + 0.6 * G.high + 0.1 * G.energy);
            let win = step(0.3, wl.x) * step(wl.x, 0.75) * step(0.3, wl.y) * step(wl.y, 0.75) * step(wg.x, 2.5) * step(0.5, wg.x);
            col += mix(csun, NH_CYAN, step(0.6, hash21(wg + bc))) * win * lit * 0.8;
            col += cpink * nh_ln(bhgt - above, pxs) * 0.3;       // roof rim light
            // antenna beacon on tall towers, blinks on the beat
            if (bh0 > 0.8) {
                col += vec3f(1.0, 0.2, 0.2) * smoothstep(pxs * 3.0, 0.0, length(wq - vec2f(0.015, bhgt + 0.004))) * (1.0 - G.beat_phase);
            }
        }
        col += cviol * 0.06 * smoothstep(0.2, 0.0, above);
    } else {
        // ---------------- ground: racing perspective grid ----------------
        let dy = -above;
        let z = NH_CAMH / max(dy, 1e-4);
        let xw = (p.x + pan) * z;
        let fz = z * z * pxs / NH_CAMH;
        let fx = z * pxs;
        let zz = z + speed;
        let dzl = abs(fract(zz * 0.5 + 0.5) - 0.5) * 2.0;
        let dxl = abs(fract(xw * 0.5 + 0.5) - 0.5) * 2.0;
        let fog = exp(-z * 0.035);
        let gpulse = 1.0 + 0.8 * G.snare + 1.5 * G.drop;
        var grid = nh_ln(dzl, fz * 1.3) * clamp(1.0 - fz * 1.5, 0.0, 1.0) + nh_ln(dxl, fx * 1.3);
        col = vec3f(0.015, 0.0, 0.03) + cviol * 0.05 * fog;
        // sun reflection: rippled mirror image
        let ry = yh + dy * 1.0;
        let rq = vec2f(p.x + pan * 0.35 + sin(z * 3.0 + G.time * 2.0) * 0.012 * dy * 4.0, ry - (yh + 0.27));
        let rsd = length(rq) - 0.36;
        let rstripe = step(0.5, fract(z * 1.5 + speed * 0.5));
        col += mix(cpink, csun, 0.5) * fill(rsd, pxs * 4.0) * 0.35 * smoothstep(0.35, 0.0, dy) * rstripe;
        // road: dark asphalt, glowing edges, dashed centre line
        let ax = abs(xw);
        let road = step(ax, 1.4);
        col = mix(col, vec3f(0.01, 0.0, 0.02), road * 0.8);
        grid *= 1.0 - road * 0.85;
        col += cpink * grid * 0.9 * fog * gpulse;
        col += NH_CYAN * nh_ln(abs(ax - 1.4), fx * 1.5) * 1.1 * fog;
        let dash = step(fract(zz * 0.25), 0.45);
        col += vec3f(1.0, 0.9, 0.7) * nh_ln(ax, fx * 1.8) * dash * 0.9 * fog * clamp(1.0 - fz * 0.5, 0.0, 1.0);
        // kick shockwave rolling out across the grid
        let kw = abs(z - (2.0 + (1.0 - G.kick) * 25.0));
        col += cpink * nh_ln(kw, fz * 4.0 + 0.05) * G.kick * 0.6 * fog * (1.0 - road);
        col += cpink * 0.25 * exp(-dy * 14.0);        // horizon haze
    }

    // ---------------- mountains from the spectrum history, scrolling toward us ----------------
    let nl = 9 + i32(G.quality) * 3;
    var bestz = 1e5;
    var mcol = vec3f(0.0);
    var rimg = vec3f(0.0);
    for (var k = 0; k < nl; k++) {
        let zk = 3.0 + 42.0 * fract(f32(k) / f32(nl) - G.travel * 0.04);
        if (zk > bestz) { continue; }
        let xw = (p.x + pan) * zk;
        let a = abs(xw);
        let env = smoothstep(2.2, 9.0, a);
        let age = clamp(zk / 45.0, 0.0, 1.0);
        let bx = clamp(a / 40.0, 0.0, 1.0) * 0.8 + 0.03;
        let hs = hist(bx, age);
        let h = env * (0.8 + 2.2 * noise2(vec2f(xw * 0.12, f32(k) * 7.3)) + 7.0 * hs * hs + 1.2 * hs);
        let ybase = yh - NH_CAMH / zk;
        let ytop = yh + (h - NH_CAMH) / zk;
        let fade = smoothstep(45.0, 30.0, zk) * smoothstep(3.0, 6.0, zk);
        if (p.y < ytop && p.y > ybase && h > 0.05) {
            bestz = zk;
            let hw = (p.y - ybase) * zk;
            let fpx = pxs * zk;
            let cont = nh_ln(abs(fract(hw / 0.6 + 0.5) - 0.5) * 0.6, fpx * 1.2) * 0.25;
            let vert = nh_ln(abs(fract(xw * 0.5 + 0.5) - 0.5) * 2.0, fpx * 1.2) * 0.18;
            let rim = nh_ln(ytop - p.y, pxs * 1.4);
            let bg = mix(vec3f(0.01, 0.0, 0.03), cviol * 0.12, hw / max(h, 0.1));
            let wire = mix(cviol * 1.3, NH_CYAN, hs) * (cont + vert);
            mcol = mix(col * 0.6, bg + wire + mix(cpink, NH_CYAN, hs) * rim * (1.0 + G.snare), fade);
        } else if (p.y >= ytop && h > 0.05) {
            rimg += mix(cpink, NH_CYAN, hs) * 0.25 * exp(-(p.y - ytop) / (pxs * 6.0)) * fade;
        }
    }
    if (bestz < 1e4) { col = mcol; } else { col += rimg; }

    // ---------------- palms ----------------
    let sway = sin(G.time * 0.8) * 0.04 + G.bass * 0.06;
    let pd1 = nh_palm(p - vec2f(-1.25 - pan * 1.3, yh - 0.55), 0.95, 0.18, sway);
    let pd2 = nh_palm(vec2f(-1.0, 1.0) * (p - vec2f(1.35 - pan * 1.3, yh - 0.5)), 0.85, 0.15, -sway);
    let pd3 = nh_palm(p - vec2f(-0.75 - pan * 0.9, yh - 0.15), 0.35, 0.1, sway);
    let pd = min(min(pd1, pd2), pd3);
    col = mix(col, vec3f(0.005, 0.0, 0.012), fill(pd, pxs * 1.5));
    col += cpink * nh_ln(abs(pd), pxs * 1.2) * 0.35 * (0.6 + 0.6 * G.energy);

    // ---------------- the car (rear view), tail lights flare on the kick ----------------
    let bounce = 0.008 * (1.0 - G.beat_phase) * G.energy + 0.004 * sin(G.time * 9.0) * G.bass;
    let cq = p - vec2f(-pan * 0.15, -0.72 + bounce);
    let body = sd_round_box(cq, vec2f(0.32, 0.07), 0.03);
    let cab = sd_round_box(cq - vec2f(0.0, 0.11), vec2f(0.2 - (cq.y - 0.11) * 0.8, 0.05), 0.02);
    let whl = min(sd_box(cq - vec2f(-0.24, -0.1), vec2f(0.055, 0.04)), sd_box(cq - vec2f(0.24, -0.1), vec2f(0.055, 0.04)));
    let car = min(min(body, cab), whl);
    col = mix(col, vec3f(0.01, 0.0, 0.02), fill(car, pxs));
    col += NH_CYAN * nh_ln(abs(min(body, cab)), pxs * 1.2) * 0.7;
    col += cviol * 0.3 * fill(-(cab + 0.012), pxs) * (0.5 + 0.5 * smoothstep(0.0, 0.05, cq.y - 0.08));   // rear window sheen
    // tail light bar
    let tlq = vec2f(abs(cq.x), cq.y) - vec2f(0.19, 0.025);
    let tl = min(sd_round_box(tlq, vec2f(0.09, 0.016), 0.006), sd_box(cq - vec2f(0.0, 0.025), vec2f(0.1, 0.003)));
    // licence plate + bumper line + spoiler
    col += vec3f(0.6, 0.7, 0.9) * nh_ln(abs(sd_box(cq - vec2f(0.0, -0.035), vec2f(0.05, 0.016))), pxs) * 0.5;
    col += NH_CYAN * nh_ln(abs(sd_box(cq - vec2f(0.0, 0.085), vec2f(0.34, 0.006))), pxs) * 0.6;
    let tli = 0.8 + 1.6 * G.kick + 0.8 * G.drop;
    col += vec3f(1.0, 0.12, 0.25) * (fill(tl, pxs) * tli + exp(-max(tl, 0.0) / 0.03) * 0.35 * tli);
    // light trails reflected on the road
    let tr = abs(cq.x) - 0.2;
    col += vec3f(1.0, 0.1, 0.3) * smoothstep(0.08, 0.0, abs(tr)) * smoothstep(-0.1, -0.35, cq.y) * step(cq.y, -0.1) * 0.25 * tli * step(-0.42 - bounce, cq.y + 0.0) ;
    // waveform as the car's exhaust heat line
    let wx = cq.x * 1.2 + 0.5;
    if (cq.y < -0.12 && cq.y > -0.28 && abs(cq.x) < 0.4) {
        let wv = wave(wx) * 0.05;
        col += cpink * nh_ln(abs(cq.y + 0.2 - wv), pxs * 1.2) * 0.6 * smoothstep(0.4, 0.1, abs(cq.x));
    }

    // ---------------- VHS overlay ----------------
    // tape counter + PLAY triangle
    let hp = vec2f(fc0.x / res.y, 1.0 - fc0.y / res.y);  // y up, height 1
    let hw = res.x / res.y;
    let dcnt = nh_counter((hp - vec2f(hw - 0.24, 0.07)) / 0.017, G.look_time) * 0.017;
    col += vec3f(0.9, 0.95, 1.0) * nh_ln(dcnt, 1.8 / res.y) * 0.9;
    let tq = hp - vec2f(0.06, 0.92);
    let tri = max(max(-tq.x, abs(tq.y) * 1.6 + tq.x * 0.9 - 0.02), tq.x - 0.03);
    col += vec3f(0.9, 0.95, 1.0) * fill(tri, 1.5 / res.y) * 0.9;
    col += vec3f(1.0, 0.1, 0.1) * fill(length(hp - vec2f(0.12, 0.92)) - 0.008, 1.5 / res.y) * step(0.5, fract(G.time * 0.8));
    // tracking band noise
    col += vec3f(hash21(fc0 * vec2f(0.05, 1.0) + G.time)) * inband * 0.25;
    // chroma bleed from last frame, stronger on the drop
    let ob = vec2f((1.5 + 6.0 * G.drop) / res.x, 0.0);
    col.r = mix(col.r, prev(uv + ob).r, 0.25 + 0.2 * G.drop);
    col.b = mix(col.b, prev(uv - ob).b, 0.25 + 0.2 * G.drop);
    // scanlines, grain, vignette
    col *= 0.8 + 0.2 * sin(fc0.y / max(res.y / 360.0, 1.0) * PI);
    col += (hash21(fc0 + fract(G.time * 7.0) * 113.0) - 0.5) * 0.04;
    let vq = uv - 0.5;
    col *= clamp(1.0 - dot(vq, vq) * 1.2, 0.0, 1.0);
    col += cpink * G.drop * 0.15 * (1.0 - length(vq));
    return vec4f(col, 1.0);
}
