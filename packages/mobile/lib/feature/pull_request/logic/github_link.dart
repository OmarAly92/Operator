final RegExp _githubUrl = RegExp(r'^https?://(?:www\.)?github\.com(/[^?#]*)?', caseSensitive: false);
final RegExp _numeric = RegExp(r'^\d+$');

const Set<String> _reservedRoots = {
  'settings', 'orgs', 'organizations', 'notifications', 'explore', 'marketplace', 'pulls',
  'issues', 'search', 'login', 'join', 'about', 'features', 'sponsors', 'apps', 'topics',
  'collections', 'trending', 'new', 'codespaces',
};

List<String>? _segments(String url) {
  final match = _githubUrl.firstMatch(url.trim());
  if (match == null) return null;
  return (match.group(1) ?? '').split('/').where((s) => s.isNotEmpty).toList();
}

String? githubAppUrl(String url) {
  final segments = _segments(url);
  if (segments == null || segments.length < 2) return null;
  final owner = segments.first;
  final repo = segments[1];
  final rest = segments.sublist(2);
  if (owner.startsWith('_') || _reservedRoots.contains(owner.toLowerCase())) return null;
  final base = 'github://repo/$owner/$repo';
  if (rest.isEmpty) return base;
  if (rest.length == 2 && (rest.first == 'pull' || rest.first == 'issues') && _numeric.hasMatch(rest[1])) {
    return '$base/${rest.first}/${rest[1]}';
  }
  return null;
}
