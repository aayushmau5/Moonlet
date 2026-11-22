// Mesh Gradient: soft spots of color drifting and swirling into each other.
// Ported to Metal from the Mesh Gradient shader in Paper Shaders
// (https://github.com/paper-design/shaders), Apache License 2.0.
// Powered by Paper Shaders: https://shaders.paper.design
// Changes: ported from GLSL, slowed down, fixed to the default colors, and
// a light dither added to stop banding.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.25;
constant float distortion = 0.8;
constant float swirl = 0.1;
constant int colorCount = 4;
constant float3 colors[colorCount] = {
    float3(0.878, 0.918, 1.0),
    float3(0.141, 0.114, 0.604),
    float3(0.969, 0.314, 0.573),
    float3(0.624, 0.314, 0.827),
};

float2 rotate(float2 uv, float angle) {
    return float2x2(float2(cos(angle), sin(angle)), float2(-sin(angle), cos(angle))) * uv;
}

float2 spotPosition(int i, float t) {
    float a = float(i) * 0.37;
    float b = 0.6 + fract(float(i) / 3.0) * 0.9;
    float c = 0.8 + fract(float(i + 1) / 4.0);
    return 0.5 + 0.5 * float2(sin(t * b + a), cos(t * c + a * 1.5));
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 uv = (in.uv - 0.5) * float2(1.0, 1.0 / aspect) + 0.5;

    float t = 0.5 * (u.time * speed + 41.5);

    float radius = smoothstep(0.0, 1.0, length(uv - 0.5));
    float center = 1.0 - radius;
    for (float i = 1.0; i <= 2.0; i += 1.0) {
        uv.x += distortion * center / i * sin(t + i * 0.4 * smoothstep(0.0, 1.0, uv.y)) * cos(0.2 * t + i * 2.4 * smoothstep(0.0, 1.0, uv.y));
        uv.y += distortion * center / i * cos(t + i * 2.0 * smoothstep(0.0, 1.0, uv.x));
    }

    float2 swirled = rotate(uv - 0.5, -3.0 * swirl * radius) + 0.5;

    float3 color = float3(0.0);
    float totalWeight = 0.0;
    for (int i = 0; i < colorCount; i++) {
        float distance = pow(length(swirled - spotPosition(i, t)), 3.5);
        float weight = 1.0 / (distance + 1e-3);
        color += colors[i] * weight;
        totalWeight += weight;
    }
    color /= max(1e-4, totalWeight);

    float2 pixel = in.uv * u.resolution;
    color += (fract(sin(dot(pixel, float2(12.9898, 78.233))) * 43758.5453) - 0.5) / 255.0;
    return float4(color, 1.0);
}
