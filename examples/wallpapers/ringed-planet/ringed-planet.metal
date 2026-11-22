// Ringed Planet: a banded gas giant with a tilted ring, drawn in six colors with a
// chunky 4x4 ordered dither. The ring throws its shadow on the planet, the planet
// throws its shadow on the ring, and the sunlight slowly swings so the line
// between day and night drifts across the clouds.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float cellsPerScreen = 300.0;
constant int paletteSize = 6;

constant float3 palette[paletteSize] = {
    float3(0.024, 0.020, 0.043),
    float3(0.090, 0.067, 0.137),
    float3(0.247, 0.153, 0.200),
    float3(0.541, 0.329, 0.255),
    float3(0.835, 0.588, 0.373),
    float3(0.973, 0.878, 0.682),
};

constant float bayer4x4[16] = {
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
};

constant float planetRadius = 0.22;
constant float2 planetCenter = float2(0.1, 0.02);
constant float ringInner = 1.35;
constant float ringOuter = 2.35;

float bayerValue(float2 cell) {
    int2 position = int2(cell) & 3;
    return bayer4x4[position.y * 4 + position.x] / 16.0;
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float hash31(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float valueNoise3(float3 p) {
    float3 cell = floor(p);
    float3 f = fract(p);
    float3 blend = f * f * (3.0 - 2.0 * f);
    float a = mix(hash31(cell), hash31(cell + float3(1, 0, 0)), blend.x);
    float b = mix(hash31(cell + float3(0, 1, 0)), hash31(cell + float3(1, 1, 0)), blend.x);
    float c = mix(hash31(cell + float3(0, 0, 1)), hash31(cell + float3(1, 0, 1)), blend.x);
    float d = mix(hash31(cell + float3(0, 1, 1)), hash31(cell + float3(1, 1, 1)), blend.x);
    return mix(mix(a, b, blend.y), mix(c, d, blend.y), blend.z);
}

float ringDensity(float r) {
    float density = smoothstep(ringInner, ringInner + 0.1, r) * smoothstep(ringOuter, ringOuter - 0.15, r);
    density *= 1.0 - 0.9 * exp(-pow((r - 1.95) / 0.035, 2.0));
    density *= 0.7 + 0.3 * sin(r * 61.0) * sin(r * 23.0 + 1.0);
    return density;
}

float planetScene(float2 p, float2 cell, float time) {
    float3 ringNormal = normalize(float3(-0.25, 1.0, 0.42));
    float swing = 2.35 + 0.55 * sin(time * 0.012);
    float3 light = normalize(float3(cos(swing), 0.3, sin(swing)));

    float2 xy = p - planetCenter;
    float R = planetRadius;
    float sky = hash21(cell) < 0.0025 ? 0.35 + 0.35 * hash21(cell + 3.0) : 0.0;

    float planetZ = -10.0;
    float planet = 0.0;
    float d2 = dot(xy, xy);
    if (d2 < R * R) {
        planetZ = sqrt(R * R - d2);
        float3 surface = float3(xy, planetZ);
        float3 n = surface / R;

        float spin = time * 0.02;
        float3 turned = n * cos(spin) + cross(ringNormal, n) * sin(spin) + ringNormal * dot(ringNormal, n) * (1.0 - cos(spin));
        float latitude = dot(n, ringNormal);
        float swirl = valueNoise3(turned * 4.0) * 0.6 + valueNoise3(turned * 9.0) * 0.4;
        float bands = 0.5 + 0.5 * sin(latitude * 24.0 + swirl * 3.5);
        float albedo = 0.5 + 0.3 * bands + 0.15 * sin(latitude * 7.0 + 1.0);
        albedo *= 1.0 - 0.45 * pow(abs(latitude), 3.0);

        float diffuse = saturate(dot(n, light));
        float s = -dot(surface, ringNormal) / dot(light, ringNormal);
        if (s > 0.0) {
            float shadowRadius = length(surface + light * s) / R;
            diffuse *= 1.0 - 0.75 * ringDensity(shadowRadius);
        }
        planet = albedo * diffuse * (0.75 + 0.25 * n.z) + 0.015;
    }

    float ringZ = -(ringNormal.x * xy.x + ringNormal.y * xy.y) / ringNormal.z;
    float3 ringPoint = float3(xy, ringZ);
    float ringRadius = length(ringPoint) / R;
    float density = ringDensity(ringRadius);
    float base = d2 < R * R ? planet : sky;
    if (density > 0.0 && ringZ > planetZ) {
        float b = dot(ringPoint, light);
        float c = dot(ringPoint, ringPoint) - R * R;
        float disc = b * b - c;
        bool shadowed = disc > 0.0 && -b + sqrt(disc) > 0.0 && -b - sqrt(disc) > 0.0;
        float ringLight = (0.35 + 0.65 * abs(dot(ringNormal, light))) * (shadowed ? 0.06 : 1.0);
        base = mix(base, 0.75 * ringLight, density * 0.85);
    }
    return base;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 cell = floor(cellUV);
    float2 p = (cell + 0.5) / cellsPerScreen;

    float light = planetScene(p, cell, u.time);
    float level = sqrt(saturate(light)) * float(paletteSize - 1);
    int index = clamp(int(floor(level + bayerValue(cell))), 0, paletteSize - 1);
    return float4(palette[index], 1.0);
}
