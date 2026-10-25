//! The looks: one WGSL file each in shaders/looks, embedded into the exe.
//! Each file starts with header comments the app reads:
//!   // name: Bass Drop
//!   // palette: #ff28c8 #9628ff #28dcff

pub struct Look {
    pub file: &'static str,
    pub src: &'static str,
}

macro_rules! look {
    ($f:literal) => {
        Look { file: $f, src: include_str!(concat!("../shaders/looks/", $f)) }
    };
}

pub const LOOKS: &[Look] = &[
    look!("bass_drop.wgsl"),
    look!("ferrofluid.wgsl"),
    look!("data_bus.wgsl"),
    look!("pulse_ring.wgsl"),
    look!("neon_horizon.wgsl"),
    look!("reef_arcade.wgsl"),
    look!("deep_wreck.wgsl"),
    look!("moonlight_piano.wgsl"),
    look!("aurora.wgsl"),
    look!("classic_bars.wgsl"),
    look!("storm_front.wgsl"),
    look!("volcano_forge.wgsl"),
    look!("hyperspace.wgsl"),
    look!("neon_city.wgsl"),
    look!("kaleido_temple.wgsl"),
    look!("ink_bloom.wgsl"),
];

pub fn header(src: &str, key: &str) -> Option<String> {
    src.lines()
        .take(12)
        .find_map(|l| l.trim().strip_prefix("//").and_then(|r| r.trim().strip_prefix(key)).map(|v| v.trim_start_matches(':').trim().to_string()))
}

pub fn name(src: &str) -> String {
    header(src, "name").unwrap_or_else(|| "Look".into())
}

fn hex(s: &str) -> Option<[f32; 4]> {
    let s = s.trim_start_matches('#');
    if s.len() != 6 {
        return None;
    }
    let v = u32::from_str_radix(s, 16).ok()?;
    Some([((v >> 16) & 255) as f32 / 255.0, ((v >> 8) & 255) as f32 / 255.0, (v & 255) as f32 / 255.0, 1.0])
}

pub fn palette(src: &str) -> [[f32; 4]; 3] {
    let mut p = [[1.0, 0.3, 0.8, 1.0], [0.6, 0.2, 1.0, 1.0], [0.2, 0.85, 1.0, 1.0]];
    if let Some(h) = header(src, "palette") {
        for (i, c) in h.split_whitespace().filter_map(hex).take(3).enumerate() {
            p[i] = c;
        }
    }
    p
}
