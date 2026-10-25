// name: Volcano Forge
// palette: #ff3a12 #ff9a2a #ffe07a
// A giant's forge at the foot of a volcano: lava rivers and glowing cracks across a basalt plain,
// a smoking caldera, an anvil and a colossal hammer that strikes on the beat, sparks and embers.

// heat 0..1.3 -> crust black, deep red, orange, gold, white
fn vf_heat(x: f32) -> vec3f {
    let h = max(x, 0.0);
    if (h < 0.33) { return mix(vec3f(0.02, 0.004, 0.0), G.pal0.rgb * 0.7, h / 0.33); }
    if (h < 0.66) { return mix(G.pal0.rgb * 0.7, G.pal1.rgb * 1.4, (h - 0.33) / 0.33); }
    if (h < 1.0) { return mix(G.pal1.rgb * 1.4, G.pal2.rgb * 2.2, (h - 0.66) / 0.34); }
    return G.pal2.rgb * 2.2 + vec3f(1.0) * (h - 1.0) * 3.0;
}

// voronoi: x = distance to the nearest cell edge, y = cell id hash
fn vf_vor(p: vec2f) -> vec2f {
    let ip = floor(p);
    let fp = fract(p);
    var d1 = 9.0;
    var d2 = 9.0;
    var id = 0.0;
    for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
            let o = vec2f(f32(i), f32(j));
            let c = o + hash22(ip + o) * 0.85;
            let d = length(c - fp);
            if (d < d1) { d2 = d1; d1 = d; id = hash21(ip + o); } else if (d < d2) { d2 = d; }
        }
    }
    return vec2f(d2 - d1, id);
}

fn vf_volc(x: f32, xv: f32) -> f32 {
    let dx = abs(x - xv);
    var h = 0.6 * exp(-pow(dx / 0.62, 1.25)) + 0.025 * fbm2(vec2f(x * 6.0, 1.0), 3) - 0.02;
    h = min(h, 0.46) - 0.035 * smoothstep(0.11, 0.02, dx);
    return h;
}

fn vf_anvil(q: vec2f) -> f32 {
    var d = sd_round_box(q - vec2f(0.0, 0.12), vec2f(0.32, 0.05), 0.01);           // face
    let hx = clamp((-q.x - 0.3) / 0.33, 0.0, 1.0);                                    // horn
    let hc = vec2f(-0.3 - hx * 0.33, 0.13 - hx * hx * 0.04 + hx * 0.01);
    d = min(d, max(length(q - hc) - mix(0.055, 0.006, sqrt(hx)), -q.x - 0.64));
    d = min(d, sd_box(q - vec2f(0.33, 0.135), vec2f(0.04, 0.035)));                 // heel
    let wy = clamp((q.y + 0.08) / 0.16, 0.0, 1.0);
    d = min(d, sd_box(q - vec2f(0.0, 0.0), vec2f(0.11 + 0.08 * (1.0 - wy) * (1.0 - wy) + 0.06 * wy * wy, 0.08)));  // waist
    d = min(d, sd_round_box(q - vec2f(0.0, -0.11), vec2f(0.25, 0.04), 0.01));      // base
    return d;
}

// sec() with a quicker 0.6 s cross-fade
fn vf_sec(k: f32) -> f32 {
    return sec(k);
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let px = 2.0 / G.res.y;
    let t = G.time;
    let A = G.aspect;
    let ph = G.beat_phase;
    let bc = floor(G.beat_count);

    let wq = vf_sec(SEC_QUIET);
    let wv = vf_sec(SEC_VERSE);
    let wb = vf_sec(SEC_BUILD);
    let wc = vf_sec(SEC_CHORUS);
    let wk = vf_sec(SEC_BREAKDOWN);
    let wd = vf_sec(SEC_DROP);
    let bp = wb * sec_progress(12.0);
    let strikeW = wv + wc + wd;

    // camera: rumbles through the build-up, kicks shake it in the drop; cursor pans a little
    var p = centered(fc);
    let mp = vec2f((G.mouse.x - 0.5) * A * 2.0, (0.5 - G.mouse.y) * 2.0);
    p += vec2f(sin(t * 53.0), cos(t * 47.0)) * (bp * bp * 0.008 + wd * G.kick * 0.03 + G.drop * 0.015);
    let par = (G.mouse - 0.5) * G.mouse_on * vec2f(0.12, -0.06);

    // lava heat by section, plus the bass
    let heat = 0.22 * wq + 0.68 * wv + (0.65 + 0.35 * bp) * wb + 1.15 * wd + 1.1 * wc + 0.3 * wk + 0.15 * G.bass;
    let crater = 0.25 * wq + 0.6 * wv + (0.6 + 1.2 * bp + 0.8 * G.snare * bp) * wb + 2.2 * wd + 1.2 * wc + 0.12 * wk;
    let crackAmt = 0.08 * wq + 0.25 * wv + (0.25 + 0.65 * bp) * wb + 0.75 * wd + 0.6 * wc + 0.05 * wk;
    let gold = wc;

    let hy = -0.18;
    let xv = 0.42 + par.x * 0.5;
    let vp = p - vec2f(par.x * 0.5, par.y * 0.5);
    let vh = vf_volc(vp.x, xv);
    let ctop = vec2f(xv, hy + vf_volc(xv, xv) + 0.02);

    // ======================= SKY: ash clouds lit from below =======================
    let skyT = smoothstep(hy, 1.1, p.y);
    var col = mix(vec3f(0.09, 0.03, 0.02), vec3f(0.012, 0.01, 0.018), skyT);
    col = mix(col, mix(vec3f(0.07, 0.085, 0.13), vec3f(0.01, 0.014, 0.03), skyT), wk + wq * 0.4);
    col += G.pal1.rgb * gold * 0.35 * (1.0 - skyT);
    // stars through the ash when it is calm
    let sg = p * 60.0;
    let sci = floor(sg);
    let sdist = length(fract(sg) - 0.5 - (hash22(sci) - 0.5) * 0.7);
    col += vec3f(0.8, 0.85, 1.0) * smoothstep(0.08, 0.0, sdist) * step(0.9, hash21(sci + 3.0)) * (wq * 0.5 + wk) * skyT * (0.6 + 0.4 * sin(t * 3.0 + sci.x));

    let ap = vec2f(p.x * 0.8 + t * 0.015, p.y * 1.6 - t * 0.01);
    let an = fbm2(ap * 1.8 + vec2f(fbm2(ap * 1.3 + 4.0, 3), 0.0) * 1.5, 4 + i32(G.quality > 1.5));
    let ash = smoothstep(0.3, 0.75, an) * smoothstep(hy, hy + 0.3, p.y) * (0.5 + 0.5 * (1.0 - wk * 0.6) - wq * 0.2);
    let under = exp(-length((p - ctop) * vec2f(0.6, 1.0)) * 1.4);
    var acol = vec3f(0.05, 0.04, 0.045) * (0.6 + 0.8 * an);
    acol += vf_heat(0.45 + 0.2 * crater) * under * crater * 0.35 * (0.4 + an);
    acol += G.pal1.rgb * gold * 0.3 * (1.0 - skyT * 0.5);
    acol = mix(acol, vec3f(0.06, 0.07, 0.1) * (0.5 + an), wk * 0.6);
    col = mix(col, acol, ash);
    // drop: the whole sky flips to fire
    col += G.pal0.rgb * wd * (0.12 + 0.25 * G.kick) * (1.0 - skyT * 0.6);
    // chorus: golden rays fanning up from the caldera
    let ra = atan2(p.x - ctop.x, p.y - ctop.y);
    let rays = smoothstep(0.5, 0.85, noise2(vec2f(ra * 7.0, t * 0.12))) * step(ctop.y, p.y) * exp(-(p.y - ctop.y) * 0.8);
    col += G.pal2.rgb * rays * gold * 0.45;

    // ======================= SMOKE PLUME =======================
    let py = p.y - ctop.y;
    if (py > -0.02) {
        let windx = 0.35 + 0.15 * sin(t * 0.1);
        let pcx = ctop.x + pow(max(py, 0.0), 1.5) * windx;
        let pw = 0.06 + py * (0.4 + 0.3 * wd) + 0.03 * G.bass;
        let pq = vec2f((p.x - pcx) / pw, py);
        let sn = fbm2(vec2f(pq.x * 1.5, py * 2.5 - t * (0.35 + 0.6 * wd)) + vec2f(0.0, 3.0), 4);
        let plume = smoothstep(1.0, 0.2, abs(pq.x) + (0.5 - sn) * 1.2) * smoothstep(-0.02, 0.03, py)
                  * (0.35 * wq + 0.75 * wv + 0.8 * wb + 1.0 * wd + 0.8 * wc + 0.25 * wk);
        var pcol = vec3f(0.07, 0.06, 0.06) * (0.5 + sn);
        pcol += vf_heat(0.5 + 0.3 * crater) * exp(-py * 3.5) * crater * 0.6 * (0.5 + sn);
        pcol += G.pal2.rgb * gold * 0.25 * (0.5 + sn);
        pcol = mix(pcol, vec3f(0.12, 0.13, 0.16) * (0.4 + sn), wk * 0.5);
        col = mix(col, pcol, clamp(plume, 0.0, 1.0) * 0.9);
        // drop: volcanic lightning in the ash on snares and kicks
        let li = (G.snare + 0.6 * G.kick) * wd;
        if (li > 0.02 && abs(pq.x) < 1.2) {
            let seed = bc * 3.3 + floor(t * 6.0);
            let ly = py;
            let lx = pcx + (hash11(seed) - 0.5) * pw * 1.2 + (noise2(vec2f(ly * 12.0, seed)) - 0.5) * 0.15 + (noise2(vec2f(ly * 40.0, seed + 2.0)) - 0.5) * 0.04;
            let ld = abs(p.x - lx) + max(abs(ly - 0.35 - hash11(seed + 1.0) * 0.2) - 0.18, 0.0) * 2.0;
            col += mix(vec3f(0.7, 0.75, 1.0), vec3f(1.0), 0.5) * (exp(-ld / (px * 1.3)) + exp(-ld / 0.03) * 0.25) * li * 1.4;
        }
    }

    // ======================= VOLCANO =======================
    // far ridges
    let rid = hy + 0.09 + 0.06 * fbm2(vec2f(p.x * 1.5 + par.x * 0.3, 4.0), 3);
    col = mix(col, vec3f(0.025, 0.012, 0.012) + G.pal0.rgb * heat * 0.04 + G.pal1.rgb * gold * 0.08 + vec3f(0.02, 0.03, 0.05) * wk, fill(p.y - rid, px));
    let vtop = hy + vh;
    if (vp.y < vtop + px && vp.y > hy - 0.02) {
        let apex = hy + 0.6;
        let a = (vp.x - xv) / max(apex - vp.y, 0.05);
        let rock = fbm2(vp * vec2f(9.0, 14.0), 4);
        var vcol = vec3f(0.035, 0.022, 0.02) * (0.6 + 0.8 * rock);
        vcol *= 0.7 + 0.6 * smoothstep(0.3, -0.3, a);
        vcol = mix(vcol, vcol * vec3f(0.7, 0.8, 1.2) + vec3f(0.01, 0.015, 0.03), wk);
        // lava channels down the flanks, flowing
        let chan = sin(a * 8.0 + noise2(vec2f(a * 3.0, vp.y * 3.0)) * 3.0 + 1.0);
        let chW = smoothstep(0.86 - 0.08 * wc, 0.98, chan) * smoothstep(vtop + 0.01, vtop - 0.05, vp.y + 0.0) ;
        let flow = fbm2(vec2f(a * 25.0, vp.y * 22.0 + t * 1.3), 3);
        let chanH = chW * heat * (0.55 + 0.6 * flow) * (0.6 + 0.4 * spec(0.1 + abs(a) * 0.3));
        vcol = mix(vcol, vf_heat(chanH), smoothstep(0.05, 0.3, chanH));
        // build-up: cracks spreading over the cone, glowing
        let vr = 1.0 - abs(2.0 * noise2(vp * vec2f(14.0, 9.0)) - 1.0);
        let vthr = 1.0 - 0.05 - 0.13 * bp - 0.08 * wd - 0.05 * wc;
        let vcr = smoothstep(vthr, vthr + 0.02, vr) * (bp * 1.2 + wd + 0.5 * wc + 0.2 * wv) * (0.7 + 0.5 * G.snare);
        vcol += vf_heat(0.55 + 0.2 * bp) * vcr * 0.7;
        // summit glow
        vcol += vf_heat(0.6) * exp(-length((vp - ctop) * vec2f(1.0, 2.5)) * 7.0) * crater * 0.8;
        vcol += vec3f(0.25, 0.3, 0.45) * exp((vp.y - vtop) / 0.006) * (wk + wq * 0.4) * 0.5;
        col = mix(col, vcol, fill(vp.y - vtop, px));
    }
    // caldera glow and snare spurts
    col += vf_heat(0.7 + 0.2 * crater) * glow(length((p - ctop) * vec2f(0.6, 1.5)), 0.02) * crater * 0.45;
    col += vf_heat(1.0) * exp(-length((p - ctop - vec2f(0.0, 0.03)) * vec2f(1.2, 0.8)) * 25.0) * G.snare * (bp + wv * 0.4) * 1.5;

    // ---- drop only: the eruption, a lava fountain and flying bombs ----
    if (wd > 0.01) {
        let fh = 0.25 + 0.35 * G.kick + 0.2 * G.bass + 0.2 * G.drop;
        let fy = (p.y - ctop.y) / fh;
        if (fy > -0.05 && fy < 1.3) {
            let fw = 0.03 + 0.06 * fy + 0.01 * sin(fy * 20.0 - t * 30.0);
            let fx = abs(p.x - ctop.x - 0.04 * fy * fy) / fw;
            let fnz = fbm2(vec2f(fx * 2.0, fy * 4.0 - t * 4.0), 3);
            let fnt = smoothstep(1.0, 0.2, fx + (0.5 - fnz)) * smoothstep(1.2, 0.3, fy + (0.5 - fnz) * 0.5);
            col += vf_heat(0.7 + 0.5 * (1.0 - fy) + 0.3 * fnz) * fnt * wd * 1.3;
        }
        let nb = 10 + i32(G.quality) * 5;
        for (var i = 0; i < 20; i++) {
            if (i >= nb) { break; }
            let fi = f32(i);
            let life = fract(t * (0.35 + 0.15 * hash11(fi * 2.1)) + hash11(fi * 7.3));
            let gen = floor(t * (0.35 + 0.15 * hash11(fi * 2.1)) + hash11(fi * 7.3));
            let hs = hash22(vec2f(fi, gen));
            let v0 = vec2f((hs.x - 0.5) * 1.6, 0.9 + hs.y * 0.9);
            let pos = ctop + v0 * life + vec2f(0.0, -1.3) * life * life;
            let vel = v0 + vec2f(0.0, -2.6) * life;
            let bd = sd_segment(p, pos, pos - vel * 0.06) - 0.006;
            if (bd < 0.1) {
                col += vf_heat(1.0 - life * 0.6) * (fill(bd, px) + glow(bd, 0.008) * 0.3) * wd * (1.0 - life * 0.7);
            }
        }
    }

    // ======================= BASALT PLAIN: cracks + lava river =======================
    if (p.y < hy) {
        let z = 0.55 / (hy - p.y + 0.015);
        let g = vec2f((p.x - par.x * 0.2) * z, z);
        let rock = fbm2(g * vec2f(1.5, 0.8), 4);
        var gcol = vec3f(0.03, 0.02, 0.018) * (0.5 + 1.0 * rock);
        gcol = mix(gcol, gcol * vec3f(0.7, 0.8, 1.2) + vec3f(0.006, 0.01, 0.02), wk);
        // glowing cracks: more cells crack open as the pressure rises
        let vo = vf_vor(g * vec2f(1.6, 1.0) + vec2f(0.0, 3.0));
        let open = step(vo.y, crackAmt + 0.05 * G.kick);
        let cw = 0.06 + 0.04 * vo.y;
        let cr = smoothstep(cw, 0.0, vo.x) * open;
        let pulse = 0.6 + 0.5 * sin(t * 2.0 + vo.y * 40.0) * 0.3 + 0.4 * G.kick;
        gcol = mix(gcol, vf_heat((0.45 + 0.45 * heat) * pulse * (1.0 - vo.x / cw * 0.5)), cr * smoothstep(9.0, 2.0, z));
        // the river: meanders from the volcano's foot toward us
        let rcx = 0.55 * sin(z * 0.32 + 0.8) + 0.25 * sin(z * 0.11 + t * 0.02) + 0.35;
        let rw = 0.32 + 0.12 * wc + 0.06 * G.bass;
        let rdist = abs(g.x - rcx);
        let rcx2 = -1.1 + 0.4 * sin(z * 0.5 + 2.0);       // a second river opens in the chorus and the drop
        let rdist2 = abs(g.x - rcx2) + (1.0 - clamp(wc + wd, 0.0, 1.0)) * 9.0;
        let rmask = smoothstep(rw, rw * 0.75, rdist);
        let rmask2 = smoothstep(rw * 0.7, rw * 0.5, rdist2);
        let rm = max(rmask, rmask2);
        if (rm > 0.0) {
            let fq = vec2f(g.x * 2.0, g.y * 1.2 - t * (0.5 + 0.8 * heat));
            let crust = fbm2(fq * 1.5, 4);
            let vc = vf_vor(fq * 1.2);
            let hotLine = smoothstep(0.12, 0.0, vc.x);
            let sp = spec(clamp(0.05 + (z - 1.0) * 0.06, 0.0, 0.9));
            var lh = heat * (0.3 + 0.45 * hotLine + 0.3 * smoothstep(0.55, 0.3, crust)) * mix(1.0, 0.45, smoothstep(0.5, 0.65, crust) * (1.0 - hotLine)) + 0.2 * sp * heat;
            lh *= 1.0 - 0.35 * smoothstep(rw * 0.8, rw, min(rdist, rdist2 + 0.0));
            lh = mix(lh, 0.18 + 0.25 * hotLine + 0.15 * sp, wk * 0.85);         // breakdown: crusting over
            gcol = mix(gcol, vf_heat(lh), rm);
        }
        // banks lit by the river
        let bank = exp(-max(min(rdist - rw, rdist2 - rw * 0.7), 0.0) * 3.0);
        gcol += vf_heat(0.5) * bank * heat * 0.12 * (0.5 + rock);
        gcol += G.pal1.rgb * gold * 0.12 * (0.5 + rock);
        gcol = mix(gcol, vec3f(0.08, 0.03, 0.02), smoothstep(4.0, 30.0, z) * 0.6);   // haze toward the horizon
        col = gcol;
    }

    // ======================= ANVIL, ROCK, HAMMER =======================
    let a0 = vec2f(-0.85, -0.5);
    let asz = 0.85;
    let aq = (p - a0) / asz;
    let impact = a0 + vec2f(0.05, 0.215) * asz;
    // rock pedestal
    let rockTop = a0.y - 0.15 * asz + 0.03 * sin(p.x * 9.0) + 0.02 * fbm2(vec2f(p.x * 8.0, 2.0), 3);
    let pedw = 0.42 + (rockTop - p.y) * 0.5;
    if (p.y < rockTop && abs(p.x - a0.x) < pedw + 0.05) {
        let ped = max(p.y - rockTop, abs(p.x - a0.x) - pedw + 0.04 * fbm2(p * 6.0, 3));
        var rc = vec3f(0.03, 0.022, 0.02) * (0.5 + fbm2(p * vec2f(12.0, 20.0), 4));
        rc += vf_heat(0.5) * heat * 0.12 * exp(-(rockTop - p.y) * 4.0);
        rc += G.pal1.rgb * gold * 0.1;
        col = mix(col, rc, fill(ped, px));
    }
    let ad = vf_anvil(aq);
    if (ad < 0.2) {
        let af = fill(ad, px / asz);
        let topLight = smoothstep(0.05, 0.17, aq.y);
        var ac = vec3f(0.05, 0.048, 0.055) * (0.7 + 0.5 * noise2(aq * 60.0));
        ac += vec3f(0.22, 0.2, 0.2) * topLight * 0.6 * (0.4 + heat);
        ac += vf_heat(0.55) * smoothstep(-0.02, 0.0, ad / asz) * smoothstep(0.0, 0.3, aq.x) * heat * 0.6;
        ac += vec3f(0.3, 0.35, 0.5) * smoothstep(-0.02, 0.0, ad / asz) * (wk + wq * 0.5) * 0.4;
        // anvil heats with the build-up: red-hot rim creeping in
        let hot = 0.15 * wv + (0.2 + 0.8 * bp) * wb + 0.9 * wd + 0.6 * wc;
        ac += vf_heat(0.4 + 0.4 * hot) * exp(ad / asz * 40.0) * hot * 0.8;
        ac += vf_heat(0.6) * heat * 0.15 * exp(-(aq.y + 0.15) * 3.0);
        ac += G.pal1.rgb * gold * 0.2 * topLight;
        col = mix(col, ac, af);
        col += vf_heat(0.6 + 0.3 * hot) * exp(-max(ad, 0.0) / asz * 60.0) * 0.25 * hot * (1.0 - af);
    }
    // the work-piece on the anvil, white-hot on each strike
    let wpd = sd_round_box(p - impact + vec2f(0.0, 0.01), vec2f(0.12, 0.012), 0.006);
    let hitI = G.kick * strikeW;
    let wpHeat = 0.45 + 0.2 * heat + 0.6 * hitI + 0.3 * bp;
    col = mix(col, vf_heat(wpHeat + 0.08 * wave(clamp((p.x - impact.x) / 0.24 + 0.5, 0.0, 1.0))), fill(wpd, px));
    col += vf_heat(0.8) * glow(wpd, 0.02) * (0.25 + 1.2 * hitI);

    // hammer: falls on every beat in verse / chorus / drop, held high and trembling in the build-up
    let strike = smoothstep(0.0, 0.45, ph) * (1.0 - smoothstep(0.82, 1.0, ph));
    let liftA = strikeW * strike * 0.85 + wb * (1.05 + 0.03 * sin(t * 37.0) * bp) + (wq + wk) * 2.6;
    let hc = impact + vec2f(0.0, 0.085 + liftA * 0.75);
    let hdir = normalize(vec2f(0.12 * sin(liftA * 0.7), -1.0));
    let piv = hc - hdir * 2.5;
    let hperp = vec2f(-hdir.y, hdir.x);
    let hl = vec2f(dot(p - hc, hperp), dot(p - hc, hdir));
    let headD = sd_round_box(hl, vec2f(0.17, 0.085), 0.012);
    let bandD = abs(abs(hl.x) - 0.12) - 0.008;
    let handD = sd_segment(p, piv, hc - hdir * 0.08) - 0.03;
    let hamD = min(headD, handD);
    if (hamD < 0.1) {
        var hcol = vec3f(0.04, 0.038, 0.045) * (0.7 + 0.4 * noise2(hl * 40.0));
        if (handD < headD) { hcol = vec3f(0.05, 0.03, 0.02) * (0.7 + 0.5 * noise2(vec2f(dot(p, hdir) * 80.0, 0.0))); }
        else if (bandD < 0.0) { hcol *= 1.6; }
        hcol += vf_heat(0.6) * smoothstep(-0.03, 0.085, hl.y) * (0.2 * heat + 1.2 * hitI) * step(headD, handD) * smoothstep(0.0, -0.01, headD);
        hcol += G.pal1.rgb * gold * 0.15;
        col = mix(col, hcol, fill(hamD, px));
        col += vf_heat(0.6) * exp(-max(hamD, 0.0) / 0.006) * 0.2 * (heat * 0.3 + bp);
    }
    // strike flash
    col += vf_heat(1.0) * exp(-length(p - impact) * 9.0) * hitI * 0.7;

    // ======================= SPARKS =======================
    let bdur = 60.0 / max(G.bpm, 60.0);
    let sage = ph * bdur;
    if (strikeW > 0.02 && length(p - impact) < 1.6) {
        let ns = 18 + i32(G.quality) * 9;
        for (var i = 0; i < 36; i++) {
            if (i >= ns) { break; }
            let fi = f32(i);
            let hs = hash22(vec2f(fi * 1.7, bc));
            let ang = mix(0.25, PI - 0.25, hs.x);
            let spd = (0.5 + 1.3 * hs.y * hs.y) * (0.8 + 0.4 * wd + 0.3 * wc);
            let v0 = vec2f(cos(ang) * spd, sin(ang) * spd * 0.9);
            let life = 0.3 + 0.5 * hash11(fi + bc * 0.37);
            if (sage > life) { continue; }
            let pos = impact + v0 * sage + vec2f(0.0, -1.6) * sage * sage;
            let vel = v0 + vec2f(0.0, -3.2) * sage;
            let sdd = sd_segment(p, pos, pos - vel * 0.035);
            if (sdd > 0.05) { continue; }
            let k = 1.0 - sage / life;
            col += vf_heat(0.75 + 0.4 * k) * (fill(sdd - px * 0.4, px) * 1.2 + glow(sdd, 0.004) * 0.15) * k * strikeW;
        }
    }
    // click: a burst of sparks where you clicked
    let cpp = vec2f((G.click_pos.x - 0.5) * A * 2.0, (0.5 - G.click_pos.y) * 2.0);
    if (G.click_age < 1.2 && length(p - cpp) < 1.2) {
        for (var i = 0; i < 20; i++) {
            let fi = f32(i);
            let hs = hash22(vec2f(fi * 3.1, 7.0));
            let ang = hs.x * TAU;
            let v0 = vec2f(cos(ang), sin(ang)) * (0.3 + 0.9 * hs.y);
            let ca = G.click_age;
            let pos = cpp + v0 * ca + vec2f(0.0, -1.0) * ca * ca;
            let sdd = sd_segment(p, pos, pos - (v0 + vec2f(0.0, -2.0) * ca) * 0.03);
            col += vf_heat(0.9) * (fill(sdd - px * 0.5, px) + glow(sdd, 0.004) * 0.15) * (1.0 - ca / 1.2);
        }
        col += vf_heat(0.9) * exp(-length(p - cpp) * 14.0) * max(1.0 - G.click_age * 4.0, 0.0);
    }

    // ======================= EMBERS + ASH =======================
    let emb = 0.25 * wq + 0.6 * wv + (0.6 + 0.4 * bp) * wb + 1.0 * wd + 0.9 * wc + 0.9 * wk;
    for (var l = 0; l < 3; l++) {
        let fl = f32(l);
        let scl = mix(14.0 - fl * 4.0, 5.0 - fl * 1.2, wk);              // breakdown: big, slow, drifting
        let spd = mix(0.25 + fl * 0.1 + 0.3 * G.flux, 0.04 + 0.08 * G.mid, wk);
        var ep = p;
        let away = p - mp;
        ep += normalize(away + vec2f(1e-4)) * 0.08 * exp(-length(away) * 6.0) * G.mouse_on;   // embers part around the cursor
        let q = vec2f(ep.x * scl + sin(ep.y * 3.0 + t * 0.7 + fl) * 0.6 - t * 0.2 * (1.0 + fl), ep.y * scl - t * spd * scl);
        let ci = floor(q);
        let h = hash22(ci + fl * 17.0);
        let dd = length(fract(q) - 0.5 - (h - 0.5) * 0.7);
        let on = step(1.0 - emb * mix(0.12 + 0.05 * fl, 0.22, wk), hash21(ci + 5.0 + fl));
        let fl2 = 0.55 + 0.45 * sin(t * (4.0 + h.x * 8.0) + h.y * 20.0);
        let sz = mix(0.05 + 0.03 * fl, 0.09, wk);
        let sp = mix(1.0, 0.4 + 2.0 * spec(0.1 + h.x * 0.6), wk);
        var e = smoothstep(sz, 0.0, dd) * on * fl2 * sp;
        e += exp(-abs(dd - sz * 1.2) * 30.0) * on * wk * 0.12 * sp;   // soft bokeh ring when cooling
        col += vf_heat(0.55 + 0.35 * h.x + 0.2 * G.hat) * e * (0.6 + 0.4 * fl);
    }
    // breakdown + quiet: grey ash drifting down
    let ashW = wk + wq * 0.5;
    if (ashW > 0.01) {
        let q = p * 22.0 + vec2f(sin(t * 0.3) * 2.0, t * 1.2);
        let ci = floor(q);
        let dd = length(fract(q) - 0.5 - (hash22(ci + 40.0) - 0.5) * 0.7);
        col += vec3f(0.35, 0.38, 0.45) * smoothstep(0.06, 0.0, dd) * step(0.8, hash21(ci + 41.0)) * ashW * 0.35;
    }

    col += G.pal0.rgb * bp * bp * 0.12 * (0.5 + 0.5 * sin(t * 6.0 + p.x * 2.0)) * smoothstep(hy, -1.0, p.y);
    // heat haze glow at the bottom, gold grade in the chorus, vignette
    col += vf_heat(0.5) * heat * 0.05 * smoothstep(-0.2, -1.0, p.y);
    col = mix(col, col * vec3f(1.15, 1.0, 0.75) + G.pal1.rgb * 0.03, gold * 0.6);
    col *= 1.0 - 0.45 * pow(length(uv - 0.5) * 1.25, 2.2);
    return vec4f(col, 1.0);
}
