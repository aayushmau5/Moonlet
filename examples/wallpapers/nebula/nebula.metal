// Nebula: slow clouds of colored gas folding into each other, with twinkling stars.
// It renders at half resolution (see wallpaper.json), which suits its soft shapes.
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

float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float2 blend = f * f * (3.0 - 2.0 * f);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    const float2x2 rotate = float2x2(0.8, 0.6, -0.6, 0.8);
    for (int octave = 0; octave < 5; octave++) {
        value += amplitude * valueNoise(p);
        p = rotate * p * 2.03;
        amplitude *= 0.5;
    }
    return value;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 1.45;
    float t = u.time * 0.012;

    float2 q = float2(fbm(p + float2(0.0, t)), fbm(p + float2(5.2, 1.3) - t));
    float2 r = float2(
        fbm(p + 3.2 * q + float2(1.7, 9.2) + t * 1.6),
        fbm(p + 3.2 * q + float2(8.3, 2.8) - t * 1.2)
    );
    float density = fbm(p + 3.0 * r);

    float3 color = mix(float3(0.03, 0.01, 0.08), float3(0.42, 0.1, 0.52), saturate(density * density * 2.6));
    color = mix(color, float3(0.08, 0.5, 0.62), saturate(length(q) * 0.85 - 0.3));
    color = mix(color, float3(1.0, 0.52, 0.32), saturate(r.x * r.x * 1.1 - 0.25));
    color *= 0.15 + 1.7 * density * density;

    float2 cell = floor(in.uv * u.resolution / 2.0);
    float star = step(0.9975, hash21(cell));
    float twinkle = 0.5 + 0.5 * sin(u.time * 1.1 + hash21(cell + 9.0) * 6.2831);
    color += star * twinkle * (0.6 - density * 0.4);

    float vignette = smoothstep(1.35, 0.3, length((in.uv - 0.5) * float2(aspect * 0.75, 1.0)));
    return float4(color * vignette, 1.0);
}
