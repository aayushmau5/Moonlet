// Rain on Glass: drops sliding down a window, over the blurred lights of a city at night.
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

float3 cityLights(float2 uv, float time) {
    float3 color = mix(float3(0.015, 0.02, 0.045), float3(0.05, 0.05, 0.09), uv.y);
    const float3 palette[4] = {
        float3(1.0, 0.62, 0.25), float3(1.0, 0.3, 0.2), float3(0.35, 0.7, 1.0), float3(1.0, 0.85, 0.55)
    };
    for (int layer = 0; layer < 3; layer++) {
        float scale = 5.0 + float(layer) * 3.5;
        float2 grid = uv * scale + float2(float(layer) * 7.3, 0.0);
        float2 cell = floor(grid);
        float2 local = fract(grid) - 0.5;
        float chance = hash21(cell + float(layer) * 19.0);
        if (chance < 0.45) {
            continue;
        }
        float2 center = (float2(hash21(cell + 1.7), hash21(cell + 5.3)) - 0.5) * 0.2;
        float radius = 0.2 + 0.18 * hash21(cell + 9.1);
        float flicker = 0.85 + 0.15 * sin(time * (0.5 + chance) + chance * 30.0);
        float3 tint = palette[int(hash21(cell + 2.9) * 3.999)];
        float lowerBias = smoothstep(1.0, 0.2, uv.y);
        float disc = smoothstep(radius, radius * 0.35, length(local - center)) * smoothstep(0.5, 0.42, max(abs(local.x), abs(local.y)));
        color += tint * disc * (0.16 + 0.12 * lowerBias) * flicker / (1.0 + float(layer) * 0.4);
    }
    return color;
}

float3 staticDrops(float2 glass, float time) {
    const float2 cells = float2(26.0, 17.0);
    float2 grid = glass * cells;
    float2 cell = floor(grid);
    float2 local = fract(grid) - 0.5;
    float seed = hash21(cell);
    float2 center = (float2(hash21(cell + 3.1), hash21(cell + 8.7)) - 0.5) * 0.4;
    float radius = 0.1 + 0.22 * hash21(cell + 4.4);
    float phase = fract(time * 0.035 + seed);
    float life = smoothstep(0.0, 0.04, phase) * smoothstep(1.0, 0.75, phase);
    float2 offset = (local - center) / radius;
    float mask = smoothstep(1.0, 0.75, length(offset)) * step(0.58, seed) * life;
    return float3(offset * mask, mask);
}

float3 slidingDrops(float2 glass, float time) {
    const float2 cells = float2(5.0, 1.4);
    float2 grid = glass * cells;
    float2 cell = floor(grid);
    float2 local = fract(grid);
    float seed = hash21(cell * 1.31 + 0.7);
    if (seed < 0.3) {
        return float3(0.0);
    }

    float cycle = fract(time * (0.05 + 0.04 * seed) + seed * 3.7);
    float stutter = cycle + 0.05 * sin(cycle * 23.0 * (0.5 + seed));
    float dropY = 1.08 - stutter * 1.16;
    float dropX = 0.5 + (seed - 0.5) * 0.55 + 0.03 * sin(local.y * 16.0 + seed * 40.0);

    float2 toDrop = (local - float2(dropX, dropY)) / cells;
    const float radius = 0.016;
    float2 offset = toDrop / radius * float2(1.0, 0.85);
    float body = smoothstep(1.0, 0.78, length(offset));

    float above = local.y - dropY;
    float trailCore = smoothstep(0.006, 0.0, abs(toDrop.x)) * step(0.0, above) * smoothstep(0.5, 0.02, above);
    float beadPattern = smoothstep(0.42, 0.18, abs(fract(local.y * 22.0 + seed * 5.0) - 0.5));
    float beads = trailCore * beadPattern;

    float mask = saturate(body + beads * 0.75);
    float2 normal = offset * body + float2(toDrop.x / 0.006, 0.0) * beads * 0.6;
    return float3(normal * mask, mask);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = in.uv;
    float2 glass = float2(uv.x * aspect, uv.y);

    float3 small = staticDrops(glass, u.time);
    float3 large = slidingDrops(glass, u.time);
    float mask = saturate(small.z + large.z);
    float2 normal = small.xy + large.xy;

    float3 blurred = cityLights(uv, u.time) * 0.8;
    float3 throughDrop = cityLights(uv + normal * 0.06, u.time) * 1.5;
    float edge = smoothstep(0.55, 1.0, length(normal));
    throughDrop *= 1.0 - edge * 0.65;
    float3 color = mix(blurred, throughDrop, mask);

    float highlight = saturate(dot(normal, normalize(float2(-0.5, 0.7))));
    color += float3(0.95, 0.97, 1.0) * smoothstep(0.55, 0.9, highlight) * mask * 0.35;
    color += float3(0.015, 0.02, 0.03);

    float vignette = smoothstep(1.3, 0.35, length((uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * vignette, 1.0);
}
