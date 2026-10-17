# Music Visualizer (Chrome extension)

WebGPU music visualizer. The looks are the same WGSL shaders as the Windows app.

## Build

The shaders are copied from `../shaders` (and `looks.json` plus the icons are generated) by:

    node tools/build-extension.mjs

Run it from the project root (`I:\MusicVisualizer`) whenever a look changes. No npm packages needed.

## Load it

1. Open `chrome://extensions`.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and pick the `I:\MusicVisualizer\extension` folder.
4. Pin the extension and click its icon.

## Use it

- **Visualize this tab**: captures the audio of the current tab and opens the visualizer in a new tab. The tab keeps playing through the visualizer tab.
- **Visualize any audio**: opens the visualizer, click the button and pick a screen/tab in Chrome's picker; tick **Share audio**. Gives system audio when sharing the whole screen.
- **Demo**: built-in synth song (breakdown every 16 beats, so the drop fires).

If the browser blocks audio until you interact, click "Click to start audio".

Keys: Left/Right = look, F = fullscreen, M = mouse control, S = settings.
Settings (saved): look, auto-pick look, quality (render scale), sensitivity, mouse control.

Needs Chrome 113+ with WebGPU (check `chrome://gpu`). If the GPU is out of memory or WebGPU is missing, the page shows a message.

## Test without installing

    cd extension && python -m http.server 8766

then open `http://localhost:8766/visualizer.html?mode=demo` (chrome.* calls are optional outside the extension).
