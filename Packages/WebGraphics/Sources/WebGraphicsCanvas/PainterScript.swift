/// The Canvas2D decoder for `DisplayListEncoder`'s flat format, injected into the page once.
/// Kept as a Swift string so an app needs nothing but its wasm bundle. Opcodes must match
/// `DisplayOp` / `DisplayPathOp` in SwiftUIWebCore.
enum PainterScript {
    static let source = #"""
    (function () {
      if (window.__swiftuiweb) return;
      const colorCache = new Map();
      function color(r, g, b, a) {
        const k = r + ',' + g + ',' + b + ',' + a;
        let s = colorCache.get(k);
        if (!s) { s = 'rgba(' + r + ',' + g + ',' + b + ',' + a + ')'; colorCache.set(k, s); }
        return s;
      }
      // A font string may carry letter spacing (points) after a '|', and '|t<ratio>' after that
      // for tabular figures: the digit slot as a multiple of the "0" advance (Canvas2D has no
      // font-variant-numeric). Returns the spacing the context could not apply itself (no
      // letterSpacing: WebKit, Firefox), for fillSpacedText; sets tabularSlot for the font.
      let tabularSlot = 0;
      const slotCache = new Map();
      function isDigit(ch) { return ch >= '0' && ch <= '9'; }
      function setFont(ctx, font) {
        const parts = font.split('|');
        ctx.font = parts[0];
        // Kerning on, as Core Text lays out: Chrome's canvas leaves "auto" without the pairs that
        // start at a space (" W", " M" in San Francisco), so a 28 pt bold line measured 3 pt wider
        // than on iOS and in Chrome's own page text, and wrapped a word early. WebKit kerns either way.
        if (ctx.fontKerning !== undefined) ctx.fontKerning = 'normal';
        if (parts.length > 2 && parts[2][0] === 't') {
          let slot = slotCache.get(font);
          if (slot === undefined) { slot = ctx.measureText('0').width * Number(parts[2].slice(1)); slotCache.set(font, slot); }
          tabularSlot = slot;
        } else {
          tabularSlot = 0;
        }
        const spacing = parts.length > 1 ? Number(parts[1]) : 0;
        if ('letterSpacing' in ctx) { ctx.letterSpacing = spacing + 'px'; return 0; }
        return spacing;
      }
      // Draws text with `spacing` after every character when the context cannot space itself,
      // and digits centred in fixed slots when the font is tabular.
      function fillSpacedText(ctx, text, x, y, spacing) {
        if (!spacing && !tabularSlot) { ctx.fillText(text, x, y); return; }
        let cursor = x;
        const slot = tabularSlot;
        for (const ch of Array.from(text)) {
          const w = ctx.measureText(ch).width;
          if (slot && isDigit(ch)) {
            ctx.fillText(ch, cursor + (slot - w) / 2, y);
            cursor += slot + spacing;
          } else {
            ctx.fillText(ch, cursor, y);
            cursor += w + spacing;
          }
        }
      }
      // Text drawn as a stored picture of itself, in WebKit only. WebKit's canvas reuses its work
      // for a line it drew before only while letterSpacing is 0: a spaced line (most text, since
      // San Francisco is tracked at every size) costs about 11 us a call in Safari 26, against 1 us
      // unspaced and 0.25 us for drawing a stored picture (new-website#285). Chromium spaces for
      // free and draws such pictures slower, so it keeps fillText. A line becomes a picture the
      // second time it is drawn the same way, so text that changes every frame stays fillText.
      // The picture is drawn on whole device pixels and holds the text at its fraction of a pixel:
      // across, to 1/64 (WebKit places glyphs continuously, and scrolling down never changes it);
      // down, rounded up to 1/8, as WebKit itself moves text down a whole pixel at nearly any
      // fraction above one, so at most 8 pictures of a line while it scrolls.
      const textPictures = /Apple/.test(navigator.vendor || '') && typeof OffscreenCanvas === 'function';
      const pictureCache = new Map(), pictureSeen = new Set();
      let picturePixels = 0;
      const pictureBudget = 4 * 1024 * 1024; // device pixels kept, about 16 MB
      const inkCache = new Map();
      // measureText's ink box of a line in a font, kept (WebKit's measureText costs ~5 us a call).
      function ink(ctx, font, text) {
        const k = font + '\n' + text;
        let m = inkCache.get(k);
        if (m === undefined) {
          const r = ctx.measureText(text);
          m = { width: r.width, left: r.actualBoundingBoxLeft || 0, right: r.actualBoundingBoxRight || 0, ascent: r.actualBoundingBoxAscent || 0, descent: r.actualBoundingBoxDescent || 0 };
          if (inkCache.size > 4000) inkCache.clear();
          inkCache.set(k, m);
        }
        return m;
      }
      // Draws text (setFont already applied to ctx, `spacing` what it returned) as a picture when
      // that pays; returns false when the caller should draw it itself.
      function drawTextPicture(ctx, font, text, x, y, fill, spacing) {
        if (!textPictures || ctx.globalCompositeOperation !== 'source-over') return false;
        if (!spacing && !tabularSlot && (ctx.letterSpacing || '0px') === '0px') return false;
        const t = ctx.getTransform();
        if (t.b !== 0 || t.c !== 0 || t.a <= 0 || t.a !== t.d) return false;
        const s = t.a;
        const dx = s * x + t.e, dy = s * y + t.f;
        let ix = Math.floor(dx), iy = Math.floor(dy);
        let qx = Math.round((dx - ix) * 64) / 64, qy = Math.ceil((dy - iy) * 8) / 8;
        if (qx === 1) { ix++; qx = 0; }
        if (qy === 1) { iy++; qy = 0; }
        const key = font + '\n' + fill + '\n' + s + '\n' + qx + '\n' + qy + '\n' + text;
        let p = pictureCache.get(key);
        if (p === undefined) {
          if (!pictureSeen.has(key)) {
            if (pictureSeen.size > 4000) pictureSeen.clear();
            pictureSeen.add(key);
            return false;
          }
          const m = ink(ctx, font, text);
          const count = text.length;
          const pad = 2;
          const left = Math.ceil((Math.max(0, m.left) + pad) * s);
          const top = Math.ceil((m.ascent + pad) * s);
          const right = Math.ceil((Math.max(m.width, m.right) + Math.abs(spacing) * count + tabularSlot * count + pad) * s);
          const bottom = Math.ceil((m.descent + pad) * s);
          const w = left + right + 1, h = top + bottom + 1;
          const canvas = new OffscreenCanvas(w, h);
          const pctx = canvas.getContext('2d');
          pctx.setTransform(s, 0, 0, s, left + qx, top + qy);
          pctx.textBaseline = 'alphabetic';
          const own = setFont(pctx, font);
          pctx.fillStyle = fill;
          fillSpacedText(pctx, text, 0, 0, own);
          p = { canvas, left, top, w, h };
          pictureCache.set(key, p);
          picturePixels += w * h;
          for (const [k, old] of pictureCache) {
            if (picturePixels <= pictureBudget) break;
            pictureCache.delete(k);
            picturePixels -= old.w * old.h;
          }
        } else {
          // Most recently used last, so the budget drops the oldest first.
          pictureCache.delete(key);
          pictureCache.set(key, p);
        }
        ctx.drawImage(p.canvas, (ix - p.left - t.e) / s, (iy - p.top - t.f) / s, p.w / s, p.h / s);
        return true;
      }
      const lineCaps = ['butt', 'round', 'square'];
      const lineJoins = ['miter', 'round', 'bevel'];
      // The box of the path last read (its points and control points, which bound the curves),
      // for the group bounds below.
      const pathBox = { x0: 0, y0: 0, x1: 0, y1: 0 };
      function readPath(ctx, buf, i) {
        const count = buf[i++];
        ctx.beginPath();
        let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
        const pt = (x, y) => { if (x < x0) x0 = x; if (x > x1) x1 = x; if (y < y0) y0 = y; if (y > y1) y1 = y; };
        for (let k = 0; k < count; k++) {
          const tag = buf[i++];
          switch (tag) {
            case 0: { const x = buf[i++], y = buf[i++]; ctx.moveTo(x, y); pt(x, y); break; }
            case 1: { const x = buf[i++], y = buf[i++]; ctx.lineTo(x, y); pt(x, y); break; }
            case 2: { const x = buf[i++], y = buf[i++], cx = buf[i++], cy = buf[i++]; ctx.quadraticCurveTo(cx, cy, x, y); pt(x, y); pt(cx, cy); break; }
            case 3: { const x = buf[i++], y = buf[i++], c1x = buf[i++], c1y = buf[i++], c2x = buf[i++], c2y = buf[i++]; ctx.bezierCurveTo(c1x, c1y, c2x, c2y, x, y); pt(x, y); pt(c1x, c1y); pt(c2x, c2y); break; }
            case 4: ctx.closePath(); break;
          }
        }
        pathBox.x0 = x0; pathBox.y0 = y0; pathBox.x1 = x1; pathBox.y1 = y1;
        return i;
      }
      // Catalog images by file, loaded on first use; the host is told when one arrives so it
      // can paint again. `base` comes from the manifest script (window.__swiftuiwebAssets).
      const images = new Map();
      let pending = 0;
      let onImageLoad = null;
      // `background` loads (AsyncImage URLs) are not counted as pending: the page is complete
      // without them, and they may never resolve.
      function image(file, background) {
        let entry = images.get(file);
        if (entry) return entry.ready ? entry.img : null;
        const img = new Image();
        entry = { img: img, ready: false };
        images.set(file, entry);
        if (!background) pending++;
        const done = () => { if (!background) pending--; if (onImageLoad) onImageLoad(file, entry.ready); };
        img.onload = () => { entry.ready = true; done(); };
        img.onerror = () => { entry.failed = true; console.error('SwiftUIWeb: could not load image ' + file); done(); };
        const base = (window.__swiftuiwebAssets && window.__swiftuiwebAssets.base) || '';
        // Absolute URLs (AsyncImage) load as they are; catalog files sit under the asset base.
        const absolute = /^([a-z]+:)?\/\//i.test(file);
        // A cross-origin image is asked for with CORS: drawn into the canvas without it, the
        // image would taint the canvas and every later pixel read (blurs, masks, blend groups)
        // would throw, abandoning the frame. A server that does not allow the origin then fails
        // the load — AsyncImage's failure phase — instead of poisoning the page.
        if (absolute && !file.startsWith(location.origin + '/')) img.crossOrigin = 'anonymous';
        img.src = absolute || file.startsWith('data:') || file.startsWith('/') ? file : base + file;
        return null;
      }
      // AsyncImage: a load no view needs any more is dropped (the element's source cleared), so
      // a later request starts over.
      function imageCancel(url) {
        const entry = images.get(url);
        if (!entry || entry.ready || entry.failed) return;
        entry.img.onload = null;
        entry.img.onerror = null;
        entry.img.src = '';
        images.delete(url);
      }
      // AsyncImage: starts loading `url` if needed; 'loading', 'failed', or [width, height].
      function imageState(url) {
        const entry = images.get(url);
        if (!entry) { image(url, true); return 'loading'; }
        if (entry.failed) return 'failed';
        if (!entry.ready) return 'loading';
        return [entry.img.naturalWidth, entry.img.naturalHeight];
      }
      // Draws `img` (or one part of it) tinted: the image's alpha filled with `tint`.
      function tinted(img, sx, sy, sw, sh, dw, dh, dpr, tint, smoothing) {
        const pw = Math.max(1, Math.round(dw * dpr)), ph = Math.max(1, Math.round(dh * dpr));
        const off = new OffscreenCanvas(pw, ph);
        const octx = off.getContext('2d');
        octx.imageSmoothingEnabled = smoothing;
        octx.drawImage(img, sx, sy, sw, sh, 0, 0, pw, ph);
        octx.globalCompositeOperation = 'source-in';
        if (tint.gradient) {
          // The gradient was made in point space at the image's frame: map the offscreen onto it.
          octx.scale(dpr, dpr);
          octx.translate(-tint.x, -tint.y);
          octx.fillStyle = tint.gradient.style;
          octx.fillRect(tint.x, tint.y, pw / dpr, ph / dpr);
        } else {
          octx.fillStyle = tint;
          octx.fillRect(0, 0, pw, ph);
        }
        return off;
      }
      // One part of a draw: source rect in image pixels, destination in points, stretched or tiled.
      function part(ctx, img, sx, sy, sw, sh, dx, dy, dw, dh, tile, scale, dpr, tint, smoothing) {
        if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
        if (tile) {
          const tw = sw / scale, th = sh / scale;
          ctx.save();
          ctx.beginPath(); ctx.rect(dx, dy, dw, dh); ctx.clip();
          for (let y = dy; y < dy + dh; y += th) {
            for (let x = dx; x < dx + dw; x += tw) {
              if (tint) { ctx.drawImage(tinted(img, sx, sy, sw, sh, tw, th, dpr, tint, smoothing), x, y, tw, th); }
              else { ctx.drawImage(img, sx, sy, sw, sh, x, y, tw, th); }
            }
          }
          ctx.restore();
        } else if (tint) {
          ctx.drawImage(tinted(img, sx, sy, sw, sh, dw, dh, dpr, tint, smoothing), dx, dy, dw, dh);
        } else {
          ctx.drawImage(img, sx, sy, sw, sh, dx, dy, dw, dh);
        }
      }
      function drawImage(ctx, dpr, file, scale, pw, ph, x, y, w, h, tile, top, leading, bottom, trailing, smoothing, tint) {
        const img = image(file);
        if (!img) return;
        const previous = ctx.imageSmoothingEnabled;
        ctx.imageSmoothingEnabled = smoothing;
        if (top === 0 && leading === 0 && bottom === 0 && trailing === 0) {
          part(ctx, img, 0, 0, pw, ph, x, y, w, h, tile, scale, dpr, tint, smoothing);
        } else {
          // Nine parts: rigid corners, edges stretched (or tiled) along one axis, the centre along both.
          const l = leading * scale, r = trailing * scale, t = top * scale, b = bottom * scale;
          const sxs = [0, l, pw - r], sws = [l, pw - l - r, r];
          const sys = [0, t, ph - b], shs = [t, ph - t - b, b];
          const dxs = [x, x + leading, x + w - trailing], dws = [leading, w - leading - trailing, trailing];
          const dys = [y, y + top, y + h - bottom], dhs = [top, h - top - bottom, bottom];
          for (let i = 0; i < 3; i++) {
            for (let j = 0; j < 3; j++) {
              const rigid = i !== 1 && j !== 1;
              part(ctx, img, sxs[i], sys[j], sws[i], shs[j], dxs[i], dys[j], dws[i], dhs[j], tile && !rigid, scale, dpr, tint, smoothing);
            }
          }
        }
        ctx.imageSmoothingEnabled = previous;
      }
      function readGradient(ctx, buf, i) {
        const kind = buf[i++];
        let style;
        if (kind === 0) style = ctx.createLinearGradient(buf[i++], buf[i++], buf[i++], buf[i++]);
        else if (kind === 1) { const cx = buf[i++], cy = buf[i++], r0 = buf[i++], r1 = buf[i++]; style = ctx.createRadialGradient(cx, cy, r0, cx, cy, r1); }
        else if (kind === 2) { const cx = buf[i++], cy = buf[i++], angle = buf[i++]; style = ctx.createConicGradient(angle, cx, cy); }
        else if (kind === 3) { const x0 = buf[i++], y0 = buf[i++], r0 = buf[i++], x1 = buf[i++], y1 = buf[i++], r1 = buf[i++]; style = ctx.createRadialGradient(x0, y0, r0, x1, y1, r1); }
        else {
          // Elliptical: a circle in a space squashed about the centre; fills clip and fill a
          // rectangle in that space (strokes and text take the circle of the horizontal radius).
          const cx = buf[i++], cy = buf[i++], r0 = buf[i++], r1 = buf[i++], aspect = buf[i++];
          style = ctx.createRadialGradient(cx, cy, r0, cx, cy, r1);
          const squashed = ctx.createRadialGradient(0, 0, r0, 0, 0, r1);   // about the origin of the squashed space
          const count = buf[i++];
          for (let k = 0; k < count; k++) {
            const loc = Math.min(Math.max(buf[i++], 0), 1), c = color(buf[i++], buf[i++], buf[i++], buf[i++]);
            style.addColorStop(loc, c);
            squashed.addColorStop(loc, c);
          }
          return { style, i, squash: { cx, cy, aspect, style: squashed } };
        }
        const count = buf[i++];
        for (let k = 0; k < count; k++) { const loc = buf[i++]; style.addColorStop(Math.min(Math.max(loc, 0), 1), color(buf[i++], buf[i++], buf[i++], buf[i++])); }
        return { style, i };
      }
      // Fills the current path with a gradient, squashing an elliptical one about its centre.
      function fillGradient(ctx, g, rule) {
        if (!g.squash) { ctx.fillStyle = g.style; ctx.fill(rule); return; }
        const { cx, cy, aspect } = g.squash;
        ctx.save();
        ctx.clip(rule);
        ctx.translate(cx, cy);
        ctx.scale(1, aspect);
        ctx.fillStyle = g.squash.style;
        const reach = 1e5;
        ctx.fillRect(-reach, -reach / aspect, 2 * reach, 2 * reach / aspect);
        ctx.restore();
      }
      // A bitmap by value, drawn through an offscreen canvas so clips and transforms apply.
      function drawBitmap(ctx, bitmap, x, y, w, h) {
        if (!bitmap.canvas) {
          const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
          canvas.getContext('2d').putImageData(new ImageData(bitmap.pixels, bitmap.width, bitmap.height), 0, 0);
          bitmap.canvas = canvas;
        }
        ctx.drawImage(bitmap.canvas, x, y, w, h);
      }
      const blendOps = ['source-over', 'multiply', 'screen', 'overlay', 'darken', 'lighten', 'color-dodge', 'color-burn', 'soft-light', 'hard-light',
        'difference', 'exclusion', 'hue', 'saturation', 'color', 'luminosity', 'source-atop', 'destination-over', 'destination-out', 'plus-darker', 'lighter'];
      // Whether the 2D context's `filter` blurs (the native path); otherwise the box blur in
      // script runs. Told by drawing, not by the property: a context without the attribute
      // takes the assignment as a plain property and reads it back.
      let canvasFilters = null;
      function hasCanvasFilters() {
        if (canvasFilters === null) {
          const dot = new OffscreenCanvas(9, 9), dctx = dot.getContext('2d');
          dctx.fillStyle = '#000'; dctx.fillRect(4, 4, 1, 1);
          const probe = new OffscreenCanvas(9, 9).getContext('2d');
          probe.filter = 'blur(1px)'; probe.drawImage(dot, 0, 0); probe.filter = 'none';
          canvasFilters = probe.getImageData(3, 4, 1, 1).data[3] > 0;
        }
        return canvasFilters;
      }
      // The device-pixel box of a rectangle in the context's current space, padded and clamped.
      function deviceBounds(ctx, x, y, w, h, pad, cw, ch) {
        const t = ctx.getTransform();
        let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
        for (const [px, py] of [[x, y], [x + w, y], [x, y + h], [x + w, y + h]]) {
          const dx = t.a * px + t.c * py + t.e, dy = t.b * px + t.d * py + t.f;
          minX = Math.min(minX, dx); minY = Math.min(minY, dy); maxX = Math.max(maxX, dx); maxY = Math.max(maxY, dy);
        }
        minX = Math.max(0, Math.floor(minX - pad)); minY = Math.max(0, Math.floor(minY - pad));
        maxX = Math.min(cw, Math.ceil(maxX + pad)); maxY = Math.min(ch, Math.ceil(maxY + pad));
        return { x: minX, y: minY, w: Math.max(0, maxX - minX), h: Math.max(0, maxY - minY), scale: Math.hypot(t.a, t.b) };
      }
      function clamp255(v) { return v < 0 ? 0 : v > 255 ? 255 : Math.round(v); }
      // Applies a 4 × 5 colour matrix (straight alpha, 0…1) to the pixels of `b` in `octx`.
      function applyColorMatrix(octx, b, m) {
        if (b.w <= 0 || b.h <= 0) return;
        const img = octx.getImageData(b.x, b.y, b.w, b.h), d = img.data;
        for (let i = 0; i < d.length; i += 4) {
          const r = d[i] / 255, g = d[i + 1] / 255, bl = d[i + 2] / 255, a = d[i + 3] / 255;
          d[i] = clamp255((m[0] * r + m[1] * g + m[2] * bl + m[3] * a + m[4]) * 255);
          d[i + 1] = clamp255((m[5] * r + m[6] * g + m[7] * bl + m[8] * a + m[9]) * 255);
          d[i + 2] = clamp255((m[10] * r + m[11] * g + m[12] * bl + m[13] * a + m[14]) * 255);
          d[i + 3] = clamp255((m[15] * r + m[16] * g + m[17] * bl + m[18] * a + m[19]) * 255);
        }
        octx.putImageData(img, b.x, b.y);
      }
      // Blurs `off` within `b`: returns the canvas to composite (the browser's filter when it
      // has one; otherwise a fresh offscreen holding the box blurred in script). An opaque blur
      // keeps the original alpha.
      function blurred(off, b, sigma, opaque) {
        if (b.w <= 0 || b.h <= 0 || sigma <= 0) return off;
        const out = takeOffscreen(off.width, off.height);
        const ctx = out.getContext('2d');
        if (!hasCanvasFilters()) {
          // WebKit's contexts have no `filter` (Safari, Firefox's OffscreenCanvas). The blur is
          // drawn on the GPU by halving the box until one pixel stands for the blur's reach (a
          // 2^n halving averages a 2^n box, σ ≈ 0.29 · 2^n) and drawing it back up through the
          // same sizes, each step smoothed. It used to read the pixels back and box-blur them in
          // script: in Safari every canvas is drawn in the GPU process, so each readback waited
          // for the whole frame's drawing, and a material bar's three readbacks a frame were
          // four fifths of a scroll frame's paint (new-website#216: 16 → 3 ms).
          const levels = Math.max(1, Math.round(Math.log2(sigma * 3.46 / 2)));
          let cur = off, cx = b.x, cy = b.y, cw = b.w, ch = b.h;
          const chain = [];
          for (let level = 0; level < levels && (cw > 1 || ch > 1); level++) {
            const nw = Math.max(1, Math.round(cw / 2)), nh = Math.max(1, Math.round(ch / 2));
            const next = chainCanvas(level, nw, nh), nctx = next.getContext('2d');
            nctx.globalCompositeOperation = 'copy';
            nctx.drawImage(cur, cx, cy, cw, ch, 0, 0, nw, nh);
            chain.push(next); cur = next; cx = 0; cy = 0; cw = nw; ch = nh;
          }
          for (let level = chain.length - 2; level >= 0; level--) {
            const up = chain[level], uctx = up.getContext('2d');
            uctx.globalCompositeOperation = 'copy';
            uctx.drawImage(cur, 0, 0, cw, ch, 0, 0, up.width, up.height);
            cur = up; cw = up.width; ch = up.height;
          }
          ctx.imageSmoothingEnabled = true;
          ctx.imageSmoothingQuality = 'high';
          ctx.drawImage(cur, 0, 0, cw, ch, b.x, b.y, b.w, b.h);
        } else {
          ctx.filter = 'blur(' + sigma + 'px)';
          ctx.drawImage(off, 0, 0);
          ctx.filter = 'none';
        }
        if (opaque) {
          // The original's alpha, without reading pixels back: the original goes under the blur
          // (where the blur drew in transparency from past the box) and then masks it.
          ctx.save();
          ctx.globalCompositeOperation = 'destination-over';
          ctx.drawImage(off, b.x, b.y, b.w, b.h, b.x, b.y, b.w, b.h);
          ctx.globalCompositeOperation = 'destination-in';
          ctx.drawImage(off, b.x, b.y, b.w, b.h, b.x, b.y, b.w, b.h);
          ctx.restore();
        }
        return out;
      }
      // The canvases of the GPU blur's chain, kept by level and resized only when the box changes.
      const blurChain = [];
      function chainCanvas(level, w, h) {
        let canvas = blurChain[level];
        if (!canvas) { canvas = blurChain[level] = new OffscreenCanvas(w, h); }
        else if (canvas.width !== w || canvas.height !== h) { canvas.width = w; canvas.height = h; }
        const cctx = canvas.getContext('2d');
        cctx.imageSmoothingEnabled = true;
        cctx.imageSmoothingQuality = 'high';
        return canvas;
      }
      // plus-darker has no canvas operation: max(0, source + destination − 1), premultiplied.
      function plusDarker(parent, off, b) {
        if (b.w <= 0 || b.h <= 0) return;
        const dst = parent.getImageData(b.x, b.y, b.w, b.h), d = dst.data;
        const s = off.getContext('2d').getImageData(b.x, b.y, b.w, b.h).data;
        for (let i = 0; i < d.length; i += 4) {
          const sa = s[i + 3] / 255, da = d[i + 3] / 255;
          const a = Math.max(0, sa + da - 1);
          if (a <= 0) { d[i] = d[i + 1] = d[i + 2] = d[i + 3] = 0; continue; }
          for (let c = 0; c < 3; c++) d[i + c] = clamp255(Math.max(0, s[i + c] * sa + d[i + c] * da - 255) / a);
          d[i + 3] = clamp255(a * 255);
        }
        const patch = new OffscreenCanvas(b.w, b.h);
        patch.getContext('2d').putImageData(dst, 0, 0);
        parent.clearRect(b.x, b.y, b.w, b.h);
        parent.drawImage(patch, b.x, b.y);
      }
      // Offscreen canvases are kept between frames: a full-window canvas costs milliseconds to
      // allocate on a phone, and a frame with shadows or opacity groups needs a few. Each frame
      // takes them in order and `reset()` wipes pixels, state and clip; browsers without
      // `reset` get a fresh canvas every time.
      const pool = [];
      let poolUsed = 0;
      function takeOffscreen(pw, ph) {
        let off = pool[poolUsed];
        if (off && off.width === pw && off.height === ph && typeof off.getContext('2d').reset === 'function') {
          off.getContext('2d').reset();
        } else {
          off = new OffscreenCanvas(pw, ph);
          pool[poolUsed] = off;
        }
        poolUsed++;
        return off;
      }
      // A canvas-sized offscreen for a group, drawing in the parent's current space (groups can
      // begin inside a transform); it is composited back in device space.
      function beginOffscreen(ctx, dpr, w, h) {
        const off = takeOffscreen(Math.max(1, Math.round(w * dpr)), Math.max(1, Math.round(h * dpr)));
        const octx = off.getContext('2d');
        octx.setTransform(ctx.getTransform());
        octx.textBaseline = 'alphabetic';
        return { off: off, octx: octx };
      }
      // A group (opacity, shadow, filter, blend, mask) paints into a canvas-sized offscreen; what
      // it composites back is only the box its ops painted, in device pixels: every drawing op
      // inside a group unions its box, through the context's transform, into the innermost
      // group's `box` (padded a pixel for anti-aliasing; a stroke by its width and miter; text
      // by its measured ink), and a group composited into its parent unions the box it covered,
      // padded by a shadow's reach. A shadow or a blur over the whole canvas costs the whole
      // canvas (two shadows under Ember's comment rows were 20 ms of a 35 ms frame); over the
      // box it costs the box.
      function unionDeviceBox(ctx, box, x0, y0, x1, y1, pad) {
        const m = ctx.getTransform();
        const xs = [m.a * x0 + m.c * y0 + m.e, m.a * x1 + m.c * y0 + m.e, m.a * x0 + m.c * y1 + m.e, m.a * x1 + m.c * y1 + m.e];
        const ys = [m.b * x0 + m.d * y0 + m.f, m.b * x1 + m.d * y0 + m.f, m.b * x0 + m.d * y1 + m.f, m.b * x1 + m.d * y1 + m.f];
        const scale = Math.sqrt(Math.max(Math.abs(m.a * m.d - m.b * m.c), m.a * m.a + m.b * m.b));
        const p = (pad || 0) * scale + 1.5;
        const bx0 = Math.min(xs[0], xs[1], xs[2], xs[3]) - p, bx1 = Math.max(xs[0], xs[1], xs[2], xs[3]) + p;
        const by0 = Math.min(ys[0], ys[1], ys[2], ys[3]) - p, by1 = Math.max(ys[0], ys[1], ys[2], ys[3]) + p;
        if (bx0 < box.x0) box.x0 = bx0; if (bx1 > box.x1) box.x1 = bx1;
        if (by0 < box.y0) box.y0 = by0; if (by1 > box.y1) box.y1 = by1;
      }
      function emptyBox() { return { x0: Infinity, y0: Infinity, x1: -Infinity, y1: -Infinity }; }
      // The box clamped to the canvas, as integers, or null when nothing was painted.
      function clampedBox(box, cw, ch, pad) {
        const p = pad || 0;
        const x0 = Math.max(0, Math.floor(box.x0 - p)), y0 = Math.max(0, Math.floor(box.y0 - p));
        const x1 = Math.min(cw, Math.ceil(box.x1 + p)), y1 = Math.min(ch, Math.ceil(box.y1 + p));
        return x1 > x0 && y1 > y0 ? { x: x0, y: y0, w: x1 - x0, h: y1 - y0 } : null;
      }
      function textBox(ctx, font, text, x, y, box) {
        const spacing = setFont(ctx, font);
        const m = ink(ctx, font, text);
        const ascent = m.ascent, descent = m.descent;
        const left = m.left;
        const width = m.width + left + m.right + (spacing + tabularSlot) * text.length;
        unionDeviceBox(ctx, box, x - left, y - ascent, x - left + width, y + descent, 2);
      }
      // Returns the loop's own milliseconds (the host's frame split separates them from the encode).
      // Stored segments (new-website#286): a scroll view's content as the ops between its
      // beginSegment and endSegment, kept with the frame's string and bitmap tables, painted
      // again moved by reuseSegment. The main canvas forgets every segment a frame did not paint
      // (the host paints one again only in the frame after one that painted it).
      const segments = new Map();
      let segmentMisses = 0;
      // Tiles: a segment painted again is drawn into tiles between frames (one tile a task), and
      // once the tiles cover what shows, a frame draws them instead of the segment's ops: a few
      // image copies in place of every fill, shadow and line of text (new-website#286). A segment
      // whose ops read what lies beneath them (a backdrop blur, a blend mode) is never tiled, nor
      // one under a transform that is not a whole-pixel move. Tiles are whole device pixels, at
      // most 512 points and the canvas's size (its groups paint into canvas-sized offscreens).
      const tileMargin = 256;   // as the host's cull margin: a shadow reaching into a tile is in it
      // A tile is painted with this border around it (points) and only its middle kept: a group's
      // shadow is cast from what the group painted inside the canvas, so content just across a
      // tile's edge must be in the canvas for its shadow to reach into the tile.
      const tileBorder = 64;
      let tileScratch = null;
      const wantTiles = new Set();
      let tileTimer = 0, tileMillis = 0, tilesDrawn = 0;
      function tileSize(dpr, w, h) {
        return [Math.floor(Math.min(512, w) * dpr) / dpr, Math.floor(Math.min(512, h) * dpr) / dpr];
      }
      // Draws the tiles under the shown area moved by dx, dy; false when they are not all there
      // (they are asked for) or the segment cannot be drawn from tiles here.
      function drawTiles(ctx, segment, dx, dy, shown, dpr, w, h) {
        const m = ctx.getTransform();
        if (m.b !== 0 || m.c !== 0 || Math.abs(m.a - dpr) > 1e-9 || Math.abs(m.d - dpr) > 1e-9) return false;
        const ex = m.e + dx * dpr, ey = m.f + dy * dpr;
        if (Math.abs(ex - Math.round(ex)) > 1e-6 || Math.abs(ey - Math.round(ey)) > 1e-6) return false;
        const [tw, th] = tileSize(dpr, w, h);
        if (segment.tileW !== tw || segment.tileH !== th || segment.dpr !== dpr) { segment.tiles.clear(); segment.tileW = tw; segment.tileH = th; segment.dpr = dpr; segment.w = w; segment.h = h; }
        if (segment.lastDx !== undefined && (dx !== segment.lastDx || dy !== segment.lastDy)) segment.vertical = Math.abs(dy - segment.lastDy) >= Math.abs(dx - segment.lastDx);
        segment.lastDx = dx; segment.lastDy = dy;
        segment.shown = shown;
        wantTiles.add(segment);
        const i0 = Math.floor(shown.x0 / tw), i1 = Math.ceil(shown.x1 / tw) - 1, j0 = Math.floor(shown.y0 / th), j1 = Math.ceil(shown.y1 / th) - 1;
        for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) if (!segment.tiles.has(i + ',' + j)) return false;
        ctx.save();
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.imageSmoothingEnabled = false;
        for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) {
          ctx.drawImage(segment.tiles.get(i + ',' + j), Math.round(ex + i * tw * dpr), Math.round(ey + j * th * dpr));
        }
        ctx.restore();
        tilesDrawn++;
        return true;
      }
      // The missing tile nearest the shown area: those under it first, then one tile ahead along
      // the way it last moved. Tiles further than two tiles away are let go.
      function nextTile(segment) {
        const s = segment.shown, tw = segment.tileW, th = segment.tileH;
        for (const key of segment.tiles.keys()) {
          const [i, j] = key.split(',').map(Number);
          if ((i + 1) * tw < s.x0 - 2 * tw || i * tw > s.x1 + 2 * tw || (j + 1) * th < s.y0 - 2 * th || j * th > s.y1 + 2 * th) segment.tiles.delete(key);
        }
        const ax = segment.vertical === false ? tw : 0, ay = segment.vertical === false ? 0 : th;
        let best = null, bestDistance = Infinity;
        for (const [rx, ry] of [[0, 0], [ax, ay]]) {
          const i0 = Math.floor((s.x0 - rx) / tw), i1 = Math.ceil((s.x1 + rx) / tw) - 1, j0 = Math.floor((s.y0 - ry) / th), j1 = Math.ceil((s.y1 + ry) / th) - 1;
          for (let i = i0; i <= i1; i++) for (let j = j0; j <= j1; j++) {
            if (segment.tiles.has(i + ',' + j)) continue;
            const cx = (i + 0.5) * tw - (s.x0 + s.x1) / 2, cy = (j + 0.5) * th - (s.y0 + s.y1) / 2;
            const distance = cx * cx + cy * cy;
            if (distance < bestDistance) { best = [i, j]; bestDistance = distance; }
          }
          if (best) return best;
        }
        return null;
      }
      // One tile a task, between frames, until every segment painted again has the tiles it wants.
      function tileTask() {
        tileTimer = 0;
        const started = performance.now();
        for (const segment of wantTiles) {
          if (segments.get(segment.id) !== segment || !segment.tileable) { wantTiles.delete(segment); continue; }
          const next = nextTile(segment);
          if (!next) { wantTiles.delete(segment); continue; }
          const [i, j] = next, tw = segment.tileW, th = segment.tileH, x0 = i * tw, y0 = j * th;
          const dpr = segment.dpr, b = tileBorder, pw = Math.round(tw * dpr), ph = Math.round(th * dpr), pb = Math.round(b * dpr);
          if (!tileScratch || tileScratch.width !== pw + 2 * pb || tileScratch.height !== ph + 2 * pb) tileScratch = new OffscreenCanvas(pw + 2 * pb, ph + 2 * pb);
          const sctx = tileScratch.getContext('2d');
          sctx.setTransform(1, 0, 0, 1, 0, 0);
          sctx.clearRect(0, 0, tileScratch.width, tileScratch.height);
          // The groups inside paint into offscreens the size of the bordered tile.
          paint(sctx, segment.buf, segment.strings, dpr, tw + 2 * b, th + 2 * b, segment.bitmaps, false,
                { x0: x0 - b, y0: y0 - b, start: segment.start, end: segment.end, cull: { x0: x0 - tileMargin, y0: y0 - tileMargin, x1: x0 + tw + tileMargin, y1: y0 + th + tileMargin } });
          // Painting it may have found the segment cannot be tiled.
          if (segment.tileable) {
            const canvas = new OffscreenCanvas(pw, ph);
            canvas.getContext('2d').drawImage(tileScratch, pb, pb, pw, ph, 0, 0, pw, ph);
            segment.tiles.set(i + ',' + j, canvas);
          }
          break;
        }
        tileMillis += performance.now() - started;
        if (wantTiles.size && !tileTimer) tileTimer = setTimeout(tileTask, 0);
      }
      function paint(rootCtx, buf, strings, dpr, w, h, bitmaps, keepsSegments, tile) {
        const started = performance.now();
        poolUsed = 0;
        if (tile) {
          rootCtx.setTransform(dpr, 0, 0, dpr, -tile.x0 * dpr, -tile.y0 * dpr);
        } else {
          rootCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
          rootCtx.clearRect(0, 0, w, h);
        }
        rootCtx.textBaseline = 'alphabetic';
        let ctx = rootCtx;
        const groups = [];
        let box = null;   // the innermost group's painted box, null outside groups
        // The areas that show, innermost segment last: a cull block missing the top one is skipped.
        const culls = [];
        const painted = keepsSegments ? new Set() : null;
        const opened = [];
        // The segments whose ops are running, innermost last (stored or painted again).
        const running = [];
        if (tile) culls.push(tile.cull);
        run(buf, strings, bitmaps, tile ? tile.start : 0, tile ? tile.end : buf.length);
        if (painted) {
          for (const id of segments.keys()) if (!painted.has(id)) segments.delete(id);
          if (wantTiles.size && !tileTimer) tileTimer = setTimeout(tileTask, 0);
        }
        return performance.now() - started;
        function run(buf, strings, bitmaps, start, n) {
        let i = start;
        while (i < n) {
          const op = buf[i++];
          switch (op) {
            case 25: {
              const id = buf[i++], cx = buf[i++], cy = buf[i++], cw = buf[i++], ch = buf[i++];
              // Painting an enclosing segment again meets its inner ones' ops: the stored one stays.
              const stored = segments.get(id);
              const segment = stored && stored.buf === buf && stored.start === i ? stored
                : { id: id, buf: buf, strings: strings, bitmaps: bitmaps, start: i, end: -1, tiles: new Map(), tileable: true };
              segments.set(id, segment);
              opened.push(segment);
              running.push(segment);
              if (painted) painted.add(id);
              culls.push({ x0: cx, y0: cy, x1: cx + cw, y1: cy + ch });
              break;
            }
            case 26: { const segment = opened.pop(); if (segment) segment.end = i - 1; running.pop(); culls.pop(); break; }
            case 27: {
              const id = buf[i++], dx = buf[i++], dy = buf[i++];
              const sx = buf[i++], sy = buf[i++], sw = buf[i++], sh = buf[i++];
              const cx = buf[i++], cy = buf[i++], cw = buf[i++], ch = buf[i++];
              const segment = segments.get(id);
              if (!segment || segment.end < 0) {
                if (segmentMisses++ === 0) console.error('SwiftUIWeb: segment ' + id + ' was not stored');
                break;
              }
              if (painted) painted.add(id);
              // The main canvas draws the segment from its tiles once they are there (never a tile
              // being painted: its inner segments are painted as ops).
              if (!tile && segment.tileable && drawTiles(ctx, segment, dx, dy, { x0: sx, y0: sy, x1: sx + sw, y1: sy + sh }, dpr, w, h)) {
                if (box) unionDeviceBox(ctx, box, sx + dx, sy + dy, sx + sw + dx, sy + sh + dy, 0);
                break;
              }
              ctx.save();
              ctx.translate(dx, dy);
              culls.push({ x0: cx, y0: cy, x1: cx + cw, y1: cy + ch });
              running.push(segment);
              run(segment.buf, segment.strings, segment.bitmaps, segment.start, segment.end);
              running.pop();
              culls.pop();
              ctx.restore();
              break;
            }
            case 28: {
              const x = buf[i++], y = buf[i++], bw = buf[i++], bh = buf[i++], after = buf[i++];
              const c = culls.length ? culls[culls.length - 1] : null;
              // Skipped where painting it afresh would have culled it (a frame missing the area).
              if (c && (x + bw <= c.x0 || x >= c.x1 || y + bh <= c.y0 || y >= c.y1)) i = after;
              break;
            }
            case 29: break;
            case 1: ctx.save(); break;
            case 2: ctx.restore(); break;
            case 3: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; ctx.beginPath(); ctx.rect(x, y, rw, rh); ctx.clip(); break; }
            case 4: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; ctx.beginPath(); ctx.roundRect(x, y, rw, rh, r); ctx.clip(); break; }
            case 5: { i = readPath(ctx, buf, i); ctx.clip(buf[i++] === 1 ? 'evenodd' : 'nonzero'); break; }
            case 6: {
              const opacity = buf[i++];
              const o = beginOffscreen(ctx, dpr, w, h);
              groups.push({ ctx: ctx, off: o.off, opacity: opacity, box: emptyBox() });
              ctx = o.octx; box = groups[groups.length - 1].box;
              break;
            }
            case 7: {
              const g = groups.pop();
              const parent = g.ctx;
              let source = g.off;
              if (g.mask) {
                // The content shows through the mask's alpha.
                const cctx = source.getContext('2d');
                cctx.save();
                cctx.setTransform(1, 0, 0, 1, 0, 0);
                cctx.globalCompositeOperation = 'destination-in';
                cctx.drawImage(g.mask, 0, 0);
                cctx.restore();
              }
              if (g.filter) {
                if (g.filter.matrix) applyColorMatrix(g.off.getContext('2d'), g.bounds, g.filter.matrix);
                else source = blurred(g.off, g.bounds, g.filter.sigma, g.filter.opaque);
              }
              parent.save();
              parent.setTransform(1, 0, 0, 1, 0, 0);
              const outer = groups.length ? groups[groups.length - 1].box : null;
              if (g.blend === 'plus-darker') {
                plusDarker(parent, source, g.bounds);
                if (outer) { const b = g.bounds; unionDeviceBox(parent, outer, b.x, b.y, b.x + b.w, b.y + b.h, 0); }
                parent.restore(); ctx = parent; box = outer; break;
              }
              if (g.blend) parent.globalCompositeOperation = g.blend;
              parent.globalAlpha = g.opacity;
              // What the group painted (a filter group's blur reaches its padded bounds; a mask
              // confines its content, a wider box only costs pixels).
              let region = g.box;
              if (g.filter && g.bounds) { region = { x0: Math.min(region.x0, g.bounds.x), y0: Math.min(region.y0, g.bounds.y), x1: Math.max(region.x1, g.bounds.x + g.bounds.w), y1: Math.max(region.y1, g.bounds.y + g.bounds.h) }; }
              let reach = 0;
              if (g.shadow) {
                // Canvas blur is twice the Gaussian sigma; everything is in device pixels here.
                parent.shadowColor = g.shadow.color;
                parent.shadowBlur = g.shadow.radius * 2 * dpr;
                parent.shadowOffsetX = g.shadow.dx * dpr;
                parent.shadowOffsetY = g.shadow.dy * dpr;
                reach = parent.shadowBlur * 2 + Math.abs(parent.shadowOffsetX) + Math.abs(parent.shadowOffsetY);
              }
              // A shadow's group is drawn over its box widened by the shadow's reach (the extra
              // pixels are clear): WebKit cuts a drawImage shadow off at the source rectangle, so
              // a round button's shadow came out cut into a square.
              const r = clampedBox(region, source.width, source.height, g.shadow ? Math.ceil(reach) : 0);
              if (r) {
                parent.drawImage(source, r.x, r.y, r.w, r.h, r.x, r.y, r.w, r.h);
                if (outer) unionDeviceBox(parent, outer, r.x, r.y, r.x + r.w, r.y + r.h, reach);
              }
              parent.restore();
              ctx = parent; box = outer;
              break;
            }
            case 19: {
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const kind = buf[i++];
              let filter, pad = 0;
              if (kind === 0) {
                const m = [];
                for (let k = 0; k < 20; k++) m.push(buf[i++]);
                filter = { matrix: m };
              } else {
                const radius = buf[i++], opaque = buf[i++] === 1;
                filter = { radius: radius, opaque: opaque };
              }
              const o = beginOffscreen(ctx, dpr, w, h);
              const probe = deviceBounds(ctx, x, y, rw, rh, 0, o.off.width, o.off.height);
              if (filter.radius !== undefined) { filter.sigma = filter.radius * probe.scale; pad = filter.opaque ? 0 : Math.ceil(filter.sigma * 3); }
              const bounds = pad > 0 ? deviceBounds(ctx, x, y, rw, rh, pad, o.off.width, o.off.height) : probe;
              groups.push({ ctx: ctx, off: o.off, opacity: 1, filter: filter, bounds: bounds, box: emptyBox() });
              ctx = o.octx; box = groups[groups.length - 1].box;
              break;
            }
            case 23: {
              // What lies beneath a segment's tile is not in it: a segment that reads it is not tiled.
              for (const segment of running) segment.tileable = false;
              // Backdrop blur: copy what the current target holds, blur the path's device box
              // keeping its alpha, and draw the copy back clipped to the path.
              i = readPath(ctx, buf, i);
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const radius = buf[i++], saturation = buf[i++];
              const target = ctx.canvas;
              const probe = deviceBounds(ctx, x, y, rw, rh, 0, target.width, target.height);
              const sigma = radius * probe.scale;
              const b = deviceBounds(ctx, x, y, rw, rh, Math.ceil(sigma * 3), target.width, target.height);
              if (sigma > 0 && b.w > 0 && b.h > 0) {
                // Only the padded box is copied and blurred, in an offscreen of its own size: the
                // result is clipped to the path, which lies inside the box by the kernel's reach
                // (3σ), so every pixel drawn equals the full-canvas blur — at a fraction of the
                // work (a material bar over a phone's page is a strip, not the page, and the
                // alpha readback below is of the strip too).
                const box = { x: 0, y: 0, w: b.w, h: b.h };
                const copy = takeOffscreen(b.w, b.h);
                const cctx = copy.getContext('2d');
                cctx.setTransform(1, 0, 0, 1, 0, 0);
                cctx.clearRect(0, 0, b.w, b.h);
                // Inside a group (a shadow, an opacity, a filter) the target is the group's own
                // offscreen, empty under the material: the backdrop is the page beneath, so the
                // canvas and each enclosing group's offscreen as painted so far are stacked in order
                // (a glass capsule with shadows blurred nothing and showed the page through it).
                const layers = groups.length ? [groups[0].ctx.canvas].concat(groups.filter(g => !g.maskPending).map(g => g.off)) : [target];
                for (const layer of layers) cctx.drawImage(layer, b.x, b.y, b.w, b.h, 0, 0, b.w, b.h);
                const src = blurred(copy, box, sigma, true);
                if (saturation !== 1) {
                  // The saturation matrix (SVG's feColorMatrix convention) over the blurred box.
                  const s = saturation, lr = 0.2126, lg = 0.7152, lb = 0.0722;
                  applyColorMatrix(src.getContext('2d'), box, [lr + (1 - lr) * s, lg - lg * s, lb - lb * s, 0, 0,
                                                              lr - lr * s, lg + (1 - lg) * s, lb - lb * s, 0, 0,
                                                              lr - lr * s, lg - lg * s, lb + (1 - lb) * s, 0, 0,
                                                              0, 0, 0, 1, 0]);
                }
                ctx.save();
                ctx.clip();
                ctx.setTransform(1, 0, 0, 1, 0, 0);
                ctx.drawImage(src, 0, 0, b.w, b.h, b.x, b.y, b.w, b.h);
                if (box) unionDeviceBox(ctx, box, b.x, b.y, b.x + b.w, b.y + b.h, 0);
                ctx.restore();
              }
              break;
            }
            case 30: {
              // Backdrop lens (new-website#649): the backdrop blur seen through thick glass, as an
              // iOS 27 menu grows. What lies beneath is copied with `bend` points around the shape,
              // blurred, and drawn back in nested rounded rings from the rim in: the outer rings
              // squeeze in content from up to `bend` outside the shape, the centre is drawn a
              // touch magnified, so lines bend toward the rim. Everything is drawn from one small
              // blurred copy (five GPU draws), nothing is read back.
              for (const segment of running) segment.tileable = false;
              i = readPath(ctx, buf, i);
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const radius = buf[i++], bend = buf[i++], corner = buf[i++];
              const target = ctx.canvas;
              const shape = deviceBounds(ctx, x, y, rw, rh, 0, Infinity, Infinity);
              const sigma = radius * shape.scale, bd = bend * shape.scale, cr = corner * shape.scale;
              const b = deviceBounds(ctx, x, y, rw, rh, Math.ceil(bd + sigma * 3), target.width, target.height);
              if (b.w > 0 && b.h > 0 && shape.w > 0 && shape.h > 0) {
                const copyBox = { x: 0, y: 0, w: b.w, h: b.h };
                const copy = takeOffscreen(b.w, b.h);
                const cctx = copy.getContext('2d');
                cctx.setTransform(1, 0, 0, 1, 0, 0);
                cctx.clearRect(0, 0, b.w, b.h);
                const layers = groups.length ? [groups[0].ctx.canvas].concat(groups.filter(g => !g.maskPending).map(g => g.off)) : [target];
                for (const layer of layers) cctx.drawImage(layer, b.x, b.y, b.w, b.h, 0, 0, b.w, b.h);
                const src = sigma > 0 ? blurred(copy, copyBox, sigma, true) : copy;
                ctx.save();
                ctx.clip();
                ctx.setTransform(1, 0, 0, 1, 0, 0);
                ctx.imageSmoothingEnabled = true;
                // Draws the device rect `from` of the backdrop into the device rect `to`, the
                // source kept inside the copy (WebKit draws nothing for a source past its edge).
                const mapped = (fx, fy, fw, fh, tx, ty, tw, th) => {
                  let sx = fx - b.x, sy = fy - b.y, sw = fw, sh = fh;
                  const kx = tw / fw, ky = th / fh;
                  if (sx < 0) { tx -= sx * kx; tw += sx * kx; sw += sx; sx = 0; }
                  if (sy < 0) { ty -= sy * ky; th += sy * ky; sh += sy; sy = 0; }
                  if (sx + sw > b.w) { const cut = sx + sw - b.w; sw -= cut; tw -= cut * kx; }
                  if (sy + sh > b.h) { const cut = sy + sh - b.h; sh -= cut; th -= cut * ky; }
                  if (sw > 0 && sh > 0 && tw > 0 && th > 0) ctx.drawImage(src, sx, sy, sw, sh, tx, ty, tw, th);
                };
                const rim = Math.min(Math.max(bd * 2, 1), Math.min(shape.w, shape.h) / 2);
                const rings = 4;
                for (let k = 0; k <= rings; k++) {
                  const d = rim * k / rings;
                  // How far outside this ring its content comes from: most at the rim, a slight
                  // magnification (negative) at the centre.
                  const f = 1 - k / rings;
                  const o = k === rings ? -bd * 0.12 : bd * f * f;
                  if (k > 0) {
                    ctx.beginPath();
                    const rr = Math.max(0, cr - d);
                    if (ctx.roundRect) ctx.roundRect(shape.x + d, shape.y + d, shape.w - 2 * d, shape.h - 2 * d, rr);
                    else ctx.rect(shape.x + d, shape.y + d, shape.w - 2 * d, shape.h - 2 * d);
                    ctx.clip();
                  }
                  mapped(shape.x + d - o, shape.y + d - o, shape.w - 2 * (d - o), shape.h - 2 * (d - o),
                         shape.x + d, shape.y + d, shape.w - 2 * d, shape.h - 2 * d);
                }
                if (box) unionDeviceBox(ctx, box, b.x, b.y, b.x + b.w, b.y + b.h, 0);
                ctx.restore();
              }
              break;
            }
            case 21: {
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const o = beginOffscreen(ctx, dpr, w, h);
              groups.push({ ctx: ctx, off: o.off, opacity: 1, maskPending: true, box: emptyBox() });
              ctx = o.octx; box = groups[groups.length - 1].box;
              break;
            }
            case 22: {
              // The mask is drawn; the content goes into a second offscreen (its box starts
              // afresh: the content shows through the mask, within the content's own box).
              const g = groups[groups.length - 1];
              const o = beginOffscreen(g.ctx, dpr, w, h);
              g.mask = g.off;
              g.off = o.off;
              g.maskPending = false;
              g.box = emptyBox();
              ctx = o.octx; box = g.box;
              break;
            }
            case 20: {
              for (const segment of running) segment.tileable = false;
              const mode = buf[i++];
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const o = beginOffscreen(ctx, dpr, w, h);
              const bounds = deviceBounds(ctx, x, y, rw, rh, 0, o.off.width, o.off.height);
              groups.push({ ctx: ctx, off: o.off, opacity: 1, blend: blendOps[mode] || 'source-over', bounds: bounds, box: emptyBox() });
              ctx = o.octx; box = groups[groups.length - 1].box;
              break;
            }
            case 18: {
              const shadowColor = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              const radius = buf[i++], dx = buf[i++], dy = buf[i++];
              const o = beginOffscreen(ctx, dpr, w, h);
              groups.push({ ctx: ctx, off: o.off, opacity: 1, shadow: { color: shadowColor, radius: radius, dx: dx, dy: dy }, box: emptyBox() });
              ctx = o.octx; box = groups[groups.length - 1].box;
              break;
            }
            case 8: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++]; ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.fillRect(x, y, rw, rh); if (box) unionDeviceBox(ctx, box, x, y, x + rw, y + rh, 0); break; }
            case 9: { const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++], r = buf[i++]; ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.beginPath(); ctx.roundRect(x, y, rw, rh, r); ctx.fill(); if (box) unionDeviceBox(ctx, box, x, y, x + rw, y + rh, 0); break; }
            case 10: { i = readPath(ctx, buf, i); ctx.fillStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]); ctx.fill(buf[i++] === 1 ? 'evenodd' : 'nonzero'); if (box) unionDeviceBox(ctx, box, pathBox.x0, pathBox.y0, pathBox.x1, pathBox.y1, 0); break; }
            case 11: {
              i = readPath(ctx, buf, i);
              ctx.lineWidth = buf[i++];
              ctx.lineCap = lineCaps[buf[i++]];
              ctx.lineJoin = lineJoins[buf[i++]];
              ctx.miterLimit = buf[i++];
              const dashCount = buf[i++];
              const dashes = [];
              for (let k = 0; k < dashCount; k++) dashes.push(buf[i++]);
              ctx.setLineDash(dashes);
              ctx.lineDashOffset = buf[i++];
              ctx.strokeStyle = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              ctx.stroke();
              if (box) unionDeviceBox(ctx, box, pathBox.x0, pathBox.y0, pathBox.x1, pathBox.y1, ctx.lineWidth * Math.max(1, ctx.miterLimit));
              break;
            }
            case 12: {
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              const fill = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              ctx.fillStyle = fill;
              const spacing = setFont(ctx, font);
              if (!drawTextPicture(ctx, font, text, x, y, fill, spacing)) fillSpacedText(ctx, text, x, y, spacing);
              if (box) textBox(ctx, font, text, x, y, box);
              break;
            }
            case 17: {
              // Gradient text: the text is drawn into an offscreen the size of its ink, the
              // gradient is filled through it (source-in) in the same absolute coordinates, and
              // the result is composited back.
              const text = strings[buf[i++]], font = strings[buf[i++]], x = buf[i++], y = buf[i++];
              setFont(ctx, font);
              const m = ctx.measureText(text);
              const ascent = (m.actualBoundingBoxAscent || 0) + 2, descent = (m.actualBoundingBoxDescent || 0) + 2;
              const left = (m.actualBoundingBoxLeft || 0) + 2, width = Math.ceil(m.width + left + (m.actualBoundingBoxRight || 0) + 4);
              const height = Math.ceil(ascent + descent);
              const ox = x - left, oy = y - ascent;
              const off = new OffscreenCanvas(Math.max(1, Math.ceil(width * dpr)), Math.max(1, Math.ceil(height * dpr)));
              const octx = off.getContext('2d');
              octx.setTransform(dpr, 0, 0, dpr, -ox * dpr, -oy * dpr);
              octx.textBaseline = 'alphabetic';
              const spacing = setFont(octx, font);
              octx.fillStyle = '#000';
              fillSpacedText(octx, text, x, y, spacing);
              const g = readGradient(octx, buf, i); i = g.i;
              octx.globalCompositeOperation = 'source-in';
              octx.fillStyle = g.style;
              octx.fillRect(ox, oy, width, height);
              ctx.drawImage(off, ox, oy, width, height);
              if (box) unionDeviceBox(ctx, box, ox, oy, ox + width, oy + height, 0);
              break;
            }
            case 13: {
              const file = strings[buf[i++]], scale = buf[i++], pw = buf[i++], ph = buf[i++];
              const x = buf[i++], y = buf[i++], rw = buf[i++], rh = buf[i++];
              const tile = buf[i++] === 1, top = buf[i++], leading = buf[i++], bottom = buf[i++], trailing = buf[i++];
              const smoothing = buf[i++] === 1, tintKind = buf[i++];
              let tint = color(buf[i++], buf[i++], buf[i++], buf[i++]);
              if (tintKind === 2) {
                // A gradient tint: the gradient in the image's own space (its frame).
                const g = readGradient(ctx, buf, i); i = g.i;
                tint = { gradient: g, x, y };
              }
              drawImage(ctx, dpr, file, scale, pw, ph, x, y, rw, rh, tile, top, leading, bottom, trailing, smoothing, tintKind > 0 ? tint : null);
              if (box) unionDeviceBox(ctx, box, x, y, x + rw, y + rh, 0);
              break;
            }
            case 14: { const a = buf[i++], b = buf[i++], c = buf[i++], d = buf[i++], e = buf[i++], f = buf[i++]; ctx.transform(a, b, c, d, e, f); break; }
            case 15: {
              i = readPath(ctx, buf, i);
              const g = readGradient(ctx, buf, i); i = g.i;
              fillGradient(ctx, g, buf[i++] === 1 ? 'evenodd' : 'nonzero');
              if (box) unionDeviceBox(ctx, box, pathBox.x0, pathBox.y0, pathBox.x1, pathBox.y1, 0);
              break;
            }
            case 24: {
              const bitmap = (bitmaps || [])[buf[i++]];
              const bx = buf[i++], by = buf[i++], bw = buf[i++], bh = buf[i++];
              drawBitmap(ctx, bitmap, bx, by, bw, bh);
              if (box) unionDeviceBox(ctx, box, bx, by, bx + bw, by + bh, 0);
              break;
            }
            case 16: {
              i = readPath(ctx, buf, i);
              ctx.lineWidth = buf[i++];
              ctx.lineCap = lineCaps[buf[i++]];
              ctx.lineJoin = lineJoins[buf[i++]];
              ctx.miterLimit = buf[i++];
              const dashCount = buf[i++];
              const dashes = [];
              for (let k = 0; k < dashCount; k++) dashes.push(buf[i++]);
              ctx.setLineDash(dashes);
              ctx.lineDashOffset = buf[i++];
              const g = readGradient(ctx, buf, i); i = g.i;
              ctx.strokeStyle = g.style;
              ctx.stroke();
              if (box) unionDeviceBox(ctx, box, pathBox.x0, pathBox.y0, pathBox.x1, pathBox.y1, ctx.lineWidth * Math.max(1, ctx.miterLimit));
              break;
            }
            default: throw new Error('SwiftUIWeb: unknown display op ' + op + ' at ' + (i - 1));
          }
        }
        }
      }
      // The accessibility overlay's elements by semantics identifier: the host positions the
      // ones that moved with one call per frame (each property write crosses the bridge).
      const overlay = new Map();
      function overlayFrames(buf) {
        for (let i = 0; i < buf.length; i += 5) {
          const style = overlay.get(buf[i]);
          if (!style) continue;
          style.left = buf[i + 1] + 'px';
          style.top = buf[i + 2] + 'px';
          if (buf[i + 3] >= 0) { style.width = buf[i + 3] + 'px'; style.height = buf[i + 4] + 'px'; }
        }
      }
      const measureCache = new Map();
      // A bundled font arrived: widths measured with its fallback face are stale.
      function forgetMeasurements() { measureCache.clear(); slotCache.clear(); inkCache.clear(); pictureCache.clear(); pictureSeen.clear(); picturePixels = 0; }
      function measure(ctx, font, text) {
        const k = font + ' ' + text;
        let w = measureCache.get(k);
        if (w === undefined) {
          setFont(ctx, font);
          if (tabularSlot) {
            // Digits on the slot, the runs between them measured as they are.
            w = 0; let run = '';
            for (const ch of Array.from(text)) {
              if (isDigit(ch)) { if (run) { w += ctx.measureText(run).width; run = ''; } w += tabularSlot; }
              else run += ch;
            }
            if (run) w += ctx.measureText(run).width;
          } else {
            w = ctx.measureText(text).width;
          }
          measureCache.set(k, w);
        }
        return w;
      }
      // A display list painted into a canvas of its own, as a PNG data URL (UIImage.pngData).
      function rasterize(buf, strings, dpr, w, h) {
        const canvas = document.createElement('canvas');
        canvas.width = Math.max(1, Math.round(w * dpr));
        canvas.height = Math.max(1, Math.round(h * dpr));
        paint(canvas.getContext('2d'), buf, strings, dpr, w, h, []);
        return canvas.toDataURL('image/png');
      }
      // The frame-time HUD (`?perf` in the page URL): every animation frame samples the host's
      // frame split and the gap since the previous frame; a 120-frame window gives the median,
      // p90 and maximum of each. "drive" runs the host's scripted finger drag up the middle of
      // the page so a phone measures the same scroll every time; "copy" puts the report on the
      // clipboard. Gaps over 25 ms with short frames point at the compositor, not at this code.
      function installHud(debug) {
        const hud = document.createElement('div');
        hud.id = 'swiftuiweb-perf';
        hud.style.cssText = 'position:fixed;left:8px;bottom:8px;z-index:2147483647;font:11px/1.35 ui-monospace,Menlo,monospace;color:#fff;background:rgba(0,0,0,.72);padding:6px 8px;border-radius:8px;white-space:pre-wrap;pointer-events:none;max-width:calc(100vw - 16px);box-sizing:border-box';
        const text = document.createElement('div');
        const bar = document.createElement('div');
        bar.style.cssText = 'pointer-events:auto;margin-top:4px;display:flex;gap:6px';
        const button = (label, action) => { const b = document.createElement('button'); b.textContent = label; b.style.cssText = 'font:inherit;padding:2px 8px;border-radius:6px;border:0;background:#4a8cff;color:#fff'; b.onclick = action; bar.appendChild(b); return b; };
        hud.appendChild(text); hud.appendChild(bar);
        document.body.appendChild(hud);
        const frames = [], gaps = [];
        let lastCount = debug.frameCount(), lastT = null, report = '';
        const stat = v => { if (!v.length) return '-'; const s = [...v].sort((a, b) => a - b); const q = p => s[Math.min(s.length - 1, Math.floor(p * s.length))]; return q(0.5).toFixed(1) + '/' + q(0.9).toFixed(1) + '/' + s[s.length - 1].toFixed(1); };
        const probe = (() => { try { const p = new OffscreenCanvas(1, 1).getContext('2d'); return 'filter ' + (hasCanvasFilters() ? 'yes' : 'no') + ' reset ' + (typeof p.reset === 'function' ? 'yes' : 'no'); } catch (e) { return 'no OffscreenCanvas'; } })();
        // The engine's speed on this device: 5 M iterations of the same arithmetic loop in the
        // module's wasm and in JavaScript (a JIT-less engine runs both some 20 times slower).
        const speed = (() => { const n = 5000000; const t0 = performance.now(); const values = new Float64Array(1024).fill(1); let acc = 0; for (let i = 0; i < n; i++) { const j = i & 1023; values[j] = values[j] * 0.5 + (i & 255) * 0.25; acc += Math.sqrt(values[j]); } const js = performance.now() - t0 + (isNaN(acc) ? 1 : 0); return 'wasm ' + (debug.bench ? debug.bench(n).toFixed(0) : '-') + ' ms  js ' + js.toFixed(0) + ' ms (5M loop)'; })();
        const tick = t => {
          if (lastT !== null) { gaps.push(t - lastT); if (gaps.length > 120) gaps.shift(); }
          lastT = t;
          const count = debug.frameCount();
          if (count !== lastCount) { lastCount = count; frames.push({ ms: debug.frameMillis(), ...debug.framePhases() }); if (frames.length > 120) frames.shift(); }
          if (frames.length && (count & 3) === 0) {
            const canvas = document.querySelector('canvas');
            const long = frames.filter(f => f.ms > 16).length, dropped = gaps.filter(g => g > 25).length;
            const last = frames[frames.length - 1];
            report = 'frame ' + stat(frames.map(f => f.ms)) + ' ms  >16: ' + long + '/' + frames.length + '  gaps>25: ' + dropped + '/' + gaps.length +
              '\nlayout ' + stat(frames.map(f => f.layout)) + '  render ' + stat(frames.map(f => f.render)) +
              '\nencode ' + stat(frames.map(f => f.encode)) + '  paint ' + stat(frames.map(f => f.paint)) +
              '\nsemantics ' + stat(frames.map(f => f.semantics)) + '  overlay ' + stat(frames.map(f => f.overlay)) +
              '\nops ' + last.ops + '  dpr ' + devicePixelRatio + '  canvas ' + (canvas ? canvas.width + 'x' + canvas.height : '-') + '  pool ' + pool.length + '  ' + probe + '\n' + speed;
            text.textContent = report;
          }
          requestAnimationFrame(tick);
        };
        requestAnimationFrame(tick);
        button('drive', () => { frames.length = 0; gaps.length = 0; debug.drag(innerWidth / 2, innerHeight * 0.75, 0, -innerHeight * 0.6, 0.4); });
        button('copy', () => { const r = report + '\n' + navigator.userAgent; if (navigator.clipboard) navigator.clipboard.writeText(r); else prompt('report', r); });
      }
      window.__swiftuiweb = {
        paint: paint, rasterize: rasterize, segmentMisses: function () { return segmentMisses; }, segmentCount: function () { return segments.size; },
        tileStats: function () { let tiles = 0; for (const s of segments.values()) tiles += s.tiles.size; return { tiles: tiles, tileMillis: tileMillis, tilesDrawn: tilesDrawn }; }, measure: measure, forgetMeasurements: forgetMeasurements, imageState: imageState, imageCancel: imageCancel, version: 4, installHud: installHud,
        setImageLoadHandler: function (handler) { onImageLoad = handler; },
        overlayAdd: function (id, element) { overlay.set(id, element.style); },
        overlayRemove: function (id) { overlay.delete(id); },
        overlayFrames: overlayFrames,
        pendingImages: function () { return pending; },
      };
    })();
    """#
}
