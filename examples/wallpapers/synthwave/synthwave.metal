// Synthwave: a striped sun sinking behind neon mountains, over a grid that rolls toward you.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float gridLine(float coordinate) {
    float distanceToLine = abs(fract(coordinate + 0.5) - 0.5);
    float width = fwidth(coordinate);
    return 1.0 - smoothstep(0.0, 1.5 * width, distanceToLine);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = in.uv;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y);
    const float horizon = 0.4;
    float3 neon = float3(1.0, 0.22, 0.75);
    float3 color;

    if (uv.y >= horizon) {
        float height = (uv.y - horizon) / (1.0 - horizon);
        color = mix(float3(0.95, 0.32, 0.52), float3(0.05, 0.02, 0.16), pow(height, 0.55));

        float2 cell = floor(uv * u.resolution / 3.0);
        float star = step(0.9986, hash21(cell)) * smoothstep(0.25, 0.9, height);
        color += star * (0.55 + 0.45 * sin(u.time * 1.7 + hash21(cell + 3.0) * 6.2831)) * 0.8;

        float2 sunCenter = float2(0.0, horizon + 0.2);
        const float sunRadius = 0.21;
        float distanceToSun = length(p - sunCenter);
        float disc = 1.0 - smoothstep(sunRadius - 0.002, sunRadius, distanceToSun);
        float vertical = saturate((p.y - (sunCenter.y - sunRadius)) / (2.0 * sunRadius));
        float3 sunColor = mix(float3(1.0, 0.2, 0.55), float3(1.0, 0.88, 0.3), vertical);

        float below = (sunCenter.y - p.y) / sunRadius;
        float stripes = 1.0;
        if (below > 0.0) {
            float band = fract(below * 6.0 + u.time * 0.12);
            stripes = step(below * 0.65, band);
        }
        color += float3(1.0, 0.3, 0.55) * exp(-distanceToSun * 5.0) * 0.35;
        color = mix(color, sunColor, disc * stripes);

        float ridge = horizon + 0.03
            + 0.05 * abs(sin(p.x * 2.6 + 0.8)) * (0.55 + 0.45 * sin(p.x * 6.7 + 2.0));
        if (uv.y < ridge) {
            color = float3(0.09, 0.02, 0.17);
        }
        float rim = 1.0 - smoothstep(0.0, 0.004, abs(uv.y - ridge));
        color += neon * rim * 0.7;
    } else {
        float depth = horizon - uv.y;
        float distance = 0.12 / max(depth, 0.0005);
        float across = p.x * distance * 7.0;
        float along = distance * 3.2 + u.time * 1.6;
        float fade = exp(-distance * 0.035);
        float grid = max(gridLine(across), gridLine(along)) * fade;

        color = float3(0.05, 0.0, 0.1);
        color += neon * grid * 0.95;
        color += float3(1.0, 0.35, 0.6) * exp(-depth * 22.0) * 0.55;
    }

    float vignette = smoothstep(1.25, 0.35, length((uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * vignette, 1.0);
}
