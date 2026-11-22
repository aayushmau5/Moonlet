// Dithering: flowing warped stripes drawn in two colors with a chunky 4x4 ordered
// dither, like an old computer screen.
// Ported to Metal from the Dithering shader in Paper Shaders
// (https://github.com/paper-design/shaders), Apache License 2.0.
// Powered by Paper Shaders: https://shaders.paper.design
// Changes: ported from GLSL, fixed to the "Warp" preset with a 4x4 Bayer matrix,
// slowed down, and the dither cell sized from the screen height.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float speed = 0.5;
constant float cellsPerScreen = 330.0;
constant float3 colorBack = float3(0.188, 0.110, 0.165);
constant float3 colorFront = float3(0.337, 0.682, 0.424);

constant float bayer4x4[16] = {
    0.0, 8.0, 2.0, 10.0,
    12.0, 4.0, 14.0, 6.0,
    3.0, 11.0, 1.0, 9.0,
    15.0, 7.0, 13.0, 5.0,
};

float bayerValue(float2 cellUV) {
    int2 position = int2(fract(cellUV / 4.0) * 4.0);
    return bayer4x4[position.y * 4 + position.x] / 16.0;
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float t = 0.5 * u.time * speed;

    float cellSize = u.resolution.y / cellsPerScreen;
    float2 cellUV = (in.uv * u.resolution - 0.5 * u.resolution) / cellSize;
    float2 snapped = (floor(cellUV) + 0.5) * cellSize;
    float2 normalized = snapped / u.resolution + 0.5;

    float pointsTall = 900.0;
    float2 shapeUV = normalized * float2(u.resolution.x / u.resolution.y, 1.0) * pointsTall * 0.003;
    for (float i = 1.0; i < 6.0; i += 1.0) {
        shapeUV.x += 0.6 / i * cos(i * 2.5 * shapeUV.y + t);
        shapeUV.y += 0.6 / i * cos(i * 1.5 * shapeUV.x + t);
    }
    float shape = 0.15 / max(0.001, abs(sin(t - shapeUV.y - shapeUV.x)));
    shape = smoothstep(0.02, 1.0, shape);

    float dither = bayerValue(cellUV) - 0.5;
    float lit = step(0.5, shape + dither);

    return float4(mix(colorBack, colorFront, lit), 1.0);
}
