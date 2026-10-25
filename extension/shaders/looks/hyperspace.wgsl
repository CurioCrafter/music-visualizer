// name: Hyperspace
// palette: #3cc8ff #b04dff #ff8a3c
// Space flight: nebula + ringed planet, deep starfield, warp charge HUD, warp tunnel, giant planet at dawn,
// asteroid canyon. pal0 = cyan (HUD, atmosphere), pal1 = violet (nebula), pal2 = orange (planets, sun).

fn hs_ln(d: f32, w: f32) -> f32 { return clamp(1.0 - d / w, 0.0, 1.0) + 0.3 * exp(-d / (w * 5.0)); }

// stars flowing out of the vanishing point in polar cells; stretch 0 = dots, 1 = long warp streaks.
// returns (brightness, per-star hash)
fn hs_stars(p: vec2f, T: f32, na: f32, seed: f32, dens: f32, stretch: f32, px: f32) -> vec2f {
    let r = max(length(p), 1e-4);
    let a = atan2(p.y, p.x);
    let u = (a / TAU + 0.5) * na;
    let cu = floor(u);
    let fu = fract(u);
    let v = log(r) * 5.0 - T + hash11(cu * 1.37 + seed) * 7.0;
    let cv = floor(v);
    let fv = fract(v) - 0.5;
    let h = hash21(vec2f(cu, cv) + vec2f(seed * 17.0, seed));
    if (h > dens) { return vec2f(0.0); }
    let h2 = hash21(vec2f(cv * 1.7, cu * 0.3) + seed);
    let cu0 = fu - 0.25 - 0.5 * h2;
    let pd = cu0 / na * TAU * r;
    let L = 0.02 + stretch * 0.3;
    let ad = max(abs(fv) - L, 0.0) / 5.0 * r;
    let w = px * (0.6 + 1.1 * r) * (0.6 + h2);
    let d = length(vec2f(pd, ad));
    let head = mix(1.0, smoothstep(-L, L, fv) * 0.85 + 0.15, clamp(stretch * 2.0, 0.0, 1.0));
    let b = (exp(-d * d / (w * w)) + 0.05 * exp(-d / (w * 2.5))) * head * smoothstep(0.03, 0.35, r) * (0.5 + h2)
        * smoothstep(0.25, 0.12, abs(cu0)) * smoothstep(0.5, 0.38, abs(fv));   // fade out before the cell border
    return vec2f(b, h2);
}

// shaded sphere with banded surface; rgb + coverage
fn hs_planet(q: vec2f, R: f32, ldir: vec3f, ca: vec3f, cb: vec3f, spin: f32, px: f32) -> vec4f {
    let d = length(q);
    let cov = clamp((R - d) / px + 0.5, 0.0, 1.0);
    if (cov <= 0.0) { return vec4f(0.0); }
    let s = q / R;
    let n = vec3f(s, sqrt(max(1.0 - dot(s, s), 0.0)));
    let warp = fbm2(vec2f(n.x * 3.0 + spin, n.y * 5.0), 3);
    let bands = fbm2(vec2f(n.y * 9.0 + warp * 2.2, spin * 0.3 + n.x * 0.6), 4);
    let base = mix(ca, cb, smoothstep(0.3, 0.72, bands)) * (0.7 + 0.5 * warp);
    let dif = max(dot(n, ldir), 0.0);
    let rim = pow(1.0 - n.z, 3.0);
    let col = base * (0.02 + 1.15 * dif) + ca * rim * 0.3 * (0.2 + dif);
    return vec4f(col, cov);
}

fn look(fc: vec2f) -> vec4f {
    let res = G.res;
    let px = 2.0 / res.y;
    let uv = fc / res;
    let asp = G.aspect;
    let wq = sec(SEC_QUIET);
    let wv = sec(SEC_VERSE);
    let wb = sec(SEC_BUILD);
    let wc = sec(SEC_CHORUS);
    let wk = sec(SEC_BREAKDOWN);
    let wd = sec(SEC_DROP);
    let bp = select(1.0, sec_progress(12.0), G.section == SEC_BUILD);
    let tens = wb * bp;
    let lt = G.look_time;
    let c0 = G.pal0.rgb;
    let c1 = G.pal1.rgb;
    let c2 = G.pal2.rgb;

    // camera: mouse steers the vanishing point; the charge shakes it, drop kicks jolt it
    let shake = (vec2f(noise2(vec2f(lt * 23.0, 1.0)), noise2(vec2f(lt * 23.0, 7.0))) - 0.5) * (tens * tens * 0.025 + wd * G.kick * 0.035);
    let vp = vec2f((G.mouse.x - 0.5) * 0.9 * asp, (0.5 - G.mouse.y) * 0.7) + vec2f(sin(lt * 0.13), cos(lt * 0.11)) * 0.04 * (1.0 - wd);
    let p0 = centered(fc) + shake;
    let p = p0 - vp;
    let r = length(p);
    let ang = atan2(p.y, p.x);
    let T = G.travel * 1.6 + lt * 0.15;
    let stretch = wb * (0.08 + 0.5 * bp * bp) + wd * (0.85 + 0.15 * G.bass) + wc * 0.1;

    // ---------------- deep space + far stars ----------------
    var col = vec3f(0.004, 0.005, 0.014) + c1 * 0.025 * (1.0 - min(r * 0.4, 1.0));
    let sp = (p0 - vp * 0.1 + vec2f(lt * 0.004, 0.0)) * 70.0;
    let sc = floor(sp);
    let sh = hash21(sc);
    if (sh > 0.88) {
        let so = hash22(sc) * 0.7 + 0.15;
        let tw = 0.6 + 0.4 * sin(lt * (1.0 + 4.0 * sh) + sh * 50.0) + G.hat * step(0.97, sh) * 2.0;
        let sb = smoothstep(0.14, 0.0, length(fract(sp) - so)) * tw * (sh - 0.88) * 9.0;
        col += mix(vec3f(0.7, 0.8, 1.0), vec3f(1.0, 0.85, 0.7), hash11(sh * 91.0)) * sb * (1.0 - 0.8 * wd);
    }
    // milky band
    let mb = fbm2(rot(0.5) * p0 * vec2f(0.7, 2.5) + vec2f(lt * 0.003, 0.0), 4);
    col += mix(c1, c0, mb) * 0.06 * smoothstep(0.45, 0.8, mb) * exp(-abs((rot(0.5) * p0).y) * 2.0) * (1.0 - wd - wc * 0.5);

    // ---------------- nebula: a slow cloud, or in the chorus a bright canyon rushing past ----------------
    let cloudw = 0.6 * wq + 0.3 * wv + 0.2 * wb + 0.35 * wk;
    if (cloudw > 0.01) {
        let np = p0 * 1.1 + vec2f(lt * 0.01, lt * 0.004) - vp * 0.3;
        let n1 = fbm2(np, 5);
        let n2 = fbm2(np * 2.1 + vec2f(n1 * 2.0, 3.0), 4);
        let neb = smoothstep(0.38, 0.85, n1) * (0.4 + 0.9 * n2);
        let ncol = mix(c1, c0, smoothstep(0.3, 0.7, n2)) + c2 * 0.3 * smoothstep(0.6, 0.9, n2);
        col += ncol * neb * cloudw * (0.6 + 0.6 * G.mid);
        col *= 1.0 - 0.5 * smoothstep(0.55, 0.75, n2) * smoothstep(0.4, 0.6, n1) * cloudw;   // dark dust lanes
    }
    if (wc > 0.01) {
        let dir = p / max(r, 1e-3);
        let tz = 0.6 / max(r, 0.05) + T * 0.45;
        let cn = fbm3(vec3f(dir * 2.2, tz), 4);
        let cn2 = noise3(vec3f(dir * 7.0, tz * 2.0));
        let walls = smoothstep(0.15, 0.95, abs(p.x) + 0.4 * abs(p.y) * 0.5) ;
        let canyon = smoothstep(0.3, 0.75, cn) * (0.5 + 0.8 * cn2) * (0.25 + walls);
        let ccol = palc(cn * 1.5 + tz * 0.02 + lt * 0.02) * (1.0 + 0.6 * G.centroid);
        col += ccol * canyon * wc * (0.9 + 0.5 * G.energy) * smoothstep(0.02, 0.4, r);
        // light at the canyon exit
        col += mix(vec3f(1.0, 0.9, 0.7), c2, 0.3) * (exp(-r * 3.5) * 0.9 + exp(-r * 12.0)) * wc * (0.8 + 0.4 * G.beat);
    }

    // ---------------- flowing stars / warp streaks ----------------
    let flow = clamp(1.0 - wk - wq * 0.8, 0.0, 1.0);
    if (flow > 0.01) {
        let nl = 2 + i32(G.quality);
        let dens = 0.12 + 0.22 * wd + 0.15 * tens + 0.08 * wc + 0.06 * G.flux;
        for (var i = 0; i < nl; i++) {
            let fi = f32(i);
            let s = hs_stars(p, T * (1.0 + fi * 0.35), 70.0 + fi * 37.0, fi * 3.1, dens, stretch, px);
            if (s.x > 0.0) {
                let sv = spec(s.y * 0.9);
                let rainbow = (hsv(fract(s.y + ang / TAU + lt * 0.05), 0.9, 1.0) * 0.6 + palc(s.y + lt * 0.1) * 0.5) * (0.6 + 1.6 * sv);
                let white = mix(vec3f(0.75, 0.85, 1.0), vec3f(1.0, 0.95, 0.9), s.y) * (0.8 + 1.2 * sv * (wv + wc));
                col += mix(white, rainbow, clamp(wd * 0.9 + wc * 0.3 + tens * 0.4, 0.0, 1.0)) * s.x * flow * (1.0 + G.drop + 0.5 * G.hat * (wv + wc));
            }
        }
    }

    // ---------------- quiet: ringed planet drifting by ----------------
    let plw = wq + 0.35 * wv;
    if (plw > 0.01) {
        let pc = vec2f(-0.62 + 0.08 * sin(lt * 0.03), 0.2 + 0.04 * cos(lt * 0.025)) - vp * 0.25;
        let q = p0 - pc;
        let R = 0.3;
        let Ld = normalize(vec3f(0.75, 0.35, 0.45));
        let rq = rot(0.32) * q;
        let e = vec2f(rq.x, rq.y / 0.24) / R;
        let rr = length(e);
        let rband = smoothstep(1.35, 1.42, rr) * smoothstep(2.35, 2.25, rr) * (0.6 + 0.4 * sin(rr * 46.0))
                  * (1.0 - 0.8 * smoothstep(1.77, 1.8, rr) * smoothstep(1.93, 1.9, rr));
        let rlit = 0.35 + 0.65 * smoothstep(-1.5, 1.5, e.x);
        let ringc = mix(c2, vec3f(0.95, 0.9, 0.8), 0.55) * rlit;
        let pl = hs_planet(q, R, Ld, c2, mix(c1, vec3f(0.9, 0.8, 0.7), 0.4), lt * 0.02, px);
        var pcol = col;
        pcol = mix(pcol, ringc, rband * step(0.0, rq.y) * 0.85);
        pcol = mix(pcol, pl.rgb, pl.a);
        // ring shadow band on the planet
        pcol *= 1.0 - 0.45 * pl.a * smoothstep(0.03, 0.0, abs(rq.y + 0.06 + rq.x * 0.05)) * step(rq.y, 0.0);
        pcol = mix(pcol, ringc, rband * step(rq.y, 0.0) * 0.85);
        let lq = length(q);
        pcol += c0 * 0.22 * exp(-max(lq - R, 0.0) / 0.025) * step(R, lq) * (0.4 + 0.6 * smoothstep(-0.3, 0.3, q.x));
        // small moon
        let mq = p0 - (pc + vec2f(0.75 + 0.05 * sin(lt * 0.05), -0.18));
        let mr = 0.045;
        let md = length(mq);
        let ms = mq / mr;
        let mn = vec3f(ms, sqrt(max(1.0 - dot(ms, ms), 0.0)));
        let mcol = vec3f(0.6, 0.58, 0.62) * (0.03 + max(dot(mn, Ld), 0.0)) * (0.8 + 0.3 * noise2(ms * 4.0));
        pcol = mix(pcol, mcol, fill(md - mr, px));
        col = mix(col, pcol, plw);
    }

    // ---------------- build-up: engines charging, HUD rings tighten ----------------
    let hudw = wb + 0.12 * wv;
    if (hudw > 0.01) {
        let sz = mix(1.0, 0.45, tens);
        let spin = lt * (0.05 + 0.6 * tens * tens);
        var hud = 0.0;
        for (var i = 0; i < 4; i++) {
            let fi = f32(i);
            let Ri = (0.26 + 0.2 * fi) * sz * (1.0 + 0.03 * G.snare);
            let dirn = select(-1.0, 1.0, (i & 1) == 0);
            let segs = 8.0 + fi * 8.0;
            let sg = fract(ang / TAU * segs + dirn * spin * (1.0 + fi * 0.3));
            let dash = select(step(0.3, sg), step(sg, 0.85), (i & 1) == 0);
            hud += hs_ln(abs(r - Ri), px * 1.3) * dash * (0.5 + 0.2 * fi);
            // ticks outside each ring
            let tk = abs(fract(ang / TAU * 72.0) - 0.5);
            hud += step(tk, 0.08) * step(Ri, r) * step(r, Ri + 0.012 + 0.01 * spec(fi * 0.25 + tk)) * 0.5;
        }
        // charge arc fills clockwise from the top
        let a01 = fract(0.25 - ang / TAU);
        let Ra = 0.26 * sz - 0.03;
        hud += hs_ln(abs(r - Ra), px * 2.5) * step(a01, bp) * 1.6;
        // reticle brackets
        let bq = abs(p) - vec2f(0.07) * sz;
        hud += hs_ln(min(sd_segment(bq, vec2f(0.0), vec2f(-0.025, 0.0)), sd_segment(bq, vec2f(0.0), vec2f(0.0, -0.025))), px * 1.2);
        let warnc = mix(c0, c2, smoothstep(0.7, 0.95, tens) * (1.0 - G.beat_phase));
        col += warnc * hud * hudw * (0.9 + 0.8 * tens + 2.0 * G.snare * wb);
        // charging core and engine glow from below
        let core = exp(-r * mix(10.0, 3.5, tens)) * tens * (0.7 + 0.3 * sin(lt * (8.0 + 40.0 * tens)));
        col += mix(c0, vec3f(1.0), tens) * core * 1.2;
        col += c2 * exp(-(p0.y + 1.0) * mix(9.0, 3.0, tens)) * tens * 0.5 * (0.8 + 0.4 * G.bass);
    }

    // ---------------- drop: the jump. warp tunnel, spectrum streaks, kick shockwaves ----------------
    if (wd > 0.01) {
        let tz = 0.45 / max(r, 0.03) + T * 1.2;
        let ta = fract(ang / TAU + 0.5) * 120.0;
        let cell = floor(ta);
        let fu = fract(ta) - 0.5;
        let hh = hash11(cell * 7.13);
        let seg = fract((tz * (0.6 + hh) + hh * 40.0) * 0.25);
        let streak = smoothstep(0.32, 0.0, abs(fu)) * smoothstep(0.0, 0.08, seg) * smoothstep(0.75, 0.25, seg);
        let hue = cell / 120.0 + lt * 0.08;
        let sv = spec(hh * 0.9);
        let tcol = hsv(hue, 0.8, 1.0) * 0.6 + palc(hue * 2.0) * 0.6;
        let depthfade = smoothstep(0.02, 0.5, r);
        col += tcol * streak * (0.2 + 1.8 * sv) * depthfade * wd * (0.6 + 0.6 * G.bass);
        col += mix(c0, c1, 0.5 + 0.5 * sin(tz * 0.5)) * 0.18 * depthfade * wd * (0.7 + 0.3 * noise2(vec2f(ta * 0.2, tz * 0.3)));
        col += vec3f(1.0, 0.95, 0.9) * (0.35 * exp(-r * 7.0) + exp(-r * 30.0)) * wd * (0.7 + 0.8 * G.kick);
        // shockwave rings on the kick (drop only)
        let rk = 0.06 + (1.0 - G.kick) * 1.9;
        let sw = exp(-abs(r - rk) / (0.012 + 0.05 * (1.0 - G.kick))) * G.kick;
        col += (c0 + vec3f(0.5)) * sw * wd * 1.6;
        col += hsv(fract(ang / TAU + lt * 0.2), 0.6, 1.0) * exp(-abs(r - rk * 0.9) / 0.01) * G.kick * wd * 0.7;
    }

    // ---------------- breakdown: out of warp, a giant planet and a rising sun ----------------
    if (wk > 0.01) {
        let gc = vec2f(0.15, -2.45) - vp * 0.15;
        let GR = 2.05;
        let q = p0 - gc;
        let d = length(q) - GR;
        let sunp = vec2f(-0.55, -0.36) - vp * 0.1;
        let sd = length(p0 - sunp);
        let mel = G.mid;
        var bcol = col;
        bcol += mix(c2, vec3f(1.0, 0.96, 0.88), exp(-sd * 14.0)) * (exp(-sd * 9.0) * 1.4 + 0.25 * exp(-sd * 2.0)) * (0.6 + 0.8 * mel);
        bcol += mix(c2, vec3f(1.0), 0.4) * exp(-abs(p0.y - sunp.y) * 70.0) * exp(-abs(p0.x - sunp.x) * 1.2) * 0.5 * (0.5 + mel);
        // atmosphere over the limb, brightest near the sun
        let near = exp(-sd * 1.3);
        let atm = exp(-max(d, 0.0) / (0.03 + 0.05 * near)) * step(0.0, d);
        bcol += mix(c0, c2, near) * atm * (0.35 + 1.5 * near) * (0.8 + 0.4 * mel);
        // aurora curtains over the limb, one per piano key region
        let kx = clamp((p0.x + asp) / (2.0 * asp), 0.0, 1.0);
        let kg = key(i32(kx * 52.0) + 24) + 0.2 * spec(0.3 + kx * 0.4);
        let rays = 0.5 + 0.5 * sin(p0.x * 90.0 + noise2(vec2f(p0.x * 5.0, lt * 0.3)) * 7.0);
        bcol += mix(c0, c1, smoothstep(0.0, 0.3, d)) * kg * rays * smoothstep(0.0, 0.03, d) * exp(-d / (0.03 + 0.22 * kg)) * 0.9;
        let pl = hs_planet(q, GR, normalize(vec3f(-0.45, 0.55, -0.3)), c1 * 0.7, c0 * 0.5, lt * 0.004, px);
        bcol = mix(bcol, pl.rgb + vec3f(0.004, 0.005, 0.012), pl.a);
        // thin lit crescent at the limb
        bcol += mix(c0, c2, near) * pl.a * exp(d / 0.012) * (0.3 + near) * 0.8;
        // floating dust motes catching the sunlight
        let mp = (p0 + vec2f(lt * 0.01, -lt * 0.015)) * 6.0;
        let mc = floor(mp);
        let mh = hash21(mc + 4.0);
        if (mh > 0.7) {
            let mo = hash22(mc) * 0.6 + 0.2;
            let md = length(fract(mp) - mo);
            bcol += mix(c2, c0, hash11(mh * 9.0)) * smoothstep(0.12, 0.06, md) * 0.12 * (0.5 + 0.5 * sin(lt + mh * 30.0));
        }
        col = mix(col, bcol, wk);
    }

    // ---------------- chorus: racing through an asteroid field ----------------
    if (wc > 0.01) {
        let nl = 4 + 2 * i32(G.quality);
        var bestd = -1.0;
        var acol = vec3f(0.0);
        var aa = 0.0;
        let sunL = normalize(vec3f(0.6, 0.6, 0.5));
        for (var i = 0; i < nl; i++) {
            let fi = f32(i);
            let dz = fract(fi / f32(nl) + G.travel * 0.12 + lt * 0.01);
            if (dz < bestd) { continue; }
            let scl = mix(9.0, 0.7, dz * dz);
            let q = p * scl + vec2f(fi * 13.7, fi * 5.3);
            let cell = floor(q);
            let h = hash21(cell + fi * 31.0);
            if (h > 0.3) { continue; }
            let o = hash22(cell + fi) * 0.36 - 0.18;
            let l = fract(q) - 0.5 - o;
            let rad = 0.10 + 0.13 * hash11(h * 77.0);   // max radius*wobble stays inside the cell
            let ll = length(l);
            let dv = l / max(ll, 1e-4);
            let wob = 1.0 + 0.32 * (noise2(dv * 1.8 + vec2f(h * 50.0, fi)) - 0.5) + 0.1 * (noise2(dv * 5.0 + h * 20.0) - 0.5);
            let ar = rad * wob;
            let cov = clamp((ar - ll) / (px * scl) + 0.5, 0.0, 1.0);
            if (cov <= 0.0) { continue; }
            let s = l / ar;
            let n = normalize(vec3f(s, sqrt(max(1.0 - dot(s, s), 0.04))));
            let tex = noise2(l / rad * 3.0 + h * 9.0) * 0.6 + noise2(l / rad * 9.0 + h * 3.0) * 0.4;
            let dif = max(dot(n, sunL), 0.0);
            let rim = pow(1.0 - n.z, 2.0);
            let fade = smoothstep(0.0, 0.25, dz) * smoothstep(1.0, 0.9, dz);
            let rc = palc(h * 3.0 + lt * 0.03);
            acol = vec3f(0.05, 0.045, 0.055) * (0.5 + tex) + vec3f(1.0, 0.86, 0.62) * dif * (0.4 + 0.7 * tex)
                 + rc * rim * (0.8 + 1.2 * G.mid + 1.5 * G.snare);
            aa = cov * fade;
            bestd = dz;
        }
        col = mix(col, acol, aa * wc);
    }

    // ---------------- cockpit: canopy struts + dashboard with spectrum LEDs ----------------
    let ds = min(sd_segment(p0, vec2f(-asp * 0.6, 1.1), vec2f(-asp * 1.05, -0.5)),
                 sd_segment(p0, vec2f(asp * 0.6, 1.1), vec2f(asp * 1.05, -0.5))) - 0.03;
    col = mix(col, vec3f(0.008, 0.01, 0.018), fill(ds, px * 1.5));
    col += c0 * hs_ln(abs(ds), px * 1.2) * (0.1 + 0.3 * G.beat * (1.0 - wq - wk));
    let xn = p0.x / asp;
    let dtop = -0.84 + 0.07 * (1.0 - xn * xn);
    if (p0.y < dtop) {
        let lit = 1.0 - 0.6 * wq;
        col = vec3f(0.012, 0.014, 0.022) + c0 * 0.04 * smoothstep(-1.0, dtop, p0.y);
        col += c0 * hs_ln(dtop - p0.y, px * 1.2) * 0.4 * lit;
        // spectrum screen
        let scr = sd_round_box(p0 - vec2f(0.0, -0.94), vec2f(0.55, 0.045), 0.01);
        if (scr < 0.0) {
            let bx = (p0.x + 0.55) / 1.1 * 48.0;
            let bi = floor(bx);
            let bh = spec(bi / 48.0);
            let by = (p0.y + 0.985) / 0.09;
            let led = step(0.2, fract(bx)) * step(0.25, fract(by * 8.0));
            let on = step(by, bh * 1.1 + 0.05);
            col = vec3f(0.01, 0.02, 0.03) + mix(c0, c2, by) * led * on * (0.6 + 0.6 * bh) * lit;
        }
        col += c0 * hs_ln(abs(scr), px) * 0.4 * lit;
        // warning lamps: blink on the hats, red in the drop
        let lq = vec2f(abs(p0.x) - 0.72, p0.y + 0.94);
        let lamp = fill(length(lq) - 0.018, px);
        let lampc = mix(mix(c0, vec3f(0.2, 1.0, 0.4), 0.5), vec3f(1.0, 0.15, 0.1), wd + tens);
        col += lampc * (lamp * 1.5 + exp(-length(lq) * 40.0) * 0.4) * (0.2 + G.hat + wd * (1.0 - G.beat_phase)) * lit;
    }

    // ---------------- click: a sensor ping ----------------
    let cp = vec2f((G.click_pos.x - 0.5) * 2.0 * asp, (0.5 - G.click_pos.y) * 2.0);
    let cd = length(p0 - cp);
    let ca = G.click_age;
    col += mix(c0, vec3f(1.0), 0.4) * (exp(-abs(cd - ca * 1.1) / 0.012) * exp(-ca * 2.5) * 1.2 + exp(-cd * 20.0) * exp(-ca * 6.0) * 2.0);

    // ---------------- warp trails from the last frame, flash, vignette ----------------
    let vpu = vec2f(vp.x / (2.0 * asp) + 0.5, 0.5 - vp.y * 0.5);
    let trail = 0.45 * wd + 0.25 * tens * tens + 0.1 * wc;
    if (trail > 0.01) {
        col = max(col, prev(vpu + (uv - vpu) * 0.985) * trail * 1.6);
    }
    col += mix(c0, vec3f(1.0), 0.6) * G.drop * 0.5 * exp(-r * 1.5);
    let vq = uv - 0.5;
    col *= clamp(1.0 - dot(vq, vq) * 1.1, 0.0, 1.0);
    col += (hash21(fc + fract(lt * 7.0) * 113.0) - 0.5) * 0.015;
    return vec4f(col, 1.0);
}
