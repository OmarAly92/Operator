sealed class PickerFilter {
  static bool matches(String query, Iterable<String?> fields) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return true;
    return fields.any((field) => field != null && field.toLowerCase().contains(needle));
  }
}
