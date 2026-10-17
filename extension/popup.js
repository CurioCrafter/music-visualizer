const err = (m) => { document.getElementById('err').textContent = m; };
const open = (qs) => { chrome.tabs.create({ url: chrome.runtime.getURL('visualizer.html?' + qs) }); window.close(); };

document.getElementById('tab').onclick = async () => {
  try {
    const [t] = await chrome.tabs.query({ active: true, currentWindow: true });
    const id = await chrome.tabCapture.getMediaStreamId({ targetTabId: t.id });
    open(`mode=tab&streamId=${encodeURIComponent(id)}&tab=${t.id}`);
  } catch (e) { err('Cannot capture this tab: ' + (e.message || e)); }
};
document.getElementById('display').onclick = () => open('mode=display');
document.getElementById('demo').onclick = () => open('mode=demo');
