// Post-processing + the glass UI, drawn on the GPU.
// Passes: bright (scene -> 1/4 res), blur_h, blur_v (bloom), composite (scene + bloom + glass + text).

struct Rect {
    r: vec4f,   // x, y, w, h in screen pixels
    p: vec4f,   // radius, alpha, hot (hover 0..1), kind (0 glass, 1 dark glass for text, 2 album art, 3 hover tint, 4 accent pill)
    q: vec4f,   // shine (0..1 sweeping, <0 none), press, _, _
}

struct Ui {
    screen: vec2f,
    count: f32,
    beat: f32,
    accent: vec4f,
    fx: vec4f,          // x = bloom strength, y = vignette, z = edge glow (beat), w = fullscreen
    text_alpha: vec4f,  // alpha for text channels r (buttons) g (look name) b (song) a (panel/hint)
    rects: array<Rect, 32>,
}

@group(0) @binding(0) var<uniform> U: Ui;
@group(0) @binding(1) var scene: texture_2d<f32>;
@group(0) @binding(2) var bloom: texture_2d<f32>;
@group(0) @binding(3) var lin: sampler;
@group(0) @binding(4) var textmask: texture_2d<f32>;
@group(0) @binding(5) var art: texture_2d<f32>;

struct VOut { @builtin(position) pos: vec4f, @location(0) uv: vec2f }

@vertex
fn vs_post(@builtin(vertex_index) i: u32) -> VOut {
    let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
    var o: VOut;
    o.pos = vec4f(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = vec2f(p.x, 1.0 - p.y);
    return o;
}

// ---------- bloom ----------
@fragment
fn fs_bright(v: VOut) -> @location(0) vec4f {
    let px = 1.0 / vec2f(textureDimensions(scene));
    var c = vec3f(0.0);
    for (var y = -1; y <= 1; y++) {
        for (var x = -1; x <= 1; x++) {
            c += textureSampleLevel(scene, lin, v.uv + vec2f(f32(x), f32(y)) * px * 1.5, 0.0).rgb;
        }
    }
    c /= 9.0;
    let l = max(c.r, max(c.g, c.b));
    let k = smoothstep(0.45, 1.1, l);
    return vec4f(c * k, 1.0);
}

fn blur(uv: vec2f, dir: vec2f) -> vec4f {
    let px = dir / vec2f(textureDimensions(scene));
    let w = array<f32, 5>(0.227, 0.1946, 0.1216, 0.054, 0.0162);
    var c = textureSampleLevel(scene, lin, uv, 0.0).rgb * w[0];
    for (var i = 1; i < 5; i++) {
        let o = px * f32(i) * 1.6;
        c += textureSampleLevel(scene, lin, uv + o, 0.0).rgb * w[i];
        c += textureSampleLevel(scene, lin, uv - o, 0.0).rgb * w[i];
    }
    return vec4f(c, 1.0);
}
@fragment fn fs_blur_h(v: VOut) -> @location(0) vec4f { return blur(v.uv, vec2f(1.0, 0.0)); }
@fragment fn fs_blur_v(v: VOut) -> @location(0) vec4f { return blur(v.uv, vec2f(0.0, 1.0)); }

// ---------- composite ----------
fn tonemap(c: vec3f) -> vec3f {
    // linear up to 0.8, then a soft shoulder to 1 so bright glows don't clip harshly
    let k = 0.8;
    let over = max(c - vec3f(k), vec3f(0.0));
    return min(c, vec3f(k)) + (1.0 - k) * (1.0 - exp(-over * 4.0));
}

fn base(uv: vec2f) -> vec3f {
    var c = textureSampleLevel(scene, lin, uv, 0.0).rgb + textureSampleLevel(bloom, lin, uv, 0.0).rgb * U.fx.x;
    let d = uv - 0.5;
    c *= 1.0 - U.fx.y * dot(d, d) * 1.6;
    return tonemap(c);
}

// frosted backdrop: 16 taps in a golden-angle spiral
fn frosted(uv: vec2f, radius: f32) -> vec3f {
    var c = vec3f(0.0);
    for (var i = 0; i < 16; i++) {
        let fi = f32(i);
        let r = sqrt((fi + 0.5) / 16.0) * radius;
        let a = fi * 2.39996;
        c += base(uv + vec2f(cos(a), sin(a)) * r / U.screen);
    }
    return c / 16.0;
}

fn sd_round_box(p: vec2f, b: vec2f, r: f32) -> f32 {
    let q = abs(p) - b + vec2f(r);
    return length(max(q, vec2f(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

@fragment
fn fs_composite(v: VOut) -> @location(0) vec4f {
    let px = v.pos.xy;
    let uv = px / U.screen;
    var col = base(uv);

    for (var i = 0; i < i32(U.count); i++) {
        let R = U.rects[i];
        let a = R.p.y;
        if (a < 0.005) { continue; }
        let half = R.r.zw * 0.5;
        let c = R.r.xy + half;
        let rad = min(R.p.x, min(half.x, half.y));
        let kind = i32(R.p.w);
        let d = sd_round_box(px - c, half, rad);

        if (kind == 3) { // hover tint
            col = mix(col, col + vec3f(0.12), a * clamp(0.5 - d, 0.0, 1.0));
            continue;
        }
        if (kind == 4) { // accent pill (switch "on")
            col = mix(col, U.accent.rgb, a * 0.85 * clamp(0.5 - d, 0.0, 1.0));
            continue;
        }

        // soft drop shadow
        let ds = sd_round_box(px - c - vec2f(0.0, 3.0), half, rad);
        col *= 1.0 - 0.28 * a * (1.0 - smoothstep(-2.0, 10.0, ds)) * step(0.0, d);

        if (d < 1.0) {
            let inside = clamp(0.5 - d, 0.0, 1.0);
            let yy = (px.y - R.r.y) / R.r.w;
            var g = frosted(uv, 14.0);
            if (kind == 2) {
                g = textureSampleLevel(art, lin, (px - R.r.xy) / R.r.zw, 0.0).rgb;
            } else {
                g = mix(g, vec3f(1.0), 0.2 + 0.1 * R.p.z);                    // white frost
                if (kind == 1) { g = mix(g, vec3f(0.03, 0.05, 0.1), 0.45); }  // darker for text
                g = mix(g, U.accent.rgb, 0.07);
                g += vec3f(0.22) * (1.0 - smoothstep(0.0, 0.55, yy));          // light from above
                g += vec3f(0.10) * smoothstep(0.6, 1.0, yy);                   // bounce from below
                // gloss crescent
                let gp = vec2f((px.x - c.x) / half.x, (px.y - R.r.y) / R.r.w);
                g += vec3f(0.18) * (1.0 - smoothstep(0.0, 0.42, gp.y)) * (1.0 - smoothstep(0.55, 0.95, abs(gp.x)));
                // sweeping shine on hover
                let sh = R.q.x;
                if (sh >= 0.0 && sh <= 1.0) {
                    let pos = R.r.x - R.r.w * 2.0 + (R.r.z + R.r.w * 4.0) * sh;
                    let dist = abs((px.x - pos) - (R.r.y + R.r.w - px.y) * 0.5);
                    g += vec3f(0.45) * sin(sh * 3.14159) * (1.0 - smoothstep(0.0, R.r.w * 0.3, dist));
                }
                g *= 1.0 - 0.15 * R.q.y; // pressed
            }
            // bright rim (glints on the beat), lit from the top
            let edge = 1.0 - smoothstep(0.0, 1.6, abs(d + 0.7));
            let light = mix(0.9, 0.3, yy) + U.beat * 0.35;
            g = mix(g, vec3f(1.0), edge * clamp(light, 0.0, 1.0));
            col = mix(col, g, inside * a);
        }
        // dark hairline outside so glass shows up on bright looks too
        col = mix(col, vec3f(0.0), 0.3 * a * (1.0 - smoothstep(0.0, 1.4, abs(d - 1.0))));
    }

    // text + icons: 4 channels with their own fade, with a soft shadow
    let ts = vec2i(textureDimensions(textmask));
    let ip = vec2i(px);
    if (ip.x < ts.x && ip.y < ts.y) {
        let m = textureLoad(textmask, ip, 0) * U.text_alpha;
        let sp = clamp(ip - vec2i(1, 1), vec2i(0), ts - 1);
        let s = textureLoad(textmask, sp, 0) * U.text_alpha;
        let shadow = max(max(s.r, s.g), max(s.b, s.a));
        col = mix(col, vec3f(0.0), shadow * 0.55);
        let t = max(max(m.r, m.g), max(m.b, m.a));
        col = mix(col, vec3f(1.0), t);
    }

    // window edge glows on the beat
    if (U.fx.z > 0.01) {
        let half = U.screen * 0.5;
        let d = sd_round_box(px - half, half - vec2f(0.5), select(9.0, 0.5, U.fx.w > 0.5));
        let e = (1.0 - smoothstep(0.0, 6.0, -d)) * U.fx.z;
        col = mix(col, mix(U.accent.rgb, vec3f(1.0), 0.3), e * 0.8);
    }
    return vec4f(col, 1.0);
}
