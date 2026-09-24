#version 460 core
precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uBandHeight;
uniform float uMaxRadius;
uniform float uFromTop;
uniform float uBandOriginY;
uniform vec4 uTint;
uniform float uKnee;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    float distFromEdge = uFromTop > 0.5 ? (frag.y - uBandOriginY) : (uBandOriginY + uBandHeight - frag.y);
    float s = clamp(distFromEdge / uBandHeight, 0.0, 1.0);
    float t = 1.0 - s;
    float w = smoothstep(0.0, uKnee, t);
    float r = uMaxRadius * w;
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -3; i <= 3; i++) {
        for (int j = -3; j <= 3; j++) {
            vec2 o = vec2(float(i), float(j)) * (r / 3.0);
            float wk = exp(-float(i * i + j * j) / 8.0);
            acc += texture(uTexture, (frag + o) / uSize) * wk;
            wsum += wk;
        }
    }
    vec4 blurred = acc / wsum;
    fragColor = mix(blurred, vec4(uTint.rgb * blurred.a, blurred.a), uTint.a * w);
}
