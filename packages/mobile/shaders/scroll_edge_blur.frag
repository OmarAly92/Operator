#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uMaxRadius;
uniform float uFromTop;
uniform vec4 uTint;
uniform sampler2D uTexture;

out vec4 fragColor;

void main() {
    vec2 frag = FlutterFragCoord().xy;
    vec2 uv = frag / uSize;
    float t = uFromTop > 0.5 ? 1.0 - uv.y : uv.y;
    float r = uMaxRadius * t;
    vec4 acc = vec4(0.0);
    float wsum = 0.0;
    for (int i = -3; i <= 3; i++) {
        for (int j = -3; j <= 3; j++) {
            vec2 o = vec2(float(i), float(j)) * (r / 3.0);
            float w = exp(-float(i * i + j * j) / 8.0);
            acc += texture(uTexture, (frag + o) / uSize) * w;
            wsum += w;
        }
    }
    vec4 blurred = acc / wsum;
    fragColor = mix(blurred, vec4(uTint.rgb * blurred.a, blurred.a), uTint.a * t);
}
