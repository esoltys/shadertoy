# AGENTS.md — ShaderToy project

Rules and conventions for AI agents working in this repository.

## Project layout

- `src/project-NN/shader.glsl` — one GLSL file per project, numbered sequentially
- `runner/` — shared browser runner, do not modify unless fixing the runtime itself
- `assets/` — shared assets (e.g. textures) so they can be re-used by projects
- `server.js` — zero-dependency HTTP server, do not add npm dependencies to it
- `shadertoy` — bash CLI script


## Adding a new shader project

This runner specifically targets ShaderToy **Image** shaders. It does not support Sound, VR, or multipass buffers (Buffer A-D) at this time.

1. Create `src/project-NN/shader.glsl` (pad to two digits: `01`, `02`, …)
2. The entry point must be exactly:
   ```glsl
   void mainImage(out vec4 fragColor, in vec2 fragCoord) { … }
   ```
3. Do **not** declare the standard uniforms (`iResolution`, `iTime`, etc.) — they are injected by the runner preamble.
4. Commit the new shader as a single commit: `feat: add project-NN <short description>`
5. Place any texture/image assets in the `assets/` directory rather than the project directory so they can be reused.


## Modifying the runner

- The runner targets **WebGL2 / GLSL ES 3.00** (`#version 300 es`).
- The fragment preamble is defined in `runner/runner.js` as `FRAG_PREAMBLE`. If you add a new uniform here, also update `cacheUniforms()` and the `updateUniforms` block in `render()`.
- Error line numbers are remapped to user-file lines via `remapLines()` — update `PREAMBLE_LINES` if the preamble changes.

## Commit conventions

Use [Conventional Commits](https://www.conventionalcommits.org/):

| Prefix | When to use |
|---|---|
| `feat:` | new shader project or new runner capability |
| `fix:` | bug fix in runner, server, or CLI |
| `chore:` | tooling, config, non-functional changes |
| `docs:` | README or AGENTS.md only |

Group related changes into a single commit. Each project's shader should be its own commit.

## Dependencies

This project is intentionally **zero-dependency** at runtime. Do not add npm packages to `package.json` without a strong reason and explicit user approval.

## GLSL style

- Normalize coordinates early: `vec2 uv = fragCoord / iResolution.xy;`
- Correct for aspect ratio before computing distances: `uv.x *= iResolution.x / iResolution.y;`
- Use `smoothstep` for soft edges, `mix` for blending.
- Comment each logical stage of the shader.
