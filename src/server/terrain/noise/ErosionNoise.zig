const std = @import("std");
const math = std.math;

const main = @import("main");
const vec = main.vec;

const Vec2f = vec.Vec2f;
const Vec3f = vec.Vec3f;
const Vec4f = vec.Vec4f;

const NeverFailingAllocator = main.heap.NeverFailingAllocator;
const Array2D = main.utils.Array2D;

const PerlinNoise = main.server.terrain.noise.PerlinNoise;

fn clamp(x: f32, a: f32, b: f32) f32 {
    return @max(a, @min(b, x));
}

fn clamp01(x: f32) f32 {
    return clamp(x, 0.0, 1.0);
}

fn mix(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * t;
}

fn safeNormalize(v: Vec2f) Vec2f {
    const len = length2(v);
    if (len < 1e-6) return Vec2f{0.0, 0.0};
    return Vec2f{ v[0] / len, v[1] / len };
}

fn mix2(a: Vec2f, b: Vec2f, t: f32) Vec2f {
    return Vec2f{
        mix(a[0], b[0], t),
        mix(a[1], b[1], t),
    };
}

fn mix3(a: Vec3f, b: Vec3f, t: f32) Vec3f {
    return Vec3f{
        mix(a[0], b[0], t),
        mix(a[1], b[1], t),
        mix(a[2], b[2], t),
    };
}

fn dot2(a: Vec2f, b: Vec2f) f32 {
    return a[0]*b[0] + a[1]*b[1];
}

fn length2(v: Vec2f) f32 {
    return math.sqrt(dot2(v, v));
}

fn fract(x: f32) f32 {
    return x - math.floor(x);
}

fn hash(p: Vec2f) Vec2f {
    const K1: f32 = 127.1;
    const K2: f32 = 311.7;
    const K3: f32 = 269.5;
    const K4: f32 = 183.3;

    var x = p[0] * K1 + p[1] * K2;
    var y = p[0] * K3 + p[1] * K4;

    x = fract(math.sin(x) * 43758.5453) - 0.5;
    y = fract(math.sin(y) * 43758.5453) - 0.5;

    return Vec2f{ x, y };
}

fn phacelleNoise(p: Vec2f, normDir: Vec2f, freq: f32, offset: f32, normalization: f32) Vec4f {
    const TAU: f32 = 6.28318530717959;

    const sideDir = Vec2f{
        -normDir[1] * freq * TAU,
         normDir[0] * freq * TAU,
    };

    const offsetTAU = offset * TAU;

    const pInt = Vec2f{ math.floor(p[0]), math.floor(p[1]) };
    const pFrac = Vec2f{ fract(p[0]), fract(p[1]) };

    var phaseDir = Vec2f{0, 0};
    var weightSum: f32 = 0.0;

    var i: i32 = -1;
    while (i <= 2) : (i += 1) {
        var j: i32 = -1;
        while (j <= 2) : (j += 1) {
            const gridOffset = Vec2f{ @floatFromInt(i), @floatFromInt(j) };
            const gridPoint = Vec2f{
                pInt[0] + gridOffset[0],
                pInt[1] + gridOffset[1],
            };

            const h = hash(gridPoint);
            const randomOffset = Vec2f{ h[0] * 0.5, h[1] * 0.5 };

            const v = Vec2f{
                pFrac[0] - gridOffset[0] - randomOffset[0],
                pFrac[1] - gridOffset[1] - randomOffset[1],
            };

            const sqrDist = dot2(v, v);
            var weight = math.exp(-sqrDist * 2.0);
            weight = @max(0.0, weight - 0.01111);

            weightSum += weight;

            const waveInput = dot2(v, sideDir) + offsetTAU;

            phaseDir[0] += math.cos(waveInput) * weight;
            phaseDir[1] += math.sin(waveInput) * weight;
        }
    }

    const invWeight = if (weightSum > 1e-6) 1.0 / weightSum else 0.0;

    const interpolated = Vec2f{
        phaseDir[0] * invWeight,
        phaseDir[1] * invWeight,
    };

    var magnitude = length2(interpolated);
    magnitude = @max(1.0 - normalization, magnitude);

    return Vec4f{
        interpolated[0] / magnitude,
        interpolated[1] / magnitude,
        sideDir[0],
        sideDir[1],
    };
}

fn pow_inv(t: f32, power: f32) f32 {
    return 1.0 - math.pow(f32, 1.0 - clamp01(t), power);
}

fn ease_out(t: f32) f32 {
    const v = 1.0 - clamp01(t);
    return 1.0 - v * v;
}

fn smooth_start(t: f32, smoothing: f32) f32 {
    if (t >= smoothing) return t - 0.5 * smoothing;
    return 0.5 * t * t / smoothing;
}

fn erosionFilter(
    p: Vec2f,
    heightAndSlope: Vec3f,
    fadeTarget: f32,
    strength: f32,
    gullyWeight: f32,
    detail: f32,
    rounding: Vec4f,
    onset: Vec4f,
    assumedSlope: Vec2f,
    scale: f32,
    octaves: usize,
    lacunarity: f32,
    gain: f32,
    cellScale: f32,
    normalization: f32,
    ridgeMap: *f32,
    debug: *f32,
) Vec4f {
    var strengthMut = strength * scale;
    var fade = clamp(fadeTarget, -1.0, 1.0);

    const inputHS = heightAndSlope;

    var freq: f32 = 1.0 / (scale * cellScale);
    const slopeLen = @max(length2(Vec2f{heightAndSlope[1], heightAndSlope[2]}), 1e-10);

    var magnitude: f32 = 0.0;
    var roundingMult: f32 = 1.0;

    const roundingForInput =
        mix(rounding[1], rounding[0], clamp01(fade + 0.5)) * rounding[2];

    var combiMask =
        ease_out(smooth_start(slopeLen * onset[0], roundingForInput * onset[0]));

    var ridgeMapCombiMask = ease_out(slopeLen * onset[2]);
    var ridgeMapFadeTarget = fade;

    var gullySlope = mix2(
        Vec2f{heightAndSlope[1], heightAndSlope[2]},
        Vec2f{
            heightAndSlope[1] / slopeLen * assumedSlope[0],
            heightAndSlope[2] / slopeLen * assumedSlope[0],
        },
        assumedSlope[1],
    );

    var h = heightAndSlope;

    for (0..octaves) |_| {
        var ph = phacelleNoise(
            Vec2f{ p[0] * freq, p[1] * freq },
            safeNormalize(gullySlope),
            cellScale,
            0.25,
            normalization,
        );

        ph[2] *= -freq;
        ph[3] *= -freq;

        const sloping = @abs(ph[1]);

        gullySlope[0] += math.sign(ph[1]) * ph[2] * strengthMut * gullyWeight;
        gullySlope[1] += math.sign(ph[1]) * ph[3] * strengthMut * gullyWeight;

        const gullies = Vec3f{
            ph[0],
            ph[1] * ph[2],
            ph[1] * ph[3],
        };

        const faded = mix3(
            Vec3f{fade, 0.0, 0.0},
            Vec3f{
                gullies[0] * gullyWeight,
                gullies[1] * gullyWeight,
                gullies[2] * gullyWeight,
            },
            combiMask,
        );

        h[0] += faded[0] * strengthMut;
        h[1] += faded[1] * strengthMut;
        h[2] += faded[2] * strengthMut;

        magnitude += strengthMut;

        fade = faded[0];

        const roundingForOctave =
            mix(rounding[1], rounding[0], clamp01(ph[0] + 0.5)) * roundingMult;

        const newMask =
            ease_out(smooth_start(sloping * onset[1], roundingForOctave * onset[1]));

        combiMask = pow_inv(combiMask, detail) * newMask;

        ridgeMapFadeTarget =
            mix(ridgeMapFadeTarget, gullies[0], ridgeMapCombiMask);

        const newRidgeMask = ease_out(sloping * onset[3]);
        ridgeMapCombiMask *= newRidgeMask;

        strengthMut *= gain;
        freq *= lacunarity;
        roundingMult *= rounding[3];
    }

    ridgeMap.* = ridgeMapFadeTarget * (1.0 - ridgeMapCombiMask);
    debug.* = fade;

    return Vec4f{
        h[0] - inputHS[0],
        h[1] - inputHS[1],
        h[2] - inputHS[2],
        magnitude,
    };
}

fn noised(p: Vec2f) Vec3f {
    const i = Vec2f{ math.floor(p[0]), math.floor(p[1]) };
    const f = Vec2f{ fract(p[0]), fract(p[1]) };

    const u = Vec2f{
        f[0]*f[0]*f[0]*(f[0]*(f[0]*6.0 - 15.0) + 10.0),
        f[1]*f[1]*f[1]*(f[1]*(f[1]*6.0 - 15.0) + 10.0),
    };

    const du = Vec2f{
        30.0 * f[0]*f[0]*(f[0]*(f[0]-2.0)+1.0),
        30.0 * f[1]*f[1]*(f[1]*(f[1]-2.0)+1.0),
    };

    const ga = hash(Vec2f{ i[0], i[1] });
    const gb = hash(Vec2f{ i[0]+1.0, i[1] });
    const gc = hash(Vec2f{ i[0], i[1]+1.0 });
    const gd = hash(Vec2f{ i[0]+1.0, i[1]+1.0 });

    const va = dot2(ga, Vec2f{ f[0], f[1] });
    const vb = dot2(gb, Vec2f{ f[0]-1.0, f[1] });
    const vc = dot2(gc, Vec2f{ f[0], f[1]-1.0 });
    const vd = dot2(gd, Vec2f{ f[0]-1.0, f[1]-1.0 });

    const value =
        va + u[0]*(vb-va) + u[1]*(vc-va) + u[0]*u[1]*(va - vb - vc + vd);

    const deriv = Vec2f{
        ga[0] + u[0]*(gb[0]-ga[0]) + u[1]*(gc[0]-ga[0]) +
            du[0]*(u[1]*(va-vb-vc+vd) + vb - va),

        ga[1] + u[0]*(gb[1]-ga[1]) + u[1]*(gc[1]-ga[1]) +
            du[1]*(u[0]*(va-vb-vc+vd) + vc - va),
    };

    return Vec3f{ value, deriv[0], deriv[1] };
}

fn fractalNoise(p: Vec2f, freq: f32, octaves: usize, lacunarity: f32, gain: f32) Vec3f {
    var n = Vec3f{0,0,0};
    var nf = freq;
    var na: f32 = 1.0;

    for (0..octaves) |_| {
        const noise = noised(Vec2f{ p[0]*nf, p[1]*nf });

        n[0] += noise[0] * na;
        n[1] += noise[1] * na * nf;
        n[2] += noise[2] * na * nf;

        na *= gain;
        nf *= lacunarity;
    }

    return n;
}

pub fn generateErosionHeightmap(
    allocator: NeverFailingAllocator,
    x: i32,
    y: i32,
    width: u31,
    height: u31,
    scale: f32,
    voxelSize: u31,
) Array2D(f32) {
    const map = Array2D(f32).init(allocator, width / voxelSize, height / voxelSize);
    @memset(map.mem, 0);

    const HEIGHT_FREQUENCY: f32 = 1.0 / 256.0;
    const HEIGHT_AMP: f32 = 0.125 * 256.0;
    const HEIGHT_OCTAVES: usize = 3;
    const HEIGHT_LACUNARITY: f32 = 2.0;
    const HEIGHT_GAIN: f32 = 0.1;
    const HEIGHT_FUNC_SCALE: f32 = 1.0;

    for (0..height / voxelSize) |j| {
        for (0..width / voxelSize) |i| {

            const uv = Vec2f{
                @as(f32, @floatFromInt(x + @as(i32, @intCast(i * voxelSize)))),

                @as(f32, @floatFromInt(y + @as(i32, @intCast(j * voxelSize)))),
            };

            var n = fractalNoise(
                uv / @as(Vec2f, @splat(HEIGHT_FUNC_SCALE)),
                HEIGHT_FREQUENCY,
                HEIGHT_OCTAVES,
                HEIGHT_LACUNARITY,
                HEIGHT_GAIN,
            );

            n[0] *= HEIGHT_AMP * HEIGHT_FUNC_SCALE;
            n[1] *= HEIGHT_AMP;
            n[2] *= HEIGHT_AMP;

            const fadeTarget = clamp(n[0] / (HEIGHT_AMP * 0.6), -1.0, 1.0);

            n[0] = n[0] * 0.5 + 0.5;
            n[1] = n[1] * 0.5;
            n[2] = n[2] * 0.5;

            var ridgeMap: f32 = 0;
            var debug: f32 = 0;

            const h = erosionFilter(
                uv,
                n,
                fadeTarget,
                0.22,
                0.5,
                1.5,
                Vec4f{0.1, 0.0, 0.1, 2.0},
                Vec4f{1.25, 1.25, 2.8, 1.5},
                Vec2f{0.7, 1.0},
                scale,
                5,
                2.0,
                0.5,
                0.7,
                0.5,
                &ridgeMap,
                &debug,
            );

            const offset = 0;//mix(-0.65, -fadeTarget, 0) * h[3];//-0.65 * h[3];
            const eroded = n[0] + h[0] * 1.0 + offset;
            _ = eroded;

            map.ptr(i, j).* = h[0];
        }
    }

    return map;
}