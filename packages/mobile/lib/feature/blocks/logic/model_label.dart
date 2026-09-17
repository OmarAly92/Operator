final RegExp _kClaudeModelId = RegExp(r'^claude-([a-z]+)-(\d+)(?:-(\d+))?(?:-\d{8})?(?:\[(\w+)\])?$');

String formatModelLabel(String raw) {
  final id = raw.trim();
  if (id.isEmpty) return id;
  final match = _kClaudeModelId.firstMatch(id);
  if (match == null) return id;
  final family = match.group(1)!;
  final name = '${family[0].toUpperCase()}${family.substring(1)}';
  final version = match.group(3) == null ? match.group(2)! : '${match.group(2)}.${match.group(3)}';
  final suffix = match.group(4);
  return suffix == null ? '$name $version' : '$name $version (${suffix.toUpperCase()})';
}
