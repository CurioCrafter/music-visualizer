// WebGPU renderer mirroring src/render.rs: look pass (HDR, with feedback) -> bright -> blur h/v -> composite.
import { Analyzer, Signals } from './analyzer.js';

const SCENE_FMT = 'rgba16float';
const AUDIO_W = 256, AUDIO_H = 66;
const QUALITY_SCALE = [0.5, 0.75, 1];
const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const mode = params.get('mode') || 'demo';
const clamp = (v, a, b) => Math.min(Math.max(v, a), b);

// ---------- settings (chrome.storage.local when in the extension, localStorage otherwise) ----------
const area = globalThis.chrome?.storage?.local;
const DEFAULTS = { look: '', auto: false, quality: 1, sens: 1, mouse: false };
let settings = { ...DEFAULTS };
async function loadSettings() {
  try {
    if (area) settings = { ...DEFAULTS, ...((await area.get('settings')).settings || {}) };
    else settings = { ...DEFAULTS, ...JSON.parse(localStorage.getItem('mvSettings') || '{}') };
  } catch { /* storage unavailable: keep defaults */ }
}
function saveSettings() {
  try {
    if (area) area.set({ settings }); else localStorage.setItem('mvSettings', JSON.stringify(settings));
  } catch { /* ignore */ }
}

function fatal(msg) { const f = $('fatal'); f.textContent = msg; f.hidden = false; }
let msgTimer = 0;
function toast(msg, ms = 6000) {
  const m = $('msg'); m.textContent = msg; m.hidden = false;
  clearTimeout(msgTimer); if (ms) msgTimer = setTimeout(() => { m.hidden = true; }, ms);
}
const getText = (u) => fetch(u).then((r) => { if (!r.ok) throw new Error(u + ': HTTP ' + r.status); return r.text(); });
const hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16) / 255);

async function main() {
  await loadSettings();
  if (!navigator.gpu) return fatal('WebGPU is not available in this browser.\nUse a recent Chrome (113+) with hardware acceleration enabled (chrome://gpu).');
  let device = null, why = '';
  // hardware first, then the software fallback adapter if the GPU is out of memory or unavailable
  for (const opt of [{ powerPreference: 'high-performance' }, { forceFallbackAdapter: true }]) {
    try {
      const adapter = await navigator.gpu.requestAdapter(opt);
      if (adapter) { device = await adapter.requestDevice(); break; }
    } catch (e) { why = e.message; console.warn('requestDevice failed:', e.message); }
  }
  if (!device) return fatal('No WebGPU adapter/device could be created.\nCheck chrome://gpu, that hardware acceleration is on and that the GPU has free memory.' + (why ? '\n(' + why.split('\n')[0] + ')' : ''));
  device.lost.then((i) => fatal('The GPU device was lost: ' + i.message + '\nReload the page.'));
  device.addEventListener('uncapturederror', (e) => console.error('WebGPU:', e.error.message));

  const canvas = $('c');
  const ctxGpu = canvas.getContext('webgpu');
  const outFmt = navigator.gpu.getPreferredCanvasFormat();
  ctxGpu.configure({ device, format: outFmt, alphaMode: 'opaque' });

  const [common, post, looks] = await Promise.all([
    getText('shaders/common.wgsl'), getText('shaders/post.wgsl'), fetch('shaders/looks.json').then((r) => r.json())]);

  // ---------- layouts (same as Renderer::new) ----------
  const F = GPUShaderStage.FRAGMENT, V = GPUShaderStage.VERTEX;
  const tex = (binding, sampleType = 'float') => ({ binding, visibility: F, texture: { sampleType, viewDimension: '2d' } });
  const ubo = (binding) => ({ binding, visibility: F | V, buffer: { type: 'uniform' } });
  const smp = (binding) => ({ binding, visibility: F, sampler: { type: 'filtering' } });
  const lookLayout = device.createBindGroupLayout({ entries: [ubo(0), tex(1, 'unfilterable-float'), tex(2), smp(3)] });
  const postLayout = device.createBindGroupLayout({ entries: [ubo(0), tex(1), tex(2), smp(3), tex(4), tex(5)] });
  const lookPL = device.createPipelineLayout({ bindGroupLayouts: [lookLayout] });
  const postPL = device.createPipelineLayout({ bindGroupLayouts: [postLayout] });
  const postMod = device.createShaderModule({ code: post });
  const mk = (fs, format) => device.createRenderPipeline({
    layout: postPL, vertex: { module: postMod, entryPoint: 'vs_post' },
    fragment: { module: postMod, entryPoint: fs, targets: [{ format }] },
  });
  const pBright = mk('fs_bright', SCENE_FMT), pBlurH = mk('fs_blur_h', SCENE_FMT), pBlurV = mk('fs_blur_v', SCENE_FMT);
  const pComp = mk('fs_composite', outFmt);

  // ---------- resources ----------
  const globalsBuf = device.createBuffer({ size: 176, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const uiBuf = device.createBuffer({ size: 64 + 32 * 48, usage: GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST });
  const sampler = device.createSampler({ magFilter: 'linear', minFilter: 'linear', addressModeU: 'clamp-to-edge', addressModeV: 'clamp-to-edge' });
  const U = GPUTextureUsage;
  const target = (w, h, format, extra = 0) => {
    const t = device.createTexture({ size: [Math.max(w, 1), Math.max(h, 1)], format, usage: U.RENDER_ATTACHMENT | U.TEXTURE_BINDING | U.COPY_DST | extra });
    return { tex: t, view: t.createView() };
  };
  const audioTex = target(AUDIO_W, AUDIO_H, 'r32float');
  const textTex = target(1, 1, 'rgba8unorm'), artTex = target(1, 1, 'rgba8unorm'); // 1x1 transparent (zero) textures
  device.queue.writeTexture({ texture: textTex.tex }, new Uint8Array(4), { bytesPerRow: 4 }, [1, 1]);
  device.queue.writeTexture({ texture: artTex.tex }, new Uint8Array(4), { bytesPerRow: 4 }, [1, 1]);
  let scene = [], bloom = [], sceneSize = [0, 0], cur = 0;

  function clearScene() {
    const enc = device.createCommandEncoder();
    for (const t of scene) enc.beginRenderPass({ colorAttachments: [{ view: t.view, loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 1] }] }).end();
    device.queue.submit([enc.finish()]);
  }
  function resize() {
    const dpr = window.devicePixelRatio || 1;
    const sw = Math.max(1, Math.round(innerWidth * dpr)), sh = Math.max(1, Math.round(innerHeight * dpr));
    if (canvas.width !== sw || canvas.height !== sh) { canvas.width = sw; canvas.height = sh; }
    const k = QUALITY_SCALE[settings.quality] ?? 0.75;
    const w = Math.max(1, Math.round(sw * k)), h = Math.max(1, Math.round(sh * k));
    if (w !== sceneSize[0] || h !== sceneSize[1]) {
      scene.forEach((t) => t.tex.destroy()); bloom.forEach((t) => t.tex.destroy());
      sceneSize = [w, h];
      scene = [target(w, h, SCENE_FMT), target(w, h, SCENE_FMT)];
      const bw = Math.max(1, w >> 2), bh = Math.max(1, h >> 2);
      bloom = [target(bw, bh, SCENE_FMT), target(bw, bh, SCENE_FMT)];
      clearScene();
    }
    return [sw, sh];
  }

  // ---------- looks ----------
  let lookPipe = null, lookIdx = -1, lookStart = 0, lookToken = 0;
  const lookSrc = {};
  const analyzer = new Analyzer();
  const pill = $('pill');
  let pillTimer = 0;
  function showPill(text, err) {
    pill.textContent = text.replace(/_/g, ' ');
    if (err) { const s = document.createElement('small'); s.textContent = err; pill.appendChild(s); }
    pill.classList.add('show'); clearTimeout(pillTimer);
    pillTimer = setTimeout(() => pill.classList.remove('show'), err ? 6000 : 2200);
  }
  async function setLook(i, now) {
    i = (i + looks.length) % looks.length;
    const token = ++lookToken, L = looks[i];
    lookIdx = i; settings.look = L.name; $('s-look').value = String(i); saveSettings();
    let err = '';
    try {
      const src = lookSrc[L.file] ??= await getText('shaders/looks/' + L.file);
      if (token !== lookToken) return; // a newer switch won
      // all of these calls are synchronous, so only the look's own errors land in the scope
      device.pushErrorScope('validation');
      const module = device.createShaderModule({ code: common + '\n' + src });
      const info = module.getCompilationInfo();
      const pipe = device.createRenderPipeline({
        layout: lookPL, vertex: { module, entryPoint: 'vs_main' },
        fragment: { module, entryPoint: 'fs_main', targets: [{ format: SCENE_FMT }] },
      });
      const popped = device.popErrorScope();
      const [ci, e] = [await info, await popped];
      const errs = ci.messages.filter((m) => m.type === 'error');
      if (token !== lookToken) return;
      if (e || errs.length) {
        err = errs.length ? errs.slice(0, 3).map((m) => `line ${m.lineNum - common.split('\n').length}: ${m.message}`).join('\n') : e.message;
        console.error(`Look ${L.name} failed to compile:\n${err}`);
      } else {
        lookPipe = pipe; analyzer.wantNotes = /\bkey\s*\(/.test(src);
        const p = L.palette.map(hex); palette = [...p[0], 1, ...p[1], 1, ...p[2], 1];
        lookStart = now ?? performance.now() / 1000; clearScene();
      }
    } catch (ex) { err = String(ex.message || ex); console.error(ex); }
    showPill(L.name, err && ('Could not run this look (kept the previous one):\n' + err));
  }
  let palette = [1, 0.16, 0.78, 1, 0.59, 0.16, 1, 1, 0.16, 0.86, 1, 1];
  const next = (d) => setLook(lookIdx + d);

  // ---------- UI ----------
  const sel = $('s-look');
  looks.forEach((l, i) => sel.add(new Option(l.name.replace(/_/g, ' '), String(i))));
  sel.onchange = () => setLook(+sel.value);
  $('s-auto').checked = settings.auto; $('s-auto').onchange = (e) => { settings.auto = e.target.checked; autoAt = 0; saveSettings(); };
  $('s-quality').value = String(settings.quality); $('s-quality').onchange = (e) => { settings.quality = +e.target.value; saveSettings(); };
  $('s-sens').value = String(settings.sens); $('s-sens').oninput = (e) => { settings.sens = +e.target.value; saveSettings(); };
  const setMouse = (on) => { settings.mouse = on; $('s-mouse').checked = on; $('b-mouse').classList.toggle('on', on); saveSettings(); };
  $('s-mouse').onchange = (e) => setMouse(e.target.checked);
  setMouse(settings.mouse);
  const toggleSettings = () => { $('settings').hidden = !$('settings').hidden; $('b-set').classList.toggle('on', !$('settings').hidden); };
  const toggleFull = () => (document.fullscreenElement ? document.exitFullscreen() : document.documentElement.requestFullscreen()).catch(() => {});
  $('b-prev').onclick = () => next(-1); $('b-next').onclick = () => next(1);
  $('b-mouse').onclick = () => setMouse(!settings.mouse);
  $('b-set').onclick = toggleSettings; $('b-full').onclick = toggleFull;
  document.addEventListener('fullscreenchange', () => document.body.classList.toggle('fs', !!document.fullscreenElement));
  addEventListener('keydown', (e) => {
    if (e.target.tagName === 'SELECT' || e.ctrlKey || e.metaKey || e.altKey) return;
    const k = e.key.toLowerCase();
    if (k === 'arrowleft') next(-1); else if (k === 'arrowright') next(1);
    else if (k === 'f') toggleFull(); else if (k === 'm') setMouse(!settings.mouse); else if (k === 's') toggleSettings();
    else if (k === 'escape' && !$('settings').hidden) toggleSettings();
    else return;
    e.preventDefault();
  });

  // idle fade / hide (and cursor) after 2.5 s without mouse movement
  let lastMove = performance.now(), mouse = [0.5, 0.5], inside = true, clickPos = [0.5, 0.5], clickTime = -999;
  addEventListener('mousemove', (e) => {
    lastMove = performance.now(); mouse = [e.clientX / innerWidth, e.clientY / innerHeight]; inside = true;
    document.body.classList.remove('idle', 'hide-cursor');
  });
  document.addEventListener('mouseleave', () => { inside = false; });
  document.addEventListener('mouseenter', () => { inside = true; });
  canvas.addEventListener('pointerdown', (e) => { clickPos = [e.clientX / innerWidth, e.clientY / innerHeight]; clickTime = performance.now() / 1000; });

  // ---------- audio ----------
  let audioCtx = null;
  const startBtn = $('start');
  function askGesture(text, fn) {
    startBtn.textContent = text; startBtn.hidden = false;
    startBtn.onclick = async () => { startBtn.hidden = true; try { await fn(); } catch (e) { audioError(e); } };
  }
  function audioError(e) {
    console.error(e);
    const name = e?.name === 'NotAllowedError' || e?.name === 'AbortError' ? 'Permission was denied or the picker was cancelled.' : (e?.message || String(e));
    toast('Audio problem: ' + name, 0);
    askGesture('Click to try again', startAudio);
  }
  async function startAudio() {
    audioCtx ??= new AudioContext({ latencyHint: 'interactive' });
    let src;
    if (mode === 'tab') {
      const id = params.get('streamId');
      if (!id || !globalThis.chrome?.runtime) throw new Error('Tab capture only works from the extension popup ("Visualize this tab").');
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { mandatory: { chromeMediaSource: 'tab', chromeMediaSourceId: id } }, video: false });
      src = audioCtx.createMediaStreamSource(stream);
      src.connect(audioCtx.destination); // capturing mutes the tab, so play it back
      stream.getAudioTracks()[0].onended = () => toast('The captured tab stopped.', 0);
    } else if (mode === 'display') {
      const stream = await navigator.mediaDevices.getDisplayMedia({ audio: true, video: true });
      stream.getVideoTracks().forEach((t) => t.stop()); // we only want the sound
      if (!stream.getAudioTracks().length) throw new Error('No audio was shared. In the picker choose a tab or the whole screen and tick "Share audio".');
      src = audioCtx.createMediaStreamSource(new MediaStream(stream.getAudioTracks())); // not played back: the source keeps playing itself
      stream.getAudioTracks()[0].onended = () => toast('Audio sharing stopped.', 0);
    } else if (mode === 'mic') {
      // music from the speakers through the microphone; never played back (that would feed back)
      const stream = await navigator.mediaDevices.getUserMedia({ audio: { echoCancellation: false, noiseSuppression: false, autoGainControl: false }, video: false });
      src = audioCtx.createMediaStreamSource(stream);
    } else {
      await audioCtx.audioWorklet.addModule('demo-worklet.js');
      src = new AudioWorkletNode(audioCtx, 'demo-synth', { outputChannelCount: [1] });
      src.connect(audioCtx.destination);
    }
    analyzer.attach(audioCtx, src);
    $('msg').hidden = true;
    if (audioCtx.state !== 'running') {
      try { await audioCtx.resume(); } catch { /* needs a gesture */ }
      if (audioCtx.state !== 'running') askGesture('Click to start audio', () => audioCtx.resume());
    }
  }
  addEventListener('pointerdown', () => { if (audioCtx && audioCtx.state === 'suspended') audioCtx.resume(); });
  if (mode === 'display') askGesture('Click to choose what audio to visualize', startAudio);
  else if (mode === 'mic') askGesture('Click to listen through your microphone', startAudio);
  else startAudio().catch(audioError);

  // ---------- frame ----------
  const G = new Float32Array(44), Ui = new Float32Array(400), audioData = new Float32Array(AUDIO_W * AUDIO_H);
  const sig = new Signals();
  let last = performance.now() / 1000, autoAt = 0;
  const gbuf = (t) => device.createBindGroup({
    layout: lookLayout, entries: [
      { binding: 0, resource: { buffer: globalsBuf } }, { binding: 1, resource: audioTex.view },
      { binding: 2, resource: t.view }, { binding: 3, resource: sampler }],
  });
  const pbuf = (input, bl) => device.createBindGroup({
    layout: postLayout, entries: [
      { binding: 0, resource: { buffer: uiBuf } }, { binding: 1, resource: input.view }, { binding: 2, resource: bl.view },
      { binding: 3, resource: sampler }, { binding: 4, resource: textTex.view }, { binding: 5, resource: artTex.view }],
  });
  const pass = (enc, view, pipe, group) => {
    const rp = enc.beginRenderPass({ colorAttachments: [{ view, loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 1] }] });
    rp.setPipeline(pipe); rp.setBindGroup(0, group); rp.draw(3); rp.end();
  };

  function frame() {
    requestAnimationFrame(frame);
    const now = performance.now() / 1000, dt = clamp(now - last, 0.001, 0.1);
    last = now;
    const [sw, sh] = resize();
    const fs = !!document.fullscreenElement;
    if (now * 1000 - lastMove > 2500) { document.body.classList.add('idle'); document.body.classList.toggle('hide-cursor', fs); }

    analyzer.sensitivity = settings.sens;
    analyzer.update(now, dt);
    sig.step(analyzer, dt);
    if (settings.auto) { // switch looks every 45 s, or on a drop if the look is older than 20 s
      if (!autoAt) autoAt = now;
      if (now - autoAt > 45 || (analyzer.drop && now - autoAt > 20)) { autoAt = now; next(1 + Math.floor(Math.random() * (looks.length - 1))); }
    }

    const mOn = settings.mouse && inside ? 1 : 0;
    const a = analyzer;
    G.set([sceneSize[0], sceneSize[1], now, dt, mOn ? mouse[0] : 0.5, mOn ? mouse[1] : 0.5, mOn, Math.min(now - clickTime, 999),
      clickPos[0], clickPos[1], a.bass, a.mid, a.high, a.vol, sig.beat, sig.drop, sig.beatCount, sig.travel,
      settings.quality, sceneSize[0] / sceneSize[1], a.kick, a.snare, a.hat, a.flux, a.centroid, a.energy, a.beatPhase, a.bpm,
      now - lookStart, 0, 0, 0, ...palette]);
    // Ui: count = 0 (glass UI is HTML/CSS), fx = [bloom, vignette, beat edge glow, fullscreen]
    Ui.set([sw, sh, 0, sig.beat, palette[4], palette[5], palette[6], 1, 0.9, 0.35, sig.beat * sig.beat * 0.5, fs ? 1 : 0, 0, 0, 0, 0]);
    analyzer.writeTexture(audioData);
    device.queue.writeBuffer(globalsBuf, 0, G);
    device.queue.writeBuffer(uiBuf, 0, Ui);
    device.queue.writeTexture({ texture: audioTex.tex }, audioData, { bytesPerRow: AUDIO_W * 4, rowsPerImage: AUDIO_H }, [AUDIO_W, AUDIO_H]);

    const out = ctxGpu.getCurrentTexture().createView();
    const enc = device.createCommandEncoder();
    if (lookPipe) {
      const prev = 1 - cur;
      pass(enc, scene[cur].view, lookPipe, gbuf(scene[prev]));
      pass(enc, bloom[0].view, pBright, pbuf(scene[cur], bloom[1]));
      pass(enc, bloom[1].view, pBlurH, pbuf(bloom[0], bloom[0]));
      pass(enc, bloom[0].view, pBlurV, pbuf(bloom[1], bloom[1]));
      pass(enc, out, pComp, pbuf(scene[cur], bloom[0]));
      cur = prev;
    } else enc.beginRenderPass({ colorAttachments: [{ view: out, loadOp: 'clear', storeOp: 'store', clearValue: [0, 0, 0, 1] }] }).end();
    device.queue.submit([enc.finish()]);
  }

  const start = Math.max(0, looks.findIndex((l) => l.name === settings.look));
  await setLook(start, performance.now() / 1000);
  // test hooks (also handy in the console)
  window.viz = { setLook, looks, analyzer, sig, get lookIdx() { return lookIdx; } };
  requestAnimationFrame(frame);
}

main().catch((e) => { console.error(e); fatal('Something went wrong: ' + (e.message || e)); });
