// Leaf Shadows: afternoon sun on a pale plaster wall, and the shadow of a tree
// outside moving across it. Three boughs hang at different distances from the
// wall: the nearest casts crisp, dark leaves, the furthest only a soft haze, and
// each sways on its own in a gusty breeze. Leaves spiral off their twigs by the
// golden angle, so they never settle into a pattern. The canopy further off
// throws soft shade with round spots of sun, and a warm gold glow lines the
// sharp shadow edges. Rendered in four tones, from deep teal shadow to pale
// mint light, with a fine 8x8 ordered dither.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels

constant float ditherPixels = 1.0;
constant int toneCount = 4;
constant float3 tones[toneCount] = {
    float3(0.050, 0.220, 0.240),
    float3(0.180, 0.420, 0.420),
    float3(0.720, 0.880, 0.820),
    float3(0.880, 0.960, 0.910),
};
constant float3 gold = float3(0.980, 0.840, 0.500);
constant float goldenAngle = 2.39996;

constant int boughCount = 3;
constant int twigsPerBough = 3;
constant int leavesPerLimb = 9;
// x (fraction of half width), y, heading in radians, length
constant float4 boughs[boughCount] = {
    float4(1.10, 0.62, 3.50, 1.20),
    float4(1.10, -0.38, 2.95, 0.90),
    float4(-0.35, 0.62, 5.15, 0.75),
};
constant float boughBend[boughCount] = { 0.40, -0.35, -0.30 };
// 0 touches the wall and stays crisp, 1 is far off and hazy
constant float boughDepth[boughCount] = { 0.10, 0.45, 0.85 };
constant float2 lightDirection = float2(0.8, 0.6);

float bayer2(float2 a) {
    a = floor(a);
    return fract(dot(a, float2(0.5, a.y * 0.75)));
}

float bayer4(float2 a) {
    return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

float bayer8(float2 a) {
    return bayer4(0.5 * a) * 0.25 + bayer2(a);
}

float2 rotate(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

float2 hash22(float2 p) {
    float h = hash21(p);
    return float2(h, hash21(p + h + 17.17));
}

float valueNoise(float2 p) {
    float2 cell = floor(p);
    float2 f = fract(p);
    float2 blend = f * f * (3.0 - 2.0 * f);
    float a = hash21(cell);
    float b = hash21(cell + float2(1.0, 0.0));
    float c = hash21(cell + float2(0.0, 1.0));
    float d = hash21(cell + float2(1.0, 1.0));
    return mix(mix(a, b, blend.x), mix(c, d, blend.x), blend.y);
}

float fbm(float2 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 3; octave++) {
        value += amplitude * valueNoise(p);
        p = rotate(p, 0.6) * 2.07 + 13.1;
        amplitude *= 0.5;
    }
    return value;
}

float gust(float time) {
    return 0.5 + 0.5 * sin(time * 0.11) * sin(time * 0.067 + 1.3);
}

float segmentDistance(float2 p, float2 a, float2 b) {
    float2 pa = p - a;
    float2 ba = b - a;
    float k = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    return length(pa - ba * k);
}

float leafDistance(float2 p, float2 center, float2 axis, float size) {
    float2 offset = p - center;
    float2 q = float2(dot(offset, float2(axis.y, -axis.x)), dot(offset, axis));
    float y = clamp(q.y / size, -1.0, 1.0);
    float halfWidth = size * 0.42 * sqrt(1.0 - y * y);
    return max(abs(q.x) - halfWidth, abs(q.y) - size);
}

float2 limbPoint(float2 base, float heading, float bend, float length, float s) {
    float curved = heading + bend * s;
    return base + (float2(cos(heading), sin(heading)) + float2(cos(curved), sin(curved))) * s * length * 0.5;
}

float2 limbTangent(float2 start, float bend, float heading, float s) {
    float curved = heading + bend * s;
    float2 direction = float2(cos(curved), sin(curved));
    return normalize(start + direction + bend * s * float2(-direction.y, direction.x));
}

// Distance to one limb: a tapering stem with leaves spiralling off it.
float limbDistance(float2 p, float2 base, float heading, float bend, float length,
                   float width, float leafSize, float seed, float time, float wind, float margin) {
    float d = 1e5;
    float2 a = base;
    for (int i = 0; i < 4; i++) {
        float s1 = float(i + 1) / 4.0;
        float2 b = limbPoint(base, heading, bend, length, s1);
        d = min(d, segmentDistance(p, a, b) - width * (1.0 - 0.8 * s1));
        a = b;
    }
    float reach = leafSize * 2.4;
    if (d - reach > margin) {
        return d - reach;
    }

    float2 start = float2(cos(heading), sin(heading));
    float spin = seed * 3.1;
    for (int i = 0; i < leavesPerLimb; i++) {
        spin += goldenAngle;
        float h = hash21(float2(float(i), seed));
        float s = 0.2 + 0.8 * (float(i) + 0.5 + 0.4 * (h - 0.5)) / float(leavesPerLimb);
        float side = cos(spin) >= 0.0 ? 1.0 : -1.0;
        float size = leafSize * (0.65 + 0.45 * abs(cos(spin))) * (1.0 - 0.35 * s);
        float2 along = limbPoint(base, heading, bend, length, s);
        if (distance(p, along) - 2.0 * size > margin) {
            continue;
        }
        float2 tangent = limbTangent(start, bend, heading, s);
        float flutter = sin(time * (1.2 + h) + h * 30.0) * 0.22 * wind;
        float spread = side * (0.35 + 0.6 * abs(sin(spin)));
        float2 leafAxis = rotate(tangent, spread + flutter);
        d = min(d, leafDistance(p, along + leafAxis * size * 0.95, leafAxis, size));
    }
    return d;
}

// Distance to a whole bough: a main limb with twigs forking off it. The bough
// swings from its base, and each twig swings a little more on top of that.
float boughDistance(float2 p, int index, float halfWidth, float time, float margin) {
    float4 bough = boughs[index];
    float2 base = float2(bough.x * halfWidth, bough.y);
    float phase = float(index) * 1.7;
    float strength = 0.4 + gust(time);
    float swing = (0.03 * sin(time * 0.37 + phase) + 0.015 * sin(time * 0.83 + phase)) * strength;
    float2 q = base + rotate(p - base, swing);

    float seed = float(index) * 7.3;
    float bend = boughBend[index];
    float twigReach = bough.w * 0.45 + 0.2;
    float2 tip = limbPoint(base, bough.z, bend, bough.w, 1.0);
    float bound = segmentDistance(q, base, tip) - abs(bend) * bough.w * 0.15 - twigReach - 0.03;
    if (bound > margin) {
        return bound;
    }
    float wind = 0.3 + gust(time);
    float d = limbDistance(q, base, bough.z, bend, bough.w, 0.014, 0.075, seed, time, wind, margin + twigReach);
    if (d - twigReach > margin) {
        return d - twigReach;
    }

    float spin = seed;
    for (int t = 0; t < twigsPerBough; t++) {
        spin += goldenAngle;
        float s = 0.3 + 0.55 * float(t) / float(twigsPerBough - 1);
        float side = cos(spin) >= 0.0 ? 1.0 : -1.0;
        float2 forkPoint = limbPoint(base, bough.z, bend, bough.w, s);
        float length = bough.w * (0.45 - 0.12 * s);
        if (distance(q, forkPoint) - length - 0.13 > margin) {
            continue;
        }
        float2 tangent = limbTangent(float2(cos(bough.z), sin(bough.z)), bend, bough.z, s);
        float heading = atan2(tangent.y, tangent.x) + side * (0.55 + 0.3 * abs(sin(spin)));
        float twigSwing = 0.05 * sin(time * 0.6 + spin) * strength;
        float2 tq = forkPoint + rotate(q - forkPoint, twigSwing);
        d = min(d, limbDistance(tq, forkPoint, heading, -side * 0.4, length, 0.007, 0.06, seed + float(t) + 1.0, time, wind, margin));
    }
    return d;
}

// Shadow of the canopy further off: soft blobs, with round spots of sun
// where the gaps between leaves act like pinholes.
float farShadow(float2 p, float time) {
    float2 drift = float2(sin(time * 0.21), cos(time * 0.17)) * 0.015 * (0.5 + gust(time));
    float2 q = p + drift;
    float side = smoothstep(-0.6, 0.8, p.x + p.y * 0.6);
    float canopy = smoothstep(0.5, 0.7, fbm(q * 1.3 + 3.0) + 0.12 * side);
    if (canopy <= 0.0) {
        return 0.0;
    }

    float scale = 9.0;
    float2 g = q * scale;
    float2 cell = floor(g);
    float spots = 0.0;
    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            float2 c = cell + float2(i, j);
            float2 jitter = hash22(c);
            float2 wobble = float2(sin(time * 0.6 + jitter.x * 20.0), cos(time * 0.5 + jitter.y * 20.0)) * 0.08 * gust(time);
            float2 center = c + 0.5 + (jitter - 0.5) * 0.7 + wobble;
            float2 offset = rotate(g - center, atan2(lightDirection.y, lightDirection.x));
            float radius = 0.12 + 0.18 * hash21(c + 4.0);
            float spot = smoothstep(radius, radius * 0.35, length(offset * float2(0.8, 1.15)));
            spots = max(spots, spot * step(0.6, hash21(c + 9.0)));
        }
    }
    return canopy * (1.0 - spots * 0.9);
}

float sunPatch(float2 p, float halfWidth) {
    float falloff = length((p - float2(-0.3 * halfWidth, 0.15)) * float2(0.6, 0.9));
    return 1.0 - 0.35 * smoothstep(0.2, 1.0, falloff);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float2 pixel = floor(in.uv * u.resolution / ditherPixels);
    float2 p = ((pixel + 0.5) * ditherPixels - 0.5 * u.resolution) / u.resolution.y;
    float halfWidth = 0.5 * u.resolution.x / u.resolution.y;
    float time = u.time;

    float light = sunPatch(p, halfWidth) * (1.0 - 0.5 * farShadow(p, time));
    float fringe = 0.0;
    for (int b = 0; b < boughCount; b++) {
        float depth = boughDepth[b];
        float blur = mix(0.004, 0.05, depth);
        float band = blur * 1.5 + 0.004;
        float d = boughDistance(p, b, halfWidth, time, band + blur);
        float shade = smoothstep(blur, -blur, d);
        light *= 1.0 - mix(0.8, 0.35, depth) * shade;
        float edge = smoothstep(band, 0.0, d) * (1.0 - shade);
        fringe = max(fringe, edge * (1.0 - depth) * (1.0 - depth));
    }
    light += (valueNoise(p * 30.0) - 0.5) * 0.06;

    float threshold = bayer8(pixel);
    float level = saturate(light) * float(toneCount - 1);
    float index = floor(level);
    int tone = min(int(index + ((level - index) > threshold ? 1.0 : 0.0)), toneCount - 1);
    float3 color = tones[tone];
    if (tone >= 1 && tone <= 2 && fringe * 0.75 > bayer8(pixel + float2(3.0, 5.0))) {
        color = gold;
    }
    return float4(color, 1.0);
}
