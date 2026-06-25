/* ──────────────────────────────────────────────────────────────
   ShaderToy Runner — runner.js
   WebGL2 engine that mirrors the ShaderToy runtime environment.

   Uniforms provided to every shader:
     uniform vec3  iResolution   – viewport size in pixels (z = pixel ratio)
     uniform float iTime         – elapsed seconds (pauses when paused)
     uniform float iTimeDelta    – seconds since last frame
     uniform int   iFrame        – frame counter (resets on restart)
     uniform vec4  iMouse        – xy: current pos, zw: last-click pos
     uniform vec4  iDate         – year, month (0-based), day, seconds since midnight
   ────────────────────────────────────────────────────────────── */
'use strict';

(function () {

// ── Vertex shader: full-screen triangle (no geometry needed) ────────────────

const VERT_SRC = `#version 300 es
void main() {
    // Map vertex IDs 0-1-2 to a triangle that covers the entire clip space.
    // Clip coords: (-1,-1), (3,-1), (-1,3) — oversized triangle, clipped to viewport.
    float x = float((gl_VertexID & 1) * 4) - 1.0;
    float y = float((gl_VertexID & 2) * 2) - 1.0;
    gl_Position = vec4(x, y, 0.0, 1.0);
}`;

// ── Fragment shader preamble ─────────────────────────────────────────────────
// The user's shader is inserted between preamble and footer.

const FRAG_PREAMBLE = `#version 300 es
precision highp float;
precision highp int;

uniform vec3  iResolution;
uniform float iTime;
uniform float iTimeDelta;
uniform int   iFrame;
uniform vec4  iMouse;
uniform vec4  iDate;

out vec4 fragColor;

`;

const FRAG_FOOTER = `

void main() {
    mainImage(fragColor, gl_FragCoord.xy);
}`;

// Number of lines in the preamble, used to remap error line numbers
// back to user-file line numbers.
const PREAMBLE_LINES = FRAG_PREAMBLE.split('\n').length - 1;

// ── Runner class ─────────────────────────────────────────────────────────────

class Runner {
    constructor() {
        // DOM
        this.canvas      = document.getElementById('canvas');
        this.hud         = document.getElementById('hud');
        this.hudFps      = document.getElementById('hud-fps');
        this.hudTime     = document.getElementById('hud-time');
        this.hudName     = document.getElementById('shader-name');
        this.btnPause    = document.getElementById('btn-pause');
        this.pausedBadge = document.getElementById('paused-badge');
        this.errorOverlay= document.getElementById('error-overlay');
        this.errorText   = document.getElementById('error-text');
        this.loading     = document.getElementById('loading');

        // WebGL
        this.gl      = null;
        this.program = null;
        this.uloc    = {};      // cached uniform locations

        // Timing
        this.startTime       = 0;
        this.pausedAt        = null; // non-null while paused
        this.pausedDuration  = 0;
        this.lastFrameTime   = 0;
        this.frame           = 0;

        // FPS sampling
        this.fpsFrames = 0;
        this.fpsWindow = 0;

        // Mouse (ShaderToy convention: origin bottom-left, pixels)
        this.mouse = { x: 0, y: 0, clickX: 0, clickY: 0, down: false };

        // Render-loop handle
        this.rafId = null;

        // HUD auto-hide
        this.hudTimeout = null;
    }

    // ── Boot ────────────────────────────────────────────────────────────────

    async init() {
        const params      = new URLSearchParams(location.search);
        const shaderName  = params.get('shader') || 'project-01';

        document.title    = `ShaderToy — ${shaderName}`;
        this.hudName.textContent = shaderName;

        // WebGL2 context
        this.gl = this.canvas.getContext('webgl2', { antialias: false });
        if (!this.gl) {
            return this.showError('WebGL2 is not supported in this browser.\nTry a recent version of Chrome or Firefox.');
        }

        // Load shader
        let userSrc;
        try {
            userSrc = await this.fetchShader(shaderName);
        } catch (err) {
            return this.showError(err.message);
        }

        // Compile
        try {
            this.program = this.buildProgram(FRAG_PREAMBLE + userSrc + FRAG_FOOTER);
            this.uloc    = this.cacheUniforms();
        } catch (err) {
            return this.showError(err.message);
        }

        // Canvas sizing
        this.resize();
        window.addEventListener('resize', () => this.resize());

        // Input
        this.bindMouse();
        this.bindKeys();
        this.bindButtons();
        this.bindHudAutoHide();

        // Hide loading screen
        this.loading.classList.add('hidden');

        // Start
        this.startTime    = performance.now();
        this.lastFrameTime= this.startTime;
        this.fpsWindow    = this.startTime;
        this.render();
    }

    // ── Shader loading ───────────────────────────────────────────────────────

    async fetchShader(name) {
        const url = `/src/${name}/shader.glsl`;
        const res = await fetch(url);
        if (!res.ok) throw new Error(`Could not load shader:\n${url}\n(HTTP ${res.status})`);
        return res.text();
    }

    // ── WebGL helpers ────────────────────────────────────────────────────────

    buildProgram(fragSrc) {
        const gl   = this.gl;
        const vert = this.compileShader(gl.VERTEX_SHADER,   VERT_SRC);
        const frag = this.compileShader(gl.FRAGMENT_SHADER, fragSrc);

        const prog = gl.createProgram();
        gl.attachShader(prog, vert);
        gl.attachShader(prog, frag);
        gl.linkProgram(prog);
        gl.deleteShader(vert);
        gl.deleteShader(frag);

        if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
            throw new Error(`Shader link failed:\n${gl.getProgramInfoLog(prog)}`);
        }
        return prog;
    }

    compileShader(type, source) {
        const gl     = this.gl;
        const shader = gl.createShader(type);
        gl.shaderSource(shader, source);
        gl.compileShader(shader);

        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
            const raw  = gl.getShaderInfoLog(shader) || '';
            const kind = type === gl.VERTEX_SHADER ? 'Vertex' : 'Fragment';
            const log  = (type === gl.FRAGMENT_SHADER)
                ? this.remapLines(raw)
                : raw;
            throw new Error(`${kind} shader error:\n\n${log}`);
        }
        return shader;
    }

    // Remap WebGL error line numbers back to user-shader line numbers
    remapLines(log) {
        return log.replace(/ERROR:\s*\d+:(\d+)/g, (_m, n) => {
            const userLine = Math.max(1, parseInt(n, 10) - PREAMBLE_LINES);
            return `ERROR: line ${userLine}`;
        });
    }

    cacheUniforms() {
        const gl = this.gl;
        const p  = this.program;
        return {
            iResolution: gl.getUniformLocation(p, 'iResolution'),
            iTime:       gl.getUniformLocation(p, 'iTime'),
            iTimeDelta:  gl.getUniformLocation(p, 'iTimeDelta'),
            iFrame:      gl.getUniformLocation(p, 'iFrame'),
            iMouse:      gl.getUniformLocation(p, 'iMouse'),
            iDate:       gl.getUniformLocation(p, 'iDate'),
        };
    }

    // ── Resize ───────────────────────────────────────────────────────────────

    resize() {
        const dpr = devicePixelRatio || 1;
        const w   = Math.floor(window.innerWidth  * dpr);
        const h   = Math.floor(window.innerHeight * dpr);
        this.canvas.width  = w;
        this.canvas.height = h;
        this.canvas.style.width  = window.innerWidth  + 'px';
        this.canvas.style.height = window.innerHeight + 'px';
        if (this.gl) this.gl.viewport(0, 0, w, h);
    }

    // ── Input ─────────────────────────────────────────────────────────────────

    bindMouse() {
        const c   = this.canvas;
        const dpr = () => devicePixelRatio || 1;

        // Convert DOM coordinates to ShaderToy coords (origin = bottom-left)
        const toShader = (e) => ({
            x: e.clientX * dpr(),
            y: (window.innerHeight - e.clientY) * dpr(),
        });

        c.addEventListener('mousemove', (e) => {
            const p = toShader(e);
            this.mouse.x = p.x;
            this.mouse.y = p.y;
            if (this.mouse.down) {
                this.mouse.clickX = p.x;
                this.mouse.clickY = p.y;
            }
        });

        c.addEventListener('mousedown', (e) => {
            const p = toShader(e);
            this.mouse.down   = true;
            this.mouse.x      = p.x;
            this.mouse.y      = p.y;
            this.mouse.clickX = p.x;
            this.mouse.clickY = p.y;
        });

        c.addEventListener('mouseup', () => {
            this.mouse.down   = false;
            // Negative zw = click released (ShaderToy convention)
            this.mouse.clickX = -Math.abs(this.mouse.clickX);
            this.mouse.clickY = -Math.abs(this.mouse.clickY);
        });
    }

    bindKeys() {
        document.addEventListener('keydown', (e) => {
            if (e.code === 'Space') { e.preventDefault(); this.togglePause(); }
            if (e.code === 'KeyR')  this.restart();
            if (e.code === 'KeyF')  this.toggleFullscreen();
        });
    }

    bindButtons() {
        document.getElementById('btn-pause').addEventListener('click',
            () => this.togglePause());
        document.getElementById('btn-restart').addEventListener('click',
            () => this.restart());
        document.getElementById('btn-fullscreen').addEventListener('click',
            () => this.toggleFullscreen());
    }

    bindHudAutoHide() {
        const show = () => {
            this.hud.classList.add('visible');
            clearTimeout(this.hudTimeout);
            this.hudTimeout = setTimeout(
                () => this.hud.classList.remove('visible'), 2800);
        };
        document.addEventListener('mousemove', show);
        show(); // visible on load
    }

    // ── Playback controls ─────────────────────────────────────────────────────

    togglePause() {
        if (this.pausedAt === null) {
            // Pause
            this.pausedAt = performance.now();
            cancelAnimationFrame(this.rafId);
            this.btnPause.textContent = '▶';
            this.pausedBadge.classList.add('visible');
        } else {
            // Resume
            this.pausedDuration += performance.now() - this.pausedAt;
            this.pausedAt = null;
            this.btnPause.textContent = '⏸';
            this.pausedBadge.classList.remove('visible');
            this.lastFrameTime = performance.now();
            this.render();
        }
    }

    restart() {
        const now          = performance.now();
        this.startTime     = now;
        this.pausedDuration= 0;
        this.frame         = 0;
        this.fpsFrames     = 0;
        this.fpsWindow     = now;
        if (this.pausedAt !== null) this.pausedAt = now;
    }

    toggleFullscreen() {
        if (!document.fullscreenElement) {
            document.documentElement.requestFullscreen?.();
        } else {
            document.exitFullscreen?.();
        }
    }

    // ── Time helpers ─────────────────────────────────────────────────────────

    elapsedSeconds() {
        const now = this.pausedAt !== null ? this.pausedAt : performance.now();
        return (now - this.startTime - this.pausedDuration) / 1000;
    }

    // ── Render loop ───────────────────────────────────────────────────────────

    render() {
        const gl  = this.gl;
        const now = performance.now();
        const dt  = Math.min((now - this.lastFrameTime) / 1000, 0.1); // cap delta at 100ms
        this.lastFrameTime = now;

        const t = this.elapsedSeconds();

        // Update uniforms
        gl.useProgram(this.program);
        const u = this.uloc;

        gl.uniform3f(u.iResolution, this.canvas.width, this.canvas.height, devicePixelRatio || 1);
        gl.uniform1f(u.iTime,      t);
        gl.uniform1f(u.iTimeDelta, dt);
        gl.uniform1i(u.iFrame,     this.frame);
        gl.uniform4f(u.iMouse,
            this.mouse.x,      this.mouse.y,
            this.mouse.clickX, this.mouse.clickY);

        const d = new Date();
        gl.uniform4f(u.iDate,
            d.getFullYear(),
            d.getMonth(),      // 0-based, matching ShaderToy
            d.getDate(),
            d.getHours() * 3600 + d.getMinutes() * 60 +
            d.getSeconds() + d.getMilliseconds() / 1000);

        // Draw full-screen triangle (3 verts, no VBO needed)
        gl.drawArrays(gl.TRIANGLES, 0, 3);

        this.frame++;

        // Update HUD
        this.fpsFrames++;
        if (now - this.fpsWindow >= 600) {
            const fps = (this.fpsFrames / ((now - this.fpsWindow) / 1000)).toFixed(0);
            this.hudFps.textContent  = `${fps} fps`;
            this.fpsFrames = 0;
            this.fpsWindow = now;
        }
        this.hudTime.textContent = `${t.toFixed(2)}s`;

        this.rafId = requestAnimationFrame(() => this.render());
    }

    // ── Error display ─────────────────────────────────────────────────────────

    showError(msg) {
        this.loading.classList.add('hidden');
        this.errorOverlay.classList.remove('hidden');
        this.errorText.textContent = msg;
        console.error('[ShaderToy Runner]', msg);
    }
}

// ── Boot ──────────────────────────────────────────────────────────────────────

window.addEventListener('DOMContentLoaded', () => new Runner().init());

})();
