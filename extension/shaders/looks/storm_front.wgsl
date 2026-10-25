// name: Storm Front
// palette: #8cc8ff #b48cff #ffcf7a
// A night thunderstorm rolling in over the sea: painterly fbm clouds, rain curtains, a lighthouse
// headland, wind-bent dune grass and lightning. Every song section changes the weather.

// sin-free value noise: common noise2()'s sin(dot*43758) hash loses precision for big arguments (late in the song),
// so a lattice point can hash differently on the two sides of a cell border -> straight-edged glassy shards.
fn sf_h(p: vec2f) -> f32 {
    var p3 = fract(vec3f(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}
fn sf_nz(p: vec2f) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(sf_h(i), sf_h(i + vec2f(1.0, 0.0)), u.x), mix(sf_h(i + vec2f(0.0, 1.0)), sf_h(i + vec2f(1.0, 1.0)), u.x), u.y);
}

fn sf_fbm(p0: vec2f, oct: i32) -> f32 {
    var p = p0; var a = 0.5; var s = 0.0;
    for (var i = 0; i < oct; i++) { s += a * sf_nz(p); p = p * 2.03 + vec2f(1.7, 9.2); a *= 0.5; }
    return s;
}
fn sf_n1(x: f32, s: f32) -> f32 { return noise2(vec2f(x, s * 13.7)) - 0.5; }

// jagged lightning bolt from (x0, top) down to y = bot, with two forks. Returns a distance.
fn sf_bolt(p: vec2f, x0: f32, top: f32, bot: f32, seed: f32) -> f32 {
    // early-out only where the bolt halo is < 1/255; inside it, distance grows past the bolt's ends
    if (p.y > top + 0.4 || p.y < bot - 0.4 || abs(p.x - x0) > 0.9) { return 1e3; }
    let endd = max(max(p.y - top - 0.01, bot - p.y), 0.0);
    let s = clamp((top - p.y) / (top - bot), 0.0, 1.0);
    let y = p.y;
    let bx = x0 + sf_n1(y * 4.0, seed) * 0.4 * s + sf_n1(y * 14.0, seed + 1.0) * 0.09 * (0.3 + s)
                + sf_n1(y * 47.0, seed + 2.0) * 0.022;
    var d = abs(p.x - bx) + endd;
    for (var k = 0; k < 2; k++) {
        let fk = f32(k);
        let s0 = 0.15 + 0.35 * hash11(seed * 3.1 + fk);
        let s1 = s0 + 0.2 + 0.25 * hash11(seed * 5.3 + fk);
        if (s > s0 && s < s1) {
            let dir = select(-1.0, 1.0, hash11(seed * 7.7 + fk * 2.0) > 0.5);
            let u = (s - s0) * (top - bot);
            let brx = bx + dir * u * (0.5 + 0.7 * hash11(seed + fk * 9.0)) + sf_n1(y * 31.0, seed + 4.0 + fk) * 0.1 * u;
            let fade = (s - s0) / (s1 - s0);
            d = min(d, abs(p.x - brx) + fade * 0.006 + smoothstep(0.6, 1.0, fade) * 0.4 + endd);
        }
    }
    return d;
}

fn sf_bolt_light(d: f32, px: f32) -> f32 {
    return exp(-d / (px * 1.3)) * 1.6 + exp(-d / 0.01) * 0.4 + exp(-d / 0.07) * 0.12;
}

// land above the horizon: a headland on the right, a low far coast on the left
fn sf_land(x: f32) -> f32 {
    let r = 0.16 * smoothstep(0.72, 1.02, x) + 0.025 * fbm2(vec2f(x * 7.0, 2.0), 3) * step(0.7, x)
          - 0.03 * smoothstep(1.45, 1.9, x);
    let l = 0.05 * smoothstep(-0.55, -1.5, x) + 0.02 * fbm2(vec2f(x * 5.0, 7.0), 3) * smoothstep(-0.5, -0.8, x);
    return max(r, l) - 0.012;
}

// wind-bent grass blades. base = ground y, hmax = tallest blade, n = blades per unit
fn sf_grass(p: vec2f, base: f32, hmax: f32, n: f32, bend: f32, t: f32, seed: f32, px: f32) -> f32 {
    let s = (p.y - base) / hmax;
    if (s < 0.0 || s > 1.0) { return 0.0; }
    var cover = 0.0;
    for (var k = 0; k < 2; k++) {
        let fk = f32(k);
        let nn = n * (1.0 + fk * 0.37);
        let gust = bend * (0.75 + 0.5 * noise2(vec2f(p.x * 1.3 - t * 1.2, fk + seed)));
        let xb = p.x - gust * s * s * hmax - sin(t * 3.0 + p.x * 9.0 + fk) * 0.004 * s;
        let ci = floor(xb * nn);
        let h = hash22(vec2f(ci, seed + fk * 3.0));
        let hh = 0.25 + 0.75 * h.y * h.y;
        if (s > hh) { continue; }
        let cx = (ci + 0.5 + (h.x - 0.5) * 0.6) / nn;
        let w = (0.28 / nn) * (1.0 - s / hh) + px * 0.4;
        cover = max(cover, fill(abs(xb - cx) - w, px));
    }
    return cover;
}

// sec() with a quicker 0.6 s cross-fade, so a storm can change its weather fast
fn sf_sec(k: f32) -> f32 {
    return sec(k);
}

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let px = 2.0 / G.res.y;
    let t = G.time;
    let A = G.aspect;
    let ph = G.beat_phase;
    let bc = floor(G.beat_count);

    // ---- section weights ----
    let wq = sf_sec(SEC_QUIET);
    let wv = sf_sec(SEC_VERSE);
    let wb = sf_sec(SEC_BUILD);
    let wc = sf_sec(SEC_CHORUS);
    let wk = sf_sec(SEC_BREAKDOWN);
    let wd = sf_sec(SEC_DROP);
    let bp = wb * sec_progress(12.0);
    let kopen = wk * smoothstep(0.0, 2.5, G.section_age + (1.0 - select(0.0, 1.0, G.section == SEC_BREAKDOWN)) * 3.0);

    // camera: kicks shake it in the drop, the build-up buffets it
    var p = centered(fc);
    p += (vec2f(hash11(floor(t * 30.0)), hash11(floor(t * 30.0) + 5.0)) - 0.5) * (wd * G.kick * 0.035 + bp * 0.006);
    let mp = vec2f((G.mouse.x - 0.5) * A * 2.0, (0.5 - G.mouse.y) * 2.0);

    // wind: strength by section + bass gusts; the cursor steers its direction
    var wind = 0.06 * wq + 0.35 * wv + (0.4 + 0.5 * bp) * wb + 0.9 * wd + 0.6 * wc + 0.05 * wk;
    wind = wind * (1.0 + 0.4 * G.bass) + 0.08 * noise2(vec2f(t * 0.4, 1.0));
    wind *= mix(1.0, clamp((G.mouse.x - 0.5) * 3.0, -1.5, 1.5), G.mouse_on);
    let rainA = clamp(0.55 * wv + (0.6 + 0.35 * bp) * wb + 1.0 * wd + 0.75 * wc, 0.0, 1.0);

    let hy = -0.3;                                   // horizon
    let moonP = vec2f(0.95, 0.62);
    let moonI = 0.25 * wq + 0.08 * wv + 0.03 * wb + 1.1 * kopen + 0.15 * wc;

    // ---- lightning sources: (x, intensity) ----
    // heat lightning: silent flicker low on the horizon
    let hx = (hash11(floor(t * 0.6) + 0.3) * 2.0 - 1.0) * A * 0.8;
    let flick = smoothstep(0.6, 0.85, noise2(vec2f(t * 2.6, 3.1))) * (0.65 + 0.35 * sin(t * 53.0)) + G.hat * 0.25;
    let hI = flick * (wq * 1.0 + wv * 0.35 + wk * 0.2);
    // snare: sheet flash inside the clouds (the build-up's tell)
    let snx = (hash11(bc * 1.7 + 0.3) * 2.0 - 1.0) * A * 0.85;
    let sI = G.snare * (0.3 * wv + (0.3 + 1.6 * bp) * wb + 0.6 * wc + 0.7 * wd);
    // kick: a bolt that reaches the sea (drop every kick, chorus every other beat, late build now and then)
    var kx = (hash11(bc * 3.7 + 1.0) * 2.0 - 1.0) * A * 0.75;
    kx = mix(kx, mp.x, G.mouse_on * 0.85);
    let kI = G.kick * (wd * 2.0 + wc * 0.9 * step(0.5, fract(bc * 0.5)) + bp * bp * 0.9 * step(0.55, hash11(bc)));
    // drop: a second bolt on snares
    let dx2 = (hash11(bc * 5.1 + 2.0) * 2.0 - 1.0) * A * 0.8;
    let dI2 = G.snare * wd * 1.6;
    // verse: a small far bolt on some snares
    let vx = (hash11(bc * 2.3 + 7.0) * 2.0 - 1.0) * A * 0.9;
    let vI = G.snare * (wv * 0.9 + wc * 0.5) * step(0.45, hash11(bc * 9.1));
    // click: a bolt strikes where you clicked
    let cpp = vec2f((G.click_pos.x - 0.5) * A * 2.0, (0.5 - G.click_pos.y) * 2.0);
    let cI = exp(-G.click_age * 3.0) * (0.6 + 0.4 * sin(G.click_age * 70.0)) * step(G.click_age, 1.6) * 1.8;
    let F0 = hI * 0.35 + sI + kI + dI2 + vI * 0.4 + cI;
    let F = F0 / (1.0 + 0.7 * F0);                     // overall light for the landscape, soft-limited

    // ======================= SKY =======================
    var col = vec3f(0.0);
    let skyT = smoothstep(hy, 1.1, p.y);
    col = mix(vec3f(0.05, 0.065, 0.11), vec3f(0.008, 0.012, 0.03), skyT);
    col += pal(0.5) * 0.05 * (1.0 - skyT) * (wq + wk);
    col += G.pal2.rgb * exp(-abs(p.y - hy) * 5.0) * wc * 0.5;     // chorus: warm light under the storm

    // stars
    let sg = p * 70.0;
    let sci = floor(sg);
    let sh = hash22(sci);
    let sdist = length(fract(sg) - 0.5 - (sh - 0.5) * 0.7);
    let tw = 0.6 + 0.4 * sin(t * (2.0 + sh.x * 4.0) + sh.y * 30.0) + G.hat * sh.x;
    let star = smoothstep(0.08, 0.0, sdist) * step(0.86, hash21(sci + 3.0)) * tw * smoothstep(hy + 0.05, hy + 0.5, p.y);

    // moon
    let md = length(p - moonP);
    let moonDisc = fill(md - 0.065, px);
    let moonTex = 0.82 + 0.18 * fbm2((p - moonP) * 30.0, 3);
    let moonCol = vec3f(0.95, 0.93, 0.85) * moonTex;
    let halo = exp(-md * 3.0) * 0.25 + exp(-md * 12.0) * 0.3;

    // ---- clouds: perspective deck rolling toward us, domain-warped fbm ----
    var cq = p;
    let cs = vec2f(0.0, 0.62);
    let rel = cq - cs;
    let rr = length(rel);
    cq = cs + rot(bp * 2.8 * exp(-rr * 1.3) + bp * t * 0.15) * rel * (1.0 + bp * 0.25 * smoothstep(1.2, 0.0, rr));  // build: converge + swirl
    let zz = 1.0 / (max(cq.y - hy, 0.0) + 0.22);
    var cp = vec2f(cq.x * zz * 0.55, zz * 0.9);
    cp += vec2f(t * 0.02 * (0.3 + wind), t * (0.04 + 0.1 * wind) + G.travel * 0.01);
    let oct = 4 + i32(G.quality > 1.5);
    let wrp = vec2f(sf_fbm(cp * 1.2 + vec2f(t * 0.03, 0.0), 3), sf_fbm(cp * 1.2 + vec2f(5.2, 1.3 - t * 0.02), 3));
    let n = sf_fbm(cp * 1.5 + wrp * 1.9, oct);
    let n2 = sf_fbm(cp * 3.3 + vec2f(t * 0.3 * wind, t * 0.08), 3);
    var cov = 0.18 * wq + 0.62 * wv + (0.68 + 0.27 * bp) * wb + 0.95 * wd + 0.72 * wc + 0.6 * wk;
    cov += wq * (0.42 * smoothstep(0.1, -0.25, p.y));                                    // quiet: a low bank on the horizon
    cov -= kopen * 0.9 * smoothstep(1.15, 0.2, length((p - moonP + vec2f(0.4, 0.15)) * vec2f(0.5, 0.9)));  // breakdown: the eye opens
    let cfield = n + n2 * 0.28;
    var dens = smoothstep(1.0 - cov, 1.16 - cov, cfield) * smoothstep(hy - 0.02, hy + 0.06, p.y);
    // painterly brush grain
    let brush = 0.85 + 0.3 * noise2(rot(0.25 + wind * 0.2) * p * vec2f(48.0, 5.0));
    let shade = smoothstep(0.35, 0.95, n2 + (n - 0.5) * 0.6);
    var ccol = mix(vec3f(0.035, 0.04, 0.06), vec3f(0.26, 0.26, 0.32), shade * shade) * brush;
    ccol *= 0.6 + 0.6 * smoothstep(0.3, 0.75, n);
    ccol = mix(ccol, ccol * G.pal1.rgb * 1.6, 0.25);
    ccol *= 0.75 + 0.5 * smoothstep(hy, 0.8, p.y) * (1.0 - wd * 0.5);
    // silver lining from the moon
    let rim = smoothstep(0.0, 0.5, dens) * smoothstep(1.0, 0.4, dens);
    ccol += vec3f(0.75, 0.8, 0.95) * rim * moonI * (0.15 + 1.4 * exp(-md * 1.6));
    ccol += vec3f(0.6, 0.65, 0.8) * moonI * 0.06 * exp(-md * 1.0);
    // lightning lights the clouds from inside
    var cl = 0.0;
    cl += hI * 1.6 * exp(-length((p - vec2f(hx, hy + 0.08)) * vec2f(0.8, 2.0)) * 2.5);
    cl += sI * 1.4 * exp(-length(p - vec2f(snx, 0.45)) * 1.6);
    cl += kI * 1.5 * exp(-length(p - vec2f(kx, 0.35)) * 1.4);
    cl += dI2 * 1.3 * exp(-length(p - vec2f(dx2, 0.4)) * 1.4);
    cl += vI * 1.0 * exp(-length(p - vec2f(vx, 0.05)) * 2.5);
    cl += cI * 1.2 * exp(-length(p - vec2f(cpp.x, 0.4)) * 1.5);
    ccol += mix(G.pal0.rgb, vec3f(1.0), 0.35) * (cl / (1.0 + 0.8 * cl)) * (0.25 + 0.6 * (1.0 - shade)) * brush;
    // chorus: broad sheet-lightning glow, pulsing with the beat, and warm underlight
    ccol += G.pal0.rgb * wc * (0.12 + 0.35 * pow(1.0 - ph, 3.0)) * (0.5 + 0.5 * noise2(p * 2.0 + bc));
    ccol += G.pal2.rgb * wc * 0.35 * smoothstep(0.5, -0.2, p.y) * (1.0 - shade * 0.5);
    // build-up: static charge crawling through the clouds
    let ridge = 1.0 - abs(2.0 * sf_nz(cp * 4.0 + vec2f(t * 1.7, -t * 1.1)) - 1.0);
    let ridge2 = 1.0 - abs(2.0 * sf_nz(cp * 9.0 - vec2f(t * 2.3, t * 0.7) + 3.0) - 1.0);
    let charge = (pow(ridge, 40.0) + pow(ridge2, 60.0) * 0.7) * dens * bp * (0.7 + 2.0 * G.high + 1.5 * G.snare);
    ccol += mix(G.pal1.rgb, G.pal0.rgb, ridge2) * charge * 2.2;

    // sky behind the clouds: stars, moon, chorus light rays, moonbow
    var behind = col + vec3f(0.85, 0.9, 1.0) * star * (wq + wk * 1.2 + wv * 0.25 + wc * 0.2) * 0.9;
    behind = mix(behind, moonCol * (0.5 + moonI), moonDisc * clamp(moonI * 2.0, 0.0, 1.0));
    behind += vec3f(0.6, 0.65, 0.8) * halo * moonI;
    let rang = atan2(p.x * 0.6, p.y - hy + 0.1);
    let rays = smoothstep(0.45, 0.8, noise2(vec2f(rang * 10.0, t * 0.15))) * smoothstep(hy, hy + 0.9, p.y) * smoothstep(1.2, 0.0, p.y);
    behind += G.pal2.rgb * rays * wc * 0.6;
    let bowR = length(p - vec2f(-0.3, -1.25));
    let bowB = (bowR - 1.38) / 0.09;
    let bow = smoothstep(0.0, 0.25, bowB) * smoothstep(1.0, 0.75, bowB) * smoothstep(hy, hy + 0.15, p.y);
    behind += hsv(0.82 - clamp(bowB, 0.0, 1.0) * 0.82, 0.55, 1.0) * bow * (wc * 0.35 + kopen * 0.1);
    col = mix(behind, ccol, dens);
    col += rays * G.pal2.rgb * wc * 0.15 * dens;
    col += mix(G.pal0.rgb, vec3f(1.0), 0.5) * F * 0.04 * smoothstep(hy - 0.1, 0.8, p.y);

    // rain curtains hanging from the cloud base
    let curt = fbm2(vec2f(p.x * 3.5 - p.y * wind * 0.9 + t * 0.15 * wind, p.y * 0.35 - t * 0.3), 3);
    let curtA = smoothstep(0.45, 0.75, curt) * smoothstep(hy - 0.02, hy + 0.15, p.y) * smoothstep(0.5, 0.05, p.y) * rainA;
    col = mix(col, vec3f(0.08, 0.09, 0.12) + G.pal0.rgb * F * 0.25 + G.pal2.rgb * wc * 0.15, curtA * 0.55);

    // ---- drop only: shelf cloud and a waterspout funnel ----
    if (wd > 0.01) {
        let ye = 0.2 + 0.06 * fbm2(vec2f(p.x * 1.8 + t * 0.25, 3.0), 3) + 0.025 * sin(p.x * 3.0 - t);
        if (p.y > ye - 0.01) {
            let sa = fill(ye - p.y, px * 3.0) * smoothstep(0.85, 0.4, p.y + 0.1 * noise2(vec2f(p.x * 3.0, t * 0.2)));
            let str = 0.5 + 0.5 * sin((p.y - ye) * 75.0 + fbm2(p * vec2f(1.4, 7.0) + vec2f(t * 0.3, 0.0), 3) * 9.0);
            var shelf = mix(vec3f(0.02, 0.04, 0.045), vec3f(0.1, 0.15, 0.16), str * 0.7) * brush;
            shelf += mix(G.pal0.rgb, vec3f(1.0), 0.3) * F * exp(-max(p.y - ye, 0.0) * 14.0) * (0.15 + 0.25 * str);
            col = mix(col, shelf, sa * wd);
        }
        let desc = select(1.0, smoothstep(0.0, 0.35, G.section_age), G.section == SEC_DROP);
        let fbot = mix(0.2, hy - 0.04, desc);
        let ftop = 0.25;
        if (p.y < ftop && p.y > fbot - 0.06) {
            let s = clamp((ftop - p.y) / (ftop - hy), 0.0, 1.0);
            let fx = -0.6 + 0.12 * sin(t * 0.35);
            let cx = fx + sin(p.y * 5.0 + t * 1.7) * 0.035 * s + s * s * 0.12;
            let w = mix(0.17, 0.022, pow(s, 0.42)) * (1.0 + 0.2 * G.bass);
            let fd = abs(p.x - cx) - w * (0.85 + 0.3 * noise2(vec2f(p.y * 20.0, t * 3.0)));
            let fa = fill(fd, px * 4.0) * smoothstep(fbot - 0.02, fbot + 0.04, p.y) * wd;
            let stripes = 0.5 + 0.5 * sin((p.x - cx) / w * 2.6 - t * 9.0 + p.y * 16.0);
            var fcol = vec3f(0.03, 0.04, 0.05) * (0.6 + 0.7 * stripes) + G.pal0.rgb * F * 0.12 * (1.0 - stripes * 0.5);
            fcol += vec3f(0.12, 0.14, 0.16) * smoothstep(-w, 0.0, fd) * 0.5;
            col = mix(col, fcol, fa * 0.92);
            // spray at the base where it touches the sea
            let sp = length((p - vec2f(cx, hy)) * vec2f(1.0, 2.2));
            let spray = smoothstep(0.17, 0.0, sp + 0.05 * noise2(p * 25.0 + vec2f(t * 4.0, 0.0))) * desc * wd;
            col = mix(col, vec3f(0.2, 0.23, 0.27) + G.pal0.rgb * F * 0.4, spray * 0.7);
        }
    }

    // ---- land above the horizon: headland with a lighthouse, low far coast ----
    let lh = sf_land(p.x);
    let landA = fill(p.y - (hy + lh), px) * step(hy - 0.005, p.y);
    if (landA > 0.0) {
        var lc = vec3f(0.012, 0.016, 0.022) * (0.8 + 0.4 * fbm2(p * 30.0, 3));
        lc += G.pal0.rgb * F * 0.12 * smoothstep(hy, hy + lh, p.y);
        lc += vec3f(0.5, 0.55, 0.7) * moonI * 0.04;
        lc += G.pal2.rgb * wc * 0.08;
        col = mix(col, lc, landA);
    }
    // lighthouse
    let lb = vec2f(1.24, hy + sf_land(1.24) - 0.005);
    let lq = p - lb;
    let lamp = lb + vec2f(0.0, 0.135);
    if (abs(lq.x) < 0.05 && lq.y > -0.01 && lq.y < 0.16) {
        let hw = mix(0.018, 0.011, clamp(lq.y / 0.12, 0.0, 1.0));
        let td = max(abs(lq.x) - hw, max(-lq.y, lq.y - 0.12));
        let cap = max(abs(lq.x) - 0.016, abs(lq.y - 0.142) - 0.012);
        let roof = max(abs(lq.x) - (0.018 - (lq.y - 0.154) * 0.9), abs(lq.y - 0.162) - 0.008);
        var lt = vec3f(0.06, 0.06, 0.07);
        if (fract(lq.y * 25.0) < 0.5) { lt = vec3f(0.12, 0.02, 0.02); }
        lt *= 0.6 + 0.8 * smoothstep(0.02, -0.02, lq.x);
        lt += G.pal0.rgb * F * 0.15;
        col = mix(col, lt, fill(td, px));
        col = mix(col, vec3f(0.03), fill(roof, px));
        col = mix(col, G.pal2.rgb * 2.5, fill(cap, px) * 0.9);
    }
    // the sweeping beam, brighter in rain; flares when it faces us. St Elmo's fire in the build-up.
    let bphi = t * 0.9 + G.beat_count * 0.05;
    let bdir = normalize(vec2f(cos(bphi), -0.035));
    let br = p - lamp;
    let bal = dot(br, bdir);
    let bperp = abs(br.x * bdir.y - br.y * bdir.x);
    let beam = smoothstep(0.1 * bal + 0.006, 0.03 * bal, bperp) * step(0.0, bal) * exp(-bal * 0.9) * abs(cos(bphi));
    let lampI = 0.6 + 0.4 * wq + 0.5 * rainA;
    col += G.pal2.rgb * beam * lampI * (0.25 + 0.3 * rainA) * (0.8 + 0.4 * noise2(p * 8.0 + vec2f(t, 0.0)));
    col += G.pal2.rgb * (glow(length(br), 0.006) * 0.5 + pow(max(sin(bphi), 0.0), 12.0) * glow(length(br), 0.04) * 1.2) * lampI;
    col += mix(G.pal1.rgb, G.pal0.rgb, 0.5) * bp * glow(length(p - lamp - vec2f(0.0, 0.04)), 0.01 + 0.01 * G.snare) * (0.6 + 0.6 * sin(t * 40.0));

    // ---- lightning bolts ----
    var bl = 0.0;
    if (kI > 0.01) { bl += sf_bolt_light(sf_bolt(p, kx, 0.38, -0.46, bc + 0.17), px) * kI; }
    if (dI2 > 0.01) { bl += sf_bolt_light(sf_bolt(p, dx2, 0.42, hy - 0.04, bc + 31.3), px) * dI2; }
    if (vI > 0.01) { bl += sf_bolt_light(sf_bolt((p - vec2f(vx, hy)) * 2.2 + vec2f(vx, hy), vx, hy + 0.7, hy, bc + 57.0), px * 2.2) * vI * 0.6; }
    if (cI > 0.01) { bl += sf_bolt_light(sf_bolt(p, cpp.x, 0.45, max(cpp.y, -0.5), 77.0 + floor(G.click_pos.x * 100.0)), px) * cI; }
    col += mix(G.pal0.rgb, vec3f(1.0), 0.6) * bl;

    // ======================= SEA =======================
    let ys = -0.62 + 0.05 * sin(p.x * 1.3 + 0.5) + 0.03 * fbm2(vec2f(p.x * 2.0, 5.0), 3);
    if (p.y < hy) {
        let wz = 1.0 / (hy - p.y + 0.04);
        let wamp = 0.25 + wind * 0.9 + G.kick * wd * 0.6;
        let wvn = fbm2(vec2f(p.x * wz * 0.7 + t * 0.15 * wind, wz * 2.2 - t * (0.4 + 0.6 * wind) - ph * 0.3 * wd), 3);
        let uvh = (1.0 - hy) * 0.5;
        let ruv = vec2f(uv.x + (wvn - 0.5) * 0.02 * wamp, 2.0 * uvh - uv.y + (wvn - 0.5) * 0.06 * wamp / wz * 4.0);
        let refl = prev(clamp(ruv, vec2f(0.001), vec2f(0.999)));
        let fres = mix(0.35, 0.8, smoothstep(hy - 0.35, hy, p.y));
        var sea = vec3f(0.01, 0.018, 0.03) + refl * fres * (0.6 + 0.4 * wvn);
        let caps = smoothstep(0.72, 0.8, wvn + 0.25 * noise2(vec2f(p.x * wz * 3.0, wz * 6.0 - t * 2.0))) * clamp(wind - 0.2, 0.0, 1.0);
        sea += (vec3f(0.25, 0.28, 0.32) + G.pal0.rgb * F * 0.6 + G.pal2.rgb * wc * 0.4) * caps * 0.6;
        // moon glitter path and strike glows
        let glit = pow(noise2(vec2f(p.x * wz * 4.0, wz * 9.0 - t * 1.5)), 5.0) * exp(-abs(p.x - moonP.x) * (2.5 + 0.3 * wz));
        sea += vec3f(0.9, 0.9, 0.8) * glit * moonI * 2.0;
        sea += mix(G.pal0.rgb, vec3f(1.0), 0.5) * kI * exp(-length((p - vec2f(kx, -0.46)) * vec2f(1.0, 3.0)) * 6.0) * 0.8;
        sea += G.pal2.rgb * wc * 0.25 * exp(-(hy - p.y) * 5.0);
        col = sea;
    }

    // ======================= SHORE + GRASS =======================
    if (p.y < ys + 0.15) {
        // dunes below the shore line
        if (p.y < ys) {
            let gz = clamp((ys - p.y) / 0.4, 0.0, 1.0);
            var g = mix(vec3f(0.07, 0.068, 0.06), vec3f(0.03, 0.034, 0.03), gz);
            g *= 0.75 + 0.5 * fbm2(p * vec2f(14.0, 40.0), 3);
            let wave = 0.5 + 0.5 * sin(p.x * 4.0 - t * (1.0 + 3.0 * wind) + fbm2(p * 3.0, 2) * 4.0);
            g += vec3f(0.04, 0.05, 0.035) * wave * wind * (1.0 - gz);
            g += G.pal0.rgb * F * 0.08 * (1.0 - gz) + vec3f(0.4, 0.45, 0.6) * moonI * 0.03 + G.pal2.rgb * wc * 0.06;
            col = mix(col, g, fill(p.y - ys, px));
            // surf line
            col += vec3f(0.3, 0.33, 0.38) * exp(-abs(p.y - ys + 0.004) / 0.004) * (0.3 + 0.5 * noise2(vec2f(p.x * 20.0 - t * 2.0, 0.0))) * (0.3 + wind);
        }
        let back = sf_grass(p, ys - 0.01, 0.12, 90.0, wind * 0.9, t, 1.0, px);
        let bgc = vec3f(0.02, 0.025, 0.018) + G.pal0.rgb * F * 0.05 + G.pal2.rgb * wc * 0.05;
        col = mix(col, bgc, back);
    }
    // foreground grass, taller toward the sides, rim-lit by lightning and moon
    let fh = 0.55 * (0.35 + 0.65 * smoothstep(0.2, 1.5, abs(p.x)));
    let front = sf_grass(p, -1.04, fh, 34.0, wind * 1.2, t * 1.1, 9.0, px);
    if (front > 0.0) {
        let s = clamp((p.y + 1.04) / fh, 0.0, 1.0);
        var fgc = vec3f(0.004, 0.006, 0.004) + vec3f(0.05, 0.06, 0.035) * s * s;
        fgc += vec3f(0.25, 0.3, 0.2) * smoothstep(0.75, 1.0, s) * (0.15 + F * 0.6 + moonI * 0.3);
        fgc += mix(G.pal0.rgb, vec3f(1.0), 0.3) * F * 0.18 * s + vec3f(0.5, 0.55, 0.7) * moonI * 0.05 * s + G.pal2.rgb * wc * 0.12 * s;
        col = mix(col, fgc, front);
    }

    // ======================= RAIN =======================
    if (rainA > 0.01) {
        let ra = -0.12 - wind * 0.35;
        let rq = rot(ra) * p;
        for (var l = 0; l < 3; l++) {
            let fl = f32(l);
            let nx = 90.0 - fl * 28.0;
            let gx = rq.x * nx;
            let ci = floor(gx);
            let h = hash11(ci * 1.37 + fl * 11.0);
            let yy = rq.y * (0.9 - fl * 0.2) + t * (2.4 + h + fl * 0.8) + h * 13.0;
            let cell = floor(yy);
            let fy = fract(yy);
            let on = step(hash21(vec2f(ci, cell + fl * 7.0)), rainA * (0.55 + fl * 0.1));
            let dxs = abs(fract(gx) - 0.5 - (h - 0.5) * 0.5) / nx;
            let streak = fill(dxs - px * (0.35 + fl * 0.4), px) * smoothstep(0.0, 0.05, fy) * smoothstep(0.32 + fl * 0.1, 0.1, fy) * on;
            let rcol = vec3f(0.35, 0.4, 0.5) * (0.12 + 0.05 * fl) + mix(G.pal0.rgb, vec3f(1.0), 0.4) * F * 0.35 + G.pal2.rgb * wc * 0.15 + G.pal2.rgb * beam * 0.6;
            col += rcol * streak * (0.6 + 0.4 * G.hat);
        }
    }
    // breakdown: the rain hangs in the air, glinting with the melody
    if (wk > 0.01) {
        for (var l = 0; l < 2; l++) {
            let fl = f32(l);
            let sc2 = 14.0 + fl * 9.0;
            let q = p * sc2 + vec2f(sin(t * 0.15 + fl) * 0.6, t * (0.06 + 0.25 * G.mid) * (1.0 + fl));
            let ci = floor(q);
            let h = hash22(ci + fl * 31.0);
            let dd = length(fract(q) - 0.5 - (h - 0.5) * 0.7);
            let sp = spec(0.05 + h.x * 0.7);
            let hang = smoothstep(0.07, 0.02, dd) * step(0.55, hash21(ci + 9.0 + fl));
            let rimd = exp(-abs(dd - 0.05) * 60.0) * step(0.55, hash21(ci + 9.0 + fl)) * 0.4;
            col += (vec3f(0.65, 0.72, 0.9) * (0.15 + moonI * 0.25) + G.pal1.rgb * sp * 1.2) * (hang * 0.6 + rimd) * wk;
        }
    }

    // flash brightens everything for a moment
    col += mix(G.pal0.rgb, vec3f(1.0), 0.5) * F * 0.015;
    col *= 1.0 + 0.2 * wc;
    col *= 1.0 - 0.4 * pow(length(uv - 0.5) * 1.25, 2.2);
    return vec4f(col, 1.0);
}
