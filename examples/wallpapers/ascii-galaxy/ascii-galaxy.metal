// ASCII Galaxy: the Dithered Galaxy scene typed out in text characters. Each character
// cell picks a glyph by brightness, from a dot for faint dust to an at sign for the
// core, and is tinted by the same palette, so the arms turn as a flicker of symbols.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float textRows = 56.0;
constant float tilt = 0.5;
constant float armWinding = 2.7;
constant int glyphCount = 10;
constant int paletteSize = 6;
constant float3 background = float3(0.016, 0.012, 0.035);

constant int glyphs[glyphCount] = {
    0, 4194304, 131200, 14336, 459200, 145536, 332096, 469440, 11512810, 7264174,
};

constant float3 palette[paletteSize] = {
    float3(0.090, 0.063, 0.180),
    float3(0.235, 0.165, 0.420),
    float3(0.420, 0.420, 0.760),
    float3(0.580, 0.600, 0.900),
    float3(0.760, 0.780, 0.950),
    float3(1.000, 0.910, 0.760),
};

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

float galaxyLight(float2 p, float2 cell, float time) {
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
    if (starSeed < 0.006 + 0.04 * arms * disk) {
        float twinkle = 0.5 + 0.5 * sin(time * (0.5 + 3.0 * hash21(cell + 7.0)) + starSeed * 900.0);
        light = max(light, 0.35 + 0.3 * twinkle);
    }
    return light;
}

float3 tint(float level) {
    float scaled = level * float(paletteSize - 1);
    int low = clamp(int(floor(scaled)), 0, paletteSize - 2);
    return mix(palette[low], palette[low + 1], saturate(scaled - float(low)));
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float unit = u.resolution.y / (textRows * 7.0);
    float2 pixel = in.uv * u.resolution - 0.5 * u.resolution;
    float2 units = floor(pixel / unit);
    float2 cell = floor(units / float2(6.0, 7.0));
    float2 inside = units - cell * float2(6.0, 7.0);

    float2 p = (cell + 0.5) * float2(6.0, 7.0) * unit / u.resolution.y;
    float level = sqrt(saturate(galaxyLight(p, cell, u.time)));
    int glyph = glyphs[clamp(int(level * float(glyphCount - 1) + 0.6), 0, glyphCount - 1)];

    int column = int(inside.x);
    int row = 5 - int(inside.y);
    bool on = column < 5 && row >= 0 && row < 5 && ((glyph >> (row * 5 + column)) & 1) != 0;
    return float4(on ? tint(level) : background, 1.0);
}
