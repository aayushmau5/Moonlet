// Grid Glow: a flight through glowing, rainbow-tinted canyons drawn by a grid of light.
// Ported to Metal from "Grid glow tracer" by mrange, released under CC0:
// https://gist.github.com/mrange/653cc6c31598d4a776911b956e5b037c
// Its noise is based on "Dot noise" by XorDev.
// It traces fewer planes than the original and renders at 40% resolution (see wallpaper.json) to keep the GPU cool.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.6;

float dotNoise(float3 p) {
    float amplitude = 0.6;
    float value = 0.0;
    const float2x2 rotate = float2x2(float2(0.6, 0.8), float2(-0.8, 0.6));
    p *= 0.2;
    for (int octave = 0; octave < 3; octave++) {
        value += amplitude * (1.0 + dot(sin(p), cos(p * 1.618).yzx));
        amplitude *= 0.5;
        p.yz = p.yz * (2.0 * rotate);
        p = p.yzx;
    }
    return value;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pixel = in.uv * u.resolution;
    float3 direction = normalize(float3(pixel - 0.5 * u.resolution, u.resolution.y));
    float3 origin = float3(0.0, 0.0, u.time * speed);
    float3 planes = fract(-origin) / direction;

    float3 glow = float3(0.0);
    int axis = 0;
    for (int i = 0; i < 84; i++) {
        axis ^= 2;
        float distance = planes[axis];
        float fadeOut = smoothstep(42.0, 28.0, distance);
        float fog = smoothstep(7.0, 42.0, distance);
        float3 p = origin + distance * direction;

        float d = dotNoise(p) + 0.2 * p.y;
        float4 tint = 1.0 + sin(p.x * 0.1 + p.y * 0.3 + p.z * 0.2 + float4(2.0, 7.0, 0.0, 2.0));
        d = abs(d) + 5e-4 / (direction[axis] * direction[axis]) + 1e-2 * fog;
        glow += tint.w / d * tint.xyz * fadeOut;

        planes += 0.5 / abs(direction);
    }
    return float4(tanh(glow / 400.0), 1.0);
}
