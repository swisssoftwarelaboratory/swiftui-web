// The browser behind the Speech framework (decision 0022, pf-speech): Chrome's on-device
// `SpeechRecognition` (`processLocally`, Chrome 139+) fed the buffers the app appends to its
// request — each buffer is resampled to 16 kHz (the rate the recogniser transcribes; a 48 kHz
// track is heard and never transcribed) and queued in an AudioWorklet that plays it out, in
// real time, into a `MediaStreamAudioDestinationNode` whose track `start(track)` listens to.
// Nothing leaves the device; the one download is the locale's language pack, from the
// browser's vendor, on `requestAuthorization`. Browsers without on-device recognition (or
// without `start(track)`) answer "unavailable", and `SFSpeechRecognizer.isAvailable` is false.
//
// Chrome's continuous session reports a final per utterance and keeps running; Apple's result
// is cumulative and final once. Every `onresult` here joins all finals and the current
// interim into one transcript (not final); `endAudio` drains the worklet's queue, lets a short
// tail of silence through and stops the recogniser, whose `end` delivers the joined finals as
// the one final result.
#if os(WASI)
import JavaScriptKit
import Speech

@MainActor
enum SpeechHost {
    /// `(lang, install, done)`: resolves `done` with "available", "downloadable" or "unavailable"
    /// (installing the pack first when `install`, waiting for the download to land).
    private static let availability: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var R = window.SpeechRecognition || window.webkitSpeechRecognition;
        var usable = !!R && typeof R.available === 'function' && ('processLocally' in R.prototype)
          && !!(window.AudioContext && window.AudioWorkletNode && window.MediaStreamAudioDestinationNode);
        if (!usable) { done('unavailable'); return; }
        var ask = function () { return R.available({ langs: [lang], processLocally: true }); };
        var wait = function (tries) {
          ask().then(function (a) {
            if (a === 'available' || a === 'unavailable' || tries <= 0) { done(a === 'available' ? 'available' : (a === 'unavailable' ? 'unavailable' : 'downloadable')); return; }
            setTimeout(function () { wait(tries - 1); }, 1000);
          }, function () { done('unavailable'); });
        };
        ask().then(function (a) {
          if (a === 'available') { done('available'); return; }
          if (a === 'unavailable' || !install || typeof R.install !== 'function') { done(a === 'unavailable' ? 'unavailable' : 'downloadable'); return; }
          R.install({ langs: [lang], processLocally: true }).then(function (ok) {
            if (ok === false) { done('unavailable'); return; }
            wait(600);
          }, function () { done('unavailable'); });
        }, function () { done('unavailable'); });
        """
        return try? make.throws.new("lang", "install", "done", body)
    }()

    /// `(lang, interim, onResult, onError)` → the session object, with `append(samples, rate)`,
    /// `endAudio()`, `stop()` and `cancel()`. `onResult(transcript, isFinal)`; `onError(message)`.
    private static let session: JSObject? = {
        guard let make = JSObject.global.Function.function else { return nil }
        let body = """
        var R = window.SpeechRecognition || window.webkitSpeechRecognition;
        var RATE = 16000;
        var worklet = "class Feeder extends AudioWorkletProcessor {"
          + " constructor() { super(); this.chunks = []; this.offset = 0; this.draining = false; this.tail = 0; this.port.onmessage = (e) => { if (e.data === 'drain') { this.draining = true; } else { this.chunks.push(e.data); } }; }"
          + " process(inputs, outputs) { var out = outputs[0][0]; var i = 0;"
          + "   while (i < out.length && this.chunks.length) { var c = this.chunks[0]; var n = Math.min(out.length - i, c.length - this.offset); out.set(c.subarray(this.offset, this.offset + n), i); i += n; this.offset += n; if (this.offset >= c.length) { this.chunks.shift(); this.offset = 0; } }"
          + "   for (; i < out.length; i++) out[i] = 0;"
          + "   if (this.draining && !this.chunks.length) { this.tail += out.length; if (this.tail >= " + (RATE * 0.6) + " && !this.drained) { this.drained = true; this.port.postMessage('drained'); } }"
          + "   return true; } }"
          + " registerProcessor('swiftuiweb-speech-feeder', Feeder);";
        var state = { finals: [], carried: [], interim: '', ended: false, cancelled: false, stopping: false, drainAsked: false };
        var ctx = new AudioContext({ sampleRate: RATE });
        var node = null, dest = null, track = null, rec = null;
        var deliverFinal = function () {
          if (state.ended) return; state.ended = true;
          try { if (track) track.stop(); } catch (e) {}
          try { ctx.close(); } catch (e) {}
          if (!state.cancelled) onResult(state.finals.join(' '), true);
        };
        var transcript = function () { var parts = state.finals.slice(); if (state.interim) parts.push(state.interim); return parts.join(' '); };
        var fail = function (message) { if (state.ended) return; state.ended = true; try { if (track) track.stop(); } catch (e) {} try { ctx.close(); } catch (e) {} onError(message); };
        var stopRecognition = function () { if (state.stopping) return; state.stopping = true; try { rec.stop(); } catch (e) { deliverFinal(); } };
        var resample = function (samples, rate) {
          if (rate === RATE) return samples;
          var ratio = rate / RATE, count = Math.max(0, Math.floor(samples.length / ratio));
          var out = new Float32Array(count);
          for (var i = 0; i < count; i++) { var p = i * ratio, j = Math.floor(p), f = p - j, a = samples[j], b = j + 1 < samples.length ? samples[j + 1] : a; out[i] = a + (b - a) * f; }
          return out;
        };
        var queued = [];
        // The module loads while the context may still be suspended (a page without a gesture
        // yet); resume is asked for and not awaited, as its promise waits for the gesture.
        ctx.audioWorklet.addModule(URL.createObjectURL(new Blob([worklet], { type: 'text/javascript' }))).then(function () {
          if (state.ended) return;
          node = new AudioWorkletNode(ctx, 'swiftuiweb-speech-feeder', { numberOfInputs: 0, numberOfOutputs: 1, outputChannelCount: [1] });
          dest = ctx.createMediaStreamDestination(); node.connect(dest); track = dest.stream.getAudioTracks()[0];
          node.port.onmessage = function (e) { if (e.data === 'drained') stopRecognition(); };
          rec = new R(); rec.lang = lang; rec.processLocally = true; rec.continuous = true; rec.interimResults = !!interim;
          rec.onresult = function (e) {
            var finals = [], current = '';
            for (var i = 0; i < e.results.length; i++) { var t = e.results[i][0].transcript.trim(); if (!t) continue; if (e.results[i].isFinal) finals.push(t); else current = current ? current + ' ' + t : t; }
            state.finals = state.carried.concat(finals); state.interim = current;
            if (!state.ended) onResult(transcript(), false);
          };
          rec.onerror = function (e) {
            // Silence long enough ends Chrome's session (restarted below, as Apple's keeps
            // listening); `aborted` is our own cancel.
            if (e.error === 'no-speech' || e.error === 'aborted') return;
            fail('Speech: ' + e.error + (e.message ? ' (' + e.message + ')' : ''));
          };
          rec.onend = function () {
            if (state.ended || state.stopping || state.cancelled) { deliverFinal(); return; }
            state.carried = state.finals.slice(); state.interim = '';
            try { rec.start(track); } catch (e) { deliverFinal(); }
          };
          try { rec.start(track); } catch (e) { fail('Speech: ' + (e.message || e)); return; }
          for (var i = 0; i < queued.length; i++) node.port.postMessage(queued[i]);
          queued = [];
          if (state.drainAsked) node.port.postMessage('drain');
        }).catch(function (e) { fail('Speech: ' + (e.message || e)); });
        ctx.resume().catch(function () {});
        return {
          append: function (samples, rate) {
            if (state.ended || state.drainAsked) return;
            var frames = resample(samples, rate);
            if (!frames.length) return;
            if (node) node.port.postMessage(frames); else queued.push(frames);
          },
          // Both finish with what was accepted: the queue plays out, a tail of silence lets the
          // recogniser close the last utterance, then the session stops.
          endAudio: function () { if (state.ended || state.drainAsked) return; state.drainAsked = true; if (node) node.port.postMessage('drain'); },
          stop: function () { if (state.ended) return; if (!node) { deliverFinal(); return; } if (!state.drainAsked) { state.drainAsked = true; node.port.postMessage('drain'); } },
          cancel: function () { if (state.ended) return; state.cancelled = true; try { if (rec) rec.abort(); } catch (e) {} deliverFinal(); }
        };
        """
        return try? make.throws.new("lang", "interim", "onResult", "onError", body)
    }()

    static func install() {
        guard availability != nil, session != nil else { return }
        _SpeechHost.availability = { locale, install, completion in
            guard let availability else { completion(.unavailable); return }
            let done = JSClosure { (arguments: [JSValue]) -> JSValue in
                let answer: _SpeechAvailability = switch arguments.first?.string {
                case "available": .available
                case "downloadable": .downloadable
                default: .unavailable
                }
                MainActor.assumeIsolated { completion(answer) }
                return .undefined
            }
            retained.append(done)
            _ = availability(locale, install, done)
        }
        _SpeechHost.start = { locale, partial, result, failed in
            guard let session else { return nil }
            return SpeechSession(session, locale: locale, partial: partial, result: result, failed: failed)
        }
    }

    nonisolated(unsafe) static var retained: [JSClosure] = []
}

/// One recognition in the page: the JavaScript session and the closures it calls back.
final class SpeechSession: _SpeechSession {
    private let object: JSObject
    private var closures: [JSClosure] = []

    init?(_ make: JSObject, locale: String, partial: Bool, result: @escaping @MainActor (String, Bool) -> Void, failed: @escaping @MainActor (String) -> Void) {
        nonisolated(unsafe) let result = result, failed = failed   // run on the main actor; Swift 5 mode (decision 0027)
        let onResult = JSClosure { (arguments: [JSValue]) -> JSValue in
            let transcript = arguments.first?.string ?? ""
            let isFinal = arguments.count > 1 ? (arguments[1].boolean ?? false) : false
            MainActor.assumeIsolated { result(transcript, isFinal) }
            return .undefined
        }
        let onError = JSClosure { (arguments: [JSValue]) -> JSValue in
            let message = arguments.first?.string ?? "Speech: recognition failed"
            MainActor.assumeIsolated { failed(message) }
            return .undefined
        }
        closures = [onResult, onError]
        guard let object = make(locale, partial, onResult, onError).object else { return nil }
        self.object = object
    }

    func append(_ samples: [Float], sampleRate: Double) {
        guard !samples.isEmpty else { return }
        let array = JSTypedArray<Float32>(samples)
        _ = object.append?(array, sampleRate)
    }
    func endAudio() { _ = object.endAudio?() }
    func stop() { _ = object.stop?() }
    func cancel() { _ = object.cancel?() }
}
#endif
