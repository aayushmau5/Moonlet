// Orbit: a planet with a small moon circling it, over a quiet starfield.
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

float3 shadedSphere(float2 offset, float radius, float3 baseColor) {
    float2 n2 = offset / radius;
    float z = sqrt(max(1.0 - dot(n2, n2), 0.0));
    float3 normal = float3(n2, z);
    float3 light = normalize(float3(-0.6, 0.5, 0.65));
    float diffuse = max(dot(normal, light), 0.0);
    return baseColor * (0.12 + 0.88 * diffuse);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0);
    float pixel = 1.0 / u.resolution.y;

    float3 color = mix(float3(0.012, 0.012, 0.03), float3(0.035, 0.03, 0.075), in.uv.y);

    float2 starCell = floor(in.uv * u.resolution / 3.0);
    float star = step(0.9984, hash21(starCell));
    float twinkle = 0.55 + 0.45 * sin(u.time * 1.3 + hash21(starCell + 7.0) * 6.2831);
    color += star * twinkle * 0.7;

    float orbitRadius = 0.3;
    float distanceFromCenter = length(p);
    float ring = 1.0 - smoothstep(0.0, 2.5 * pixel, abs(distanceFromCenter - orbitRadius));
    color += float3(0.55, 0.6, 0.8) * ring * 0.18;

    float planetRadius = 0.11;
    float3 planetColor = float3(0.95, 0.62, 0.38);
    float halo = exp(-max(distanceFromCenter - planetRadius, 0.0) * 22.0);
    color += planetColor * halo * 0.12;
    float planetMask = 1.0 - smoothstep(planetRadius - 1.5 * pixel, planetRadius, distanceFromCenter);
    color = mix(color, shadedSphere(p, planetRadius, planetColor), planetMask);

    float angle = u.time * 0.15;
    float2 moonCenter = orbitRadius * float2(cos(angle), sin(angle));
    float moonRadius = 0.022;
    float2 moonOffset = p - moonCenter;
    float moonMask = 1.0 - smoothstep(moonRadius - 1.5 * pixel, moonRadius, length(moonOffset));
    color = mix(color, shadedSphere(moonOffset, moonRadius, float3(0.82, 0.84, 0.9)), moonMask);

    return float4(color, 1.0);
}
