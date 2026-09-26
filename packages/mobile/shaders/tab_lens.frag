#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uRect;
uniform vec3 uScale;
uniform vec3 uCap;
uniform vec2 uRimWidth;
uniform vec3 uRimAlpha;
uniform float uTopGlow;
uniform vec3 uShade;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 hs = uRect.zw * 0.5;
    vec2 center = uRect.xy + hs;
    vec2 d = frag - center;

    float radius = min(hs.x, hs.y);
    vec2 core = max(hs - vec2(radius), vec2(0.0));
    vec2 nearest = clamp(d, -core, core);
    vec2 v = d - nearest;
    float dist = length(v);
    vec2 normal = dist > 0.001 ? v / dist : vec2(0.0, -1.0);
    float inside = radius - dist;

    vec2 axis = center + nearest;
    float intoCap = max(abs(d.x) - core.x - uCap.x, 0.0) / uCap.y;
    float ellipse = clamp(1.0 - intoCap * intoCap, 0.0, 1.0);
    float capBlend = 1.0 - ellipse;
    vec3 scale = mix(vec3(uCap.z), uScale, ellipse);
    float r = texture(uTexture, (axis + v * scale.r) / uSize).r;
    vec4 g = texture(uTexture, (axis + v * scale.g) / uSize);
    float b = texture(uTexture, (axis + v * scale.b) / uSize).b;
    vec3 color = vec3(r, g.g, b);
    float depth = smoothstep(0.0, uShade.z, max(inside, 0.0));
    color *= 1.0 - mix(uShade.y, uShade.x, depth);

    float top = clamp(-normal.y, 0.0, 1.0);
    float bottom = clamp(normal.y, 0.0, 1.0);
    float edge = max(inside, 0.0);
    float line = 1.0 - smoothstep(0.0, uRimWidth.x, edge);
    float lineAlpha = uRimAlpha.x + (uRimAlpha.z - uRimAlpha.x) * top + (uRimAlpha.y - uRimAlpha.x) * bottom;
    float glow = uTopGlow * top * top * exp(-edge / (uRimWidth.y * (1.0 + 2.5 * capBlend)));
    color = mix(color, vec3(1.0), clamp(line * lineAlpha + glow, 0.0, 1.0));

    fragColor = vec4(color, 1.0);
}
