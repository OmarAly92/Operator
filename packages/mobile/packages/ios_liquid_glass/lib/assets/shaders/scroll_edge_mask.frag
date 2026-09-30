#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBandOriginY;
uniform float uBandHeight;
uniform float uFromTop;
uniform float uKnee;
uniform vec4 uRamp;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    float dist = uFromTop > 0.5 ? frag.y - uBandOriginY : uBandOriginY + uBandHeight - frag.y;
    float t = 1.0 - clamp(dist / uBandHeight, 0.0, 1.0);
    float w = uKnee > 0.0 ? smoothstep(0.0, uKnee, t) : step(0.0001, t);
    float cap = uRamp.z > 0.0 ? 1.0 - smoothstep(uRamp.z * 0.6, uRamp.z, dist) : 0.0;
    float level = uRamp.w > 0.5 ? cap : clamp((w - uRamp.x) / max(uRamp.y - uRamp.x, 0.0001), 0.0, 1.0);
    fragColor = texture(uTexture, frag / uSize) * level;
}
