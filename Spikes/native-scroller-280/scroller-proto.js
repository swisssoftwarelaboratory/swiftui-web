// PROTOTYPE (new-website#280): a real Safari scroller driving the canvas. Throwaway.
// ?scroll=native     the canvas sits pinned inside an invisible native scroll box; Safari scrolls the
//                    box (its own momentum, bounce, scrolling thread) and each frame the app's scroll
//                    view is moved to the box's position.
// ?scroll=nobounce   the same, with Safari's bounce at the ends switched off.
// ?scroll=ours       (default) today's way: every wheel event goes straight to the app.
(function () {
  const params = new URLSearchParams(location.search);
  const mode = ['native', 'nobounce'].includes(params.get('scroll')) ? params.get('scroll') : 'ours';
  window.__scrollProto = { mode };

  // The switch, below the iPhone, outside the app.
  const bar = document.createElement('div');
  bar.id = 'proto-bar';
  const label = { ours: 'Today', native: 'Safari scroller', nobounce: 'Safari scroller, no bounce' };
  bar.innerHTML = Object.keys(label).map(m => {
    const p = new URLSearchParams(location.search);
    p.set('scroll', m);
    return `<a href="?${p}"${m === mode ? ' class="on"' : ''}>${label[m]}</a>`;
  }).join('');
  const style = document.createElement('style');
  style.textContent = `
    #proto-bar{position:fixed;left:12px;top:12px;z-index:5;display:flex;flex-direction:column;gap:4px;padding:4px;border-radius:10px;background:rgba(0,0,0,.06);font:13px/1 -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    #proto-bar a{padding:7px 10px;border-radius:7px;color:#6e6e73;text-decoration:none}
    #proto-bar a.on{background:#fff;color:#1a1a1f}
    @media (max-width:899px){#proto-bar{display:none}}
    #native-scroller{position:absolute;inset:0;overflow-x:hidden;overflow-y:scroll;scrollbar-width:none;background:#fff}
    #native-scroller::-webkit-scrollbar{display:none}
    #native-scroller.nobounce{overscroll-behavior:none}
    #native-pin{position:sticky;top:0;height:100%}`;
  document.head.appendChild(style);
  addEventListener('DOMContentLoaded', () => document.body.appendChild(bar));
  if (mode === 'ours') return;

  const app = () => document.getElementById('app');
  const wait = () => {
    const canvas = app() && app().querySelector('canvas');
    if (!canvas || !window.__swiftuiwebDebug || !window.__swiftuiwebDebug.scrollViews) return requestAnimationFrame(wait);
    setup(canvas);
  };
  requestAnimationFrame(wait);

  function setup(canvas) {
    const D = window.__swiftuiwebDebug;
    const scroller = document.createElement('div');
    scroller.id = 'native-scroller';
    if (mode === 'nobounce') scroller.classList.add('nobounce');
    const pin = document.createElement('div');
    pin.id = 'native-pin';
    const spacer = document.createElement('div');
    canvas.parentNode.insertBefore(scroller, canvas);
    pin.appendChild(canvas);
    scroller.append(pin, spacer);

    // The app's vertical scroll view the box stands for: the innermost one under the pointer that
    // can scroll vertically. [index, point in the canvas where synthetic wheels are aimed]
    let target = null, pointer = null, applied = 0, lastMove = -1e9;
    const log = [];
    window.__scrollProto.state = () => ({ target, applied, top: scroller.scrollTop, height: spacer.style.height });

    scroller.addEventListener('pointermove', e => { pointer = [e.clientX, e.clientY]; }, { capture: true, passive: true });
    // Vertical trackpad and wheel events go to the native box only (no preventDefault: Safari scrolls
    // it). Pinches and sideways swipes still reach the app, which handles them as today.
    scroller.addEventListener('wheel', e => {
      if (e.__proxy || e.ctrlKey || !target) return;
      if (Math.abs(e.deltaX) > Math.abs(e.deltaY)) return;
      e.stopPropagation();
    }, { capture: true, passive: true });

    function resync() {
      const views = D.scrollViews();
      const rect = canvas.getBoundingClientRect();
      const p = pointer || [rect.left + rect.width / 2, rect.top + rect.height / 2];
      const x = p[0] - rect.left, y = p[1] - rect.top;
      let pick = -1;
      for (let i = 0; i < views.length; i++) {
        const v = views[i];
        // [x, y, w, h, offsetX, offsetY, maxX, maxY, reached]: a hidden tab's view is not reached.
        if (v.length < 9 || v[7] <= 0 || v[8] !== 1) continue;
        if (x >= v[0] && x < v[0] + v[2] && y >= v[1] && y < v[1] + v[3]) pick = i;
      }
      if (pick < 0) { target = null; spacer.style.height = '0px'; return; }
      const v = views[pick];
      target = { i: pick, x, y };
      const height = Math.round(v[7]) + 'px';
      if (spacer.style.height !== height) spacer.style.height = height;
      if (Math.abs(scroller.scrollTop - v[5]) >= 1) scroller.scrollTop = v[5];
      applied = scroller.scrollTop;
    }

    const frame = () => {
      requestAnimationFrame(frame);
      const now = performance.now();
      const top = scroller.scrollTop;
      if (target && top !== applied) {
        const v = D.scrollViews()[target.i];
        if (v) {
          const delta = top - v[5];
          if (delta !== 0) {
            const rect = canvas.getBoundingClientRect();
            const ev = new WheelEvent('wheel', { deltaX: 0, deltaY: delta, deltaMode: 0, clientX: rect.left + target.x, clientY: rect.top + target.y, bubbles: true, cancelable: true });
            ev.__proxy = true;
            canvas.dispatchEvent(ev);
          }
          if (log.length < 3000) log.push([Math.round(now * 10) / 10, Math.round(top * 10) / 10, Math.round(v[5] * 10) / 10, Math.round(delta * 10) / 10]);
        }
        applied = top;
        lastMove = now;
      } else if (now - lastMove > 200) {
        resync();
      }
    };
    requestAnimationFrame(frame);

    // Each frame of a native scroll: [time, box position, app offset before, delta sent].
    setInterval(() => {
      if (log.length && window.__phoneTry) window.__phoneTry.send('native-scroll', { mode, frames: log.splice(0) });
    }, 4000);
  }
})();
