import 'dart:math' as math;

class MirrorShape {
  const MirrorShape(this.type, this.cx, this.cy, this.width, this.height, this.radius);

  const MirrorShape.circle(double cx, double cy, double diameter) : this(2, cx, cy, diameter, diameter, 0);

  final double type;
  final double cx;
  final double cy;
  final double width;
  final double height;
  final double radius;
}

class Sdf {
  const Sdf(this.d, this.nx, this.ny);

  final double d;
  final double nx;
  final double ny;
}

const double _squircleExponent = 3.5;
const double _squircleExtent = 1.65;

double _sign(double v) => v > 0 ? 1 : (v < 0 ? -1 : 0);

double _length(double x, double y) => math.sqrt(x * x + y * y);

Sdf sdfRRect(double px, double py, double bx, double by, double r) {
  r = math.min(r, math.min(bx, by));
  final qx = px.abs() - bx + r, qy = py.abs() - by + r;
  final mx = math.max(qx, 0.0), my = math.max(qy, 0.0);
  final d = math.min(math.max(qx, qy), 0.0) + _length(mx, my) - r;
  final (gx, gy) = mx > 0 || my > 0 ? (mx, my) : (qx > qy ? (1.0, 0.0) : (0.0, 1.0));
  return _shaped(d, gx, gy, px, py);
}

Sdf sdfSquircle(double px, double py, double bx, double by, double r) {
  r = math.min(r * _squircleExtent, math.min(bx, by));
  final qx = px.abs() - bx + r, qy = py.abs() - by + r;
  final mx = math.max(qx, 0.0), my = math.max(qy, 0.0);
  final corner = math.pow(math.pow(mx, _squircleExponent) + math.pow(my, _squircleExponent), 1 / _squircleExponent).toDouble();
  final d = math.min(math.max(qx, qy), 0.0) + corner - r;
  final (gx, gy) = mx > 0 || my > 0
      ? (math.pow(mx, _squircleExponent - 1).toDouble(), math.pow(my, _squircleExponent - 1).toDouble())
      : (qx > qy ? (1.0, 0.0) : (0.0, 1.0));
  return _shaped(d, gx, gy, px, py);
}

Sdf _shaped(double d, double gx, double gy, double px, double py) {
  final length = _length(gx, gy);
  return length > 0 ? Sdf(d, gx / length * _sign(px), gy / length * _sign(py)) : Sdf(d, 0, 0);
}

Sdf sdfEllipse(double px, double py, double rx, double ry) {
  rx = math.max(rx, 1e-4);
  ry = math.max(ry, 1e-4);
  final k1 = _length(px / rx, py / ry);
  final gx = px / (rx * rx), gy = py / (ry * ry);
  final k2 = _length(gx, gy);
  final d = (k1 * (k1 - 1)) / math.max(k2, 1e-4);
  return k2 > 0 ? Sdf(d, gx / k2, gy / k2) : Sdf(d, 0, 0);
}

Sdf shapeSdfWithNormal(MirrorShape s, double x, double y) {
  final px = x - s.cx, py = y - s.cy;
  return switch (s.type) {
    1 => sdfSquircle(px, py, s.width / 2, s.height / 2, s.radius),
    2 => sdfEllipse(px, py, s.width / 2, s.height / 2),
    3 => sdfRRect(px, py, s.width / 2, s.height / 2, s.radius),
    _ => const Sdf(1e9, 0, 0),
  };
}

double shapeSdf(MirrorShape s, double x, double y) => shapeSdfWithNormal(s, x, y).d;

Sdf angleSmoothUnion(Sdf a, Sdf b, double k) {
  final h = math.max(k - (a.d - b.d).abs(), 0.0) / k;
  final w = (1 - (a.nx * b.nx + a.ny * b.ny)) * 0.5;
  final near = a.d < b.d ? a : b, far = a.d < b.d ? b : a;
  final t = h * w * 0.5;
  final gx = near.nx + (far.nx - near.nx) * t, gy = near.ny + (far.ny - near.ny) * t;
  final length = _length(gx, gy);
  return length > 1e-6 ? Sdf(near.d - k * 0.25 * h * h * w, gx / length, gy / length) : Sdf(near.d - k * 0.25 * h * h * w, near.nx, near.ny);
}

Sdf sceneSdfWithNormal(List<MirrorShape> shapes, double x, double y, double blend) {
  var result = shapeSdfWithNormal(shapes.first, x, y);
  for (final shape in shapes.skip(1)) {
    result = angleSmoothUnion(result, shapeSdfWithNormal(shape, x, y), blend);
  }
  return result;
}

double sceneSdf(List<MirrorShape> shapes, double x, double y, double blend) {
  if (shapes.isEmpty) return 1e9;
  if (blend <= 0) {
    var result = shapeSdf(shapes.first, x, y);
    for (final shape in shapes.skip(1)) {
      result = math.min(result, shapeSdf(shape, x, y));
    }
    return result;
  }
  return sceneSdfWithNormal(shapes, x, y, blend).d;
}
