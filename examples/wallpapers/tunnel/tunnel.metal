// Tunnel: checkered walls stream toward a soft glow at the center, slowly twisting.
// Each pixel's angle and inverse distance from the center become a point on the
// tunnel wall, so the pattern flows inward forever without any geometry.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.6;
constant float segments = 12.0;

float3 palette(float t) {
    return 0.5 + 0.5 * cos(6.2831 * (t + float3(0.0, 0.1, 0.2)));
}

float softSquare(float x) {
    float wave = sin(x);
    return wave / max(fwidth(wave) * 1.5 + 0.02, abs(wave));
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float time = u.time;

    p += 0.05 * float2(sin(time * 0.13), cos(time * 0.11));
    float radius = max(length(p), 1e-3);
    float angle = atan2(p.y, p.x);

    float depth = 0.5 / radius + time * speed;
    float twist = angle + 0.08 * depth + 0.4 * sin(depth * 0.25 + time * 0.1);

    float checker = softSquare(twist * segments * 0.5) * softSquare(depth * 3.1416 * 2.0);
    float pattern = 0.5 + 0.5 * checker;
    float detail = smoothstep(0.03, 0.2, radius);
    pattern = mix(0.5, pattern, detail);

    float3 tint = palette(depth * 0.025 + 0.6);
    float3 wall = tint * (0.12 + 0.88 * pattern);
    float fog = smoothstep(0.0, 0.5, radius);
    float3 color = wall * fog * fog;

    color += palette(depth * 0.025 + 0.6) * exp(-radius * 7.0) * 0.5;
    color += float3(1.0, 0.95, 0.9) * exp(-radius * 25.0) * 0.5;

    float edge = smoothstep(1.2, 0.35, length(p * float2(0.75, 1.0)));
    return float4(color * edge, 1.0);
}
