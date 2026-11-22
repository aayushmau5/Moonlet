// Black Hole: a glowing, swirling disk around a black hole that bends the starlight behind it.
// It renders at half resolution (see wallpaper.json) to keep the GPU cool.
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
    return mix(mix(hash21(cell), hash21(cell + float2(1, 0)), blend.x),
               mix(hash21(cell + float2(0, 1)), hash21(cell + float2(1, 1)), blend.x), blend.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * valueNoise(p);
        p *= 2.1;
        amplitude *= 0.5;
    }
    return value;
}

float3 starfield(float2 p) {
    float3 color = float3(0.01, 0.01, 0.025);
    color += float3(0.12, 0.05, 0.18) * fbm(p * 1.5 + 4.0) * 0.6;
    float2 cell = floor(p * 90.0);
    float star = step(0.993, hash21(cell));
    return color + star * (0.4 + 0.6 * hash21(cell + 2.0));
}

float3 disk(float2 p, float time, float tilt) {
    float2 flat = float2(p.x, p.y / tilt);
    float radius = length(flat);
    float angle = atan2(flat.y, flat.x);
    float inner = 0.2;
    float outer = 0.62;
    float band = smoothstep(inner, inner + 0.04, radius) * smoothstep(outer, outer - 0.25, radius);
    float swirl = fbm(float2(angle * 2.0 + radius * 9.0 - time * 0.6, radius * 6.0));
    float doppler = 1.0 + 0.75 * cos(angle - 0.4);
    float heat = smoothstep(outer, inner, radius);
    float3 hot = mix(float3(1.0, 0.42, 0.12), float3(1.0, 0.92, 0.75), heat);
    return hot * band * (0.35 + 0.9 * swirl) * doppler * 1.3;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 1.6;
    float radius = length(p);
    const float shadow = 0.17;

    float bend = shadow * shadow * 1.4 / max(radius, 1e-3);
    float2 lensed = p * (1.0 - bend / max(radius, 1e-3));
    const float tilt = 0.22;
    float3 front = disk(p, u.time, tilt);
    float2 arched = float2(p.x, -(p.y - 0.0) * 0.55 - shadow * 0.2);
    float3 back = disk(arched, u.time, tilt * 2.6) * smoothstep(-0.02, 0.06, p.y);
    float glow = saturate(dot(front + back, float3(0.3, 0.5, 0.2)) * 1.5);
    float3 color = starfield(lensed + float2(u.time * 0.004, 0.0)) * (1.0 - glow);

    color += back * 0.9;
    float hole = smoothstep(shadow, shadow - 0.012, radius);
    color *= 1.0 - hole;
    float photonRing = exp(-abs(radius - shadow * 1.12) * 90.0);
    color += float3(1.0, 0.75, 0.5) * photonRing * 0.8;

    bool inFront = p.y < 0.0 || radius > shadow * 1.05;
    if (inFront) {
        color += front * (p.y < 0.0 ? 1.0 : 1.0 - hole);
    }

    float vignette = smoothstep(1.4, 0.3, length((in.uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * vignette, 1.0);
}
