// Lava Lamp: warm blobs that drift, merge, and split.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = float2(in.uv.x * aspect, in.uv.y);
    float t = u.time * 0.12;

    float field = 0.0;
    for (int i = 0; i < 8; i++) {
        float fi = float(i);
        float2 center = float2(
            aspect * (0.5 + 0.36 * sin(t * (0.55 + 0.09 * fi) + fi * 1.7)),
            0.5 + 0.44 * sin(t * (0.42 + 0.07 * fi) + fi * 2.3)
        );
        float radius = 0.085 + 0.035 * sin(fi * 3.1 + 0.4);
        float2 offset = p - center;
        field += radius * radius / max(dot(offset, offset), 1e-4);
    }

    float3 background = mix(float3(0.08, 0.01, 0.10), float3(0.22, 0.03, 0.16), in.uv.y);
    float3 color = background;
    color += float3(1.0, 0.3, 0.15) * smoothstep(0.15, 1.0, field) * 0.12;

    float blob = smoothstep(0.96, 1.04, field);
    float core = saturate((field - 1.0) * 0.35);
    float3 lava = mix(float3(0.95, 0.28, 0.08), float3(1.0, 0.78, 0.3), core + in.uv.y * 0.25);
    float rim = smoothstep(0.85, 1.0, field) * (1.0 - blob);
    color += float3(1.0, 0.45, 0.25) * rim * 0.5;
    color = mix(color, lava, blob);

    float vignette = smoothstep(1.3, 0.4, length((in.uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * vignette, 1.0);
}
