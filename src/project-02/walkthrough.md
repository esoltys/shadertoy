# Walkthrough - Project-02: Centipede 3D Shader

Created the second ShaderToy project, which renders a 3D raymarched undulating centipede on a grid floor winding through neon mushrooms, under a curved CRT monitor screen effect.

## Changes Made

### Project Shader
- **[NEW] [shader.glsl](file:///home/esoltys/source/shadertoy/src/project-02/shader.glsl)**: Created the fragment shader using WebGL2 / GLSL ES 3.00.
- **[MODIFY] [AGENTS.md](file:///home/esoltys/source/shadertoy/AGENTS.md)**: Updated rules to specify that project textures and shared assets belong in the `assets/` directory.

---

## Technical Design

- **Centipede Pathing**: The centipede follows a continuous 30-second loop. It crawls down horizontally across 4 levels (doing smooth U-turns at screen edges), wiggles horizontally and vertically to simulate slithering, and then climbs up the left side bypass channel to loop back to the top.
- **Collision-Free Mushrooms**: Mushrooms are procedurally generated in the gaps between the centipede's channels, aligning with the grid cell centers so the centipede slides right past them without clipping.
- **Retro Arcade Shading**: Uses bright self-emissive components (neon green segments, glowing orange head, flickering red eyes, glowing magenta cap spots, neon cyan grid) and Blinn-Phong specular highlights.
- **CRT Post-Processing**: Simulates a physical CRT monitor using barrel distortion (curved screen), horizontal scanlines, screen flicker, and a lens vignette.

---

## Optimization Iterations

Raymarching is computationally expensive. We optimized the shader through four distinct phases:

1. **Path Call Caching (5 FPS $\to$ 15 FPS)**:
   - *Problem*: Evaluating `getPath(s)` for each segment in the distance field loop was causing 1200+ trigonometric calculations per pixel.
   - *Fix*: Pre-computed all 13 segment positions and eye offsets once at the beginning of `mainImage` and cached them in global variables.
2. **Step reduction & Quadrant Culling (15 FPS $\to$ 23 FPS)**:
   - *Problem*: Raymarching glossy reflections and soft shadows required casting a second set of rays for every pixel.
   - *Fix*: Removed secondary rays (reflections/shadows), reduced primary steps to 48, and replaced the $3 \times 3$ grid cell search (9 cells) for mushrooms with a quadrant-based $2 \times 2$ cell search (4 cells).
3. **Sky Ray Culling & Normal Optimizations (23 FPS $\to$ 36+ FPS)**:
   - *Problem*: Raymarching pixels pointing upwards (sky) is wasteful because no objects reside above $y = 0.5$.
   - *Fix*: Added a sky ray early-exit that skips raymarching entirely if `rd.y >= 0.0` (skips top half of screen). Added column culling for mushrooms and switched to a 3-tap forward difference for normals to save one SDF evaluation on hit.
4. **Fog Opaque Fix (Stars Transparency)**:
   - *Problem*: Distant objects looked translucent because fog was blending them with the background starfield, causing stars to shine through them.
   - *Fix*: Implemented `getFogColor(rd)` which returns only the dark horizon glow without stars. Blending with this starless color makes all distant mushrooms and centipede segments 100% solid and opaque.
5. **Fog Banding Fix (Shifted Linear Fog + Dithering)**:
   - *Problem*: Quadratic fog ($t^2$) accelerating quickly in the foreground combined with WebGL's 8-bit channel precision created noticeable concentric color bands on the dark floor grid near the camera.
   - *Fix*: Switched to a linear fog function shifted to start $2.5$ units away from the camera. Added a high-frequency dither noise overlay (`hash(fragCoord)`) centered at zero with a width of $\pm 0.5$ color steps to blend the discrete color bands into a smooth gradient.
6. **Analytical Floor Capping & Uniform Mushrooms**:
   - *Problem*: Raymarching floor pixels was wastefully looping through all steps until convergence.
   - *Fix*: Calculated the exact analytical intersection distance to the floor plane $y = 0.0$ (`tFloor = -ro.y / rd.y`). Capped the raymarcher loop at `tFloor` and added an early exit that returns a floor hit immediately when $t$ gets within $0.005$ units of `tFloor`. Additionally, we standardized mushroom stalk and cap sizes, removing five expensive `fract()` and multiplication calls inside the distance field loop.


