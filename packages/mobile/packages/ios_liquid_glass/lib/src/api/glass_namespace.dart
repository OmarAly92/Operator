import 'package:flutter/foundation.dart';

class GlassNamespace {
  GlassNamespace();
}

@immutable
class GlassEffectUnion {
  const GlassEffectUnion(this.id, this.namespace);

  final Object id;
  final GlassNamespace namespace;

  @override
  bool operator ==(Object other) => other is GlassEffectUnion && other.id == id && identical(other.namespace, namespace);

  @override
  int get hashCode => Object.hash(id, identityHashCode(namespace));
}
