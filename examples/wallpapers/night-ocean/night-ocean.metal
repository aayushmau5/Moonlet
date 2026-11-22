// Night Ocean: a full moon over rolling waves, with a broken path of moonlight that
// glitters as the waves move. Drawn in six cold colors with a chunky 4x4 ordered dither.
// Each wave facet that tilts toward you catches the moon and flashes.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float cellsPerScreen = 300.0;
constant int paletteSize = 6;
constant float horizon = -0.04;
constant float2 moonCenter = float2(-0.32, 0.27);
constant float moonRadius = 0.065;

constant float3 palette[paletteSize] = {
    float3(0.012, 0.020, 0.047),
    float3(0.043, 0.078, 0.188),
    float3(0.114, 0.184, 0.361),
    float3(0.267, 0.376, 0.604),
    float3(0.561, 0.655, 0.831),
    float3(0.902, 0.933, 0.988),
};

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

float sky(float2 p, float time) {
    float toMoon = length(p - moonCenter);
    float light = 0.018 + 0.05 * smoothstep(0.4, horizon, p.y);
    light += 0.1 * exp(-toMoon * 7.0) + 0.2 * exp(-toMoon * 28.0);
    float disk = smoothstep(moonRadius, moonRadius - 0.006, toMoon);
    float maria = fbm((p - moonCenter) * 40.0 + 3.0);
    light = mix(light, 1.0 - 0.25 * smoothstep(0.45, 0.65, maria), disk);

    float clouds = smoothstep(0.5, 0.78, fbm(float2(p.x * 1.6 - time * 0.006, p.y * 6.0 + 2.0)));
    clouds *= smoothstep(horizon + 0.03, horizon + 0.15, p.y);
    float cloudLight = 0.03 + 0.45 * exp(-toMoon * 7.0);
    return mix(light, cloudLight, clouds * 0.85);
}

float scene(float2 p, float2 cell, float time) {
    if (p.y > horizon) {
        float light = sky(p, time);
        if (hash21(cell) < 0.003) {
            light += 0.3 + 0.2 * sin(time * (0.4 + hash21(cell + 2.0)) + cell.x);
        }
        return light;
    }

    float below = horizon - p.y;
    float depth = 1.5 / below;
    float2 world = float2(p.x * depth, depth);
    float2 slope = float2(0.0);
    float height = 0.0;
    const float2 directions[4] = { float2(0.9, 0.44), float2(-0.6, 0.8), float2(0.2, 0.98), float2(-0.95, 0.3) };
    const float frequencies[4] = { 1.7, 3.1, 5.3, 8.9 };
    for (int i = 0; i < 4; i++) {
        float k = frequencies[i];
        float phase = dot(directions[i], world) * k - time * sqrt(k) * 0.55 + float(i) * 1.7;
        float amplitude = 0.5 / k;
        height += amplitude * sin(phase);
        slope += directions[i] * cos(phase) * amplitude * k;
    }
    float fade = exp(-depth * 0.015);
    float facing = slope.y * fade / 1.6;

    float spread = 0.012 + 0.35 * below;
    float path = exp(-pow((p.x - moonCenter.x - slope.x * 0.02) / spread, 2.0));
    float glints = smoothstep(0.15, 0.75, facing) * path;
    float sheen = 0.12 * path * smoothstep(-0.4, 0.6, facing);

    float water = 0.022 + 0.03 * height * fade + 0.025 * smoothstep(0.12, 0.0, below);
    return water + sheen + glints * 0.95;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 cell = floor(cellUV);
    float2 p = (cell + 0.5) / cellsPerScreen;

    float light = scene(p, cell, u.time);
    float level = sqrt(saturate(light)) * float(paletteSize - 1);
    int index = clamp(int(floor(level + bayerValue(cell))), 0, paletteSize - 1);
    return float4(palette[index], 1.0);
}
