// Halftone Moon: a cratered moon that runs through all its phases every ten minutes,
// with thin clouds drifting past, printed as cream halftone dots on night-blue paper.
// The moon always shows the same face, so its seas and craters stay put while the
// sunlight sweeps across them; near the shadow line the crater walls cast shade.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float dotsPerScreen = 160.0;
constant float gridAngle = 0.785;
constant float phasePeriod = 600.0;
constant float moonRadius = 0.34;
constant float3 paper = float3(0.067, 0.075, 0.122);
constant float3 inkDim = float3(0.420, 0.470, 0.620);
constant float3 inkBright = float3(0.960, 0.910, 0.780);

float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
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

float craters(float2 q, float scale, float2 sunAcross, float seed) {
    float2 grid = q * scale;
    float2 home = floor(grid);
    float shade = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            float2 cell = home + float2(x, y);
            float chance = hash21(cell + seed);
            if (chance > 0.55) {
                continue;
            }
            float2 center = cell + 0.2 + 0.6 * float2(hash21(cell + seed + 1.3), hash21(cell + seed + 7.1));
            float radius = 0.18 + 0.3 * hash21(cell + seed + 4.7);
            float2 offset = grid - center;
            float d = length(offset) / radius;
            if (d < 1.25) {
                float bowl = smoothstep(1.0, 0.6, d);
                float wall = dot(-offset / max(length(offset), 1e-3), sunAcross) * smoothstep(0.25, 1.0, d) * bowl;
                float rim = exp(-pow((d - 1.0) / 0.13, 2.0));
                shade += -0.16 * bowl + 0.5 * wall + 0.2 * rim;
            }
        }
    }
    return shade;
}

float moonScene(float2 p, float2 cell, float time) {
    float phase = 6.2831853 * time / phasePeriod + 2.2;
    float3 sun = normalize(float3(sin(phase), 0.12, -cos(phase)));

    float2 center = float2(0.0, 0.01);
    float2 offset = p - center;
    float distance = length(offset);

    float sky = hash21(cell) < 0.015 ? 0.12 + 0.15 * hash21(cell + 5.0) : 0.0;
    sky += 0.1 * exp(-max(distance - moonRadius, 0.0) * 14.0) * saturate(-sun.z * 0.5 + 0.6);

    float light = sky;
    if (distance < moonRadius) {
        float2 q = offset / moonRadius;
        float3 n = float3(q, sqrt(1.0 - dot(q, q)));
        float lit = dot(n, sun);
        float day = smoothstep(-0.03, 0.12, lit);

        float seas = smoothstep(0.42, 0.62, fbm(q * 2.1 + float2(3.0, 1.0)));
        float albedo = 0.72 - 0.36 * seas + 0.12 * (fbm(q * 9.0) - 0.5);
        float grazing = 0.35 + 0.65 * (1.0 - smoothstep(0.0, 0.6, lit));
        float2 sunAcross = normalize(sun.xy + 1e-4) * grazing;
        albedo += craters(q, 7.0, sunAcross, 0.0) * (1.0 - 0.6 * seas);
        albedo += 0.7 * craters(q, 17.0, sunAcross, 31.0);

        float limb = 0.7 + 0.3 * n.z;
        light = saturate(albedo) * (day * limb + 0.04);
    }

    float cloud = smoothstep(0.56, 0.82, fbm(float2(p.x * 1.4 - time * 0.01, p.y * 5.0 + 4.0)));
    float cloudLight = 0.05 + 0.65 * exp(-max(distance - moonRadius * 0.6, 0.0) * 5.0) * saturate(-sun.z * 0.6 + 0.4);
    return mix(light, max(light, cloudLight), cloud * 0.5);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pixel = in.uv * u.resolution - 0.5 * u.resolution;
    float cellSize = u.resolution.y / dotsPerScreen;
    float2 grid = rotate(pixel, gridAngle) / cellSize;
    float2 cell = floor(grid);
    float2 offset = fract(grid) - 0.5;
    float2 p = rotate((cell + 0.5) * cellSize, -gridAngle) / u.resolution.y;

    float light = saturate(moonScene(p, cell, u.time));
    float radius = sqrt(light) * 0.66;
    float edge = 0.8 / cellSize;
    float cover = 1.0 - smoothstep(radius - edge, radius + edge, length(offset));
    float3 ink = mix(inkDim, inkBright, smoothstep(0.1, 0.6, light));
    return float4(mix(paper, ink, cover), 1.0);
}
