// Copyright 2025, Tim Lehmann for whynotmake.it

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "displacement_encoding.glsl"

uniform vec2 uSize;
uniform vec2 uGeometryOffset;
uniform vec2 uGeometrySize;
uniform vec4 uGlassColor;
uniform vec4 uOptics;
uniform vec4 uTone;
uniform vec4 uTintTone;
uniform vec4 uEdge;
uniform vec4 uLight;
uniform vec2 uLightDirection;

uniform sampler2D uBackgroundTexture;
uniform sampler2D uGeometryTexture;

layout(location = 0) out vec4 fragColor;

const vec3 LUMA = vec3(0.2126, 0.7152, 0.0722);

float toneCurve(float l) {
    return uTone.x * (1.0 - l) * (1.0 - 2.0 * l) + 4.0 * uTone.y * l * (1.0 - l) + uTone.z * l * (2.0 * l - 1.0);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    vec2 screenUV = fragCoord / uSize;
    vec2 geometryUV = (fragCoord - uGeometryOffset) / uGeometrySize;
    #ifdef IMPELLER_TARGET_OPENGLES
        screenUV.y = 1.0 - screenUV.y;
        geometryUV.y = 1.0 - geometryUV.y;
    #endif

    vec4 geometryData = texture(uGeometryTexture, geometryUV);
    if (geometryData.a < 0.01) {
        fragColor = vec4(0.0);
        return;
    }

    float thickness = max(uOptics.x, 0.001);
    vec2 displacement = decodeDisplacement(geometryData, thickness * 10.0);
    float heightNorm = clamp(geometryData.b, 0.0, 1.0);
    float edgeDistance = thickness * (1.0 - sqrt(max(0.0, 1.0 - heightNorm * heightNorm)));
    float bevel = 1.0 - heightNorm;

    vec2 texel = 1.0 / uSize;
    float spread = uOptics.y * bevel;
    vec4 centre = texture(uBackgroundTexture, screenUV + displacement * texel);
    vec3 color = vec3(
        texture(uBackgroundTexture, screenUV + displacement * (1.0 + spread) * texel).r,
        centre.g,
        texture(uBackgroundTexture, screenUV + displacement * (1.0 - spread) * texel).b
    );

    float luminance = dot(color, LUMA);
    vec3 chroma = color - vec3(luminance);
    float toned = clamp(toneCurve(luminance), 0.0, 1.0);
    color = clamp(vec3(toned) + chroma * uOptics.z, 0.0, 1.0);

    vec3 tintTone = clamp(uGlassColor.rgb * mix(uTintTone.x, uTintTone.y, luminance), 0.0, 1.0);
    color = mix(color, tintTone, uGlassColor.a);

    vec3 hairlineColor = mix(vec3(uEdge.w), vec3(uEdge.z), smoothstep(0.35, 0.65, luminance));
    float hairlineMask = 1.0 - smoothstep(0.0, max(uEdge.y, 0.001), edgeDistance);
    color = mix(color, hairlineColor, clamp(uEdge.x * hairlineMask, 0.0, 1.0));

    vec2 normal = length(displacement) > 0.0001 ? normalize(displacement) : vec2(0.0);
    float power = max(uLight.z, 0.001);
    float key = pow(max(0.0, dot(normal, uLightDirection)), power);
    float fill = uLight.w * pow(max(0.0, dot(normal, -uLightDirection)), power);
    float specularMask = 1.0 - smoothstep(0.0, max(uLight.y, 0.001), edgeDistance);
    color = clamp(color + vec3((key + fill) * uLight.x * specularMask), 0.0, 1.0);

    float alpha = geometryData.a;
    fragColor = vec4(color * alpha, alpha);
}
