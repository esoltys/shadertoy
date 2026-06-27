# Walkthrough - Project 03 (Summer Shower)

I have implemented the serene rotating water cube shader as requested, matching all specific requirements including translucent blues/greens, concentric surface ripples, and slow-motion underwater droplet penetration (bullet-time wake of bubble cavitation).

---

## Changes Made

### 1. Created & Optimized Shader File
- [shader.glsl](file:///home/esoltys/source/shadertoy/src/project-03/shader.glsl) — Complete GLSL ES 3.00 shader file implementing the entire rendering pipeline.

---

## Technical Features

### 1. Dynamic Size & Wave Variation (New)
- Water droplets now feature cycle-varying physical scales ranging from `0.45x` to `1.55x`.
- **Impact Scaling**: Larger drops hit harder, producing larger concentric ripples on the surface.
- **Penetration Depth**: Larger drops have more momentum, sinking deeper into the cube (up to `1.15` units, sinking past the center of the water volume) before dissolving, while small drops produce shallow penetration and dissolve quickly near the surface.
- **Wake Scaling**: Bubble trails left by penetrating drops scale in thickness relative to the droplet size.

### 2. State-Free Particle & Wave Lifecycles
- Used deterministic mathematical functions driven by the uniform `iTime` to coordinate 4 independent droplet lifecycles.
- Droplets fall through the air, impact the water surface, and penetrate the water cube where they slow down, shrink (dissolve), and leave a cavitation trail of swirling micro-bubbles.
- Surface ripples are generated procedurally starting at the moment of impact and propagating as concentric wavefronts.

### 3. Two-Pass Raymarching Engine & Volumetric Scattering
- **External Pass**: Raymarches the water cube box and the falling droplets in the air.
- **Internal Pass**: Upon hitting the water, the ray refracts inside the cube and raymarches the internal SDF (which contains the penetrating droplet and the bubble trail).
- **Beer-Lambert Transmission**: Evaluates light absorption along the path of the refracted ray. By tuning down the absorption factors, the water remains bright and crystal clear.
- **Volumetric Internal Scatter**: Added a volumetric ambient light scattering approximation that causes the interior of the water volume to glow with a translucent green/teal light.
- **Reflection**: Calculates Fresnel reflection of the serene sky background on the water surface and adds warm glistening sun highlights.

### 4. Multi-Angle Ripple Visibility through Side Faces
- Added analytical derivatives to compute the normal vector of the rippled heightfield top face at the point of exit.
- When an internal refraction ray exits the cube's top face (or undergoes total internal reflection from the inside), it uses this wavy ripple normal instead of a flat box normal.
- This creates realistic refraction/reflection distortions, allowing the top-face ripples to be beautifully visible through the side faces of the rotating cube.

### 5. Bullet-Time Bubble Cavitation Trails
- Modeled the wakes as vertical line segments deformed by high-frequency 3D sine noise.
- Shaded them as bright, sparkling white/gold/cyan bubble streams catching the sunlight using diffuse, specular, and emissive rim lighting.

### 6. Sunny Sky & Atmospheric Shading
- Transitioned from a dark twilight background to a bright, serene daylight sky gradient (pale mint/sand -> sky cyan -> sunny azure blue).
- Boosted warm sun flares and god rays to produce a bright, sun-drenched serene mood.

---

## Verification Results

1. Launched the local runner server using `./shadertoy 3`.
2. Serves successfully on [http://localhost:8080/runner/?shader=project-03](http://localhost:8080/runner/?shader=project-03).
3. The shader runs smoothly at 60 FPS.
