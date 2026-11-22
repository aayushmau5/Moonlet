// Neuro: a glowing web of fluid blue lines, like nerves or light through water.
// Ported to Metal from the Neuro Noise shader in Paper Shaders
// (https://github.com/paper-design/shaders), Apache License 2.0.
// Powered by Paper Shaders: https://shaders.paper.design
// The original algorithm is by zozuar: https://x.com/zozuar/status/1625182758745128981
// Changes: ported from GLSL, slowed down, and fixed to the default colors.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.4;
constant float brightness = 0.05;
constant float contrast = 0.3;
constant float3 colorFront = float3(1.0, 1.0, 1.0);
constant float3 colorMid = float3(0.278, 0.651, 1.0);
constant float3 colorBack = float3(0.0, 0.0, 0.0);

float2 rotate(float2 uv, float angle) {
    return float2x2(float2(cos(angle), sin(angle)), float2(-sin(angle), cos(angle))) * uv;
}

float neuroShape(float2 uv, float t) {
    float2 sineSum = float2(0.0);
    float2 result = float2(0.0);
    float scale = 8.0;
    for (int j = 0; j < 15; j++) {
        uv = rotate(uv, 1.0);
        sineSum = rotate(sineSum, 1.0);
        float2 layer = uv * scale + float(j) + sineSum - t;
        sineSum += sin(layer);
        result += (0.5 + 0.5 * cos(layer)) / scale;
        scale *= 1.2;
    }
    return result.x + result.y;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 9.0;

    float noise = neuroShape(p * 0.13, 0.5 * u.time * speed);
    noise = (1.0 + brightness) * noise * noise;
    noise = pow(noise, 0.7 + 6.0 * contrast);
    noise = min(1.4, noise);

    float blend = smoothstep(0.7, 1.4, noise);
    float3 front = mix(colorMid, colorFront, blend);
    float strength = max(noise, 0.0);
    float opacity = saturate(strength);
    float3 color = front * strength + colorBack * (1.0 - opacity);

    float2 pixel = in.uv * u.resolution;
    color += (fract(sin(dot(pixel * 0.014, float2(12.9898, 78.233))) * 43758.5453) - 0.5) / 256.0;
    return float4(color, 1.0);
}
