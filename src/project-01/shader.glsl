void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // 1. Normalized coordinates
    vec2 uv = fragCoord / iResolution.xy;

    // 2. Base Color
    vec3 finalColor = vec3(uv.x, uv.y, 0.5 + 0.5 * sin(iTime));

    // 3. Calculate Aspect Ratio
    float aspect = iResolution.x / iResolution.y;

    // 4. Correct the coordinates for aspect ratio before calculating distance
    // We scale the X axis by the aspect ratio so distances are uniform
    vec2 centerOffset = uv - 0.5;
    centerOffset.x *= aspect;

    // Now calculate the true physical distance from the center
    float distFromCenter = length(centerOffset);

    // 5. Aggressive Vignette Falloff
    // Any pixel further than 0.65 from the center will now be pure black
    float vignette = smoothstep(0.65, 0.2, distFromCenter);

    // 6. Apply and output
    finalColor *= vignette;
    fragColor = vec4(finalColor, 1.0);
}
