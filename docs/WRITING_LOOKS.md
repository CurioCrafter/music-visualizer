# Writing a look

A look is one WGSL file in `shaders/looks/`. It runs as a full-screen fragment shader on the GPU, once per
pixel per frame, in both the Windows app and the Chrome extension. Read `shaders/common.wgsl` first: it is
the whole contract (the `G` globals, audio helpers, noise, shapes, palette).

## The file

```wgsl
// name: Bass Drop
// palette: #ff28c8 #9628ff #28dcff

fn look(fc: vec2f) -> vec4f {      // fc = pixel position, origin top-left, y down
    ...
    return vec4f(colour, 1.0);      // display space; values above 1 bloom
}
```

- The two header lines are read by the app (look name + its 3 default colours). When the user turns on
  "colours from album art", `G.pal0..2` become the cover's colours instead, so use `pal()` / `palc()` for
  the look's signature colours rather than hard-coding them (scenery like sand, night sky, wood can stay fixed).
- Put any helper functions in your file. Give them a prefix unique to the look (`bd_`, `ff_`, ...) so they
  never clash with `common.wgsl`.
- `prev(uv)` is last frame of this look: use it for trails, smoke, feedback. Mix it with care (it compounds).

## What a good look does

- **Full of detail at full screen (4K).** Several layers: background, mid-ground, hero element, foreground,
  particles/dust, light (glows, rays). Use noise/fbm for texture. Nothing flat and empty.
- **Reacts hard and in different ways to different parts of the music.** Don't just scale one thing with
  `bass`. Give each signal its own job:
  - `G.kick` (punchy hits), `G.snare`, `G.hat` (fast ticks), `G.beat` (general beat envelope)
  - `G.beat_phase` (0..1 inside the beat, from the tempo tracker: animate *on* the beat, e.g. bounce
    `1 - beat_phase`, or pulse things on the downbeat)
  - `G.bass`, `G.mid`, `G.high`, `spec(x)` / `band(i)` (spectrum), `hist(x, age)` (last 3.2 s)
  - `wave(x)` (actual waveform, great for oscilloscope lines)
  - `G.centroid` (bright vs dark sound -> colour temperature), `G.flux` (busy-ness -> particle count/speed),
    `G.energy` (quiet verse vs big chorus -> how much of the scene is "on"), `G.drop` (a big moment: go wild
    for ~1.4 s), `G.travel` (use as distance for anything that flies forward), `key(k)` (piano keys glowing).
- **Silence still looks beautiful** (slow idle motion), loud music looks spectacular.
- **Mouse control** (`G.mouse_on == 1`): the scene should respond to `G.mouse` (0..1): steer a camera,
  light follows the cursor, creatures look at it or flee, etc. `G.click_pos` + `G.click_age` (seconds since
  the click): a ripple, a burst, a splash at that spot. When mouse control is off `G.mouse` sits at the centre.
- **Fast.** Budget roughly 2-3 ms per frame at 1080p on an RTX 3080 Ti. Keep per-pixel loops modest
  (raymarch <= ~80 steps, particle loops <= ~60, fbm <= 5 octaves), scale loop counts with `G.quality`
  (0 low, 1 balanced, 2 high). No text: if you need digits/letters, draw them as shapes (e.g. a 3x5 pixel font).

## Testing without opening a window

```
tools\shots\viz-shots.exe --shots <out folder> shaders\looks\your_look.wgsl
```

renders 8 seconds of a synthetic 128 BPM song (kick, snare, hats, wobbling sub, chords, piano notes; a
breakdown then a drop) and saves `<out folder>\your_look.png`: three frames side by side
(2 s groove | 6.5 s breakdown | 8 s right after the drop, with a simulated mouse and click).
Shader errors are printed with line numbers. It also prints a rough ms/frame.
