// Grain Gradient: soft bands of violet and blue drifting in from the corners,
// broken up by a fine, sandy film grain.
// Ported to Metal from the Grain Gradient shader in Paper Shaders
// (https://github.com/paper-design/shaders), Apache License 2.0.
// Powered by Paper Shaders: https://shaders.paper.design
// Changes: ported from GLSL, fixed to the default preset (the "corners" shape),
// slowed down, and the noise texture lookup replaced by a procedural hash.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.6;
constant int colorCount = 4;
constant float3 colors[colorCount] = {
    float3(0.451, 0.0, 1.0),
    float3(0.922, 0.659, 1.0),
    float3(0.0, 0.749, 1.0),
    float3(0.165, 0.0, 1.0),
};
constant float3 colorBack = float3(0.0, 0.0, 0.0);
constant float softness = 0.5;
constant float intensity = 0.5;
constant float grainAmount = 0.25;

float2 rotate(float2 uv, float angle) {
    return float2x2(float2(cos(angle), sin(angle)), float2(-sin(angle), cos(angle))) * uv;
}

float hash21(float2 p) {
    p = fract(p * float2(0.3183099, 0.3678794)) + 0.1;
    p += dot(p, p + 19.19);
    return fract(p.x * p.y);
}

float randomR(float2 p) {
    return hash21(floor(p));
}

float valueNoiseR(float2 st) {
    float2 i = floor(st);
    float2 f = fract(st);
    float a = randomR(i);
    float b = randomR(i + float2(1.0, 0.0));
    float c = randomR(i + float2(0.0, 1.0));
    float d = randomR(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float4 fbmR(float2 n0, float2 n1, float2 n2, float2 n3) {
    float amplitude = 0.2;
    float4 total = float4(0.0);
    for (int i = 0; i < 3; i++) {
        n0 = rotate(n0, 0.3);
        n1 = rotate(n1, 0.3);
        n2 = rotate(n2, 0.3);
        n3 = rotate(n3, 0.3);
        total.x += valueNoiseR(n0) * amplitude;
        total.y += valueNoiseR(n1) * amplitude;
        total.z += valueNoiseR(n2) * amplitude;
        total.z += valueNoiseR(n3) * amplitude;
        n0 *= 1.99;
        n1 *= 1.99;
        n2 *= 1.99;
        n3 *= 1.99;
        amplitude *= 0.6;
    }
    return total;
}

float3 mod289(float3 x) {
    return x - 289.0 * floor(x / 289.0);
}

float2 mod289(float2 x) {
    return x - 289.0 * floor(x / 289.0);
}

float3 permute(float3 x) {
    return mod289((x * 34.0 + 1.0) * x);
}

float snoise(float2 v) {
    const float4 C = float4(0.211324865405187, 0.366025403784439, -0.577350269189626, 0.024390243902439);
    float2 i = floor(v + dot(v, C.yy));
    float2 x0 = v - i + dot(i, C.xx);
    float2 i1 = (x0.x > x0.y) ? float2(1.0, 0.0) : float2(0.0, 1.0);
    float4 x12 = x0.xyxy + C.xxzz;
    x12.xy -= i1;
    i = mod289(i);
    float3 p = permute(permute(i.y + float3(0.0, i1.y, 1.0)) + i.x + float3(0.0, i1.x, 1.0));
    float3 m = max(0.5 - float3(dot(x0, x0), dot(x12.xy, x12.xy), dot(x12.zw, x12.zw)), 0.0);
    m = m * m;
    m = m * m;
    float3 x = 2.0 * fract(p * C.www) - 1.0;
    float3 h = abs(x) - 0.5;
    float3 ox = floor(x + 0.5);
    float3 a0 = x - ox;
    m *= 1.79284291400159 - 0.85373472095314 * (a0 * a0 + h * h);
    float3 g = float3(a0.x * x0.x + h.x * x0.y, a0.yz * x12.xz + h.yz * x12.yw);
    return 130.0 * dot(m, g);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float t = 0.1 * (u.time * speed + 7.0);

    float2 shapeUV = (in.uv - 0.5) * float2(aspect, 1.0);
    float2 grainUV = shapeUV * u.resolution.y * 0.7;

    float2 corner = shapeUV * 0.6;
    const float2 outer = float2(0.5);
    float2 bl = smoothstep(float2(0.0), outer, corner + float2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * sin(5.25 * t)));
    float2 tr = smoothstep(float2(0.0), outer, 1.0 - corner);
    float shape = 1.0 - bl.x * bl.y * tr.x * tr.y;
    corner = -corner;
    bl = smoothstep(float2(0.0), outer, corner + float2(0.1 + 0.1 * sin(3.0 * t), 0.2 - 0.1 * cos(5.25 * t)));
    tr = smoothstep(float2(0.0), outer, 1.0 - corner);
    shape -= bl.x * bl.y * tr.x * tr.y;
    shape = 1.0 - smoothstep(0.0, 1.0, shape);

    float baseNoise = snoise(grainUV * 0.5);
    float4 fbmValues = fbmR(0.002 * grainUV + 10.0, 0.003 * grainUV, 0.001 * grainUV, rotate(0.4 * grainUV, 2.0));
    float grainDistortion = baseNoise * snoise(grainUV * 0.2) - fbmValues.x - fbmValues.y;
    float rawNoise = 0.75 * baseNoise - fbmValues.w - fbmValues.z;
    float noise = saturate(rawNoise);

    const float count = float(colorCount);
    shape += intensity * 2.0 / count * (grainDistortion + 0.5);
    shape += grainAmount * 10.0 / count * noise;

    float aa = fwidth(shape);
    shape = saturate(shape - 0.5 / count);
    float totalShape = smoothstep(0.0, softness + 2.0 * aa, saturate(shape * count));
    float mixer = shape * (count - 1.0);

    float3 gradient = colors[0];
    for (int i = 1; i < colorCount; i++) {
        float localT = saturate(mixer - float(i - 1));
        localT = smoothstep(0.5 - 0.5 * softness - aa, 0.5 + 0.5 * softness + aa, localT);
        gradient = mix(gradient, colors[i], localT);
    }

    float3 color = gradient * totalShape + colorBack * (1.0 - totalShape);
    return float4(color, 1.0);
}
