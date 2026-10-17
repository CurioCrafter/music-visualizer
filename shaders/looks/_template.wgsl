// name: Template
// palette: #ff28c8 #9628ff #28dcff
// A minimal look: spectrum bars + beat flash. Copy this to start a new look.

fn look(fc: vec2f) -> vec4f {
    let uv = fc / G.res;
    let p = centered(fc);
    var col = vec3f(0.02, 0.0, 0.05);
    let v = spec(uv.x);
    let bar = step(1.0 - uv.y, v * 0.9) * step(0.15, fract(uv.x * 64.0));
    col += pal(uv.x) * bar * 1.2;
    col += pal(0.5) * G.kick * 0.25 * glow(length(p) - 0.3, 0.2);
    col = mix(col, prev(uv) * 0.9, 0.5);
    return vec4f(col, 1.0);
}
