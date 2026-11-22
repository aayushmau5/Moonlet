// Ocean at Dusk: rolling waves under a sunset, with sunlight glittering on the water.
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

float3 skyColor(float elevation) {
    float3 color = mix(float3(1.0, 0.52, 0.28), float3(0.55, 0.25, 0.42), smoothstep(0.0, 0.18, elevation));
    return mix(color, float3(0.09, 0.07, 0.22), smoothstep(0.15, 0.7, elevation));
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = in.uv;
    float2 p = float2((uv.x - 0.5) * aspect, uv.y);
    const float horizon = 0.44;
    float2 sun = float2(0.15, horizon + 0.075);
    float3 sunColor = float3(1.0, 0.72, 0.42);
    float3 color;

    if (uv.y >= horizon) {
        float elevation = uv.y - horizon;
        color = skyColor(elevation);

        float clouds = valueNoise(float2(p.x * 3.0 + u.time * 0.01, elevation * 14.0))
            * valueNoise(float2(p.x * 7.0 - u.time * 0.015, elevation * 30.0));
        float band = smoothstep(0.05, 0.12, elevation) * smoothstep(0.45, 0.2, elevation);
        color = mix(color, float3(1.0, 0.5, 0.45), smoothstep(0.25, 0.6, clouds) * band * 0.55);

        float distanceToSun = length(p - sun);
        color += sunColor * exp(-distanceToSun * 9.0) * 0.6;
        color = mix(color, float3(1.0, 0.9, 0.7), smoothstep(0.045, 0.04, distanceToSun));
    } else {
        float depth = horizon - uv.y;
        float distance = 0.09 / max(depth, 0.0004);
        float2 world = float2(p.x * distance, distance);

        float2 slope = float2(0.0);
        const float2 directions[5] = { float2(0.0, 1.0), float2(0.6, 0.8), float2(-0.7, 0.7), float2(0.95, 0.3), float2(-0.3, 0.95) };
        float frequency = 1.6;
        float amplitude = 0.13;
        for (int i = 0; i < 5; i++) {
            float phase = dot(world, directions[i]) * frequency + u.time * (0.6 + 0.25 * float(i));
            slope += directions[i] * frequency * amplitude * cos(phase);
            frequency *= 1.9;
            amplitude *= 0.55;
        }
        float detailFade = exp(-distance * 0.12);
        slope *= detailFade;

        float3 normal = normalize(float3(-slope.x, 1.0, -slope.y));
        float3 view = normalize(float3(p.x - sun.x * 0.0, -depth * 3.0 - 0.02, 1.0));
        float3 reflected = reflect(view, normal);
        float elevation = saturate(reflected.y * 0.35);
        float fresnel = 0.2 + 0.8 * pow(1.0 - saturate(dot(-view, normal)), 4.0);

        float3 water = float3(0.03, 0.04, 0.1);
        color = mix(water, skyColor(elevation), fresnel);

        float3 sunDirection = normalize(float3(sun.x, 0.05, 1.0));
        float glitter = pow(saturate(dot(reflected, sunDirection)), 120.0);
        float column = exp(-abs(p.x - sun.x) * (3.0 + distance * 0.2));
        color += sunColor * glitter * column * 3.0;
        color += sunColor * column * exp(-depth * 10.0) * 0.18;

        color = mix(color, skyColor(0.0) * 0.8, exp(-depth * 40.0) * 0.7);
    }

    float vignette = smoothstep(1.3, 0.35, length((uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * vignette, 1.0);
}
