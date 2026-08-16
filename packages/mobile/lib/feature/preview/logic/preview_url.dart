const Set<String> _loopbackHosts = {'localhost', '127.0.0.1', '::1', '[::1]'};

final RegExp _scheme = RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false);
final RegExp _readme = RegExp(r'^readme\.(md|markdown)$', caseSensitive: false);

String normalizePreviewHost(String host) =>
    host.trim().replaceFirst(_scheme, '').replaceAll(RegExp(r'/+$'), '');

/// Rewrites a host-loopback dev-server preview so the phone can reach it, without
/// ever forwarding Operator's connection password to it.
Uri? mobileReachablePreviewUrl(String? raw, String operatorHost) {
  if (raw == null || raw.trim().isEmpty) return null;
  final parsed = Uri.tryParse(raw.trim());
  if (parsed == null) return null;
  if (parsed.scheme != 'http' && parsed.scheme != 'https') return null;
  if (!_loopbackHosts.contains(parsed.host)) return parsed;

  final host = normalizePreviewHost(operatorHost);
  if (host.isEmpty) return null;
  return parsed.replace(
    host: host.contains(':') && !host.startsWith('[') ? '[$host]' : host,
  );
}

/// What counts as a live preview: anything the daemon surfaces EXCEPT a repo
/// README, which the detector's markdown fallback always matches on a fresh
/// checkout. Filtering it out keeps the globe's dot meaningful.
bool previewWorthShowing(String? entry) {
  final trimmed = entry?.trim() ?? '';
  if (trimmed.isEmpty) return false;
  return !_readme.hasMatch(trimmed.split('/').last);
}
