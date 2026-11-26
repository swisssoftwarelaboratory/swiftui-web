// SwiftUI's `colorEffect` on the page's GPU (new-website#746). A browser can't run the app's
// Metal: its browser build ships each `[[stitchable]]` function's WGSL twin as
// `Shaders/<function>.wgsl`, a function of the same name taking the position in points, the
// colour, then the shader's arguments in order (`float`s as f32 to vec4f, colours as vec4f);
// float arrays are not parameters but storage arrays the twin reads by name, `floatArray0`,
// `floatArray1`, in order (the Metal function's pointer and count). This host wraps the twin in a
// full-view pass, renders it into a canvas at the view's pixel size and hands the frame that
// canvas as a surface. The device is the one the page asked for while loading (the manifest's
// `gpu`, any WGSL in the build).
#if os(WASI)
import JavaScriptKit
import SwiftUIWebCore
import WebFoundation

@MainActor
enum ShaderEffectHost {
    /// Twins by function name, read once (nil when the build has none: warned once, not drawn).
    private static var twins: [String: String?] = [:]

    static func install() {
        _ShaderHost.render = { function, arguments, size, scale, surface in
            guard let device = JSObject.global.__swiftuiwebGPU.object, device.queue.object != nil,
                  let code = twin(function), let script else { return false }
            var kinds: [JSValue] = [], uniforms: [Double] = [], arrays: [JSValue] = []
            for argument in arguments {
                switch argument {
                case .floats(let floats):
                    kinds.append(.string(["f", "f2", "f3", "f4"][max(0, min(3, floats.count - 1))]))
                    uniforms += (floats + [0, 0, 0, 0]).prefix(4)
                case .color(let r, let g, let b, let a):
                    kinds.append(.string("c"))
                    uniforms += [r, g, b, a]
                case .floatArray(let floats):
                    kinds.append(.string("fa"))
                    arrays.append(JSTypedArray<Float32>(floats.map(Float32.init)).jsValue)
                }
            }
            let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
            guard width > 0, height > 0, let render = script.render.object else { return false }
            let drawn = render.callAsFunction(this: script, arguments: [device, surface, function, code, kinds.jsValue,
                                                         JSTypedArray<Float32>(uniforms.map(Float32.init) + [Float32(scale), 0, 0, 0]),
                                                         arrays.jsValue, width, height])
            return drawn.boolean == true
        }
    }

    private static func twin(_ function: String) -> String? {
        if let known = twins[function] { return known }
        var code: String?
        if let url = Bundle.main.url(forResource: function, withExtension: "wgsl", subdirectory: "Shaders"),
           let data = try? Data(contentsOf: url) {
            code = String(data: data, encoding: .utf8)
        }
        if code == nil {
            _ = JSObject.global.console.object?.warn?("SwiftUIWeb: no WGSL twin for the shader function \(function): the app's browser build needs Shaders/\(function).wgsl (new-website#746)")
        }
        twins[function] = .some(code)
        return code
    }

    /// The page's script: wraps a twin into a pipeline (once per function and argument kinds),
    /// keeps a canvas per surface, and draws one full-view pass.
    private static let script: JSObject? = {
        guard let make = JSObject.global.Function.function?.new("""
            const cache = new Map();
            const swizzle = { f: '.x', f2: '.xy', f3: '.xyz', f4: '', c: '' };
            function pipeline(dev, name, code, kinds) {
              const key = name + ':' + kinds.join(',');
              let p = cache.get(key);
              if (p) return p;
              const slots = kinds.filter(k => k !== 'fa').length;
              let arrays = 0, slot = 0;
              const args = kinds.map(k => k === 'fa' ? null : `U[${slot++}]${swizzle[k]}`).filter(a => a !== null);
              let decls = `@group(0) @binding(0) var<uniform> U: array<vec4f, ${slots + 1}>;\\n`;
              kinds.forEach(k => { if (k === 'fa') { decls += `@group(0) @binding(${1 + arrays}) var<storage, read> floatArray${arrays}: array<f32>;\\n`; arrays++; } });
              const wrapper = decls + code + `
                @vertex fn swiftuiweb_v(@builtin(vertex_index) i: u32) -> @builtin(position) vec4f {
                  let x = f32((i << 1u) & 2u); let y = f32(i & 2u);
                  return vec4f(x * 2.0 - 1.0, 1.0 - y * 2.0, 0.0, 1.0);
                }
                @fragment fn swiftuiweb_f(@builtin(position) p: vec4f) -> @location(0) vec4f {
                  return ${name}(p.xy / U[${slots}].x, vec4f(0.0, 0.0, 0.0, 1.0)${args.map(a => ', ' + a).join('')});
                }`;
              const module = dev.createShaderModule({ code: wrapper });
              if (module.getCompilationInfo) module.getCompilationInfo().then(i => i.messages.filter(m => m.type === 'error')
                .forEach(m => console.warn('SwiftUIWeb: the WGSL twin of ' + name + ' did not compile: ' + m.lineNum + ':' + m.linePos + ' ' + m.message)));
              p = { arrays, slots, pipeline: dev.createRenderPipeline({ layout: 'auto', vertex: { module, entryPoint: 'swiftuiweb_v' },
                fragment: { module, entryPoint: 'swiftuiweb_f', targets: [{ format: 'bgra8unorm',
                  blend: { color: { srcFactor: 'one', dstFactor: 'zero' }, alpha: { srcFactor: 'one', dstFactor: 'zero' } } }] } }) };
              cache.set(key, p);
              return p;
            }
            return {
              render(dev, id, name, code, kinds, uniforms, arrays, w, h) {
                const p = pipeline(dev, name, code, kinds);
                const surfaces = (globalThis.__swiftuiwebSurfaces ||= new Map());
                let c = surfaces.get(id);
                if (!c) { c = document.createElement('canvas'); c.__ctx = c.getContext('webgpu'); surfaces.set(id, c); }
                if (!c.__ctx) return false;
                if (c.width !== w || c.height !== h || c.__dev !== dev) {
                  c.width = w; c.height = h; c.__dev = dev;
                  c.__ctx.configure({ device: dev, format: 'bgra8unorm', alphaMode: 'premultiplied' });
                }
                const ub = dev.createBuffer({ size: Math.max(16, uniforms.byteLength), usage: 64 | 8 });
                dev.queue.writeBuffer(ub, 0, uniforms);
                const entries = [{ binding: 0, resource: { buffer: ub } }];
                arrays.forEach((a, i) => {
                  const b = dev.createBuffer({ size: Math.max(16, Math.ceil(a.byteLength / 4) * 4), usage: 128 | 8 });
                  dev.queue.writeBuffer(b, 0, a);
                  entries.push({ binding: 1 + i, resource: { buffer: b } });
                });
                let group;
                try { group = dev.createBindGroup({ layout: p.pipeline.getBindGroupLayout(0), entries }); } catch (e) { return false; }
                const enc = dev.createCommandEncoder();
                const pass = enc.beginRenderPass({ colorAttachments: [{ view: c.__ctx.getCurrentTexture().createView(), loadOp: 'clear', storeOp: 'store',
                  clearValue: { r: 0, g: 0, b: 0, a: 0 } }] });
                pass.setPipeline(p.pipeline); pass.setBindGroup(0, group); pass.draw(3); pass.end();
                dev.queue.submit([enc.finish()]);
                return true;
              },
            };
            """) else { return nil }
        return make().object
    }()
}
#endif
