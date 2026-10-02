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
uniform vec4 uTintSheen;
uniform vec4 uOutline;
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
    if (geometryData.a < 0.5) {
        fragColor = vec4(0.0);
        return;
    }

    float thickness = max(uOptics.x, 0.001);
    float signedDistance = decodeSignedDistance(geometryData, signedDistanceReach(thickness, uOutline.z));
    vec2 displacement = decodeDisplacement(geometryData, thickness * 10.0);
    vec2 normal = length(displacement) > 0.0001 ? normalize(displacement) : vec2(0.0);

    float coverage = clamp(0.5 - signedDistance, 0.0, 1.0);
    float outlineStrength = mix(uOutline.y, uOutline.x, abs(normal.x));
    float outlineCoverage = clamp(uOutline.z + 0.5 - signedDistance, 0.0, 1.0) * (1.0 - coverage);
    float outlineAlpha = clamp(outlineStrength, 0.0, 1.0) * outlineCoverage;
    if (coverage <= 0.0) {
        fragColor = vec4(0.0, 0.0, 0.0, outlineAlpha);
        return;
    }

    float edgeDistance = clamp(-signedDistance, 0.0, thickness);
    float rise = 1.0 - edgeDistance / thickness;
    float heightNorm = sqrt(max(0.0, 1.0 - rise * rise));
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

    vec3 tintTone = clamp(uGlassColor.rgb * mix(uTintSheen.x, uTintSheen.y, luminance), 0.0, 1.0);
    color = mix(color, tintTone, uGlassColor.a);

    float power = max(uLight.z, 0.001);
    float lobes = pow(max(0.0, dot(normal, uLightDirection)), power) + uLight.w * pow(max(0.0, dot(normal, -uLightDirection)), power);
    float fade = 1.0 - smoothstep(0.7 * thickness, thickness, edgeDistance);
    float line = uLight.x * exp(-edgeDistance / max(uLight.y, 0.001));
    float sheen = uTintSheen.z * exp(-edgeDistance / max(uTintSheen.w, 0.001));
    color = clamp(color + vec3(lobes * fade * (line + sheen)), 0.0, 1.0);

    float alpha = coverage + outlineAlpha;
    fragColor = vec4(color * coverage, alpha);
}
