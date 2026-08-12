String? activityString(dynamic raw) {
  if (raw is String) return raw.isEmpty ? null : raw;
  if (raw is Map<String, dynamic> && raw['state'] is String) {
    final state = raw['state'] as String;
    return state.isEmpty ? null : state;
  }
  return null;
}
