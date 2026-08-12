const String kNormalLens = 'Back Camera';

const List<String> _qualifiers = [
  'ultra', 'telephoto', 'dual', 'triple', 'lidar', 'truedepth', 'continuity', 'desk',
];

String? pickNormalLens(List<String> lenses) {
  if (lenses.contains(kNormalLens)) return kNormalLens;

  final plain = lenses.where((lens) {
    final lower = lens.toLowerCase();
    return !_qualifiers.any(lower.contains);
  }).toList()
    ..sort((a, b) => a.length.compareTo(b.length));

  return plain.isEmpty ? null : plain.first;
}
