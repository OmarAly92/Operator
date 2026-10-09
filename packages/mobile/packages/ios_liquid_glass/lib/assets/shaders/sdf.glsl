// Shape array uniforms - 6 floats per shape (type, centerX, centerY, sizeW, sizeH, cornerRadius)
// Reduced from 64 to 16 shapes to fit Impeller's uniform buffer limit (16 * 6 = 96 floats vs 384)
#define MAX_SHAPES 16

float sdfRRect( in vec2 p, in vec2 b, in float r ) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p)-b+r;
    return min(max(q.x,q.y),0.0) + length(max(q,0.0)) - r;
}

float sdfRect(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

#define SQUIRCLE_EXPONENT 3.5
#define SQUIRCLE_EXTENT 1.65

float sdfSquircle(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r * SQUIRCLE_EXTENT, shortest);
    vec2 q = abs(p) - b + r;
    vec2 m = max(q, 0.0);
    float corner = pow(pow(m.x, SQUIRCLE_EXPONENT) + pow(m.y, SQUIRCLE_EXPONENT), 1.0 / SQUIRCLE_EXPONENT);
    return min(max(q.x, q.y), 0.0) + corner - r;
}

float sdfEllipse(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    
    vec2 invR = 1.0 / r;
    vec2 invR2 = invR * invR;
    
    vec2 pInvR = p * invR;
    float k1 = length(pInvR);
    
    vec2 pInvR2 = p * invR2;
    float k2 = length(pInvR2);
    
    return (k1 * (k1 - 1.0)) / max(k2, 1e-4);
}

vec3 shapedGradient(float d, vec2 g, vec2 p) {
    float len = length(g);
    return vec3(d, len > 0.0 ? g / len * sign(p) : vec2(0.0));
}

vec3 sdfRRectGrad(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r, shortest);
    vec2 q = abs(p) - b + r;
    vec2 m = max(q, 0.0);
    float d = min(max(q.x, q.y), 0.0) + length(m) - r;
    vec2 axis = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    return shapedGradient(d, (m.x > 0.0 || m.y > 0.0) ? m : axis, p);
}

vec3 sdfSquircleGrad(vec2 p, vec2 b, float r) {
    float shortest = min(b.x, b.y);
    r = min(r * SQUIRCLE_EXTENT, shortest);
    vec2 q = abs(p) - b + r;
    vec2 m = max(q, 0.0);
    float corner = pow(pow(m.x, SQUIRCLE_EXPONENT) + pow(m.y, SQUIRCLE_EXPONENT), 1.0 / SQUIRCLE_EXPONENT);
    float d = min(max(q.x, q.y), 0.0) + corner - r;
    vec2 axis = q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    vec2 slope = vec2(pow(m.x, SQUIRCLE_EXPONENT - 1.0), pow(m.y, SQUIRCLE_EXPONENT - 1.0));
    return shapedGradient(d, (m.x > 0.0 || m.y > 0.0) ? slope : axis, p);
}

vec3 sdfEllipseGrad(vec2 p, vec2 r) {
    r = max(r, 1e-4);
    vec2 invR = 1.0 / r;
    vec2 pInvR2 = p * invR * invR;
    float k1 = length(p * invR);
    float k2 = length(pInvR2);
    float d = (k1 * (k1 - 1.0)) / max(k2, 1e-4);
    return vec3(d, k2 > 0.0 ? pInvR2 / k2 : vec2(0.0));
}

vec3 angleSmoothUnion(vec3 a, vec3 b, float k) {
    float h = max(k - abs(a.x - b.x), 0.0) / k;
    float w = (1.0 - dot(a.yz, b.yz)) * 0.5;
    vec3 near = a.x < b.x ? a : b;
    vec3 far = a.x < b.x ? b : a;
    vec2 g = mix(near.yz, far.yz, h * w * 0.5);
    float len = length(g);
    return vec3(near.x - k * 0.25 * h * h * w, len > 1e-6 ? g / len : near.yz);
}

float getShapeSDF(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) { // squircle
        return sdfSquircle(p - center, size / 2.0, r);
    }
    if (type == 2.0) { // ellipse
        return sdfEllipse(p - center, size / 2.0);
    }
    if (type == 3.0) { // rounded rectangle
        return sdfRRect(p - center, size / 2.0, r);
    }
    return 1e9; // none
}

vec3 getShapeSDFGrad(float type, vec2 p, vec2 center, vec2 size, float r) {
    if (type == 1.0) {
        return sdfSquircleGrad(p - center, size / 2.0, r);
    }
    if (type == 2.0) {
        return sdfEllipseGrad(p - center, size / 2.0);
    }
    if (type == 3.0) {
        return sdfRRectGrad(p - center, size / 2.0, r);
    }
    return vec3(1e9, 0.0, 0.0);
}

float getShapeSDFFromArray(int index, vec2 p, float shapeData[MAX_SHAPES * 6]) {
    int baseIndex = index * 6;
    float type = shapeData[baseIndex];
    vec2 center = vec2(shapeData[baseIndex + 1], shapeData[baseIndex + 2]);
    vec2 size = vec2(shapeData[baseIndex + 3], shapeData[baseIndex + 4]);
    float cornerRadius = shapeData[baseIndex + 5];
    
    return getShapeSDF(type, p, center, size, cornerRadius);
}

vec3 getShapeSDFGradFromArray(int index, vec2 p, float shapeData[MAX_SHAPES * 6]) {
    int baseIndex = index * 6;
    vec2 center = vec2(shapeData[baseIndex + 1], shapeData[baseIndex + 2]);
    vec2 size = vec2(shapeData[baseIndex + 3], shapeData[baseIndex + 4]);
    return getShapeSDFGrad(shapeData[baseIndex], p, center, size, shapeData[baseIndex + 5]);
}

float sceneSDF(vec2 p, int numShapes, float shapeData[MAX_SHAPES * 6], float blend) {
    if (numShapes == 0) {
        return 1e9;
    }
    
    if (blend <= 0.0) {
        float result = getShapeSDFFromArray(0, p, shapeData);
        for (int i = 1; i < min(numShapes, MAX_SHAPES); i++) {
            result = min(result, getShapeSDFFromArray(i, p, shapeData));
        }
        return result;
    }
    
    vec3 blended = getShapeSDFGradFromArray(0, p, shapeData);
    for (int i = 1; i < min(numShapes, MAX_SHAPES); i++) {
        blended = angleSmoothUnion(blended, getShapeSDFGradFromArray(i, p, shapeData), blend);
    }
    return blended.x;
}

// Calculate 3D normal using derivatives (shader-specific normal calculation)
vec3 getNormal(float sd, float thickness) {
    float dx = dFdx(sd);
    float dy = dFdy(sd);
    
    // The cosine and sine between normal and the xy plane
    float n_cos = max(thickness + sd, 0.0) / thickness;
    float n_sin = sqrt(max(0.0, 1.0 - n_cos * n_cos));
    
    return normalize(vec3(dx * n_cos, dy * n_cos, n_sin));
}
