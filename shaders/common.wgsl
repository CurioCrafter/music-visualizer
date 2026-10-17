// ============================================================================================
//  common.wgsl - shared by every look, in the Windows app AND the Chrome extension.
//  A look file only defines:   fn look(fc: vec2f) -> vec4f
//  fc = pixel coordinate (origin top-left, y down), return colour in display space (0..1,
//  values above 1 are fine: they bloom). Alpha is ignored.
// ============================================================================================

struct Globals {
    res: vec2f,          // render size in pixels
    time: f32,           // seconds since start
    dt: f32,             // seconds since last frame
    mouse: vec2f,        // 0..1, (0,0) = top-left. Sits at (0.5,0.5) while mouse control is off
    mouse_on: f32,       // 1 while mouse control is on and the cursor is over the window
    click_age: f32,      // seconds since the last click (999 if none)
    click_pos: vec2f,    // 0..1 where the last click happened
    bass: f32,           // 0..1 sub + bass loudness (smoothed)
    mid: f32,            // 0..1
    high: f32,           // 0..1
    vol: f32,            // RMS loudness, ~0..0.5
    beat: f32,           // 1 on every beat, decays to 0 in ~0.33 s
    drop: f32,           // 1 when the bass slams back in after a break ("the drop"), decays in ~1.4 s
    beat_count: f32,     // number of beats so far
    travel: f32,         // distance flown: grows faster when the music is louder. Use for forward motion
    quality: f32,        // 0 low, 1 balanced, 2 high: scale loop counts with it
    aspect: f32,         // res.x / res.y
    kick: f32,           // 1 on a kick drum hit, fast decay
    snare: f32,          // 1 on a snare / clap hit, fast decay
    hat: f32,            // 1 on a hi-hat / cymbal tick, very fast decay
    flux: f32,           // 0..1 how much the sound is changing right now (busy-ness)
    centroid: f32,       // 0..1 brightness of the sound (dark/bassy -> bright/airy)
    energy: f32,         // 0..1 slow loudness of this section (quiet verse -> big chorus)
    beat_phase: f32,     // 0..1 position inside the current beat, from the tempo tracker
    bpm: f32,            // estimated tempo
    look_time: f32,      // seconds since this look was switched on
    _pad0: f32,
    _pad1: f32,
    _pad2: f32,
    pal0: vec4f,         // palette stop 0 (rgb) - album-art colours when enabled
    pal1: vec4f,
    pal2: vec4f,
}

@group(0) @binding(0) var<uniform> G: Globals;
// audio texture, R32Float, 256 x 66, read with textureLoad (helpers below)
//   row 0, x 0..95  : smoothed spectrum, 96 log bands 25 Hz .. 16 kHz, 0..1
//   row 0, x 96..183: piano key glow A0..C8 (88 keys), 0..1
//   row 1, x 0..255 : waveform, newest 256 samples, -1..1
//   rows 2..65      : spectrum history, row 2 = newest, one row per 1/20 s (3.2 s total)
@group(0) @binding(1) var audio: texture_2d<f32>;
// the previous frame of this look (same size) - for trails, feedback, smoke
@group(0) @binding(2) var prev_tex: texture_2d<f32>;
@group(0) @binding(3) var samp: sampler;

const PI: f32 = 3.14159265;
const TAU: f32 = 6.2831853;

// ---------- audio helpers ----------
fn band(i: i32) -> f32 { return textureLoad(audio, vec2i(clamp(i, 0, 95), 0), 0).r; }
// spectrum at x 0..1 (bass -> treble), interpolated
fn spec(x: f32) -> f32 {
    let f = clamp(x, 0.0, 1.0) * 95.0;
    let i = i32(floor(f));
    return mix(band(i), band(i + 1), fract(f));
}
// spectrum between band indices a..b (0..95) at x 0..1
fn spec_range(x: f32, a: f32, b: f32) -> f32 { return spec(mix(a, b, clamp(x, 0.0, 1.0)) / 95.0); }
fn band_avg(a: i32, b: i32) -> f32 {
    var s = 0.0;
    for (var i = a; i <= b; i++) { s += band(i); }
    return s / f32(b - a + 1);
}
// history: x 0..1 band, age 0..1 (0 = now, 1 = 3.2 s ago)
fn hist(x: f32, age: f32) -> f32 {
    let f = clamp(x, 0.0, 1.0) * 95.0;
    let r = 2 + i32(clamp(age, 0.0, 1.0) * 63.0);
    let i = i32(floor(f));
    return mix(textureLoad(audio, vec2i(i, r), 0).r, textureLoad(audio, vec2i(min(i + 1, 95), r), 0).r, fract(f));
}
// waveform at x 0..1, -1..1
fn wave(x: f32) -> f32 {
    let f = clamp(x, 0.0, 1.0) * 255.0;
    let i = i32(floor(f));
    return mix(textureLoad(audio, vec2i(i, 1), 0).r, textureLoad(audio, vec2i(min(i + 1, 255), 1), 0).r, fract(f));
}
// piano key glow, k = 0 (A0) .. 87 (C8)
fn key(k: i32) -> f32 { return textureLoad(audio, vec2i(96 + clamp(k, 0, 87), 0), 0).r; }
fn is_black_key(k: i32) -> bool { let n = k % 12; return n == 1 || n == 4 || n == 6 || n == 9 || n == 11; }

// ---------- colour ----------
fn pal(x: f32) -> vec3f {
    let t = clamp(x, 0.0, 1.0) * 2.0;
    if (t < 1.0) { return mix(G.pal0.rgb, G.pal1.rgb, t); }
    return mix(G.pal1.rgb, G.pal2.rgb, t - 1.0);
}
// cyclic palette (wraps 0 -> 1 -> 2 -> 0)
fn palc(x: f32) -> vec3f {
    let t = fract(x) * 3.0;
    if (t < 1.0) { return mix(G.pal0.rgb, G.pal1.rgb, t); }
    if (t < 2.0) { return mix(G.pal1.rgb, G.pal2.rgb, t - 1.0); }
    return mix(G.pal2.rgb, G.pal0.rgb, t - 2.0);
}
fn hsv(h: f32, s: f32, v: f32) -> vec3f {
    let k = vec3f(1.0, 2.0 / 3.0, 1.0 / 3.0);
    let p = abs(fract(vec3f(h) + k) * 6.0 - 3.0);
    return v * mix(vec3f(1.0), clamp(p - 1.0, vec3f(0.0), vec3f(1.0)), s);
}
fn luma(c: vec3f) -> f32 { return dot(c, vec3f(0.299, 0.587, 0.114)); }

// ---------- maths / noise ----------
fn rot(a: f32) -> mat2x2f { let c = cos(a); let s = sin(a); return mat2x2f(c, s, -s, c); }
fn hash11(p: f32) -> f32 { return fract(sin(p * 127.1) * 43758.5453); }
fn hash21(p: vec2f) -> f32 { return fract(sin(dot(p, vec2f(127.1, 311.7))) * 43758.5453); }
fn hash22(p: vec2f) -> vec2f {
    return fract(sin(vec2f(dot(p, vec2f(127.1, 311.7)), dot(p, vec2f(269.5, 183.3)))) * 43758.5453);
}
fn hash31(p: vec3f) -> f32 { return fract(sin(dot(p, vec3f(127.1, 311.7, 74.7))) * 43758.5453); }
fn noise2(p: vec2f) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2f(1.0, 0.0)), u.x),
               mix(hash21(i + vec2f(0.0, 1.0)), hash21(i + vec2f(1.0, 1.0)), u.x), u.y);
}
fn noise3(p: vec3f) -> f32 {
    let i = floor(p); let f = fract(p);
    let u = f * f * (3.0 - 2.0 * f);
    let a = mix(mix(hash31(i), hash31(i + vec3f(1, 0, 0)), u.x), mix(hash31(i + vec3f(0, 1, 0)), hash31(i + vec3f(1, 1, 0)), u.x), u.y);
    let b = mix(mix(hash31(i + vec3f(0, 0, 1)), hash31(i + vec3f(1, 0, 1)), u.x), mix(hash31(i + vec3f(0, 1, 1)), hash31(i + vec3f(1, 1, 1)), u.x), u.y);
    return mix(a, b, u.z);
}
fn fbm2(p0: vec2f, oct: i32) -> f32 {
    var p = p0; var a = 0.5; var s = 0.0;
    for (var i = 0; i < oct; i++) { s += a * noise2(p); p = p * 2.03 + vec2f(1.7, 9.2); a *= 0.5; }
    return s;
}
fn fbm3(p0: vec3f, oct: i32) -> f32 {
    var p = p0; var a = 0.5; var s = 0.0;
    for (var i = 0; i < oct; i++) { s += a * noise3(p); p = p * 2.03 + vec3f(1.7, 9.2, 3.1); a *= 0.5; }
    return s;
}

// ---------- 2D shapes (signed distances, negative inside) ----------
fn sd_circle(p: vec2f, r: f32) -> f32 { return length(p) - r; }
fn sd_box(p: vec2f, b: vec2f) -> f32 { let d = abs(p) - b; return length(max(d, vec2f(0.0))) + min(max(d.x, d.y), 0.0); }
fn sd_round_box(p: vec2f, b: vec2f, r: f32) -> f32 { return sd_box(p, b - vec2f(r)) - r; }
fn sd_segment(p: vec2f, a: vec2f, b: vec2f) -> f32 {
    let pa = p - a; let ba = b - a;
    let h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * h);
}
// soft fill / glow from a distance (px = size of one pixel in the same units)
fn fill(d: f32, px: f32) -> f32 { return clamp(0.5 - d / px, 0.0, 1.0); }
fn glow(d: f32, r: f32) -> f32 { return r / (r + max(d, 0.0)); }

// ---------- previous frame ----------
fn prev(uv: vec2f) -> vec3f { return textureSampleLevel(prev_tex, samp, uv, 0.0).rgb; }

// centred coords: y up, height = 2 (-1..1), x = -aspect..aspect
fn centered(fc: vec2f) -> vec2f { return vec2f((fc.x - 0.5 * G.res.x), (0.5 * G.res.y - fc.y)) / (0.5 * G.res.y); }

// ---------- pipeline entry points (do not change) ----------
@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
    let p = vec2f(f32((i << 1u) & 2u), f32(i & 2u));
    return vec4f(p * 2.0 - 1.0, 0.0, 1.0);
}

@fragment
fn fs_main(@builtin(position) p: vec4f) -> @location(0) vec4f {
    let c = look(p.xy);
    return vec4f(max(c.rgb, vec3f(0.0)), 1.0);
}
