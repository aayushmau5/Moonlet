// Halftone Planet: the Ringed Planet scene printed as a halftone, like a page from an
// old astronomy magazine. Each dot on a tilted grid grows with the brightness under it,
// and its ink shifts from rust to cream as it gets brighter.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float dotsPerScreen = 115.0;
constant float gridAngle = 0.785;
constant float3 paper = float3(0.051, 0.055, 0.094);
constant float3 inkDark = float3(0.780, 0.330, 0.220);
constant float3 inkLight = float3(1.000, 0.930, 0.780);

float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

constant float planetRadius = 0.22;
constant float2 planetCenter = float2(0.1, 0.02);
constant float ringInner = 1.35;
constant float ringOuter = 2.35;

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
    float sky = hash21(cell) < 0.012 ? 0.2 + 0.25 * hash21(cell + 3.0) : 0.0;

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
    float2 pixel = in.uv * u.resolution - 0.5 * u.resolution;
    float cellSize = u.resolution.y / dotsPerScreen;
    float2 grid = rotate(pixel, gridAngle) / cellSize;
    float2 cell = floor(grid);
    float2 offset = fract(grid) - 0.5;
    float2 p = rotate((cell + 0.5) * cellSize, -gridAngle) / u.resolution.y;

    float light = saturate(planetScene(p, cell, u.time));
    float radius = sqrt(light) * 0.74;
    float edge = 0.8 / cellSize;
    float cover = 1.0 - smoothstep(radius - edge, radius + edge, length(offset));
    float3 ink = mix(inkDark, inkLight, smoothstep(0.15, 0.8, light));
    return float4(mix(paper, ink, cover), 1.0);
}
