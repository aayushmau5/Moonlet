// Dithered Galaxy: a tilted spiral galaxy that slowly turns, drawn in a few colors
// with the same chunky 4x4 ordered dither as the Dithering wallpaper.
// The arms are a density wave that turns as one piece, while the gas and stars in
// them orbit faster near the core. Two copies of the gas fade into each other so
// the faster inner orbits never wind the clouds into thin lines.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float cellsPerScreen = 300.0;
constant float tilt = 0.5;
constant float armWinding = 2.7;
constant int paletteSize = 6;

constant float3 palette[paletteSize] = {
    float3(0.020, 0.016, 0.043),
    float3(0.090, 0.063, 0.180),
    float3(0.235, 0.165, 0.420),
    float3(0.420, 0.420, 0.760),
    float3(0.760, 0.780, 0.950),
    float3(1.000, 0.910, 0.760),
};

constant float bayer4x4[16] = {
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
};

float bayerValue(float2 cellUV) {
    int2 position = int2(fract(cellUV / 4.0) * 4.0);
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

float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float gas(float2 g, float radius, float time) {
    float orbit = 0.35 / (radius + 0.15);
    const float period = 40.0;
    float total = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float phase = fract(time / period + 0.5 * float(layer));
        float weight = 1.0 - abs(phase * 2.0 - 1.0);
        float2 q = rotate(g, -orbit * phase * period);
        total += weight * fbm(q * 7.0 + float(layer) * 17.3);
    }
    return total;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float time = u.time;

    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 cell = floor(cellUV);
    float2 p = (cell + 0.5) / cellsPerScreen;

    float2 g = rotate(p, 0.42);
    g.y /= tilt;
    g *= 2.3;
    float radius = length(g);
    float angle = atan2(g.y, g.x);

    float spin = time * 0.02;
    float wave = 2.0 * (angle - armWinding * log(radius + 1e-3)) + spin * 2.0;
    float arms = pow(0.5 + 0.5 * cos(wave), 2.5);
    float lane = pow(0.5 + 0.5 * cos(wave - 0.75), 10.0);

    float clouds = radius < 1.9 ? gas(g, radius, time) : 0.0;
    float disk = exp(-radius * 1.9) * smoothstep(1.9, 0.9, radius);
    float bulge = exp(-radius * radius * 60.0) * 1.3 + exp(-radius * 5.5) * 0.3;

    float light = disk * (0.18 + 1.6 * arms * (0.35 + clouds));
    light *= 1.0 - 0.85 * lane * smoothstep(0.06, 0.25, radius) * smoothstep(0.3, 0.6, clouds);
    light += bulge;

    float starSeed = hash21(cell);
    float starOdds = 0.003 + 0.03 * arms * disk;
    if (starSeed < starOdds) {
        float twinkle = 0.6 + 0.4 * sin(time * (0.5 + 3.0 * hash21(cell + 7.0)) + starSeed * 900.0);
        light += 0.6 + twinkle * 0.6;
    }

    float level = sqrt(saturate(light)) * float(paletteSize - 1);
    int index = int(floor(level + bayerValue(cellUV)));
    index = clamp(index, 0, paletteSize - 1);
    return float4(palette[index], 1.0);
}
