// name: Neon City
// palette: #ff2e88 #22e5ff #ffb22e
// Rainy night skyline: windows light up like a spectrum analyzer, flying traffic, neon signs, wet street
// reflections. pal0 = pink neon, pal1 = cyan neon, pal2 = amber (warm windows, festival light).

struct NcHit { col: vec3f, cov: f32, glow: vec3f }

var<private> ncq: f32;
var<private> ncv: f32;
var<private> ncb: f32;
var<private> ncc: f32;
var<private> nck: f32;
var<private> ncd: f32;
var<private> nctens: f32;
var<private> ncpx: f32;
var<private> ncys: f32;
var<private> ncpan: f32;

fn nc_ln(d: f32, w: f32) -> f32 { return clamp(1.0 - d / w, 0.0, 1.0) + 0.3 * exp(-d / (w * 5.0)); }

// distance from p to a ray from s along dir (x), and how far along it (y)
fn nc_ray(p: vec2f, s: vec2f, a: f32) -> vec2f {
    let dir = vec2f(cos(a), sin(a));
    let q = p - s;
    return vec2f(abs(q.x * dir.y - q.y * dir.x), dot(q, dir));
}

// one row of buildings: facade, analyzer windows, signs, spires
fn nc_layer(p: vec2f, li: f32, scale: f32, base: f32, hr: f32, rows: f32) -> NcHit {
    var o: NcHit;
    o.col = vec3f(0.0);
    o.cov = 0.0;
    o.glow = vec3f(0.0);
    let xs = p.x * scale + li * 37.3;
    let bi = floor(xs);
    let fx = fract(xs);
    let h1 = hash11(bi * 1.31 + li * 7.7);
    let h2 = hash11(bi * 2.17 + li * 3.1);
    let gap = 0.03 + 0.1 * h2;
    let cx = abs(fx - 0.5);
    var top = base + hr * (0.2 + 0.8 * h1 * h1);
    if (h2 > 0.55 && cx > 0.3 - gap) { top -= hr * 0.1; }
    // spire with a red beacon on the tallest towers
    let tip = top + 0.1 * hr;
    if (h1 > 0.7) {
        let sd = max(cx / scale - 0.0025, p.y - tip);
        o.cov = fill(sd, ncpx);
        let bl = step(0.5, fract(G.beat_count * 0.5 + h2)) * (0.4 + 0.6 * (1.0 - G.beat_phase));
        o.glow += vec3f(1.0, 0.12, 0.08) * exp(-length(vec2f(cx / scale, p.y - tip)) * 260.0) * 2.0 * bl;
    }
    let dxs = min(fx - gap, 1.0 - gap - fx) / scale;
    let cov = clamp(min(dxs, top - p.y) / ncpx + 0.5, 0.0, 1.0);
    o.cov = max(o.cov, cov);
    if (cov <= 0.0) { return o; }

    // facade
    let fy = (p.y - ncys) / max(top - ncys, 0.01);
    var fac = vec3f(0.018, 0.02, 0.038) * (0.7 + 0.5 * fy) + G.pal1.rgb * 0.015;
    fac += G.pal2.rgb * 0.18 * ncc * smoothstep(0.2, 1.0, fx);          // warm side light in the chorus
    fac *= 0.85 + 0.3 * noise2(vec2f(fx * 20.0, p.y * 60.0));

    // windows
    let cols = max(2.0, floor((1.0 - 2.0 * gap) / scale * rows * (0.55 + 0.4 * h2)));
    let wu = (fx - gap) / (1.0 - 2.0 * gap) * cols;
    let wv = (p.y - ncys) * rows;
    let iu = floor(wu);
    let iv = floor(wv);
    let rect = step(0.18, fract(wu)) * step(fract(wu), 0.82) * step(0.28, fract(wv)) * step(fract(wv), 0.78) * step(fy, 0.97);
    let rnd = hash21(vec2f(iu, iv) + vec2f(bi * 13.1, li * 5.3));
    let slow = hash21(vec2f(iu + bi * 7.0, iv) + floor(G.time * 0.12 + rnd * 8.0));
    let fb = fract(bi * 0.618 + li * 0.27);
    let sv = spec(0.04 + 0.8 * fb);
    let analyzer = step(fy, sv * 1.25 + 0.02) * step(0.25, rnd);
    let dens = 0.1 * ncq + 0.16 * ncv + 0.22 * ncb + 0.12 * nck + 0.85 * ncc + ncd;
    var lit = step(slow, dens);
    lit = max(lit, analyzer * (ncv + 0.8 * ncb + 0.5 * ncc));
    let mel = step(rnd, G.mid * 0.55 + key(i32(fb * 50.0) + 30) * 0.6) * nck;
    lit = max(lit, mel);
    let warm = mix(vec3f(1.0, 0.7, 0.38), mix(G.pal1.rgb, vec3f(0.9, 0.95, 1.0), 0.5), step(0.7, fract(rnd * 31.0)));
    var winc = mix(warm * (0.6 + 0.4 * fract(rnd * 7.0)), pal(fy) * 1.4, analyzer * (ncv + ncb) * 0.8);
    winc = mix(winc, mix(G.pal2.rgb, vec3f(1.0, 0.85, 0.6), 0.5) * 1.3, ncc * 0.6);
    winc = mix(winc, mix(G.pal0.rgb, vec3f(1.0, 0.9, 0.8), 0.25) * 0.9, nck * 0.5);
    // drop: the whole skyline strobes in sync, colour flips every beat
    let strobe = palc(floor(G.beat_count) * 0.37 + fb * 0.15) * (0.4 + 1.8 * pow(1.0 - G.beat_phase, 2.0));
    winc = mix(winc, strobe, ncd);
    o.col = fac + winc * rect * lit * (0.8 + 0.4 * G.high);

    // neon roof rim on some buildings
    if (h2 > 0.3 && h2 < 0.6) {
        let rc = palc(h1 * 2.0 + li * 0.3);
        o.col += rc * nc_ln(abs(top - p.y), ncpx * 1.5) * (0.6 + 0.8 * G.beat);
        o.glow += rc * exp(-abs(p.y - top) * 60.0) * 0.08 * step(top, p.y) * step(gap, fx) * step(fx, 1.0 - gap);
    }
    // vertical signs on the near row: abstract glyph blocks (no text), flicker faster in the build-up
    if (li > 1.5 && h2 < 0.55) {
        let sx = gap + 0.12;
        let sc = vec2f((fx - sx) / scale, p.y - (top - 0.1 - 0.08 * h1));
        let hs = vec2f(0.024, 0.1 + 0.04 * h1);
        let sd = sd_box(sc, hs);
        let rate = 1.0 + 28.0 * nctens;
        let fl = smoothstep(0.25, 0.35, noise2(vec2f(G.time * rate, bi * 3.7)));
        let on = clamp(fl * (0.3 + 0.7 * (1.0 - ncq)) + 1.5 * G.snare * ncb + ncd * (1.0 - G.beat_phase), 0.0, 2.0);
        let gq = (sc + hs) / (hs * 2.0) * vec2f(2.0, 7.0);
        let glyph = step(0.45, hash21(floor(gq) + bi)) * step(0.15, fract(gq.x)) * step(0.2, fract(gq.y));
        let scol = palc(h1 * 3.0 + floor(G.beat_count / 8.0) * 0.33 * ncd);
        o.col = mix(o.col, vec3f(0.01), fill(sd, ncpx));
        o.col += scol * fill(sd + 0.003, ncpx) * glyph * on * 1.6;
        o.col += scol * nc_ln(abs(sd), ncpx * 1.5) * on;
        o.glow += scol * exp(-max(sd, 0.0) * 35.0) * 0.3 * on;
    }
    return o;
}

// a firework: sparks flying out from c, ph 0..1 through its life
fn nc_burst(p: vec2f, c: vec2f, ph: f32, seed: f32, size: f32) -> vec3f {
    let q = p - c + vec2f(0.0, ph * ph * 0.12);
    let r = length(q);
    if (r > size * 0.5) { return vec3f(0.0); }
    let a = atan2(q.y, q.x);
    let n = 34.0;
    let u = (a / TAU + 0.5) * n;
    let cell = floor(u);
    let hh = hash11(cell + seed * 13.0);
    let R = size * pow(ph, 0.45) * (0.7 + 0.3 * hh);
    let perp = (fract(u) - 0.5) / n * TAU * r;
    let ad = max(max(r - R, R * 0.5 - r), 0.0);
    let d = length(vec2f(perp, ad));
    let head = smoothstep(R * 0.5, R, r);
    let tw = mix(1.0, step(0.5, hash11(cell + floor(G.time * 20.0))), smoothstep(0.5, 0.8, ph));
    let fade = pow(1.0 - ph, 1.5);
    let c1 = palc(seed * 0.37 + hh * 0.2);
    return (c1 * (exp(-d / 0.003) * head * 2.0 + exp(-d / 0.015) * 0.2) * tw + vec3f(1.0, 0.9, 0.7) * exp(-r * 25.0) * pow(1.0 - ph, 6.0) * 3.0) * fade;
}

// everything above the street (also used for the reflection)
fn nc_scene(p: vec2f) -> vec3f {
    let lt = G.look_time;
    let above = p.y - ncys;
    // ---- sky: night with low clouds lit from below, or a golden festival evening in the chorus
    var night = mix(vec3f(0.06, 0.025, 0.1), vec3f(0.004, 0.005, 0.02), smoothstep(0.0, 1.3, above));
    night += mix(G.pal0.rgb, G.pal1.rgb, 0.35) * 0.18 * exp(-above * 3.0) * (0.5 + 0.5 * G.energy);
    let golden = mix(mix(vec3f(1.0, 0.55, 0.25), G.pal2.rgb, 0.4) * 1.1, mix(vec3f(0.35, 0.22, 0.55), G.pal0.rgb * 0.5, 0.3), smoothstep(0.0, 1.2, above));
    var col = mix(night, golden, ncc);
    let cl = fbm2(vec2f(p.x * 1.3 + lt * 0.015 + ncpan * 0.1, above * 4.0), 4);
    let cloud = smoothstep(0.45, 0.8, cl) * smoothstep(0.2, 0.6, above);
    let cloudc = mix(mix(G.pal0.rgb, vec3f(0.3, 0.3, 0.45), 0.6) * 0.25 * exp(-above * 1.5), vec3f(1.0, 0.7, 0.5) * 0.6, ncc);
    col = mix(col, cloudc + col * 0.4, cloud * 0.7);
    // a few stars in the gaps when the city is asleep
    let sg = p * 80.0;
    let sh = hash21(floor(sg));
    col += vec3f(0.8) * step(0.985, sh) * smoothstep(0.1, 0.0, length(fract(sg) - 0.5)) * (1.0 - cloud) * (ncq + 0.4 * nck) * smoothstep(0.4, 0.9, above);

    // ---- searchlights from behind the skyline: sweep, then converge as the build-up climbs
    let slw = ncb * (0.4 + 0.6 * nctens) + 0.45 * ncc + 0.2 * ncd;
    if (slw > 0.01) {
        let tgt = vec2f(-ncpan * 0.3, ncys + 1.35);
        for (var i = 0; i < 4; i++) {
            let fi = f32(i);
            let s = vec2f((fi - 1.5) * 0.85 - ncpan * 0.3, ncys + 0.05);
            let sweep = PI * 0.5 + 0.55 * sin(G.time * (0.4 + 1.6 * nctens) + fi * 1.9);
            let tq = tgt - s;
            let a = mix(sweep, atan2(tq.y, tq.x), smoothstep(0.2, 1.0, nctens) * ncb);
            let rr = nc_ray(p, s, a);
            let w = 0.006 + rr.y * 0.05;
            let beam = exp(-(rr.x * rr.x) / (w * w)) * step(0.0, rr.y) * exp(-rr.y * 0.5);
            col += mix(vec3f(0.75, 0.85, 1.0), G.pal1.rgb, 0.3) * beam * slw * (0.35 + 0.8 * G.snare * ncb);
        }
    }

    // ---- drop only: fireworks and laser fans
    if (ncd > 0.01) {
        let bc = G.beat_count + G.beat_phase;
        for (var f = 0; f < 3; f++) {
            let ff = f32(f);
            let t = bc / 2.0 + ff / 3.0;
            let k = floor(t);
            let c = vec2f((hash11(k * 3.1 + ff) - 0.5) * 2.6, ncys + 0.75 + 0.4 * hash11(k * 7.3 + ff));
            col += nc_burst(p, c, fract(t), k + ff * 11.0, 0.3 + 0.15 * hash11(k + ff)) * ncd;
        }
        for (var i = 0; i < 3; i++) {
            let fi = f32(i);
            let s = vec2f((fi - 1.0) * 1.1 - ncpan * 0.8, ncys + 0.42);
            for (var j = 0; j < 3; j++) {
                let fj = f32(j) - 1.0;
                let a = PI * 0.5 + 0.7 * sin(G.time * 1.3 + fi * 2.1) + fj * (0.18 + 0.12 * G.bass) + (hash11(floor(G.beat_count) + fi) - 0.5) * 0.5;
                let rr = nc_ray(p, s, a);
                let lc = palc(fi / 3.0 + G.time * 0.1 + fj * 0.1);
                col += lc * (exp(-rr.x / 0.0022) + 0.15 * exp(-rr.x / 0.02)) * step(0.0, rr.y) * ncd * (0.35 + 0.9 * (1.0 - G.beat_phase));
            }
        }
    }

    // ---- buildings, far to near, with flying traffic between rows
    let fogc = mix(mix(G.pal0.rgb, vec3f(0.12, 0.12, 0.18), 0.65) * 0.35, vec3f(1.0, 0.7, 0.45) * 0.55, ncc);
    let fogk = 1.0 + 0.9 * ncq + 0.5 * nck;
    var layers = array<vec4f, 3>(
        vec4f(3.2, 0.12, 0.85, 46.0),
        vec4f(1.9, 0.04, 0.65, 30.0),
        vec4f(1.15, -0.02, 0.5, 19.0));
    var fogs = array<f32, 3>(0.55, 0.3, 0.08);
    var par = array<f32, 3>(0.25, 0.5, 1.0);
    for (var li = 0; li < 3; li++) {
        let L = layers[li];
        let lp = vec2f(p.x + ncpan * par[li], p.y);
        let h = nc_layer(lp, f32(li), L.x, ncys + L.y, L.z, L.w);
        let fg = clamp(fogs[li] * fogk, 0.0, 0.92);
        col = mix(col, mix(h.col, fogc, fg), h.cov) + h.glow * (1.0 - fg * 0.7);
        // flying traffic lane in front of this row
        if (li < 2) {
            let tw = 0.08 * ncq + 0.6 * ncv + 0.6 * ncb + 0.8 * ncc + 0.9 * ncd + 0.2 * nck;
            for (var k = 0; k < 2; k++) {
                let lane = f32(li * 2 + k);
                let dir = select(-1.0, 1.0, k == 0);
                let ly = ncys + 0.3 + 0.12 * lane + 0.01 * sin(lt * 0.7 + lane);
                let dy = p.y - ly;
                if (abs(dy) > 0.03) { continue; }
                let sc = 5.0 + 3.0 * f32(1 - li);
                let xs = (p.x + ncpan * par[li]) * sc + dir * G.travel * (0.6 + 0.2 * lane) + lt * 0.1 * dir + lane * 3.3;
                let cell = floor(xs);
                let hh = hash11(cell * 1.7 + lane);
                if (hh > tw * 0.7) { continue; }
                let lx = (fract(xs) - 0.5) * dir;   // + = ahead
                let trail = smoothstep(-0.35 - 0.4 * ncd, 0.0, lx) * step(lx, 0.0);
                let core = exp(-(lx * lx) / 0.0006);
                let tc = select(vec3f(1.0, 0.15, 0.2), vec3f(1.0, 0.92, 0.75), dir > 0.0);
                let v = exp(-(dy * dy) / (0.000012 * (2.0 - f32(li))));
                col += mix(tc, G.pal1.rgb, step(0.8, fract(hh * 13.0))) * v * (core * 2.5 + trail * 0.35) * (1.0 - fogs[li] * 0.6);
            }
        }
    }

    // ---- chorus festival: light garlands strung between the near towers
    if (ncc > 0.01) {
        for (var g = 0; g < 2; g++) {
            let fg = f32(g);
            let gx = (p.x + ncpan) / (0.9 + 0.3 * fg) + fg * 0.37;
            let lx = fract(gx) - 0.5;
            let gy = ncys + 0.42 + 0.16 * fg - 0.07 * (1.0 - 4.0 * lx * lx);
            let dy = p.y - gy;
            if (abs(dy) < 0.03) {
                col += vec3f(0.15, 0.1, 0.08) * nc_ln(abs(dy), ncpx) * ncc * 0.5;
                let bx = gx * 22.0;
                let bd = length(vec2f((fract(bx) - 0.5) / 22.0 * (0.9 + 0.3 * fg), dy));
                let bc = palc(floor(bx) * 0.21 + fg * 0.5 + G.time * 0.05);
                let tw = 0.6 + 0.4 * sin(floor(bx) * 1.7 + G.time * 3.0) + G.hat;
                col += bc * (smoothstep(0.006, 0.002, bd) * 1.6 + exp(-bd * 120.0) * 0.4) * tw * ncc;
            }
        }
    }

    // ---- fog bank at street level
    let fogf = exp(-max(above, 0.0) * (6.0 - 3.5 * ncq)) * (0.25 + 0.6 * ncq + 0.25 * nck);
    col = mix(col, fogc * 1.2, clamp(fogf, 0.0, 0.85));
    return col;
}

// streaks of rain: one layer of cells
fn nc_rain(p: vec2f, rt: f32, sc: f32, dens: f32, len: f32) -> f32 {
    let q = vec2f(p.x * sc + p.y * sc * 0.08, p.y * sc * 0.12 + rt);
    let cell = floor(q);
    let h = hash21(cell);
    if (h > dens) { return 0.0; }
    let lx = fract(q.x) - 0.5 - (hash11(h * 91.0) - 0.5) * 0.6;
    let ly = fract(q.y + h * 3.0);
    return smoothstep(0.09, 0.0, abs(lx)) * smoothstep(0.0, 0.05, ly) * smoothstep(len, len * 0.3, ly) * (0.5 + h / dens);
}

fn look(fc: vec2f) -> vec4f {
    let res = G.res;
    let uv = fc / res;
    let lt = G.look_time;
    ncq = sec(SEC_QUIET);
    ncv = sec(SEC_VERSE);
    ncb = sec(SEC_BUILD);
    ncc = sec(SEC_CHORUS);
    nck = sec(SEC_BREAKDOWN);
    ncd = sec(SEC_DROP);
    nctens = ncb * select(1.0, sec_progress(12.0), G.section == SEC_BUILD);
    let zoom = 1.0 + 0.22 * ncc - 0.1 * nck;                      // chorus pulls wide, breakdown leans in
    ncpx = 2.0 / res.y * zoom;
    ncpan = (G.mouse.x - 0.5) * 0.6 + sin(lt * 0.05) * 0.08;
    ncys = -0.45 + (G.mouse.y - 0.5) * 0.25;
    let shake = (vec2f(noise2(vec2f(lt * 20.0, 3.0)), noise2(vec2f(lt * 20.0, 9.0))) - 0.5) * (0.02 * G.kick * ncd + 0.006 * nctens * nctens);
    let p = centered(fc) * zoom + shake;

    var col = vec3f(0.0);
    if (p.y >= ncys) {
        col = nc_scene(p);
    } else {
        // ---- wet street: mirrored city, rippled, brightest in the puddles
        let depth = ncys - p.y;
        let z = 0.25 / depth;
        let gx = p.x * z;
        let puddle = smoothstep(0.42, 0.62, fbm2(vec2f(gx * 0.7, z * 0.5), 4));
        let rip = (noise2(vec2f(p.x * 7.0, depth * 70.0 + lt * 2.0)) - 0.5) * (0.012 + 0.04 * depth) * (1.0 + 2.0 * G.kick) * (1.0 - 0.7 * puddle);
        let rc = nc_scene(vec2f(p.x + rip, ncys + depth * 1.15 + rip * 0.5));
        let fres = mix(0.45, 1.0, exp(-depth * 3.0));
        col = vec3f(0.008, 0.009, 0.016) * (0.7 + 0.6 * noise2(vec2f(gx * 6.0, z * 4.0))) + rc * mix(0.35, 1.0, puddle) * fres;
        // rain rings in the puddles
        let rq = vec2f(gx * 2.5, z * 1.2);
        let rcell = floor(rq);
        let rh = hash21(rcell);
        let rph = fract(lt * 1.1 + rh * 5.0);
        let rl = (fract(rq) - 0.5 - (hash22(rcell) - 0.5) * 0.4);
        let ring = exp(-abs(length(rl) - rph * 0.45) / 0.025) * (1.0 - rph) * puddle;
        col += (luma(rc) * 0.8 + 0.04) * ring * (1.0 + 2.0 * G.kick) * vec3f(0.8, 0.9, 1.0) * (1.0 - ncd * 0.8);
        // ground traffic: headlights and tail lights, smeared down the wet road
        for (var k = 0; k < 2; k++) {
            let fk = f32(k);
            let dir = select(-1.0, 1.0, k == 0);
            let ly = ncys - 0.03 - 0.07 * fk;
            let xs = (p.x + ncpan) * (4.0 - fk) + dir * G.travel * 1.2 + fk * 7.7;
            let cell = floor(xs);
            let hh = hash11(cell * 3.3 + fk);
            if (hh < 0.15 + 0.45 * (1.0 - ncq) + 0.2 * ncc) {
                let lx = (fract(xs) - 0.5) / (4.0 - fk);
                let pair = min(abs(lx - 0.012), abs(lx + 0.012));
                let dy = p.y - ly;
                let tc = select(vec3f(1.0, 0.1, 0.12), vec3f(1.0, 0.92, 0.8), dir > 0.0);
                let lamp = exp(-(pair * pair) / 0.00002) * exp(-(dy * dy) / 0.00002);
                let smear = exp(-(pair * pair) / 0.00006) * exp(-max(-dy, 0.0) * 9.0) * step(dy, 0.0) * 0.35 * puddle;
                col += tc * (lamp * 2.0 + smear) * (1.0 + G.drop);
            }
        }
        col *= 1.0 - 0.3 * smoothstep(0.2, 0.6, depth);
    }

    // ---- rain: falling, or frozen in the light during the drop
    let rainc = mix(vec3f(0.55, 0.65, 0.85), mix(G.pal1.rgb, vec3f(1.0), 0.5), 0.3) * (0.3 + 0.6 * luma(col));
    let rw = clamp(1.0 - ncd - 0.4 * nck, 0.0, 1.0) * (0.6 + 0.4 * (1.0 - ncc));
    let rt = lt * 9.0;
    let rn = nc_rain(p, rt, 90.0, 0.25 + 0.15 * G.flux, 0.6) * 0.6 + nc_rain(p + 3.1, rt * 1.3, 55.0, 0.18, 0.8);
    col += rainc * rn * rw * (0.8 + 0.4 * G.hat);
    if (ncd > 0.01) {
        let fz = nc_rain(p, 17.0 + lt * 0.05, 90.0, 0.3, 0.12) + nc_rain(p + 1.7, 23.0 + lt * 0.03, 55.0, 0.25, 0.1) * 1.3;
        let fl = palc(floor(G.beat_count) * 0.37 + p.x * 0.1) * (0.5 + 1.5 * pow(1.0 - G.beat_phase, 2.0));
        col += mix(vec3f(1.0), fl, 0.6) * fz * ncd * 1.4;
    }

    // ---- breakdown: rain close-up on the glass, soft bokeh city lights
    if (nck > 0.01) {
        col = mix(col, col * 0.45 + vec3f(0.01, 0.01, 0.025), nck * 0.6);
        let bq = p * 1.7 + vec2f(lt * 0.03, 0.0);
        for (var b = 0; b < 2; b++) {
            let fb = f32(b);
            let q = bq * (1.0 + fb * 0.6) + fb * 5.3;
            let cell = floor(q);
            let h = hash21(cell + fb * 9.0);
            if (h < 0.45) {
                let o = (hash22(cell + fb) - 0.5) * 0.4;
                let d = length(fract(q) - 0.5 - o);
                let rad = 0.18 + 0.15 * h;
                let disc = smoothstep(rad, rad - 0.04, d) * (0.7 + 0.3 * smoothstep(rad - 0.08, rad - 0.02, d));
                let bc = palc(h * 2.7 + fb * 0.3);
                let lev = 0.15 + 0.6 * spec(0.2 + h * 0.6) + 0.6 * G.mid;
                col += bc * disc * lev * nck * 0.55;
            }
        }
        // drops on the glass that slowly trickle down
        let dq = vec2f(p.x * 7.0, p.y * 7.0 + lt * 0.15);
        let dc = floor(dq);
        let dh = hash21(dc + 31.0);
        if (dh < 0.35) {
            let slide = fract(lt * 0.05 * (0.5 + dh) + dh * 3.0);
            let dl = fract(dq) - vec2f(0.5 + (dh - 0.17) * 1.2, 0.8 - slide * 0.6);
            let dd = length(dl * vec2f(1.0, 0.85));
            let dr = 0.08 + 0.12 * dh;
            let inside = smoothstep(dr, dr - 0.02, dd);
            let refr = nc_scene(vec2f(p.x - dl.x * 0.8, ncys + 0.4 - dl.y * 1.5));
            col = mix(col, refr * 0.7, inside * nck);
            col += vec3f(0.9, 0.95, 1.0) * smoothstep(0.03, 0.0, length(dl - vec2f(-0.3, 0.35) * dr)) * inside * nck;
            col += vec3f(0.4, 0.5, 0.7) * nc_ln(abs(dd - dr), 0.012) * 0.25 * nck;
        }
    }

    // ---- click: a firework at the cursor
    let cp = vec2f((G.click_pos.x - 0.5) * 2.0 * G.aspect, (0.5 - G.click_pos.y) * 2.0) * zoom;
    if (G.click_age < 1.6) {
        col += nc_burst(p, cp, G.click_age / 1.6, 7.0, 0.35);
    }
    // mouse: a soft neon spotlight follows the cursor
    let mp = vec2f((G.mouse.x - 0.5) * 2.0 * G.aspect, (0.5 - G.mouse.y) * 2.0) * zoom;
    col += G.pal0.rgb * 0.06 * exp(-length(p - mp) * 4.0) * G.mouse_on;

    // ---- drop flash, vignette, grain
    col += mix(G.pal0.rgb, vec3f(1.0), 0.5) * G.drop * 0.35;
    let vq = uv - 0.5;
    col *= clamp(1.0 - dot(vq, vq) * 1.2, 0.0, 1.0);
    col += (hash21(fc + fract(lt * 7.0) * 113.0) - 0.5) * 0.02;
    return vec4f(col, 1.0);
}
