// name: Kaleido Temple
// palette: #ffbe3c #12b5a0 #d0306e
// A temple of light seen through a kaleidoscope. Gold filigree, jewel petals and faceted gems arranged in
// sacred geometry. Quiet: one slow lotus outline. Verse: a 6-fold mandala breathing on the beat. Build-up:
// rings spin up and flow inward while the fold count climbs. Drop: the mandala shatters into a 12/24-fold
// crystal tunnel with flashing facets. Breakdown: glass petals drift apart, lit by the melody. Chorus: looking
// up into a vast golden temple dome with an open oculus and god rays. Mouse moves/turns the centre; click rings.

fn kt_sq(x: f32) -> f32 { return x * x; }

// fold p into one mirrored wedge of an n-fold kaleidoscope (angle 0..PI/n)
fn kt_fold(p: vec2f, n: f32) -> vec2f {
    let s = TAU / n;
    let a = abs(fract(atan2(p.y, p.x) / s + 0.5) - 0.5) * s;
    return vec2f(cos(a), sin(a)) * length(p);
}

// lens / vesica with its tips on the x axis: half length L, half width W
fn kt_lens(p0: vec2f, L: f32, W: f32) -> f32 {
    let r = (L * L + W * W) / (2.0 * W);
    let d = r - W;
    let p = abs(vec2f(p0.y, p0.x));
    if ((p.y - L) * d > p.x * L) { return length(p - vec2f(0.0, L)); }
    return length(p - vec2f(-d, 0.0)) - r;
}

// polished gold: x = light amount 0..1.5
fn kt_gold(x: f32) -> vec3f {
    let k = clamp(x, 0.0, 1.6);
    let g = mix(vec3f(0.20, 0.09, 0.02), vec3f(1.0, 0.70, 0.28), smoothstep(0.0, 0.85, k))
        + vec3f(1.0, 0.92, 0.75) * smoothstep(0.85, 1.6, k);
    return mix(g, g * G.pal0.rgb * 1.5, 0.45);
}

// a faceted jewel: rgb in .xyz, coverage in .w
fn kt_gem(l: vec2f, rad: f32, c: vec3f, px: f32) -> vec4f {
    let d = length(l) - rad;
    if (d > px * 2.0 + rad * 0.2) { return vec4f(0.0); }
    let a = atan2(l.y, l.x);
    let fid = floor(a / TAU * 8.0 + 4.0);
    let rr = length(l) / rad;
    var shade = 0.45 + 0.4 * hash11(fid * 3.7 + 1.0);
    shade = mix(shade, 1.1, step(rr, 0.45));                      // table facet
    let spec = exp(-dot(l - vec2f(-0.35, 0.35) * rad, l - vec2f(-0.35, 0.35) * rad) / kt_sq(rad * 0.18));
    var rgb = c * shade + vec3f(1.0) * spec * 1.4;
    let st = abs(d + rad * 0.08) - rad * 0.1;                    // gold setting
    rgb = mix(rgb, kt_gold(1.0), fill(st, px));
    return vec4f(rgb, fill(d - rad * 0.02, px));
}

fn kt_bg(p: vec2f, t: f32) -> vec3f {
    let r = length(p);
    let n = fbm2(rot(t * 0.01) * p * 1.6 + vec2f(t * 0.015, 0.0), 4);
    var c = mix(vec3f(0.018, 0.010, 0.035), vec3f(0.003, 0.002, 0.010), smoothstep(0.0, 1.6, r));
    c += mix(G.pal1.rgb, G.pal2.rgb, n) * pow(n, 2.5) * 0.10 * (0.4 + G.energy);
    // fine stars / dust
    let g = p * 55.0;
    let ci = floor(g);
    let h = hash21(ci);
    let sd = length(fract(g) - hash22(ci) * 0.4 - 0.3);   // centre >= 0.3 from the cell border
    c += vec3f(1.0, 0.9, 0.75) * step(0.93, h) * exp(-sd * sd * 120.0) * (0.25 + 0.5 * G.hat * step(0.97, h));
    return c;
}

// ---------- Quiet: a single lotus outline ----------
fn kt_lotus(p: vec2f, px: f32) -> vec3f {
    let t = G.time;
    let pr = rot(t * 0.03) * p;
    var col = vec3f(0.0);
    let br = 0.8 + 0.2 * sin(t * 0.45) + 0.3 * G.vol;
    for (var l = 0; l < 3; l++) {
        let fl = f32(l);
        let R = 0.62 - fl * 0.17 + 0.01 * sin(t * 0.4 + fl);
        let q = kt_fold(rot(fl * PI / 8.0) * pr, 8.0);
        let d = kt_lens(q - vec2f(R * 0.52, 0.0), R * 0.5, R * 0.19);
        let ad = abs(d);
        col += kt_gold(0.9 - fl * 0.15) * (exp(-ad / (px * 1.1)) * 0.9 + 0.003 / (ad + 0.006)) * br * (1.0 - fl * 0.2);
        // inner vein
        col += kt_gold(0.6) * exp(-abs(q.y) / px) * smoothstep(0.0, -0.02, d) * 0.25 * br;
    }
    let r = length(p);
    col += kt_gold(1.2) * (exp(-r * r * 900.0) * 1.5 + 0.004 / (r + 0.01)) * br;     // bindu
    // water ring the lotus floats on
    col += G.pal1.rgb * exp(-abs(r - 0.8 - 0.03 * sin(t * 0.3)) / (px * 1.5)) * 0.25 * (0.5 + 0.5 * sin(atan2(p.y, p.x) * 3.0 + t * 0.2));
    return col * 0.6;
}

// ---------- Verse / Build-up: the mandala ----------
fn kt_mandala(p0: vec2f, n: f32, spin: f32, inflow: f32, heat: f32, px: f32) -> vec3f {
    var col = vec3f(0.0);
    let breathe = 1.0 + 0.07 * G.kick + 0.04 * G.beat * (1.0 - G.beat_phase);
    let p = p0 / breathe;
    let r = length(p);
    let lit = 0.75 + 0.5 * G.energy + heat * 0.6 + 1.4 * G.snare * heat;
    let hot = mix(vec3f(1.0), vec3f(1.0, 0.85, 0.7), heat);

    // radial spokes and a soft halo behind everything
    let qs = kt_fold(rot(spin * 0.5) * p, n);
    col += kt_gold(0.7) * exp(-abs(qs.y) / (px * 1.2)) * smoothstep(1.6, 0.1, r) * 0.25 * lit;
    col += mix(G.pal1.rgb, G.pal0.rgb, 0.5) * exp(-r * 2.5) * (0.08 + 0.12 * G.beat + 0.4 * heat);

    for (var i = 0; i < 6; i++) {
        let fi = f32(i);
        let dir = select(-1.0, 1.0, (i & 1) == 0);
        let rr = fract(fi / 6.0 + 0.08 - inflow);
        let R = 0.10 + rr * 1.4;
        let w = 0.05 + 0.06 * R;
        // soft window: the slow 1/d halos below reach zero before the annulus early-out
        let fade = smoothstep(0.0, 0.12, rr) * smoothstep(1.0, 0.8, rr) * smoothstep(w * 2.2, w * 1.5, abs(r - R));
        if (abs(r - R) > w * 2.2 || fade < 0.01) { continue; }
        let kind = i % 3;
        let nn = n * select(1.0, 2.0, kind == 1);
        let q = kt_fold(rot(spin * dir * (0.35 + 0.25 * fi) + fi * 0.7) * p, nn);
        let sx = clamp(q.y / (R * PI / nn + 1e-4), 0.0, 1.0);          // 0..1 across the wedge
        let sp = spec(0.05 + 0.55 * sx + 0.06 * fi);
        if (kind == 0) {
            // beaded gold ring, wobbling with the spectrum
            let Rw = R + 0.012 * sp * (1.0 + heat);
            let d = abs(length(q) - Rw) - 0.0025;
            col += kt_gold(1.0) * (fill(d, px) + 0.002 / (max(d, 0.0) + 0.004)) * fade * lit * hot;
            let g1 = kt_gem(q - vec2f(Rw, 0.0), w * 0.28 * (1.0 + 0.3 * G.hat), palc(fi * 0.21 + 0.4), px);
            col = mix(col, g1.xyz * lit, g1.w * fade);
            col += G.pal1.rgb * 0.004 / (length(q - vec2f(Rw, 0.0)) + 0.01) * (0.3 + G.hat) * fade;
            let e = Rw * vec2f(cos(PI / nn), sin(PI / nn));
            col += kt_gold(1.3) * fill(length(q - e) - w * 0.1, px) * fade;
        } else if (kind == 1) {
            // jewel petals with gold outline
            let L = w * (0.85 + 0.35 * sp);
            let W = w * 0.42 * PI * 6.0 / nn;
            let d = kt_lens(q - vec2f(R, 0.0), L, W);
            let inside = fill(d, px);
            let depth = clamp(-d / W, 0.0, 1.0);
            let jc = mix(G.pal2.rgb * 0.5, G.pal1.rgb * 1.2, depth) * (0.6 + 0.8 * sp) + vec3f(1.0) * pow(depth, 6.0) * 0.6;
            col = mix(col, jc * lit, inside * fade);
            col += kt_gold(1.1) * (exp(-abs(d) / (px * 1.3)) + 0.0015 / (abs(d) + 0.004)) * fade * lit * hot;
            col += kt_gold(0.8) * exp(-abs(q.y) / px) * inside * 0.5 * fade;
        } else {
            // star polygon lines with gems on the vertices
            let a1 = PI / nn;
            let e1 = abs(dot(q, vec2f(cos(a1), sin(a1))) - R * cos(a1));
            let a2 = 2.0 * PI / nn;
            let e2 = abs(dot(q, vec2f(cos(a2), sin(a2))) - R * cos(a2));
            let clip = smoothstep(R + 0.01, R - 0.01, length(q)) * smoothstep(R * 0.3, R * 0.6, length(q));
            let lines = (exp(-e1 / (px * 1.2)) + exp(-e2 / (px * 1.2)) * 0.7 + 0.001 / (min(e1, e2) + 0.003)) * clip;
            col += kt_gold(0.95) * lines * fade * lit * hot;
            let g2 = kt_gem(q - vec2f(R, 0.0), w * 0.22, palc(0.7 + fi * 0.13), px);
            col = mix(col, g2.xyz * lit, g2.w * fade);
        }
    }
    // central bindu jewel
    let gc = kt_gem(rot(spin) * p, 0.05 + 0.02 * G.kick, G.pal2.rgb * 1.3, px);
    col = mix(col, gc.xyz * lit, gc.w);
    col += G.pal2.rgb * 0.01 / (r + 0.02) * (0.4 + G.kick + heat);
    return col;
}

// ---------- Drop: shattered crystal tunnel ----------
fn kt_tunnel(p: vec2f, px: f32) -> vec3f {
    let n = 12.0 + 12.0 * step(0.5, fract(G.beat_count / 8.0));        // 12 <-> 24 fold, every 4 beats
    let r = length(p) + 1e-4;
    let q = kt_fold(rot(G.time * 0.25 + G.drop * 0.8) * p, n);
    let a = atan2(q.y, q.x) / (PI / n);                                  // 0..1 across a mirror
    let z = -log(r) * (2.0 * n / PI) + G.travel * 3.0;               // log-polar: square facets
    let g = vec2f(a * 2.0, z);
    let cell = floor(g);
    let f = fract(g) - 0.5;
    let h = hash21(cell + 13.0);
    // crystal cracks from a small kaleidoscopic IFS inside each facet
    var w = f;
    var trap = 10.0;
    var sc = 1.0;
    for (var i = 0; i < 4; i++) {
        w = abs(w) - vec2f(0.24, 0.17);
        w = rot(0.55 + 0.45 * f32(i) + h * 1.2) * w;
        w *= 1.7;
        sc *= 1.7;
        trap = min(trap, abs(w.y) / sc);
    }
    let fog = smoothstep(0.03, 0.45, r);
    let jewel = palc(h * 0.8 + 0.15 * floor(z * 0.05) + 0.3);
    let planes = 0.35 + 0.65 * fract(sin(dot(sign(f) + cell, vec2f(12.9, 78.2))) * 437.5);
    let dia = abs(f.x) + abs(f.y);
    var col = jewel * planes * (0.35 + 0.6 * smoothstep(0.5, 0.2, dia)) * (0.7 + G.bass);
    col += kt_gold(1.2) * (exp(-abs(dia - 0.45) * 60.0) + exp(-min(abs(f.x), abs(f.y)) * 90.0) * 0.6) * (0.6 + G.mid);
    col += vec3f(1.0, 0.95, 0.9) * exp(-trap * 400.0) * (0.5 + 1.5 * G.high);
    // facets flash on kicks / snares
    let fl = step(1.0 - (0.18 * G.kick + 0.15 * G.snare + 0.2 * G.drop), hash21(cell + floor(G.beat_count) * 3.1));
    col += mix(vec3f(1.0), jewel, 0.3) * fl * 2.2 * smoothstep(0.5, 0.1, dia);
    col *= fog * (0.4 + 0.8 * smoothstep(0.0, 1.0, r));
    // white-hot core at the end of the tunnel
    col += mix(G.pal2.rgb, vec3f(1.0), 0.6) * (0.03 / (r + 0.03)) * (1.0 + 2.0 * G.kick + 2.0 * G.drop);
    // shards blasting outward
    let an = atan2(p.y, p.x);
    let sid = floor(an / TAU * 90.0);
    let sp = fract(hash11(sid) + G.time * (0.6 + hash11(sid + 4.0)) + G.travel * 0.3);
    let srad = sp * 2.2;
    let shard = exp(-abs(r - srad) * 30.0) * exp(-abs(fract(an / TAU * 90.0) - 0.5) * 12.0) * step(0.7, hash11(sid + 9.0));
    col += mix(jewel, vec3f(1.0), 0.5) * shard * (0.5 + 1.5 * G.kick) * sp;
    return col;
}

// ---------- Breakdown: glass petals drifting apart ----------
fn kt_petals(p: vec2f, px: f32) -> vec3f {
    let t = G.time;
    let pd = select(1.0, sec_progress(16.0), G.section == SEC_BREAKDOWN);
    let ang = atan2(p.y, p.x);
    var col = vec3f(0.0);
    // soft glass light / caustics behind
    let cw = fbm2(p * 1.3 + vec2f(t * 0.03, -t * 0.02), 3);
    let ca = pow(abs(sin((fbm2(p * 2.6 + cw * 2.0 + t * 0.04, 3)) * 9.0)), 12.0);
    col += mix(G.pal1.rgb, vec3f(0.9, 0.85, 1.0), 0.5) * (0.05 + 0.10 * ca) * (0.5 + G.mid);
    for (var l = 0; l < 2; l++) {
        let fl = f32(l);
        let n = 8.0 * (fl + 1.0);
        let s = TAU / n;
        let off = fl * 0.5 * s + t * 0.015 * (1.0 - 2.0 * fl);
        let base = round((ang - off) / s);
        for (var j = -1; j <= 1; j++) {
            let k = base + f32(j);
            let ci = k - n * floor(k / n);
            let cang = k * s + off;
            let hh = hash11(ci * 1.7 + fl * 31.0);
            let drift = 0.04 + (0.22 + 0.25 * hh) * pd + 0.025 * sin(t * 0.4 + hh * 6.0);
            let R = 0.26 + 0.36 * fl + drift;
            let tw = (0.35 * sin(t * 0.25 + hh * 9.0)) * pd;
            let lp = rot(-(cang + tw)) * (p - vec2f(cos(cang), sin(cang)) * R);
            let L = 0.16 + 0.10 * fl;
            let W = 0.06 + 0.025 * fl;
            let d = kt_lens(lp, L, W);
            if (d > 0.1) { continue; }
            let mel = max(key(i32(34.0 + ci * 3.0 + fl * 2.0)), spec(0.3 + 0.45 * ci / n)) * (0.6 + G.mid);
            let tint = mix(pal(fract(hh * 0.7 + fl * 0.4)), vec3f(1.0), 0.4);
            let inside = fill(d, px);
            let fres = exp(-abs(d) / (px * 2.0 + 0.003));
            col += tint * (inside * (0.08 + 0.12 * smoothstep(-W, 0.0, d) + 0.7 * mel) + fres * (0.35 + 1.2 * mel));
            col += tint * mel * 0.012 / (max(d, 0.0) + 0.012) * smoothstep(0.1, 0.03, d);
            col += vec3f(1.0) * inside * exp(-abs(lp.y) / (px * 1.2)) * 0.15;                  // vein
            col += vec3f(1.0) * inside * exp(-dot(lp - vec2f(-L * 0.3, W * 0.4), lp - vec2f(-L * 0.3, W * 0.4)) * 2000.0) * 0.5;
        }
    }
    // floating motes of light
    for (var m = 0; m < 2; m++) {
        let fm = f32(m);
        let gp = p * (9.0 + fm * 6.0) + vec2f(t * 0.05, t * (0.12 + fm * 0.05));
        let gi = floor(gp);
        let gh = hash21(gi + fm * 11.0);
        let gd = length(fract(gp) - hash22(gi) * 0.6 - 0.2);
        col += mix(G.pal0.rgb, vec3f(1.0), 0.5) * step(0.8, gh) * exp(-gd * gd * 200.0) * (0.3 + 0.6 * G.high) * (0.6 + 0.4 * sin(t + gh * 30.0));
    }
    return col;
}

// ---------- Chorus: the golden temple dome ----------
fn kt_dome(p: vec2f, px: f32) -> vec3f {
    let t = G.time;
    let r = length(p) + 1e-4;
    let ocu = 0.17 + 0.015 * G.kick;
    let an = atan2(p.y, p.x) + t * 0.03;
    let N = 28.0;
    let u = an / TAU * N;
    let v = log(r / ocu) * 2.3;
    let cell = floor(vec2f(u, v));
    let f = fract(vec2f(u, v)) - 0.5;
    let light = 1.05 * exp(-max(r - ocu, 0.0) * 0.9) + 0.25;
    var col = vec3f(0.0);
    if (r > ocu) {
        let outer = sd_box(f, vec2f(0.40, 0.36));
        let inner = sd_box(f, vec2f(0.27, 0.24));
        let cpx = px * 6.0 / r;
        var c = kt_gold(0.55 * light);                                         // ribs
        if (outer < 0.0) {
            // bevelled coffer walls lit from the oculus
            var face = 0.7;
            if (abs(f.y) * 1.1 > abs(f.x)) { face = select(0.35, 1.25, f.y > 0.0); }
            c = kt_gold(face * light * 0.75);
            if (inner < 0.0) {
                c = kt_gold(0.32 * light) * (0.8 + 0.2 * noise2(f * 9.0 + cell));
                // rosette gem pulses with its row's band
                let rb = spec(0.05 + 0.1 * cell.y + 0.02 * fract(cell.x * 0.37));
                let rl = vec2f(f.x * 1.4, f.y);
                let g = kt_gem(rl, 0.12 + 0.03 * G.beat, mix(G.pal1.rgb, G.pal2.rgb, step(0.5, fract(cell.x * 0.5))) * (0.8 + 1.5 * rb), cpx);
                c = mix(c, g.xyz * light, g.w);
                c += mix(G.pal1.rgb, G.pal0.rgb, 0.5) * 0.02 / (length(rl) + 0.03) * rb * light * smoothstep(0.24, 0.1, length(rl));
            }
        }
        c += vec3f(1.0, 0.9, 0.7) * exp(-abs(outer) / cpx) * 0.5 * light;    // highlight on the rib edges
        col = c * smoothstep(ocu, ocu + 0.01, r);
        // a gilded ring around the oculus with tiny gems
        let ring = abs(r - ocu - 0.03) - 0.012;
        col = mix(col, kt_gold(1.4), fill(ring, px));
        let qq = kt_fold(rot(-t * 0.1) * p, 16.0);
        let gg = kt_gem(qq - vec2f(ocu + 0.03, 0.0), 0.009, G.pal2.rgb * 1.5, px);
        col = mix(col, gg.xyz, gg.w);
    }
    // the open sky through the oculus
    let sky = mix(vec3f(1.4, 1.3, 1.1), mix(G.pal1.rgb, vec3f(1.0), 0.6) * 1.1, smoothstep(0.0, ocu, r));
    col = mix(col, sky * (1.0 + 0.3 * G.beat), smoothstep(ocu + px, ocu - px, r));
    // god rays and rising dust
    let rays = pow(noise2(vec2f(atan2(p.y, p.x) * 9.0, t * 0.15)), 3.0) * 1.5 + 0.2;
    col += vec3f(1.0, 0.85, 0.55) * rays * exp(-r * 1.4) * (0.4 + 0.6 * G.energy + 0.4 * G.beat);
    col += vec3f(1.0, 0.95, 0.85) * 0.05 / (r + 0.05) * (0.6 + G.kick);
    let dp = vec2f(an * 6.0, log(r) * 4.0 + t * 0.6);
    let di = floor(dp * 3.0);
    let dh = hash21(di);
    let dd = length(fract(dp * 3.0) - 0.5);
    col += vec3f(1.0, 0.9, 0.7) * step(0.88, dh) * exp(-dd * dd * 60.0) * (0.3 + G.hat) * smoothstep(0.1, 0.5, r) * exp(-r);
    return col;
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let q0 = centered(fc);
    let t = G.time;
    let A = G.aspect;
    let px = 2.0 / G.res.y;

    // mouse steers the centre and turns the kaleidoscope
    let m = (G.mouse - 0.5) * vec2f(2.0 * A, -2.0) * G.mouse_on;
    let p = rot(m.x * 0.5) * (q0 - m * 0.35);

    let wq = sec(SEC_QUIET);
    let wv = sec(SEC_VERSE);
    let wb = sec(SEC_BUILD);
    let wd = sec(SEC_DROP);
    let wk = sec(SEC_BREAKDOWN);
    let wc = sec(SEC_CHORUS);

    var col = kt_bg(p, t) * (1.0 - wc);
    if (wq > 0.004) { col += kt_lotus(p, px) * wq; }
    if (wv > 0.004) { col += kt_mandala(p, 6.0, t * 0.06, 0.0, 0.0, px) * wv; }
    if (wb > 0.004) {
        let inb = G.section == SEC_BUILD;
        let age = select(12.0, G.section_age, inb);
        let prog = select(1.0, sec_progress(12.0), inb);
        let n = 6.0 + 2.0 * floor(prog * 4.999);                               // 6 -> 8 -> 10 -> 12 -> 14 folds
        let spin = t * 0.08 + age * age * 0.05;
        let inflow = age * 0.02 + age * age * 0.004;
        var c = kt_mandala(p * (1.0 + 0.25 * prog), n, spin, inflow, prog, px);
        // tension: converging light streaks
        let an = atan2(p.y, p.x);
        let st = pow(noise2(vec2f(an * 14.0, length(p) * 3.0 + age * (1.0 + prog * 4.0))), 4.0);
        c += kt_gold(1.0) * st * prog * smoothstep(0.2, 1.2, length(p)) * 0.8;
        c += vec3f(1.0, 0.9, 0.8) * G.snare * prog * 0.15;
        col += c * wb;
    }
    if (wd > 0.004) { col = mix(col, kt_tunnel(p, px), wd); }
    if (wk > 0.004) { col += kt_petals(p, px) * wk; }
    if (wc > 0.004) { col += kt_dome(p, px) * wc; }

    // click: a ring of light and a gem burst
    if (G.click_age < 2.5) {
        let cp = (G.click_pos - 0.5) * vec2f(2.0 * A, -2.0);
        let dc = length(q0 - cp);
        let ca = G.click_age;
        let ring = exp(-kt_sq((dc - ca * 0.7) * 35.0)) * exp(-ca * 1.5);
        let ck = kt_fold(q0 - cp, 8.0);
        let rays = exp(-abs(ck.y) * 120.0) * exp(-dc * 4.0) * exp(-ca * 3.0);
        col += kt_gold(1.3) * (ring * 1.5 + rays + exp(-dc * 25.0) * exp(-ca * 5.0) * 2.0);
    }

    col = col / (1.0 + 0.12 * luma(col));
    col *= 1.0 - 0.35 * pow(length(uv - 0.5) * 1.3, 2.5);
    col += (hash21(fc + fract(t) * 71.0) - 0.5) * 0.01;
    return vec4f(col, 1.0);
}
