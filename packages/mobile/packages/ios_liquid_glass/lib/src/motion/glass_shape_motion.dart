import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

@internal
abstract interface class GlassShapeMotion implements Listenable {
  Rect resolve(RenderBox shape);
}
