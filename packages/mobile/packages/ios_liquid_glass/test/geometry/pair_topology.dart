import 'dart:collection';
import 'dart:math' as math;

import 'scene_sdf_mirror.dart';

const int pairScale = 3;
const double pairRadius = 40;
const int topologyMinArea = 20;

class PairField {
  PairField._(this.gap, this.width, this.height, this.mask);

  factory PairField(double gap, double k) {
    final widthPt = 2 * pairRadius + gap + 24;
    const heightPt = 2 * pairRadius + 24;
    final width = (widthPt * pairScale).toInt();
    final height = (heightPt * pairScale).toInt();
    final cx = pairRadius + gap / 2;
    final shapes = [MirrorShape.circle(-cx, 0, 2 * pairRadius), MirrorShape.circle(cx, 0, 2 * pairRadius)];
    final mask = List.generate(height, (row) {
      final y = (row + 0.5) / pairScale - heightPt / 2;
      return List.generate(width, (column) => sceneSdf(shapes, (column + 0.5) / pairScale - widthPt / 2, y, k) < 0);
    });
    return PairField._(gap, width, height, mask);
  }

  final double gap;
  final int width;
  final int height;
  final List<List<bool>> mask;

  double xOf(int column) => (column + 0.5) / pairScale - (2 * pairRadius + gap + 24) / 2;

  int get count {
    final rows = height ~/ pairScale, columns = width ~/ pairScale;
    final points = List.generate(rows, (r) => List.generate(columns, (c) {
      var lit = 0;
      for (var dy = 0; dy < pairScale; dy++) {
        for (var dx = 0; dx < pairScale; dx++) {
          if (mask[r * pairScale + dy][c * pairScale + dx]) lit++;
        }
      }
      return lit / (pairScale * pairScale) >= 0.5;
    }));
    final seen = List.generate(rows, (_) => List.filled(columns, false));
    var found = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < columns; c++) {
        if (!points[r][c] || seen[r][c]) continue;
        seen[r][c] = true;
        final queue = Queue<(int, int)>()..add((r, c));
        var area = 0;
        while (queue.isNotEmpty) {
          final (y, x) = queue.removeFirst();
          area++;
          for (final (ny, nx) in [(y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)]) {
            if (ny >= 0 && ny < rows && nx >= 0 && nx < columns && points[ny][nx] && !seen[ny][nx]) {
              seen[ny][nx] = true;
              queue.add((ny, nx));
            }
          }
        }
        if (area >= topologyMinArea) found++;
      }
    }
    return found;
  }

  int _crossSection(double px, double py, double nx, double ny) {
    var length = 0;
    for (final direction in [1, -1]) {
      var step = direction == 1 ? 0 : 1;
      while (true) {
        final ix = (px + nx * direction * step).floor(), iy = (py + ny * direction * step).floor();
        if (!(ix >= 0 && ix < width && iy >= 0 && iy < height && mask[iy][ix])) break;
        length++;
        step++;
      }
    }
    return length;
  }

  double get neck {
    final xs = <double>[], ys = <double>[];
    for (var r = 0; r < height; r++) {
      for (var c = 0; c < width; c++) {
        if (mask[r][c]) {
          xs.add(c + 0.5);
          ys.add(r + 0.5);
        }
      }
    }
    final n = xs.length;
    final mx = xs.reduce((a, b) => a + b) / n, my = ys.reduce((a, b) => a + b) / n;
    var sxx = 0.0, syy = 0.0, sxy = 0.0;
    for (var i = 0; i < n; i++) {
      sxx += (xs[i] - mx) * (xs[i] - mx);
      syy += (ys[i] - my) * (ys[i] - my);
      sxy += (xs[i] - mx) * (ys[i] - my);
    }
    final lambda = (sxx + syy) / 2 + math.sqrt(math.pow((sxx - syy) / 2, 2) + sxy * sxy);
    var (ax, ay) = sxy != 0 ? (lambda - syy, sxy) : (sxx >= syy ? (1.0, 0.0) : (0.0, 1.0));
    final norm = math.sqrt(ax * ax + ay * ay);
    ax /= norm;
    ay /= norm;
    var lx = 0.0, ly = 0.0, rx = 0.0, ry = 0.0, ln = 0, rn = 0;
    for (var i = 0; i < n; i++) {
      if ((xs[i] - mx) * ax + (ys[i] - my) * ay < 0) {
        lx += xs[i];
        ly += ys[i];
        ln++;
      } else {
        rx += xs[i];
        ry += ys[i];
        rn++;
      }
    }
    final aX = lx / ln, aY = ly / ln, bX = rx / rn, bY = ry / rn;
    final span = math.sqrt((bX - aX) * (bX - aX) + (bY - aY) * (bY - aY));
    final alongX = (bX - aX) / span, alongY = (bY - aY) / span;
    var narrowest = 1 << 30;
    for (var t = 0.0; t <= span + 1e-9; t += 1) {
      narrowest = math.min(narrowest, _crossSection(aX + alongX * t, aY + alongY * t, -alongY, alongX));
    }
    return narrowest / pairScale;
  }

  double get tip {
    final row = mask[height ~/ 2];
    var last = -1;
    for (var c = 0; c < width ~/ 2; c++) {
      if (row[c]) last = c;
    }
    return xOf(last) + 0.5 / pairScale + gap / 2;
  }
}
