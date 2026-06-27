// ── GLSL ES 3.00 Shader: Project 02 - Undulating Centipede ───────────────────
// A 3D raymarched representation of the classic retro game 'Centipede'.
// Features a glossy grid floor, procedurally generated glow-in-the-dark mushrooms,
// a wiggling multi-segment centipede, and retro CRT scanlines/lens distortion.

// Hit structure for tracking materials and coordinates
struct Hit {
    float dist;     // raymarched distance
    int type;       // 1: Floor, 2: Stalk, 3: Cap, 4: Body, 5: Head, 6: Eyes
    int id;         // Segment ID or grid cell ID
    vec3 localP;    // Position local to the hit object
};

// ── Global Cache (to avoid thousands of path calls inside raymarch loops) ───
vec3 segPositions[13];
vec3 eyeLPos;
vec3 eyeRPos;

// ── Helper Functions ─────────────────────────────────────────────────────────

// Simple 2D hash for noise/procedural placement
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

// Polynomial smooth minimum for organic blending
float smin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// ── Path Generation ──────────────────────────────────────────────────────────

// Computes the 3D position of the centipede along its path at parameter s
vec3 getPath(float s) {
    float period = 30.0;
    float t = mod(s, period);
    
    vec3 p;
    if (t < 20.0) {
        // Slithering down the screen in rows
        float row = floor(t / 5.0); // 0, 1, 2, 3
        float rowFract = fract(t / 5.0);
        
        // Step down along Z axis at the end of each row
        float zStart = 3.0 - row * 1.5;
        float zEnd = zStart - 1.5;
        p.z = mix(zStart, zEnd, smoothstep(0.85, 1.0, rowFract));
        
        // Crawl left-to-right (dir=1) or right-to-left (dir=-1)
        float dir = (mod(row, 2.0) < 0.5) ? 1.0 : -1.0;
        p.x = -dir * 2.0 * cos(rowFract * 3.14159265);
        
        // Add high-frequency wiggle to the crawl
        p.x += 0.12 * sin(s * 5.0);
        
        // Height undulation (vertical wiggle)
        p.y = 0.16 + 0.08 * sin(s * 6.0);
    } else {
        // Crawling back up the left bypass margin
        float upT = (t - 20.0) / 10.0; // 0 to 1
        
        // Bow outward to the left (x goes from -2.0 down to -2.45 and back)
        p.x = -2.0 - 0.45 * sin(upT * 3.14159265) + 0.12 * sin(s * 5.0);
        p.z = mix(-3.0, 3.0, upT);
        
        // Height undulation
        p.y = 0.16 + 0.08 * sin(s * 6.0);
    }
    return p;
}

// Anti-aliased grid lines
float gridLine(vec2 uv, vec2 lineWidth) {
    vec2 grid = abs(fract(uv - 0.5) - 0.5) / lineWidth;
    vec2 line = vec2(1.0) - min(grid, vec2(1.0));
    return max(line.x, line.y);
}

// ── Scene Definition ─────────────────────────────────────────────────────────

// Scene Signed Distance Field (SDF)
Hit sceneSDF(vec3 p) {
    Hit res;
    res.dist = 1e5;
    res.type = 0;
    res.id = 0;
    res.localP = vec3(0.0);
    
    // 1. Floor Plane
    float dFloor = p.y;
    if (dFloor < res.dist) {
        res.dist = dFloor;
        res.type = 1;
        res.localP = p;
    }
    
    // 2. Grid-mapped Mushrooms (simplified to single cell evaluation)
    float mDist = 1e5;
    int mType = 0;
    vec3 mLocal = vec3(0.0);
    int mId = 0;
    
    // Divide floor space into cells: X spacing = 1.0, Z spacing = 1.5
    float cx = floor(p.x);
    float cz = floor(p.z / 1.5);
    
    // Limit mushrooms to grid columns -1.5, -0.5, 0.5, 1.5 (columns -2, -1, 0, 1)
    if (cx >= -2.0 && cx <= 1.0) {
        float h = hash(vec2(cx, cz));
        if (h > 0.45) { // 55% fill probability
            vec3 mCenter = vec3(cx + 0.5, 0.0, cz * 1.5 + 0.75);
            vec3 q = p - mCenter;
            
            // Stalk (fixed size: r=0.07, h=0.28)
            float dStalk = length(q.xz) - 0.07;
            dStalk = max(dStalk, q.y - 0.28);
            dStalk = max(dStalk, -q.y);
            
            // Cap (fixed size: r=0.20)
            vec3 capP = q - vec3(0.0, 0.28, 0.0);
            float dCap = length(vec3(capP.x, capP.y * 1.35, capP.z)) - 0.20;
            dCap = max(dCap, -capP.y);
            
            // Blend cap & stalk smoothly
            float dMush = smin(dStalk, dCap, 0.07);
            
            if (dMush < mDist) {
                mDist = dMush;
                mLocal = q;
                mId = int(cx + cz * 100.0);
                mType = (dCap < dStalk) ? 3 : 2; // 3 = cap, 2 = stalk
            }
        }
    }
    
    if (mDist < res.dist) {
        res.dist = mDist;
        res.type = mType;
        res.localP = mLocal;
        res.id = mId;
    }
    
    // 3. Centipede Segments (Head + 12 Body segments) using precomputed cache
    float cDist = 1e5;
    int cType = 4;
    int cSeg = -1;
    vec3 cLocal = vec3(0.0);
    
    for (int i = 0; i < 13; i++) {
        vec3 segPos = segPositions[i];
        float r = (i == 0) ? 0.21 : 0.15; // Head is slightly larger
        float d = length(p - segPos) - r;
        
        if (d < cDist) {
            cDist = d;
            cSeg = i;
            cLocal = p - segPos;
            cType = (i == 0) ? 5 : 4; // 5 = head, 4 = body segment
        }
    }
    
    // 4. Centipede Eyes (using precomputed cache)
    float dEyeL = length(p - eyeLPos) - 0.045;
    float dEyeR = length(p - eyeRPos) - 0.045;
    float dEyes = min(dEyeL, dEyeR);
    
    if (dEyes < cDist) {
        cDist = dEyes;
        cType = 6; // 6 = eyes
        cSeg = 0;
        cLocal = (dEyeL < dEyeR) ? (p - eyeLPos) : (p - eyeRPos);
    }
    
    if (cDist < res.dist) {
        res.dist = cDist;
        res.type = cType;
        res.id = cSeg;
        res.localP = cLocal;
    }
    
    return res;
}

// ── Raymarching Engines ──────────────────────────────────────────────────────

// Main camera raymarcher (highly optimized 48 steps with analytical floor intersection)
Hit raymarch(vec3 ro, vec3 rd) {
    Hit res;
    res.dist = -1.0;
    res.type = 0;
    res.id = 0;
    res.localP = vec3(0.0);
    
    // Analytical floor intersection (since rd.y is guaranteed to be < 0)
    float tFloor = -ro.y / rd.y;
    float maxT = min(15.0, tFloor);
    
    float t = 0.05;
    for (int i = 0; i < 48; i++) {
        vec3 p = ro + rd * t;
        Hit h = sceneSDF(p);
        
        // Fast convergence for the floor plane
        if (tFloor - t < 0.005) {
            res.dist = tFloor;
            res.type = 1;
            res.localP = ro + rd * tFloor;
            res.id = 0;
            return res;
        }
        
        if (h.dist < 0.001) {
            if (h.type == 1) {
                res.dist = tFloor;
                res.type = 1;
                res.localP = ro + rd * tFloor;
                res.id = 0;
                return res;
            }
            res = h;
            res.dist = t;
            return res;
        }
        t += h.dist;
        if (t > maxT) {
            if (maxT == tFloor) {
                res.dist = tFloor;
                res.type = 1;
                res.localP = ro + rd * tFloor;
                res.id = 0;
                return res;
            }
            break;
        }
    }
    return res;
}

// ── Normals & Background ─────────────────────────────────────────────────────

// Numerical central differences for normal vectors (restored robust backward difference)
vec3 getNormal(vec3 p) {
    vec2 e = vec2(0.001, 0.0);
    float d = sceneSDF(p).dist;
    vec3 n = d - vec3(
        sceneSDF(p - e.xyy).dist,
        sceneSDF(p - e.yxy).dist,
        sceneSDF(p - e.yyx).dist
    );
    return normalize(n);
}

// Neon purple fog color at horizon (no stars to prevent translucency)
vec3 getFogColor(vec3 rd) {
    float horizonGlow = smoothstep(0.15, -0.35, rd.y);
    return vec3(0.08, 0.01, 0.15) * horizonGlow;
}

// Procedural background starfield with twinkling colorful stars
vec3 getBackgroundColor(vec3 rd) {
    vec3 col = vec3(0.0);
    
    // Project ray direction to cylindrical sky coordinates
    vec2 skyUV = vec2(atan(rd.x, rd.z), rd.y);
    float stars = hash(floor(skyUV * 220.0));
    
    if (stars > 0.993) {
        float h = hash(floor(skyUV * 220.0) + 1.23);
        vec3 starCol = vec3(1.0);
        
        // Distribute colorful retro palette to stars
        if (h < 0.25)       starCol = vec3(0.0, 0.95, 0.95);  // Neon Cyan
        else if (h < 0.5)  starCol = vec3(0.95, 0.0, 0.95);  // Neon Magenta
        else if (h < 0.75) starCol = vec3(0.1, 0.95, 0.2);   // Neon Green
        else                starCol = vec3(0.95, 0.95, 0.0);  // Neon Yellow
        
        float twinkle = 0.3 + 0.7 * sin(iTime * 4.0 + h * 6.28);
        col = starCol * twinkle;
    }
    
    // Neon purple glow hugging the horizon
    float horizonGlow = smoothstep(0.15, -0.35, rd.y);
    col += vec3(0.08, 0.01, 0.15) * horizonGlow;
    
    return col;
}

// ── Shading & Lighting Shading ───────────────────────────────────────────────

// Main shading and material solver
vec3 shade(Hit hit, vec3 ro, vec3 rd, float t) {
    if (hit.type == 0) {
        return getBackgroundColor(rd);
    }
    
    vec3 pos = ro + rd * t;
    vec3 N = getNormal(pos);
    vec3 viewDir = normalize(ro - pos);
    
    // Brighter light source
    vec3 lightDir1 = normalize(vec3(0.5, 1.2, 0.4));
    vec3 lightCol1 = vec3(1.0, 1.0, 1.15) * 0.95;
    
    // Blinn-Phong Diffuse & Specular components
    float diff = max(dot(N, lightDir1), 0.0);
    vec3 reflectDir = reflect(-lightDir1, N);
    float spec = pow(max(dot(viewDir, reflectDir), 0.0), 32.0);
    
    vec3 baseColor = vec3(0.0);
    vec3 emissive = vec3(0.0);
    float roughness = 0.5;
    float specIntensity = 0.5;
    
    if (hit.type == 1) {
        // Floor
        vec2 gridUV = pos.xz;
        gridUV.x += 0.5;
        gridUV.y = (gridUV.y + 0.75) / 1.5;
        
        // Anti-aliased grid lines using pixel derivatives
        vec2 gridWidth = fwidth(gridUV) * 1.5;
        gridWidth = clamp(gridWidth, 0.01, 0.08); // Safety bounds
        
        float line = gridLine(gridUV, gridWidth);
        
        // Pulsing neon cyan gridlines
        vec3 gridCol = vec3(0.0, 0.75, 1.0) * (0.65 + 0.35 * sin(iTime * 3.0 - length(pos.xz) * 0.4));
        baseColor = mix(vec3(0.02, 0.02, 0.03), gridCol * 0.5, line);
        emissive = gridCol * line * 1.3;
        roughness = 0.1;
        specIntensity = 0.8;
    } 
    else if (hit.type == 2) {
        // Mushroom stalk (glowing blue base)
        baseColor = vec3(0.8, 0.85, 0.95);
        emissive = vec3(0.0, 0.65, 1.0) * max(0.0, 0.3 - pos.y) * 1.8;
        roughness = 0.6;
        specIntensity = 0.2;
    }
    else if (hit.type == 3) {
        // Mushroom cap (magenta with neon yellow spots)
        vec3 localN = normalize(hit.localP);
        float spots = smoothstep(0.32, 0.42, sin(localN.x * 12.0) * sin(localN.y * 12.0) * sin(localN.z * 12.0));
        
        vec3 capBase = vec3(1.0, 0.0, 0.6);
        vec3 spotCol = vec3(0.9, 0.95, 0.0);
        baseColor = mix(capBase, spotCol, spots);
        
        float pulse = sin(iTime * 2.5 + float(hit.id) * 0.5) * 0.3 + 0.7;
        emissive = mix(capBase, spotCol, spots) * 0.5 * pulse;
        roughness = 0.4;
        specIntensity = 0.5;
    }
    else if (hit.type == 4) {
        // Centipede body segments (green-to-yellow gradient)
        float tSeg = float(hit.id) / 13.0;
        vec3 green = vec3(0.0, 1.0, 0.1);
        vec3 yellow = vec3(0.9, 1.0, 0.0);
        baseColor = mix(green, yellow, tSeg);
        
        // Glow rim light for modern arcade look
        float rim = pow(1.0 - max(dot(N, viewDir), 0.0), 4.0);
        emissive = baseColor * 0.35 + vec3(0.9, 1.0, 0.4) * rim * 0.6;
        roughness = 0.2;
        specIntensity = 0.9;
    }
    else if (hit.type == 5) {
        // Centipede head (neon orange)
        baseColor = vec3(1.0, 0.4, 0.0);
        float rim = pow(1.0 - max(dot(N, viewDir), 0.0), 4.0);
        emissive = baseColor * 0.4 + vec3(1.0, 0.8, 0.2) * rim * 0.7;
        roughness = 0.2;
        specIntensity = 0.9;
    }
    else if (hit.type == 6) {
        // Centipede eyes (flickering neon red)
        baseColor = vec3(1.0, 0.0, 0.2);
        emissive = baseColor * (1.3 + 0.5 * sin(iTime * 10.0));
        roughness = 0.1;
        specIntensity = 1.0;
    }
    
    // Increased Ambient term (from 0.08 to 0.25) to brighten dark areas
    vec3 col = baseColor * (diff * lightCol1 + vec3(0.25)) + spec * specIntensity * vec3(1.0) + emissive;
    
    // ── OPTIMIZATION & BANDING FIX: Shifting Fog Start ──────────────────────
    // Using linear fog that starts 2.5 units away ensures the foreground floor grid
    // remains completely crisp and free of color banding.
    float fogT = max(0.0, t - 2.5);
    vec3 fogColor = getFogColor(rd);
    col = mix(col, fogColor, 1.0 - exp(-0.16 * fogT));
    
    return col;
}

// ── Entry Point ─────────────────────────────────────────────────────────────

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    // 1. Precompute centipede segment & eye positions once per pixel/frame.
    // This dramatically reduces math instruction count and restores performance.
    for (int i = 0; i < 13; i++) {
        segPositions[i] = getPath(iTime * 3.0 - float(i) * 0.25);
    }
    
    vec3 headPos = segPositions[0];
    vec3 diffVal = getPath(iTime * 3.0 + 0.02) - getPath(iTime * 3.0 - 0.02);
    vec3 tangent = length(diffVal) > 0.001 ? normalize(diffVal) : vec3(0.0, 0.0, 1.0);
    vec3 right = normalize(cross(tangent, vec3(0.0, 1.0, 0.0)));
    vec3 up = cross(right, tangent);
    
    eyeLPos = headPos + tangent * 0.15 + right * 0.11 + up * 0.07;
    eyeRPos = headPos + tangent * 0.15 - right * 0.11 + up * 0.07;

    // 2. Distort UVs to simulate retro CRT screen curve (barrel distortion)
    vec2 uv = fragCoord / iResolution.xy;
    vec2 uvC = uv - 0.5;
    float r2 = dot(uvC, uvC);
    
    // Curvature factor
    vec2 distUV = uv + uvC * (0.09 * r2);
    
    // Cut off borders outside the curved screen boundaries
    if (distUV.x < 0.0 || distUV.x > 1.0 || distUV.y < 0.0 || distUV.y > 1.0) {
        fragColor = vec4(0.0, 0.0, 0.0, 1.0);
        return;
    }
    
    // 3. Camera Setup (using distUV to render distorted 3D scene)
    vec2 pScreen = (distUV - 0.5) * 2.0;
    pScreen.x *= iResolution.x / iResolution.y; // Aspect ratio correction
    
    // Smooth camera drift over time
    vec3 ro = vec3(
        1.8 * sin(iTime * 0.1), 
        2.5 + 0.3 * cos(iTime * 0.15), 
        4.5 + 0.5 * sin(iTime * 0.08)
    );
    vec3 lookAt = vec3(0.0, 0.3, -0.5);
    
    // Camera transform matrix
    vec3 w = normalize(lookAt - ro);
    vec3 u = normalize(cross(w, vec3(0.0, 1.0, 0.0)));
    vec3 v = cross(u, w);
    
    // Generate view ray direction (focal length = 1.5)
    vec3 rd = normalize(pScreen.x * u + pScreen.y * v + 1.5 * w);
    
    // ── OPTIMIZATION: Sky Ray Early Exit ────────────────────────────────────
    // Since the camera is at y >= 2.2 looking down, and all objects (mushrooms,
    // floor, centipede) are strictly below y=0.5, any ray pointing upwards (rd.y >= 0.0)
    // will never intersect anything. We skip the 48-step raymarching loop entirely.
    vec3 color;
    if (rd.y >= 0.0) {
        color = getBackgroundColor(rd);
    } else {
        // Render Scene via Raymarching
        Hit hit = raymarch(ro, rd);
        color = shade(hit, ro, rd, hit.dist);
    }
    
    // 5. CRT Post-Processing Effects
    
    // Animated horizontal scanlines (made much gentler: 0.94 base brightness)
    float scanline = 0.94 + 0.06 * sin(distUV.y * iResolution.y * 1.4 + iTime * 6.0);
    color *= scanline;
    
    // Subtle retro screen voltage flicker
    color *= 0.985 + 0.015 * sin(iTime * 100.0);
    
    // Vignette (made much gentler: raised pow to 0.16)
    float vignette = distUV.x * distUV.y * (1.0 - distUV.x) * (1.0 - distUV.y);
    vignette = clamp(pow(16.0 * vignette, 0.16), 0.0, 1.0);
    color *= vignette;
    
    // ── BANDING FIX: Color Dithering ────────────────────────────────────────
    // Add sub-pixel noise to dither dark color gradients, making them look completely smooth.
    float dither = hash(fragCoord);
    color += vec3(dither - 0.5) / 255.0;
    
    // Output final color
    fragColor = vec4(color, 1.0);
}
