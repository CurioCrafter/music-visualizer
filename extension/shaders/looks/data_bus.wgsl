// name: Data Bus
// palette: #18e4ff #ff2ad4 #f0f6ff
// You are an antivirus process flying down the data bus of an infected machine. Negative line-art:
// black void, glowing vector edges. pal0 = clean system (cyan), pal1 = infected (magenta),
// pal2 = neutral (white). A giant bitstream worm waits at the end of the bus.

const AR_F: f32 = 1.35;     // focal length
const AR_R: f32 = 1.5;      // tunnel radius
const AR_GY: f32 = -4.0;    // city ground height
const AR_CS: f32 = 3.0;     // city block size

var<private> ar_ang: vec3f;  // roll, pitch, yaw

fn ar_rz(v: vec3f, a: f32) -> vec3f { let c = cos(a); let s = sin(a); return vec3f(c * v.x - s * v.y, s * v.x + c * v.y, v.z); }
fn ar_rx(v: vec3f, a: f32) -> vec3f { let c = cos(a); let s = sin(a); return vec3f(v.x, c * v.y - s * v.z, s * v.y + c * v.z); }
fn ar_ry(v: vec3f, a: f32) -> vec3f { let c = cos(a); let s = sin(a); return vec3f(c * v.x + s * v.z, v.y, -s * v.x + c * v.z); }
fn ar_to_world(v: vec3f) -> vec3f { return ar_ry(ar_rx(ar_rz(v, ar_ang.x), ar_ang.y), ar_ang.z); }
fn ar_to_cam(v: vec3f) -> vec3f { return ar_rz(ar_rx(ar_ry(v, -ar_ang.z), -ar_ang.y), -ar_ang.x); }

// crisp core + soft halo for a line at distance d, width w
fn ar_ln(d: f32, w: f32) -> f32 { return clamp(1.0 - d / w, 0.0, 1.0) + 0.3 * exp(-d / (w * 5.0)); }

// seven-segment digit, p: x -0.5..0.5, y -1..1
fn ar_seg7(p: vec2f, dg: i32) -> f32 {
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

// n-digit number, p in digit units (digit 1 wide, 2 tall, spacing 1.6), origin = left middle
fn ar_num(p: vec2f, val: f32, n: i32) -> f32 {
    let ci = i32(floor(p.x / 1.6));
    if (ci < 0 || ci >= n || abs(p.y) > 1.6) { return 1e5; }
    let lp = vec2f(p.x - (f32(ci) + 0.5) * 1.6, -p.y);   // HUD space is y-down
    let dg = i32(floor(val / pow(10.0, f32(n - 1 - ci))) % 10.0);
    return ar_seg7(lp, dg);
}

// a 0 or 1 glyph in a unit cell
fn ar_bit(lp: vec2f, one: bool) -> f32 {
    if (one) { return min(sd_segment(lp, vec2f(0.5, 0.2), vec2f(0.5, 0.8)), sd_segment(lp, vec2f(0.5, 0.8), vec2f(0.37, 0.68))); }
    let q = (lp - vec2f(0.5)) / vec2f(0.2, 0.3);
    return abs(length(q) - 1.0) * 0.2;
}

// ---------------- wireframe city below the bus (DDA through city blocks) ----------------
fn ar_city(ro: vec3f, rd: vec3f, pxw: f32, infect: f32, cclean: vec3f, cinf: vec3f) -> vec3f {
    var col = vec3f(0.0);
    let rds = select(rd, vec3f(1e-5), abs(rd) < vec3f(1e-5));
    let inv = 1.0 / rds;
    let rd2 = vec2f(rds.x, rds.z);
    var cell = floor(vec2f(ro.x, ro.z) / AR_CS);
    let st = select(vec2f(-1.0), vec2f(1.0), rd2 >= vec2f(0.0));
    let tdel = abs(AR_CS / rd2);
    var tmax = ((cell + max(st, vec2f(0.0))) * AR_CS - vec2f(ro.x, ro.z)) / rd2;
    let n = 16 + i32(G.quality) * 8;
    var hit = false;
    for (var i = 0; i < n; i++) {
        if (abs(cell.x + 0.5) > 1.0) {
            let h = hash21(cell);
            if (h > 0.2) {
                let hgt = 1.2 + 10.0 * hash21(cell + 17.3) * hash21(cell + 4.1) + 3.0 * step(abs(cell.x + 0.5), 2.0) * hash21(cell + 2.2);
                let bmin = vec3f(cell.x * AR_CS + 0.45, AR_GY, cell.y * AR_CS + 0.45);
                let bmax = vec3f(cell.x * AR_CS + AR_CS - 0.45, AR_GY + hgt, cell.y * AR_CS + AR_CS - 0.45);
                let t1 = (bmin - ro) * inv;
                let t2 = (bmax - ro) * inv;
                let tn3 = min(t1, t2);
                let tf3 = max(t1, t2);
                let tn = max(max(tn3.x, tn3.y), tn3.z);
                let tf = min(min(tf3.x, tf3.y), tf3.z);
                if (tn < tf && tn > 0.0) {
                    let hp = ro + rd * tn;
                    let c = (bmin + bmax) * 0.5;
                    let hs = (bmax - bmin) * 0.5;
                    let e = hs - abs(hp - c);
                    let emin = min(e.x, min(e.y, e.z));
                    let emax = max(e.x, max(e.y, e.z));
                    let ed = e.x + e.y + e.z - emin - emax;
                    let w = tn * pxw * 1.2;
                    let infd = hash21(cell + 9.9) < infect;
                    let base = select(cclean, cinf, infd);
                    // floors light up like an equaliser: each tower listens to its own band
                    let fy = hp.y - AR_GY;
                    let lvl = spec(0.04 + 0.9 * fract(h * 7.7)) * 1.3 * hgt;
                    let fd = abs(fract(fy / 0.5 + 0.5) - 0.5) * 0.5;
                    var fl = 0.0;
                    if (tn != tn3.y) {
                        fl = ar_ln(fd, w) * (0.05 + 0.75 * step(fy, lvl)) * clamp(1.0 - w * 6.0, 0.0, 1.0);
                    } else {
                        // roof: a beacon ring blinking with the hats
                        let rr = length(hp.xz - c.xz);
                        fl = ar_ln(abs(rr - 0.5), w) * (0.2 + 1.5 * G.hat * step(0.5, fract(h * 13.0)));
                    }
                    let fog = exp(-tn * 0.016);
                    col = base * (ar_ln(ed, w) * 0.9 + fl) * fog;
                    hit = true;
                    break;
                }
            }
        }
        if (tmax.x < tmax.y) { tmax.x += tdel.x; cell.x += st.x; } else { tmax.y += tdel.y; cell.y += st.y; }
    }
    if (!hit && rd.y < 0.0) {
        let tg = (AR_GY - ro.y) / rd.y;
        let gp = vec2f(ro.x, ro.z) + vec2f(rd.x, rd.z) * tg;
        let wx = tg * pxw * 1.2;
        let wz = wx / max(-rd.y, 0.02);
        let dx = abs(fract(gp.x / AR_CS + 0.5) - 0.5) * AR_CS;
        let dz = abs(fract(gp.y / AR_CS + 0.5) - 0.5) * AR_CS;
        let fog = exp(-tg * 0.02);
        var g = ar_ln(dx, wx) * 0.22 + ar_ln(dz, wz) * 0.22 * clamp(1.0 - wz * 3.0, 0.0, 1.0);
        // PCB traces under the bus carrying pulses on the beat
        let ax = abs(gp.x);
        var tr = 0.0;
        for (var k = 0; k < 3; k++) {
            let tx = 0.7 + 0.65 * f32(k);
            let pulse = smoothstep(0.82, 1.0, fract(gp.y / 14.0 + G.time * (0.6 + 0.3 * f32(k)) + f32(k) * 0.37));
            tr += ar_ln(abs(ax - tx), wx) * (0.15 + pulse * (0.6 + 2.0 * G.beat));
        }
        col = (cclean * g + mix(cclean, vec3f(1.0), 0.4) * tr) * fog;
    }
    return col;
}

// ---------------- The worm: flower mouth of teeth swallowing bits ----------------
fn ar_dev(q: vec2f, S: f32, px: f32, cinf: vec3f, cneu: vec3f) -> vec3f {
    let rho = length(q);
    var c = vec3f(0.0);
    // far halo
    c += cinf * 0.25 * exp(-max(rho - S, 0.0) / (S * 0.6)) * (0.4 + G.bass);
    if (rho > S * 1.8) { return c; }
    let th = atan2(q.y, q.x);
    let open = clamp(0.35 + 0.15 * sin(G.time * 0.7) + 0.35 * G.bass + 0.4 * pow(1.0 - G.beat_phase, 3.0) * G.energy + 0.5 * G.drop, 0.0, 1.0);
    // armoured outer collar, segmented
    let seg = abs(fract(th / TAU * 18.0 + G.time * 0.05) - 0.5);
    c += cneu * ar_ln(abs(rho - S * 1.3), px) * 0.9;
    c += cinf * ar_ln(abs(rho - S * 1.45), px) * 0.7;
    c += cinf * ar_ln(seg * TAU / 18.0 * rho, px) * step(abs(rho - S * 1.375), S * 0.075) * 0.8;
    // rings of teeth (petals): open mouth pulls them outward
    for (var j = 0; j < 4; j++) {
        let fj = f32(j);
        let rj = S * (1.25 - 0.2 * fj);
        let n = 9.0 + 5.0 * fj;
        let dir = select(-1.0, 1.0, j % 2 == 0);
        let ta = fract(th / TAU * n + dir * G.time * (0.03 + 0.02 * fj) + fj * 0.31) - 0.5;
        let dep = rj * (0.55 - 0.3 * open) ;
        let rc = rj - dep * (1.0 - 2.0 * abs(ta));
        let slope = 2.0 * dep * n / (TAU * max(rho, 1e-3));
        let d = abs(rho - rc) / sqrt(1.0 + slope * slope);
        let inside = step(rho, rj + px);
        let tip = 1.0 - 2.0 * abs(ta);
        c += mix(cinf, cneu, tip * tip) * ar_ln(d, px) * inside * (0.9 - 0.12 * fj);
    }
    // throat: bitstream spiralling inward and swallowed
    let throat = S * (1.25 - 0.2 * 3.0) * (0.6 + 0.4 * open);
    if (rho < throat) {
        let lr = log(max(rho, 1e-4) / S);
        let u = lr * 5.0 + G.time * (1.5 + 5.0 * G.bass + 4.0 * G.drop);
        let v = th / TAU * 20.0 + lr * 3.0;
        let cell = floor(vec2f(u, v));
        let lp = fract(vec2f(v, u));
        let one = hash21(cell) > 0.5;
        let d = ar_bit(lp, one);
        let k = smoothstep(throat, throat * 0.6, rho) * smoothstep(0.0, throat * 0.35, rho);
        c += mix(cinf, cneu, 0.3 * hash21(cell + 3.0)) * clamp(1.0 - d / 0.07, 0.0, 1.0) * k * 0.9;
        c += cinf * 0.6 * exp(-rho / (throat * 0.25)) * (0.5 + G.kick);
    }
    return c;
}

fn look(fc0: vec2f) -> vec4f {
    let res = G.res;
    // drop glitch: horizontal band tearing
    let bid = floor(fc0.y / res.y * 48.0);
    let gt = floor(G.time * 24.0);
    let gl = G.drop * step(0.6, hash21(vec2f(bid, gt)));
    let fc = fc0 + vec2f((hash21(vec2f(bid, gt + 3.0)) - 0.5) * gl * 0.12 * res.x, 0.0);
    let uv0 = fc0 / res;

    // ---- song sections: weights (cross-fade) ----
    let wq = sec(SEC_QUIET); let wv = sec(SEC_VERSE); let wb = sec(SEC_BUILD);
    let wc = sec(SEC_CHORUS); let wk = sec(SEC_BREAKDOWN); let wd = sec(SEC_DROP);
    let bprog = select(1.0, sec_progress(12.0), G.section == SEC_BUILD) * wb;   // build-up tension 0..1
    let cityK = wq * 0.12 + wv + wb * (0.5 + 0.5 * bprog) + wc * 1.5 + wk * 0.25 + wd * 1.3;
    let virK = wv + wb * bprog * 1.2 + wc * 0.8 + wd * 1.5;
    let speedK = wq * 0.3 + wv + wb * (1.0 + 2.0 * bprog) + wc * 1.2 + wk * 0.5 + wd * 1.6;
    let Rk = wq * 1.1 + wv + wb * (1.0 - 0.38 * bprog) + wc * 1.3 + wk * 1.5 + wd * 0.85;
    let wormK = wq * 0.5 + wv + wb * (1.0 + 0.9 * bprog) + wc * 1.1 + wk * 0.6 + wd * 1.4;
    let expo = wq * 0.55 + wv + wb * (0.9 + 0.2 * bprog) + wc * 1.15 + wk * 0.8 + wd * 1.2;

    var p = centered(fc);
    // build-up: the screen shakes harder as the charge builds
    p += vec2f(sin(G.time * 47.0), cos(G.time * 53.0)) * (0.003 + 0.004 * G.snare) * bprog * bprog;
    p *= 1.0 + 0.03 * dot(p, p);            // CRT barrel
    let pxs = 2.0 / res.y;

    var cclean = mix(G.pal0.rgb, G.pal2.rgb, 0.35 * G.centroid);
    var cinf = G.pal1.rgb;
    var cneu = G.pal2.rgb;
    cclean = mix(cclean, cneu, 0.3 * wc + 0.25 * wk);                 // chorus/breakdown: lighter, airier
    cinf = mix(cinf, cneu, 0.2 * wk);
    let cc0 = cclean; let ci0 = cinf;
    cclean = mix(cc0, ci0, wd);                                       // drop: colour flip, bus turns magenta
    cinf = mix(ci0, cc0, wd);
    var infect = 0.06 + 0.4 * G.energy + 0.4 * G.drop + 0.5 * bprog + 0.4 * wd - 0.2 * (wq + wk + wc);
    infect = clamp(infect, 0.0, 0.9);

    // camera: mouse steers the look direction
    let mo = G.mouse - vec2f(0.5);
    ar_ang = vec3f(sin(G.time * 0.11) * 0.08 - mo.x * 0.3 + 0.04 * sin(G.time * 13.0) * G.drop,
                   mo.y * 0.8 + sin(G.time * 0.17) * 0.05,
                   mo.x * 1.1 + sin(G.time * 0.23) * 0.1);
    let ro = vec3f(0.0, 0.0, G.travel * 5.0);
    let rd = ar_to_world(normalize(vec3f(p, AR_F)));
    let vpc = ar_to_cam(vec3f(0.0, 0.0, 1.0));
    let vp = vpc.xy / max(vpc.z, 0.05) * AR_F;
    let pxw = pxs / AR_F;

    // ---------------- The worm (screen space at the vanishing point) ----------------
    let lunge = G.drop * G.drop;
    let S = 0.17 * wormK * (1.0 + 0.12 * G.bass + 0.05 * G.kick) * (1.0 + 3.5 * lunge);
    var dev = vec3f(0.0);
    let dq = p - vp;
    if (G.drop > 0.03) {
        let o = vec2f(0.035 * G.drop, 0.0);
        dev = vec3f(ar_dev(dq - o, S, pxs * 1.3, cinf, cneu).r, ar_dev(dq, S, pxs * 1.3, cinf, cneu).g, ar_dev(dq + o, S, pxs * 1.3, cinf, cneu).b);
    } else {
        dev = ar_dev(dq, S, pxs * 1.3, cinf, cneu);
    }
    dev *= wq * 0.6 + wv + wb + wc * 1.1 + wk * 0.4 + wd * 0.8;
    let occl = smoothstep(S * 1.0, S * 1.5, length(dq));   // the head hides what is behind it

    // ---------------- the city below ----------------
    var col = ar_city(ro, rd, pxw, infect, cclean, cinf) * 0.6 * (0.5 + 0.6 * G.energy + 0.2) * occl * cityK;

    // ---------------- the Data Bus tunnel ----------------
    let m0 = max(max(abs(rd.x), abs(rd.y)), (abs(rd.x) + abs(rd.y)) * 0.7071);
    let ang = atan2(rd.y, rd.x);
    let bx = abs(ang) / PI;
    let t0 = AR_R / m0;
    let age = clamp(t0 * rd.z / 55.0, 0.0, 1.0);
    let def = hist(0.03 + 0.85 * bx, age);
    let R = AR_R * Rk * (1.0 + 0.5 * def * def + 0.07 * G.bass + 0.05 * G.kick * (1.0 - age));
    let t = R / m0;
    let hit = rd * t;
    let zw = ro.z + hit.z;
    let zrel = max(hit.z, 0.0);
    let fz = t * pxw * max(1.0, zrel / R) + 1e-4;     // z footprint of one pixel on the wall
    let fa = t * pxw;                                  // lateral footprint (world)
    let fog = exp(-zrel * 0.035);
    let la = ang / TAU * 16.0;
    let li = floor(la + 0.5);
    let da = abs(la - li) * TAU / 16.0 * R;
    let cz = floor(zw / 3.0);
    let ccell = vec2f(floor(la), cz);
    let infd = hash21(ccell) < infect;
    var wcol = select(cclean, cinf, infd);
    var tun = 0.0;
    var wl = vec3f(0.0);
    // minor rings, major rings (major ones flash on the snare)
    let dz1 = abs(fract(zw + 0.5) - 0.5);
    let dz6 = abs(fract(zw / 6.0 + 0.5) - 0.5) * 6.0;
    tun += ar_ln(dz1, fz * 1.2) * 0.3 * clamp(1.0 - fz * 4.0, 0.0, 1.0);
    let major = ar_ln(dz6, fz * 2.2) * (0.9 + 1.2 * G.snare + 0.6 * wc * G.beat + 1.5 * bprog * G.snare);
    // rails: odd lanes are the octagon corners
    let corner = abs(li % 2.0) > 0.5;
    tun += ar_ln(da, fa * 1.3) * select(0.35, 0.9, corner);
    wl += wcol * tun + mix(wcol, cneu, 0.5 + 0.5 * G.snare) * major;
    // deleted cells flash white on the kick
    let del = G.kick * step(hash21(ccell + fract(G.beat_count * 0.137) * 91.0), 0.12 + 0.3 * G.energy);
    wl += cneu * del * 0.12 * clamp(1.0 - fz * 2.0, 0.0, 1.0);
    // infected cells: magenta hatch fill
    if (infd) {
        let hatch = abs(fract((zw * 2.0 + la * 2.0)) - 0.5);
        wl += cinf * smoothstep(0.1, 0.0, hatch) * 0.12 * clamp(1.0 - fz * 3.0, 0.0, 1.0) * (0.6 + 0.4 * sin(G.time * 6.0 + cz));
    }
    // data packets streaking toward us along the rails (count/speed from flux)
    let lane = (li % 16.0 + 16.0) % 16.0;
    let act = step(hash11(lane * 3.7 + floor(G.time * 0.8)), clamp(0.3 + 0.65 * G.flux + 0.4 * bprog + 0.3 * wd - 0.25 * (wq + wk), 0.0, 1.0));
    let spd = (10.0 + 12.0 * hash11(lane) + 25.0 * G.flux + 30.0 * G.drop) * speedK;
    let g = fract((zw + G.time * spd) / 16.0 + hash11(lane * 1.3));
    let head = smoothstep(0.0, 0.01, g) * smoothstep(0.12, 0.0, g);
    let pkt = act * head * (ar_ln(da, fa * 2.5) * 2.0);
    let pcol = select(cclean, cinf, hash11(lane + 0.5) < infect * 0.6);
    wl += mix(pcol, cneu, smoothstep(0.03, 0.0, g)) * pkt;
    // 0/1 bits streaming in the wall cells, flickering with the hats
    let lpb = vec2f(fract(la + 0.5), fract(zw));
    let bcell = vec2f(floor(la + 0.5), floor(zw));
    let one = hash21(bcell + floor(G.time * (1.0 + 10.0 * G.hat))) > 0.5;
    let fpb = max(fa / (R * TAU / 16.0), fz);
    let bvis = clamp(1.0 - fpb * 9.0, 0.0, 1.0) * smoothstep(3.0, 9.0, zrel) * step(hash21(bcell + 5.0), 0.3 + 0.5 * G.high + 0.3 * wk) * (1.0 + 1.5 * wk * (0.5 + G.mid));
    wl += wcol * clamp(1.0 - ar_bit(lpb, one) / (0.05 + fpb * 1.5), 0.0, 1.0) * bvis * 0.35;
    // click: scan ring fired down the tunnel
    let sz = G.click_age * 45.0;
    wl += cneu * ar_ln(abs(zrel - sz), fz * 3.0) * 2.5 * exp(-G.click_age * 1.2) * step(G.click_age, 3.0);
    col += wl * fog * occl;
    // breakdown only: soft melody lights drifting in the wide tunnel
    if (wk > 0.01) {
        for (var i = 0; i < 7; i++) {
            let fi = f32(i);
            let hh = hash11(fi * 5.3 + 1.0);
            let oc = vec2f((hh - 0.5) * 1.5 * AR_F + 0.18 * sin(G.time * 0.3 + fi * 2.0), fract(hash11(fi * 2.9) + G.time * 0.03 * (0.5 + hh)) * 2.0 - 1.0);
            let kv = key(30 + i32(fi) * 6) + spec(0.15 + 0.1 * fi);
            col += mix(cclean, cneu, 0.5) * glow(length(p - oc), 0.015 + 0.03 * kv) * (0.15 + 1.2 * kv) * wk * 0.5;
        }
        col += cclean * 0.06 * wk * (0.4 + G.mid) * exp(-length(dq) * 0.8);
    }
    // drop only: breach beams fan out from the worm's mouth
    if (wd > 0.01) {
        let thb = atan2(dq.y, dq.x);
        let bm = pow(abs(sin(thb * 7.0 + G.time * 0.5)), 24.0) + pow(abs(sin(thb * 13.0 - G.time * 0.8)), 40.0) * 0.6;
        col += mix(cneu, cinf, 0.5) * bm * exp(-length(dq) * 0.9) * wd * (0.2 + 0.6 * G.kick + 0.3 * G.bass);
    }
    // dim glow from the far end
    col += cinf * 0.05 * exp(-length(dq) * 2.0) * (0.5 + G.energy);

    // ---------------- wireframe viruses: deleted in bursts on the kick ----------------
    let nv = i32(ceil(f32(8 + i32(G.quality) * 3) * clamp(virK, 0.0, 1.0)));
    var vir = vec3f(0.0);
    for (var i = 0; i < nv; i++) {
        let fi = f32(i);
        let h1 = hash11(fi * 7.13 + 1.0);
        let h2 = hash11(fi * 3.71 + 2.0);
        let zr = 1.8 + 13.0 * fract(h1 - (ro.z * 0.6 + G.time * 2.0) / 13.0);
        let a = h2 * TAU + G.time * 0.25 * (h1 - 0.5);
        let rad = 0.7 + 0.45 * hash11(fi + 9.0);
        let wp = vec3f(cos(a) * rad, sin(a) * rad, zr);
        let vc = ar_to_cam(wp);
        if (vc.z < 0.4) { continue; }
        let sc = vc.xy / vc.z * AR_F;
        let s = (0.22 + 0.1 * hash11(fi + 4.0)) * (1.0 + 0.3 * G.snare);
        let ss = s / vc.z * AR_F;
        let dead = hash11(fi * 13.7 + G.beat_count * 0.731) < 0.45 && G.energy > 0.08;
        let ex = select(0.0, G.beat_phase, dead);
        if (length(p - sc) > ss * (2.0 + 6.0 * ex) + 0.03) { continue; }
        let lq = (p - sc) / ss;
        let lpx = pxs / ss * 1.2;
        let sa = G.time * (0.6 + h1) + fi;
        var dmin = 1e5;
        let isCube = i % 2 == 1;
        for (var e = 0; e < 12; e++) {
            var v0 = vec3f(0.0);
            var v1 = vec3f(0.0);
            if (isCube) {
                let k = e / 3;           // corner with bit b unset
                let b = e % 3;
                var kk = u32(k);
                // insert a zero at bit b to enumerate the 12 edges
                let lo = kk & ((1u << u32(b)) - 1u);
                let hi = (kk >> u32(b)) << u32(b + 1);
                let c0 = lo | hi;
                let c1 = c0 | (1u << u32(b));
                v0 = vec3f(select(-1.0, 1.0, (c0 & 1u) != 0u), select(-1.0, 1.0, (c0 & 2u) != 0u), select(-1.0, 1.0, (c0 & 4u) != 0u)) * 0.6;
                v1 = vec3f(select(-1.0, 1.0, (c1 & 1u) != 0u), select(-1.0, 1.0, (c1 & 2u) != 0u), select(-1.0, 1.0, (c1 & 4u) != 0u)) * 0.6;
            } else {
                let ax = e / 4;
                let sg = e % 4;
                let sa1 = select(-1.0, 1.0, (sg & 1) != 0);
                let sb1 = select(-1.0, 1.0, (sg & 2) != 0);
                let ea = vec3f(f32(ax == 0), f32(ax == 1), f32(ax == 2));
                v0 = ea * sa1;
                v1 = ea.zxy * sb1;
            }
            v0 = ar_ry(ar_rx(v0, sa * 0.7), sa);
            v1 = ar_ry(ar_rx(v1, sa * 0.7), sa);
            var a2 = v0.xy; var b2 = v1.xy;
            if (dead) {
                let mid = (a2 + b2) * 0.5;
                let off = normalize(mid + vec2f(1e-3)) * ex * (1.5 + 2.0 * hash11(fi + f32(e)));
                a2 = mid + (a2 - mid) * (1.0 - ex) + off;
                b2 = mid + (b2 - mid) * (1.0 - ex) + off;
            }
            dmin = min(dmin, sd_segment(lq, a2, b2));
        }
        let fadez = exp(-vc.z * 0.03);
        if (dead) {
            let k = (1.0 - ex) * (1.0 - ex);
            vir += mix(cneu, cclean, ex) * ar_ln(dmin, lpx) * k * (1.0 + 2.0 * G.kick) * fadez;
            vir += cclean * ar_ln(abs(length(lq) - (0.5 + 5.0 * ex)), lpx * 1.5) * k * 0.8 * fadez;
        } else {
            vir += mix(cinf, cneu, 0.25 * G.snare) * ar_ln(dmin, lpx) * 1.6 * fadez;
            vir += cinf * 0.1 * exp(-length(lq) * 2.5) * fadez;
        }
    }
    col += vir * min(virK, 1.5);
    col += dev;

    // ---------------- HUD (vector segments) ----------------
    let hp = fc0 / res.y;                                  // y down, height 1
    let hw = res.x / res.y;
    let hpx = 1.0 / res.y;
    var hud = vec3f(0.0);
    // frame corner brackets
    let fq = abs(hp - vec2f(hw * 0.5, 0.5)) - vec2f(hw * 0.5 - 0.035, 0.465);
    let corner_d = max(fq.x, fq.y);
    let near_corner = step(hw * 0.5 - 0.11, abs(hp.x - hw * 0.5)) * step(0.39, abs(hp.y - 0.5));
    hud += cclean * ar_ln(abs(corner_d), hpx * 1.5) * near_corner * 0.8;
    // signature counter (deleted signatures), 7-segment
    let sig = floor(G.beat_count * 3.0 + G.time * 0.5) + 104729.0;
    let dsig = ar_num((hp - vec2f(0.075, 0.085)) / 0.014, sig, 7) * 0.014;
    hud += cclean * ar_ln(dsig, hpx * 1.6) * 1.1;
    // shield icon
    let sh = hp - vec2f(0.055, 0.085);
    let shd = max(abs(sh.x) - 0.012, sh.y - 0.01 + abs(sh.x) * 0.0);
    let shd2 = max(shd, length(sh - vec2f(0.0, -0.012)) - 0.026);
    hud += cclean * ar_ln(abs(shd2), hpx * 1.5) * (0.7 + G.kick);
    // threat meter: 24 segments, energy fills, magenta past 60%
    let tm = hp - vec2f(0.05, 0.125);
    if (tm.y > -0.006 && tm.y < 0.006 && tm.x > 0.0 && tm.x < 0.24) {
        let si = floor(tm.x / 0.01);
        let lit = step(si / 24.0, G.energy * 0.85 + G.drop * 0.3 + 0.02);
        let inner = step(fract(tm.x / 0.01), 0.75);
        hud += mix(cclean, cinf, step(14.0, si)) * inner * (0.08 + lit * 0.9);
    }
    // BPM readout, top right
    let dbpm = ar_num((hp - vec2f(hw - 0.155, 0.085)) / 0.014, round(G.bpm), 3) * 0.014;
    hud += cneu * ar_ln(dbpm, hpx * 1.6) * 0.8;
    // beat dots
    for (var b = 0; b < 4; b++) {
        let on = step(abs(f32(b) - (G.beat_count % 4.0)), 0.5);
        hud += mix(cclean, cneu, on) * ar_ln(length(hp - vec2f(hw - 0.155 + f32(b) * 0.025, 0.125)) - 0.005, hpx * 1.5) * (0.3 + 0.9 * on);
    }
    // waveform scope strip, bottom centre
    let sq = hp - vec2f(hw * 0.5, 0.905);
    if (abs(sq.x) < 0.3 && abs(sq.y) < 0.04) {
        let wv = wave(sq.x / 0.6 + 0.5) * 0.035;
        hud += cclean * ar_ln(abs(sq.y - wv), hpx * 1.5) * 1.1;
        hud += cclean * 0.12 * ar_ln(abs(abs(sq.y) - 0.04), hpx);
    }
    // spectrum ticks, bottom left
    let spq = hp - vec2f(0.05, 0.94);
    if (spq.x > 0.0 && spq.x < 0.22 && spq.y < 0.0 && spq.y > -0.07) {
        let bi = floor(spq.x / 0.0075);
        let v = spec(bi / 29.0);
        let lit = step(-spq.y, v * 0.07);
        let segy = step(fract(-spq.y / 0.006), 0.6) * step(fract(spq.x / 0.0075), 0.7);
        hud += mix(cclean, cinf, step(0.75, -spq.y / 0.07)) * segy * (0.06 + lit);
    }
    // reticle at the centre: brackets snap open on the kick, ring turns with the beat
    let rq = p;
    let rr = length(rq);
    let spread = (0.07 + 0.035 * G.kick + 0.05 * G.drop) * (1.0 - 0.45 * bprog) + 0.04 * wc * G.beat;
    let rcol = mix(cclean, cinf, G.drop);
    let rth = atan2(rq.y, rq.x) + G.beat_phase * PI * 0.5;
    let rseg = step(0.3, abs(fract(rth / TAU * 4.0) - 0.5));
    hud += rcol * ar_ln(abs(rr - spread), pxs * 1.4) * rseg * 0.9;
    hud += rcol * ar_ln(length(rq), pxs * 2.0) * 0.6;
    // build-up: a charge ring fills clockwise over the 12 s
    let cfrac = fract(0.25 - atan2(rq.y, rq.x) / TAU);
    hud += mix(cneu, cinf, bprog) * ar_ln(abs(rr - 0.2), pxs * 1.6) * step(cfrac, bprog) * wb * (1.0 + 2.0 * G.snare);
    // click: screen-space scan ring
    let cq = (uv0 - G.click_pos) * vec2f(hw, 1.0);
    let cr = G.click_age * 1.4;
    hud += cneu * ar_ln(abs(length(cq) - cr), hpx * 2.0) * exp(-G.click_age * 2.0) * 2.0;
    hud += cclean * ar_ln(abs(length(cq) - cr * 0.7), hpx * 1.5) * exp(-G.click_age * 2.5);
    col += hud * (0.45 + 0.55 * (1.0 - wq));

    // drop: RGB split of the last frame
    if (G.drop > 0.02) {
        let o = vec2f(0.012 * G.drop, 0.0);
        col.r += prev(uv0 + o).r * 0.35 * G.drop;
        col.b += prev(uv0 - o).b * 0.35 * G.drop;
    }

    // CRT: scanlines, grain, vignette, soft corners
    let sl = 0.78 + 0.22 * sin(fc0.y / max(res.y / 405.0, 1.0) * PI);
    col *= sl * (1.0 + 0.1 * G.hat) * expo;
    col += (hash21(fc0 + fract(G.time) * 97.0) - 0.5) * 0.025;
    let vq = uv0 - 0.5;
    col *= clamp(1.0 - dot(vq, vq) * 1.4, 0.0, 1.0);
    col *= smoothstep(0.0, 0.02, min(min(uv0.x, 1.0 - uv0.x), min(uv0.y, 1.0 - uv0.y)) + 0.005);
    return vec4f(col, 1.0);
}
