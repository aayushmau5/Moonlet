// Black Hole: a ray-traced black hole with a hot, spinning accretion disk.
// Each pixel follows a light ray that bends around the hole, so the far side of
// the disk shows up as an arch above the shadow and a thin ring below it.
// The side of the disk that turns toward you is brighter and bluer (Doppler beaming).
// It renders at half resolution (see wallpaper.json) to keep the GPU cool.
//
// Moonlet provides:
//   in.uv         0..1, origin at the bottom-left
//   u.time        seconds of playing time
//   u.resolution  drawable size in pixels
//
// Units: the event horizon has radius 1.

constant float diskInner = 3.0;
constant float diskOuter = 9.5;
constant int maxSteps = 180;

float hash31(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.zyx + 31.32);
    return fract((p.x + p.y) * p.z);
}

float3 hash33(float3 p) {
    p = fract(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return fract((p.xxy + p.yxx) * p.zyx);
}

float valueNoise(float3 p) {
    float3 cell = floor(p);
    float3 f = fract(p);
    float3 blend = f * f * (3.0 - 2.0 * f);
    float a = mix(hash31(cell), hash31(cell + float3(1, 0, 0)), blend.x);
    float b = mix(hash31(cell + float3(0, 1, 0)), hash31(cell + float3(1, 1, 0)), blend.x);
    float c = mix(hash31(cell + float3(0, 0, 1)), hash31(cell + float3(1, 0, 1)), blend.x);
    float d = mix(hash31(cell + float3(0, 1, 1)), hash31(cell + float3(1, 1, 1)), blend.x);
    return mix(mix(a, b, blend.y), mix(c, d, blend.y), blend.z);
}

float fbm(float3 p) {
    float value = 0.0;
    float amplitude = 0.5;
    for (int octave = 0; octave < 4; octave++) {
        value += amplitude * valueNoise(p);
        p = p * 2.03 + 11.7;
        amplitude *= 0.5;
    }
    return value;
}

// Approximate color of a glowing body; 1 is a warm orange-white.
float3 blackbody(float temperature) {
    float3 cool = float3(1.0, 0.18, 0.02);
    float3 warm = float3(1.0, 0.62, 0.28);
    float3 white = float3(1.0, 0.93, 0.85);
    float3 blue = float3(0.72, 0.82, 1.0);
    float3 color = mix(cool, warm, smoothstep(0.3, 0.8, temperature));
    color = mix(color, white, smoothstep(0.8, 1.3, temperature));
    return mix(color, blue, smoothstep(1.3, 2.2, temperature));
}

// The disk texture spins faster near the hole. Two copies, half a cycle apart, fade
// into each other so the spiral never winds up into thin lines.
float diskTexture(float radius, float angle, float time) {
    float spin = 0.9 / pow(radius, 1.5);
    const float period = 24.0;
    float total = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float phase = fract(time / period + 0.5 * float(layer));
        float weight = 1.0 - abs(phase * 2.0 - 1.0);
        float turned = angle - spin * phase * period;
        float3 q = float3(cos(turned) * 2.2, sin(turned) * 2.2, radius * 1.6 + float(layer) * 7.3);
        float streaks = fbm(q * float3(1.0, 1.0, 2.6));
        total += weight * streaks;
    }
    return total;
}

float4 shadeDisk(float3 hit, float3 rayDirection, float time) {
    float radius = length(hit.xz);
    if (radius < diskInner * 0.9 || radius > diskOuter) {
        return float4(0.0);
    }
    float angle = atan2(hit.z, hit.x);

    float speed = sqrt(0.5 / radius);
    float3 orbit = normalize(float3(-hit.z, 0.0, hit.x)) * speed * 0.8;
    float3 towardViewer = -rayDirection;
    float lorentz = rsqrt(1.0 - dot(orbit, orbit));
    float doppler = 1.0 / (lorentz * (1.0 - dot(orbit, towardViewer)));
    float gravity = sqrt(1.0 - 1.0 / radius);
    float shift = doppler * gravity;

    float x = diskInner / radius;
    float heat = pow(x, 0.75) * pow(saturate(1.0 - sqrt(x * 0.92)), 0.25) * 2.6;

    float texture = diskTexture(radius, angle, time);
    float density = saturate(texture * 1.7 - 0.25);
    density *= smoothstep(diskInner * 0.9, diskInner * 1.15, radius);
    density *= smoothstep(diskOuter, diskOuter * 0.45, radius);

    float3 color = blackbody(heat * shift * 0.75) * heat * heat * pow(shift, 3.0) * 1.3;
    color *= 0.15 + density * density * 2.0;
    float alpha = saturate(density * 1.6) * 0.92;
    return float4(color * alpha, alpha);
}

float3 starfield(float3 direction, float time) {
    float3 color = float3(0.004, 0.005, 0.01);

    float band = exp(-pow(dot(direction, normalize(float3(0.25, 1.0, 0.35))) * 3.2, 2.0));
    float dust = fbm(direction * 4.0 + 3.0);
    color += float3(0.022, 0.02, 0.03) * band * smoothstep(0.4, 0.8, dust);

    for (int layer = 0; layer < 2; layer++) {
        float scale = layer == 0 ? 70.0 : 150.0;
        float3 p = direction * scale;
        float3 cell = floor(p);
        float3 random = hash33(cell + float(layer) * 41.0);
        if (random.x > (layer == 0 ? 0.25 : 0.5)) {
            continue;
        }
        float3 center = cell + 0.25 + 0.5 * hash33(cell + 17.0);
        float distance = length(p - center);
        float size = layer == 0 ? 0.12 : 0.09;
        float glow = exp(-distance * distance / (size * size));
        float brightness = pow(random.y, 3.0) * (layer == 0 ? 1.2 : 0.6);
        float twinkle = 0.75 + 0.25 * sin(time * (0.6 + random.z) + random.z * 40.0);
        float3 tint = mix(float3(0.7, 0.8, 1.0), float3(1.0, 0.85, 0.7), random.z);
        color += tint * glow * brightness * twinkle;
    }
    return color;
}

float3 tonemap(float3 color) {
    color = color * (2.51 * color + 0.03) / (color * (2.43 * color + 0.59) + 0.14);
    return pow(saturate(color), 1.0 / 2.2);
}

fragment float4 wallpaper(VertexOut in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
    float aspect = u.resolution.x / u.resolution.y;
    float2 screen = (in.uv - 0.5) * float2(aspect, 1.0);
    float time = u.time;

    float azimuth = time * 0.006;
    float inclination = 0.17 + 0.03 * sin(time * 0.05);
    const float distance = 26.0;
    float3 camera = distance * float3(sin(azimuth) * cos(inclination), sin(inclination), -cos(azimuth) * cos(inclination));
    float3 forward = normalize(-camera);
    float3 right = normalize(cross(float3(0.0, 1.0, 0.0), forward));
    float3 up = cross(forward, right);
    float roll = 0.12;
    float2 rolled = float2(screen.x * cos(roll) - screen.y * sin(roll), screen.x * sin(roll) + screen.y * cos(roll));
    float3 direction = normalize(forward + (rolled.x * right + rolled.y * up) * 0.62);

    float3 position = camera;
    float3 velocity = direction;
    float angularMomentum = length_squared(cross(position, velocity));

    float3 color = float3(0.0);
    float opacity = 0.0;
    float glow = 0.0;
    bool captured = false;

    for (int step = 0; step < maxSteps; step++) {
        float radius = length(position);
        float stepSize = clamp(0.07 * radius, 0.03, 1.2);

        float3 acceleration = -1.5 * angularMomentum * position / pow(radius, 5.0);
        float3 nextVelocity = velocity + acceleration * stepSize;
        float3 next = position + nextVelocity * stepSize;

        if (sign(next.y) != sign(position.y)) {
            float t = position.y / (position.y - next.y);
            float3 hit = mix(position, next, t);
            float4 disk = shadeDisk(hit, normalize(nextVelocity), time);
            color += (1.0 - opacity) * disk.rgb;
            opacity += (1.0 - opacity) * disk.a;
        }

        float ringDistance = length(float2(length(position.xz) - diskInner * 1.3, position.y));
        glow += stepSize * exp(-ringDistance * 1.6) * (1.0 - opacity);

        position = next;
        velocity = nextVelocity;

        if (length_squared(position) < 1.0) {
            captured = true;
            break;
        }
        if (opacity > 0.99) {
            break;
        }
        if (radius > distance * 1.3 && dot(position, velocity) > 0.0) {
            break;
        }
    }

    float3 background = captured ? float3(0.0) : starfield(normalize(velocity), time);
    color += (1.0 - opacity) * background;
    color += float3(1.0, 0.5, 0.2) * glow * (captured ? 0.0 : 0.012);

    float vignette = smoothstep(1.5, 0.35, length(screen * float2(0.8, 1.0)));
    return float4(tonemap(color * vignette * 1.1), 1.0);
}
