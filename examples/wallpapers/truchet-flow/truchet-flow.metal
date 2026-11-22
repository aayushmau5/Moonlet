// Truchet Flow: a maze of curved paths with pulses of light gliding along them forever.
// Each square tile holds two quarter-circle arcs, flipped at random. Tiles in a
// checkerboard run their flow in opposite directions, which makes every path join up.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float tiles = 9.0;
constant float speed = 0.25;

float hash21(float2 p) {
    float3 p3 = fract(float3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

float3 palette(float t) {
    return 0.5 + 0.5 * cos(6.2831 * (t + float3(0.55, 0.65, 0.8)));
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float time = u.time;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * tiles;
    p += float2(time * 0.05, time * 0.03);
    float pixel = tiles / u.resolution.y;

    float2 cell = floor(p);
    float2 f = fract(p);
    if (hash21(cell) > 0.5) {
        f.x = 1.0 - f.x;
    }
    float2 corner = (f.x + f.y < 1.0) ? float2(0.0) : float2(1.0);
    float2 v = f - corner;
    float distance = abs(length(v) - 0.5);

    float along = atan2(abs(v.y), abs(v.x)) / 1.5708;
    bool odd = fmod(cell.x + cell.y + 1000.0, 2.0) > 0.5;
    if (odd) {
        along = 1.0 - along;
    }

    float width = 0.07 + 0.015 * sin(time * 0.4 + p.x * 0.3);
    float line = smoothstep(width + pixel, width - pixel, distance);
    float halo = exp(-distance * 14.0) * 0.35;

    float phase = fract(along * 2.0 - time * speed);
    float pulse = smoothstep(0.0, 0.08, phase) * pow(1.0 - phase, 3.0);

    float3 tint = palette(0.04 * (cell.x + cell.y) + time * 0.015);
    float3 color = float3(0.012, 0.014, 0.03);
    color += tint * (line * (0.18 + 1.1 * pulse) + halo * (0.3 + pulse));

    float fade = smoothstep(1.3, 0.3, length((in.uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * fade, 1.0);
}
