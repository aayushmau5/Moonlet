// Dithered Aurora: green and violet curtains ripple over a dark mountain ridge and shine back
// from a still lake. Each color channel is cut to six steps with a chunky 4x4
// ordered dither, like a picture on an old home computer.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float cellsPerScreen = 300.0;
constant float colorSteps = 5.0;
constant float shoreline = -0.2;

constant float bayer4x4[16] = {
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
};

float bayerValue(float2 cell) {
    int2 position = int2(cell) & 3;
    return bayer4x4[position.y * 4 + position.x] / 16.0;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
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

float noise1(float x) {
    float cell = floor(x);
    float f = x - cell;
    return mix(hash21(float2(cell, 0.5)), hash21(float2(cell + 1.0, 0.5)), f * f * (3.0 - 2.0 * f));
}

float fbm1(float x) {
    return 0.5 * noise1(x) + 0.25 * noise1(x * 2.07 + 13.1) + 0.125 * noise1(x * 4.28 + 40.2);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 3; octave++) {
        value += amplitude * valueNoise(p);
        p = p * 2.07 + 13.1;
        amplitude *= 0.5;
    }
    return value;
}

float pointed(float x) {
    return 1.0 - abs(2.0 * noise1(x + 40.0) - 1.0);
}

float ridge(float x) {
    float range = fbm1(x * 1.3 + 5.0);
    return shoreline + 0.01 + 0.07 * range + 0.1 * pointed(x * 3.0) + 0.025 * pointed(x * 10.0 + 3.0);
}

float3 aurora(float2 p, float time) {
    float3 total = float3(0.0);
    for (int k = 0; k < 3; k++) {
        float layer = float(k);
        float x = p.x + layer * 2.3;
        float drift = time * (0.02 + 0.008 * layer);
        float sway = noise1(x * 0.9 + drift + layer * 17.0);
        float bottom = 0.0 + 0.08 * layer + 0.08 * sin(x * (1.6 - 0.3 * layer) + drift * 3.0 + sway * 3.0);
        float height = p.y - bottom;
        float body = height > 0.0 ? exp(-height * (5.0 - layer)) : exp(height * 60.0);
        float rays = valueNoise(float2(x * 28.0 + sway * 6.0, time * 0.2 + layer * 5.0));
        rays = 0.45 + 0.55 * rays;
        float patches = smoothstep(0.25, 0.75, noise1(x * 2.2 - drift * 2.0 + layer * 31.0));
        float3 color = mix(float3(0.2, 1.0, 0.5), float3(0.6, 0.22, 0.95), smoothstep(0.02, 0.28, height));
        total += color * body * rays * patches * (1.05 - 0.25 * layer);
    }
    return total;
}

float3 landscape(float2 p, float top, float time) {
    float3 sky = mix(float3(0.02, 0.03, 0.07), float3(0.004, 0.006, 0.02), smoothstep(-0.2, 0.5, p.y));
    float3 glow = aurora(p, time);
    if (p.y < top) {
        return float3(0.01, 0.013, 0.025) + glow * (0.03 + 0.12 * exp((p.y - top) * 60.0));
    }
    return sky + glow;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 cell = floor(cellUV);
    float2 p = (cell + 0.5) / cellsPerScreen;
    float time = u.time;

    float3 color;
    if (p.y > shoreline) {
        float top = ridge(p.x);
        color = landscape(p, top, time);
        if (p.y > top && hash21(cell) < 0.004) {
            color += 0.5 + 0.3 * sin(time * (0.5 + 2.0 * hash21(cell + 9.0)) + cell.x);
        }
    } else {
        float depth = shoreline - p.y;
        float ripple = 0.006 * sin(depth * 160.0 / (depth + 0.05) - time * 0.8) + 0.003 * sin(p.x * 30.0 + time * 0.5);
        float2 mirrored = float2(p.x + ripple, shoreline + depth);
        color = landscape(mirrored, ridge(mirrored.x), time) * 0.55 + float3(0.004, 0.006, 0.014);
    }

    float threshold = bayerValue(cell);
    color = floor(sqrt(saturate(color)) * colorSteps + threshold) / colorSteps;
    color *= color;
    return float4(color, 1.0);
}
