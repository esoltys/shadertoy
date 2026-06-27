void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // 1. Normalized coordinates
    vec2 uv = fragCoord / iResolution.xy;

    // 2. Base Color
    vec3 finalColor = vec3(uv, 0.5 + 0.5 * sin(iTime));

    // 3. Translate to center and scale uniformly by Y resolution (corrects aspect ratio)
    vec2 centerOffset = (fragCoord - 0.5 * iResolution.xy) / iResolution.y;

    // Now calculate the true physical distance from the center
    float distFromCenter = length(centerOffset);

    // 4. Aggressive Vignette Falloff
    // Any pixel further than 0.65 from the center will now be pure black
    float vignette = smoothstep(0.65, 0.2, distFromCenter);

    // 5. Apply and output
    finalColor *= vignette;
    fragColor = vec4(finalColor, 1.0);
}
