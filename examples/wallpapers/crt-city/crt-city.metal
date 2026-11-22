// CRT City: a rainy city at night on an old curved tube TV. Office windows switch on
// and off, neon signs buzz, a red light blinks on the roofs, and the wet street
// mirrors it all. The picture is 200 lines tall with glowing scanlines, a red-green-blue
// phosphor mask, and a faint bright band that rolls down the screen.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float rows = 200.0;
constant float street = 16.0;
constant float curvature = 0.07;

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float3 windowLight(float2 id, float time, float dim) {
    float seed = hash21(id);
    float state = hash21(id + floor(time * 0.03 + seed * 7.0) * 3.1);
    if (state > 0.38) {
        return float3(-1.0);
    }
    float kind = hash21(id + 5.5);
    float3 color = kind < 0.7 ? float3(1.0, 0.76, 0.4) : float3(0.6, 0.78, 1.0);
    if (kind > 0.94) {
        color = float3(0.35, 0.5, 1.0) * (0.6 + 0.4 * sin(time * 9.0 + seed * 50.0) * sin(time * 3.7 + seed * 9.0));
    }
    return color * dim * (0.75 + 0.25 * seed);
}

float3 skyline(float x, float y, float cols, float time) {
    float height01 = y / rows;
    float3 color = mix(float3(0.32, 0.12, 0.22), float3(0.02, 0.02, 0.06), smoothstep(0.08, 0.8, height01));
    if (y > 110.0 && hash21(float2(x, y)) < 0.004) {
        color += 0.35;
    }
    float2 moon = float2(cols * 0.78, 168.0);
    float toMoon = length(float2(x, y) - moon);
    color = toMoon < 8.0 ? float3(0.95, 0.92, 0.82) : color + float3(0.12, 0.1, 0.12) * exp(-(toMoon - 8.0) * 0.12);

    const float widths[3] = { 9.0, 14.0, 22.0 };
    const float heights[3] = { 70.0, 55.0, 38.0 };
    const float3 walls[3] = { float3(0.1, 0.07, 0.16), float3(0.06, 0.045, 0.1), float3(0.025, 0.025, 0.05) };
    const float windowSteps[3] = { 2.0, 3.0, 3.0 };
    const float dims[3] = { 0.45, 0.7, 1.0 };

    for (int layer = 0; layer < 3; layer++) {
        float w = widths[layer];
        float shifted = x + float(layer) * 37.0;
        float id = floor(shifted / w);
        float local = shifted - id * w;
        float gap = 1.0 + floor(hash21(float2(id, float(layer))) * 3.0);
        float span = w - gap;
        if (local >= span) {
            continue;
        }
        float top = street + heights[layer] * (0.5 + hash21(float2(id, float(layer) + 10.0)));
        float mast = floor(span * 0.5);
        bool hasMast = layer > 0 && hash21(float2(id, float(layer) + 20.0)) > 0.55;
        if (hasMast && local == mast && y >= top && y < top + 6.0) {
            bool blink = y == top + 5.0 && sin(time * 2.2 + id) > 0.6;
            color = blink ? float3(1.0, 0.15, 0.1) : walls[layer];
            continue;
        }
        if (y >= top) {
            continue;
        }

        color = walls[layer];
        float step = windowSteps[layer];
        float wx = local - 1.0;
        float wy = y - street - 2.0;
        bool inWindow = wx >= 0.0 && local < span - 1.0 && wy >= 0.0 && y < top - 2.0
                     && fmod(wx, step) < step - 1.0 && fmod(wy, step + 1.0) < step - 1.0;
        if (inWindow) {
            float2 windowId = float2(id * 13.0 + floor(wx / step) + float(layer) * 100.0, floor(wy / (step + 1.0)));
            float3 lit = windowLight(windowId, time, dims[layer]);
            if (lit.x >= 0.0) {
                color = lit;
            }
        }

        if (layer == 2 && hash21(float2(id, 77.0)) > 0.5) {
            float signTop = top - 6.0 - floor(hash21(float2(id, 78.0)) * 10.0);
            if (local >= span - 3.0 && y < signTop && y >= signTop - 16.0) {
                bool flicker = hash21(float2(floor(time * 7.0), id)) < 0.05;
                float3 neon = hash21(float2(id, 79.0)) > 0.5 ? float3(1.0, 0.2, 0.62) : float3(0.2, 0.95, 1.0);
                bool letterGap = fmod(signTop - y, 4.0) == 3.0;
                color = flicker ? walls[layer] : neon * (letterGap ? 0.45 : 1.25);
            }
        }
    }
    return color;
}

float3 city(float2 c, float cols, float time) {
    float3 color;
    if (c.y >= street) {
        color = skyline(c.x, c.y, cols, time);
    } else {
        float below = street - c.y;
        float wobble = floor(1.5 * sin(c.y * 1.7 + time * 3.0) + 0.5 * sin(c.x * 0.3 + time));
        float3 mirrored = skyline(c.x + wobble, street + below - 1.0, cols, time);
        color = float3(0.02, 0.02, 0.035) + mirrored * 0.4 * (1.0 - below / street * 0.6);
    }

    float rain = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float speed = layer == 0 ? 60.0 : 95.0;
        float column = floor(c.x + c.y * (0.3 + 0.1 * float(layer)));
        float seed = hash21(float2(column, float(layer) * 7.0));
        float fall = fract((c.y + time * speed) / 53.0 + seed);
        if (fall < 0.08 && hash21(float2(column, float(layer) * 7.0 + 3.0)) < 0.3) {
            rain += layer == 0 ? 0.1 : 0.16;
        }
    }
    return color + rain * float3(0.6, 0.7, 0.85);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float time = u.time;
    float2 uv = in.uv * 2.0 - 1.0;
    float2 curved = uv * (1.0 + curvature * float2(uv.y * uv.y, uv.x * uv.x));
    if (abs(curved.x) > 1.0 || abs(curved.y) > 1.0) {
        return float4(0.01, 0.01, 0.012, 1.0);
    }

    float2 screen = curved * 0.5 + 0.5;
    float cols = floor(rows * aspect);
    float2 virtualPixel = screen * float2(cols, rows);
    float2 c = floor(virtualPixel);
    float2 f = fract(virtualPixel);
    float3 color = city(c, cols, time);

    float brightness = dot(color, float3(0.3, 0.59, 0.11));
    float beam = mix(0.24, 0.42, saturate(brightness * 1.4));
    float scan = exp(-pow((f.y - 0.5) / beam, 2.0));
    color *= scan * 1.7;

    int phosphor = int(in.uv.x * u.resolution.x) % 3;
    float3 mask = float3(0.78);
    mask[phosphor] = 1.22;
    color *= mask;

    color *= 1.0 + 0.05 * sin((screen.y - time * 0.06) * 6.2831853);
    float2 fromCenter = curved * float2(0.85, 1.0);
    color *= smoothstep(1.45, 0.55, length(fromCenter));
    float edge = max(abs(curved.x), abs(curved.y));
    color *= smoothstep(1.0, 0.975, edge);
    return float4(color, 1.0);
}
