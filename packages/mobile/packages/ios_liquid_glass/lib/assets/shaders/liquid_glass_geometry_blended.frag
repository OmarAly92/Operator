// Copyright 2025, Tim Lehmann for whynotmake.it
//
// Geometry precomputation shader for blended liquid glass shapes
// This shader pre-computes the refraction displacement and encodes it into a texture
// Only needs to be re-run when shape geometry or layout changes

#version 460 core
precision mediump float;

#include <flutter/runtime_effect.glsl>
#include "sdf.glsl"
#include "displacement_encoding.glsl"

layout(location = 0) uniform vec2 uSize;
layout(location = 1) uniform vec4 uOpticalProps;
layout(location = 2) uniform float uNumShapes;
layout(location = 3) uniform float uShapeData[MAX_SHAPES * 6];

float uThickness = uOpticalProps.z;
float uRefractiveIndex = uOpticalProps.x;
float uOutlineBand = max(uOpticalProps.y, 0.0);
float uBlend = uOpticalProps.w;

layout(location = 0) out vec4 fragColor;

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;
    
    #ifdef IMPELLER_TARGET_OPENGLES
        vec2 screenUV = vec2(fragCoord.x / uSize.x, 1.0 - (fragCoord.y / uSize.y));
    #else
        vec2 screenUV = vec2(fragCoord.x / uSize.x, fragCoord.y / uSize.y);
    #endif
    
    float sd = sceneSDF(fragCoord, int(uNumShapes), uShapeData, uBlend);
    
    if (sd >= uOutlineBand + 1.0 || uThickness <= 0.0) {
        fragColor = vec4(0.0);
        return;
    }
    
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    float maxDisplacement = uThickness * 10.0;
    
    if (sd >= 0.0) {
        vec2 gradient = vec2(dx, dy);
        vec2 inward = length(gradient) > 0.0 ? -normalize(gradient) : vec2(0.0);
        fragColor = encodeGeometry(inward * maxDisplacement * 0.5, maxDisplacement, sd, uThickness);
        return;
    }
    
    float n_cos = max(uThickness + sd, 0.0) / uThickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    vec3 normal = normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
    
    float x = uThickness + sd;
    float sqrtTerm = sqrt(max(0.0, uThickness * uThickness - x * x));
    float height = mix(sqrtTerm, uThickness, float(sd < -uThickness));
    
    float baseHeight = uThickness * 8.0;
    vec3 incident = vec3(0.0, 0.0, -1.0);
    
    float invRefractiveIndex = 1.0 / uRefractiveIndex;
    vec3 baseRefract = refract(incident, normal, invRefractiveIndex);
    float baseRefractLength = (height + baseHeight) / max(0.001, abs(baseRefract.z));
    vec2 displacement = baseRefract.xy * baseRefractLength;
    
    fragColor = encodeGeometry(displacement, maxDisplacement, sd, uThickness);
}
