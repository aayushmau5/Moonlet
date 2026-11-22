// Aurora: slow, flowing bands of light over a night sky.
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
    for (int octave = 0; octave < 5; octave++) {
        value += amplitude * valueNoise(p);
        p *= 2.0;
        amplitude *= 0.5;
    }
    return value;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = float2(in.uv.x * aspect, in.uv.y);
    float t = u.time * 0.04;

    float3 color = mix(float3(0.005, 0.01, 0.035), float3(0.02, 0.05, 0.12), in.uv.y);

    for (int band = 0; band < 3; band++) {
        float b = float(band);
        float drift = fbm(float2(p.x * 0.9 + t * (1.0 + b * 0.35), b * 3.7 + t * 0.6));
        float center = 0.42 + b * 0.13 + (drift - 0.5) * 0.4;
        float distance = in.uv.y - center;
        float curtain = exp(-distance * distance * 140.0);
        float rays = 0.55 + 0.45 * fbm(float2(p.x * 7.0 + t * 3.0, b * 11.0));
        float3 tint = mix(float3(0.10, 0.95, 0.60), float3(0.55, 0.30, 0.95), b / 2.0);
        color += tint * curtain * rays * 0.5;
    }

    return float4(color, 1.0);
}
