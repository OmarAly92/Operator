const int _maxLabel = 20;

String shortLabel(String value, {int max = _maxLabel}) {
  if (value.length <= max) return value;
  final keep = max - 1;
  final head = (keep / 2).ceil();
  final tail = (keep / 2).floor();
  return '${value.substring(0, head)}…${value.substring(value.length - tail)}';
}
