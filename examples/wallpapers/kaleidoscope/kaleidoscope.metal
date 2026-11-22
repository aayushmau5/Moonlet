// Kaleidoscope: neon rings folded into mirrored slices that breathe and turn.
// The angle around the center is folded into one mirrored slice, then the space is
// tiled and shrunk a few times; each round adds a layer of glowing rings.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels
//
// Kept cheap on purpose: every sine and cosine that is the same for the whole frame is
// worked out once per pixel outside the loop, and the per-layer offsets are constants.

constant float slices = 8.0;
constant float speed = 0.2;
constant int layers = 4;
constant float tau = 6.2831853;

// Each layer turns a further 0.4 radians and shifts its color a further 0.35.
constant float2 layerTurn[layers] = {
    float2(1.0, 0.0),
    float2(0.921061, 0.389418),
    float2(0.696707, 0.717356),
    float2(0.362358, 0.932039),
};
constant float2 layerHue[layers] = {
    float2(1.0, 0.0),
    float2(-0.587785, 0.809017),
    float2(-0.309017, -0.951057),
    float2(0.951057, 0.309017),
};

float2 turn(float2 p, float2 cosSin) {
    return float2(cosSin.x * p.x - cosSin.y * p.y, cosSin.y * p.x + cosSin.x * p.y);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 p = (in.uv - 0.5) * float2(aspect, 1.0) * 1.6;
    float time = u.time * speed;

    float radius = length(p) * (1.0 + 0.1 * sin(time * 0.9));
    float angle = atan2(p.y, p.x) + time * 0.15;
    const float slice = tau / slices;
    angle = abs(fmod(angle + 100.0 * slice, slice) - slice * 0.5);
    float2 origin = radius * float2(cos(angle), sin(angle));

    float spin = time * 0.2;
    float2 frameTurn = float2(cos(spin), sin(spin));
    float falloff = exp(-radius * 0.9);
    float ringPhase = time * 2.0;

    float3 hue = tau * (radius + time * 0.3 + float3(0.26, 0.42, 0.56));
    float3 hueCos = cos(hue);
    float3 hueSin = sin(hue);

    float2 q = origin;
    float3 glow = float3(0.0);
    for (int i = 0; i < layers; i++) {
        q = turn(turn(fract(q * 1.45) - 0.5, frameTurn), layerTurn[i]);
        float d = abs(sin(length(q) * falloff * 9.0 + ringPhase)) * (1.0 / 9.0);
        float3 tint = 0.5 + 0.5 * (hueCos * layerHue[i].x - hueSin * layerHue[i].y);
        glow += tint * pow(0.009 / max(d, 1e-4), 1.15);
    }

    float3 color = 1.0 - exp(-glow * 0.55);
    float fade = smoothstep(1.4, 0.2, length((in.uv - 0.5) * float2(aspect * 0.8, 1.0)));
    return float4(color * (0.25 + 0.75 * fade), 1.0);
}
