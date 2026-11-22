// Dithered Nebula: glowing clouds of gas lit by a few bright young stars, cut through by dark
// dust. The clouds fold slowly into new shapes. Each color channel is cut to six steps
// with a chunky 4x4 ordered dither.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float cellsPerScreen = 300.0;
constant float colorSteps = 5.0;

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

float fbm(float2 p, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < octaves; octave++) {
        value += amplitude * valueNoise(p);
        p = p * 2.03 + 17.3;
        amplitude *= 0.5;
    }
    return value;
}

float3 brightStars(float2 p, float time) {
    float2 grid = p * 3.0;
    float2 cell = floor(grid);
    if (hash21(cell + 3.7) > 0.45) {
        return float3(0.0);
    }
    float2 center = cell + 0.3 + 0.4 * float2(hash21(cell), hash21(cell + 9.1));
    float2 offset = (grid - center) / 3.0;
    float2 away = abs(offset);
    if (min(away.x, away.y) > 0.006 && dot(offset, offset) > 0.0012) {
        return float3(0.0);
    }
    float seed = hash21(cell + 5.3);
    float size = 0.6 + 0.8 * seed;
    float twinkle = 0.85 + 0.15 * sin(time * (0.4 + seed) + cell.x);
    float core = exp(-dot(offset, offset) * 9000.0 / size);
    float spikes = exp(-away.x * 900.0) * exp(-away.y * 35.0 / size)
                 + exp(-away.y * 900.0) * exp(-away.x * 35.0 / size);
    float3 tint = mix(float3(0.7, 0.85, 1.0), float3(1.0, 0.85, 0.7), fract(seed * 7.3));
    return tint * (core * 1.5 + spikes * 0.6) * size * twinkle;
}

float3 nebula(float2 p, float time) {
    float2 q = p * 1.7 + float2(time * 0.004, time * 0.002);
    float slow = time * 0.012;
    float2 warp = float2(fbm(q + float2(slow, 0.0), 3), fbm(q + float2(5.2, 1.3 - slow), 3));
    float gas = fbm(q + 3.0 * warp, 4);

    float glow = smoothstep(0.3, 0.8, gas);
    float3 hydrogen = float3(0.9, 0.2, 0.38);
    float3 oxygen = float3(0.12, 0.62, 0.72);
    float3 color = mix(hydrogen, oxygen, smoothstep(0.35, 0.7, warp.y)) * glow * 1.15;
    color += float3(1.0, 0.8, 0.55) * pow(glow, 4.0) * 0.9;

    float dust = smoothstep(0.45, 0.7, fbm(q * 1.6 + 2.0 * warp + 7.0, 2));
    color *= 1.0 - 0.75 * dust;
    return color + float3(0.012, 0.008, 0.025);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 cell = floor(cellUV);
    float2 p = (cell + 0.5) / cellsPerScreen;
    float time = u.time;

    float3 color = nebula(p, time) + brightStars(p, time);
    if (hash21(cell) < 0.004) {
        color += 0.35 + 0.25 * hash21(cell + 4.0);
    }

    float threshold = bayerValue(cell);
    color = floor(sqrt(saturate(color)) * colorSteps + threshold) / colorSteps;
    color *= color;
    return float4(color, 1.0);
}
