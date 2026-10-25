//! GPU renderer: the look (a WGSL fragment shader) renders into an HDR scene target with feedback
//! from its previous frame, then bloom, then the composite pass adds the glass UI and text.

use bytemuck::{Pod, Zeroable};

pub const SCENE_FMT: wgpu::TextureFormat = wgpu::TextureFormat::Rgba16Float;
pub const AUDIO_W: u32 = 256;
pub const AUDIO_H: u32 = 66;
pub const MAX_RECTS: usize = 32;

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable, Default)]
pub struct Globals {
    pub res: [f32; 2],
    pub time: f32,
    pub dt: f32,
    pub mouse: [f32; 2],
    pub mouse_on: f32,
    pub click_age: f32,
    pub click_pos: [f32; 2],
    pub bass: f32,
    pub mid: f32,
    pub high: f32,
    pub vol: f32,
    pub beat: f32,
    pub drop: f32,
    pub beat_count: f32,
    pub travel: f32,
    pub quality: f32,
    pub aspect: f32,
    pub kick: f32,
    pub snare: f32,
    pub hat: f32,
    pub flux: f32,
    pub centroid: f32,
    pub energy: f32,
    pub beat_phase: f32,
    pub bpm: f32,
    pub look_time: f32,
    pub section: f32,
    pub section_prev: f32,
    pub section_age: f32,
    pub pal0: [f32; 4],
    pub pal1: [f32; 4],
    pub pal2: [f32; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable, Default)]
pub struct Rect {
    pub r: [f32; 4],
    pub p: [f32; 4],
    pub q: [f32; 4],
}

#[repr(C)]
#[derive(Clone, Copy, Pod, Zeroable)]
pub struct Ui {
    pub screen: [f32; 2],
    pub count: f32,
    pub beat: f32,
    pub accent: [f32; 4],
    pub fx: [f32; 4],
    pub text_alpha: [f32; 4],
    pub rects: [Rect; MAX_RECTS],
}
impl Default for Ui {
    fn default() -> Self { Zeroable::zeroed() }
}

pub const COMMON_WGSL: &str = include_str!("../shaders/common.wgsl");
const POST_WGSL: &str = include_str!("../shaders/post.wgsl");

struct Target {
    tex: wgpu::Texture,
    view: wgpu::TextureView,
}

fn target(device: &wgpu::Device, w: u32, h: u32, fmt: wgpu::TextureFormat, label: &str) -> Target {
    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: Some(label),
        size: wgpu::Extent3d { width: w.max(1), height: h.max(1), depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: fmt,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT | wgpu::TextureUsages::TEXTURE_BINDING | wgpu::TextureUsages::COPY_DST | wgpu::TextureUsages::COPY_SRC,
        view_formats: &[],
    });
    let view = tex.create_view(&Default::default());
    Target { tex, view }
}

pub struct Renderer {
    pub device: wgpu::Device,
    pub queue: wgpu::Queue,
    out_fmt: wgpu::TextureFormat,
    look_layout: wgpu::BindGroupLayout,
    look_pl: wgpu::PipelineLayout,
    look_pipe: Option<wgpu::RenderPipeline>,
    post_layout: wgpu::BindGroupLayout,
    p_bright: wgpu::RenderPipeline,
    p_blur_h: wgpu::RenderPipeline,
    p_blur_v: wgpu::RenderPipeline,
    p_comp: wgpu::RenderPipeline,
    globals: wgpu::Buffer,
    ui: wgpu::Buffer,
    audio: Target,
    sampler: wgpu::Sampler,
    scene: [Target; 2],
    bloom: [Target; 2],
    text: Target,
    art: Target,
    cur: usize,
    pub scene_size: (u32, u32),
    pub screen_size: (u32, u32),
}

impl Renderer {
    pub fn new(device: wgpu::Device, queue: wgpu::Queue, out_fmt: wgpu::TextureFormat) -> Self {
        let tex_entry = |b: u32| wgpu::BindGroupLayoutEntry {
            binding: b,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Texture { sample_type: wgpu::TextureSampleType::Float { filterable: b != 1 }, view_dimension: wgpu::TextureViewDimension::D2, multisampled: false },
            count: None,
        };
        let ubo = |b: u32| wgpu::BindGroupLayoutEntry {
            binding: b,
            visibility: wgpu::ShaderStages::FRAGMENT | wgpu::ShaderStages::VERTEX,
            ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
            count: None,
        };
        let samp_entry = |b: u32| wgpu::BindGroupLayoutEntry {
            binding: b,
            visibility: wgpu::ShaderStages::FRAGMENT,
            ty: wgpu::BindingType::Sampler(wgpu::SamplerBindingType::Filtering),
            count: None,
        };
        let look_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("look"),
            entries: &[ubo(0), tex_entry(1), tex_entry(2), samp_entry(3)],
        });
        let mut t4 = tex_entry(4);
        if let wgpu::BindingType::Texture { sample_type, .. } = &mut t4.ty {
            *sample_type = wgpu::TextureSampleType::Float { filterable: true };
        }
        let post_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("post"),
            entries: &[ubo(0), tex_entry(2).with_binding(1), tex_entry(2), samp_entry(3), t4, tex_entry(5)],
        });
        let look_pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[&look_layout], push_constant_ranges: &[] });
        let post_pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[&post_layout], push_constant_ranges: &[] });
        let post_mod = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("post"), source: wgpu::ShaderSource::Wgsl(POST_WGSL.into()) });
        let mk = |fs: &str, fmt: wgpu::TextureFormat| {
            device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some(fs),
                layout: Some(&post_pl),
                vertex: wgpu::VertexState { module: &post_mod, entry_point: Some("vs_post"), buffers: &[], compilation_options: Default::default() },
                fragment: Some(wgpu::FragmentState {
                    module: &post_mod,
                    entry_point: Some(fs),
                    targets: &[Some(wgpu::ColorTargetState { format: fmt, blend: None, write_mask: wgpu::ColorWrites::ALL })],
                    compilation_options: Default::default(),
                }),
                primitive: Default::default(),
                depth_stencil: None,
                multisample: Default::default(),
                multiview: None,
                cache: None,
            })
        };
        let p_bright = mk("fs_bright", SCENE_FMT);
        let p_blur_h = mk("fs_blur_h", SCENE_FMT);
        let p_blur_v = mk("fs_blur_v", SCENE_FMT);
        let p_comp = mk("fs_composite", out_fmt);

        let globals = device.create_buffer(&wgpu::BufferDescriptor { label: Some("globals"), size: std::mem::size_of::<Globals>() as u64, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let ui = device.create_buffer(&wgpu::BufferDescriptor { label: Some("ui"), size: std::mem::size_of::<Ui>() as u64, usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST, mapped_at_creation: false });
        let sampler = device.create_sampler(&wgpu::SamplerDescriptor {
            mag_filter: wgpu::FilterMode::Linear,
            min_filter: wgpu::FilterMode::Linear,
            address_mode_u: wgpu::AddressMode::ClampToEdge,
            address_mode_v: wgpu::AddressMode::ClampToEdge,
            ..Default::default()
        });
        let audio = target(&device, AUDIO_W, AUDIO_H, wgpu::TextureFormat::R32Float, "audio");
        let text = target(&device, 1, 1, wgpu::TextureFormat::Rgba8Unorm, "text");
        let art = target(&device, 96, 96, wgpu::TextureFormat::Rgba8Unorm, "art");
        let scene = [target(&device, 1, 1, SCENE_FMT, "scene0"), target(&device, 1, 1, SCENE_FMT, "scene1")];
        let bloom = [target(&device, 1, 1, SCENE_FMT, "bloom0"), target(&device, 1, 1, SCENE_FMT, "bloom1")];
        Renderer {
            device, queue, out_fmt, look_layout, look_pl, look_pipe: None, post_layout, p_bright, p_blur_h, p_blur_v, p_comp,
            globals, ui, audio, sampler, scene, bloom, text, art, cur: 0, scene_size: (0, 0), screen_size: (0, 0),
        }
    }

    /// Compiles a look. Returns the WGSL error text instead of crashing when the shader is broken.
    pub fn set_look(&mut self, look_src: &str) -> Result<(), String> {
        // files saved with a UTF-8 BOM would otherwise fail to parse
        let src = format!("{}\n{}", COMMON_WGSL.trim_start_matches('\u{feff}'), look_src.trim_start_matches('\u{feff}'));
        self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        let module = self.device.create_shader_module(wgpu::ShaderModuleDescriptor { label: Some("look"), source: wgpu::ShaderSource::Wgsl(src.into()) });
        let pipe = self.device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("look"),
            layout: Some(&self.look_pl),
            vertex: wgpu::VertexState { module: &module, entry_point: Some("vs_main"), buffers: &[], compilation_options: Default::default() },
            fragment: Some(wgpu::FragmentState {
                module: &module,
                entry_point: Some("fs_main"),
                targets: &[Some(wgpu::ColorTargetState { format: SCENE_FMT, blend: None, write_mask: wgpu::ColorWrites::ALL })],
                compilation_options: Default::default(),
            }),
            primitive: Default::default(),
            depth_stencil: None,
            multisample: Default::default(),
            multiview: None,
            cache: None,
        });
        if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
            return Err(err.to_string());
        }
        self.look_pipe = Some(pipe);
        self.clear_scene();
        Ok(())
    }

    pub fn clear_scene(&mut self) {
        let mut enc = self.device.create_command_encoder(&Default::default());
        for t in &self.scene {
            enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &t.view,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store },
                })],
                ..Default::default()
            });
        }
        self.queue.submit([enc.finish()]);
    }

    /// screen = window size, scene = internal render size (quality scale).
    pub fn resize(&mut self, screen: (u32, u32), scene: (u32, u32)) {
        if screen != self.screen_size {
            self.screen_size = screen;
            self.text = target(&self.device, screen.0, screen.1, wgpu::TextureFormat::Rgba8Unorm, "text");
        }
        if scene != self.scene_size {
            self.scene_size = scene;
            self.scene = [target(&self.device, scene.0, scene.1, SCENE_FMT, "scene0"), target(&self.device, scene.0, scene.1, SCENE_FMT, "scene1")];
            let b = ((scene.0 / 4).max(1), (scene.1 / 4).max(1));
            self.bloom = [target(&self.device, b.0, b.1, SCENE_FMT, "bloom0"), target(&self.device, b.0, b.1, SCENE_FMT, "bloom1")];
            self.clear_scene();
        }
    }

    pub fn upload_audio(&self, data: &[f32]) {
        self.write_tex(&self.audio.tex, bytemuck::cast_slice(data), AUDIO_W * 4, AUDIO_W, AUDIO_H);
    }
    /// RGBA8, screen-sized, one channel per text group
    pub fn upload_text(&self, rgba: &[u8], w: u32, h: u32) {
        if (w, h) == self.screen_size {
            self.write_tex(&self.text.tex, rgba, w * 4, w, h);
        }
    }
    pub fn upload_art(&self, rgba: &[u8]) {
        self.write_tex(&self.art.tex, rgba, 96 * 4, 96, 96);
    }
    fn write_tex(&self, tex: &wgpu::Texture, data: &[u8], bpr: u32, w: u32, h: u32) {
        self.queue.write_texture(
            wgpu::TexelCopyTextureInfo { texture: tex, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
            data,
            wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(bpr), rows_per_image: Some(h) },
            wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
        );
    }

    fn post_group(&self, input: &wgpu::TextureView, bloom: &wgpu::TextureView) -> wgpu::BindGroup {
        self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.post_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: self.ui.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(input) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(bloom) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::Sampler(&self.sampler) },
                wgpu::BindGroupEntry { binding: 4, resource: wgpu::BindingResource::TextureView(&self.text.view) },
                wgpu::BindGroupEntry { binding: 5, resource: wgpu::BindingResource::TextureView(&self.art.view) },
            ],
        })
    }

    fn pass(enc: &mut wgpu::CommandEncoder, view: &wgpu::TextureView, pipe: &wgpu::RenderPipeline, group: &wgpu::BindGroup) {
        let mut rp = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
            label: None,
            color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                view,
                resolve_target: None,
                ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store },
            })],
            ..Default::default()
        });
        rp.set_pipeline(pipe);
        rp.set_bind_group(0, group, &[]);
        rp.draw(0..3, 0..1);
    }

    /// Renders one frame into `out` (the window's surface texture or an offscreen target).
    pub fn render(&mut self, out: &wgpu::TextureView, g: &Globals, ui: &Ui) {
        let Some(pipe) = &self.look_pipe else { return };
        self.queue.write_buffer(&self.globals, 0, bytemuck::bytes_of(g));
        self.queue.write_buffer(&self.ui, 0, bytemuck::bytes_of(ui));
        let (cur, prev) = (self.cur, 1 - self.cur);
        let look_group = self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: None,
            layout: &self.look_layout,
            entries: &[
                wgpu::BindGroupEntry { binding: 0, resource: self.globals.as_entire_binding() },
                wgpu::BindGroupEntry { binding: 1, resource: wgpu::BindingResource::TextureView(&self.audio.view) },
                wgpu::BindGroupEntry { binding: 2, resource: wgpu::BindingResource::TextureView(&self.scene[prev].view) },
                wgpu::BindGroupEntry { binding: 3, resource: wgpu::BindingResource::Sampler(&self.sampler) },
            ],
        });
        let g_bright = self.post_group(&self.scene[cur].view, &self.bloom[1].view);
        let g_h = self.post_group(&self.bloom[0].view, &self.bloom[0].view);
        let g_v = self.post_group(&self.bloom[1].view, &self.bloom[1].view);
        let g_comp = self.post_group(&self.scene[cur].view, &self.bloom[0].view);
        let mut enc = self.device.create_command_encoder(&Default::default());
        Self::pass(&mut enc, &self.scene[cur].view, pipe, &look_group);
        Self::pass(&mut enc, &self.bloom[0].view, &self.p_bright, &g_bright);
        Self::pass(&mut enc, &self.bloom[1].view, &self.p_blur_h, &g_h);
        Self::pass(&mut enc, &self.bloom[0].view, &self.p_blur_v, &g_v);
        Self::pass(&mut enc, out, &self.p_comp, &g_comp);
        self.queue.submit([enc.finish()]);
        self.cur = prev;
    }

    pub fn out_format(&self) -> wgpu::TextureFormat { self.out_fmt }
}

trait WithBinding {
    fn with_binding(self, b: u32) -> Self;
}
impl WithBinding for wgpu::BindGroupLayoutEntry {
    fn with_binding(mut self, b: u32) -> Self {
        self.binding = b;
        self
    }
}

/// Headless device for `--shots`.
pub fn headless() -> (wgpu::Device, wgpu::Queue) {
    let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor { backends: wgpu::Backends::DX12, ..Default::default() });
    let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
        power_preference: wgpu::PowerPreference::HighPerformance,
        ..Default::default()
    }))
    .expect("no GPU adapter");
    pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor { memory_hints: wgpu::MemoryHints::MemoryUsage, ..Default::default() })).expect("no GPU device")
}

/// Reads an Rgba8Unorm texture back to the CPU (for PNG shots).
pub fn read_rgba(device: &wgpu::Device, queue: &wgpu::Queue, tex: &wgpu::Texture, w: u32, h: u32) -> Vec<u8> {
    let bpr = (w * 4 + 255) / 256 * 256;
    let buf = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (bpr * h) as u64, usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ, mapped_at_creation: false });
    let mut enc = device.create_command_encoder(&Default::default());
    enc.copy_texture_to_buffer(
        wgpu::TexelCopyTextureInfo { texture: tex, mip_level: 0, origin: wgpu::Origin3d::ZERO, aspect: wgpu::TextureAspect::All },
        wgpu::TexelCopyBufferInfo { buffer: &buf, layout: wgpu::TexelCopyBufferLayout { offset: 0, bytes_per_row: Some(bpr), rows_per_image: Some(h) } },
        wgpu::Extent3d { width: w, height: h, depth_or_array_layers: 1 },
    );
    queue.submit([enc.finish()]);
    let slice = buf.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);
    let data = slice.get_mapped_range();
    let mut out = Vec::with_capacity((w * h * 4) as usize);
    for y in 0..h {
        let row = &data[(y * bpr) as usize..(y * bpr + w * 4) as usize];
        out.extend_from_slice(row);
    }
    out
}

pub fn offscreen(device: &wgpu::Device, w: u32, h: u32) -> (wgpu::Texture, wgpu::TextureView) {
    let t = target(device, w, h, wgpu::TextureFormat::Rgba8Unorm, "shot");
    (t.tex, t.view)
}


