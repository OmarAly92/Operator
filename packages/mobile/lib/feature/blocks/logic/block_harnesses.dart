sealed class BlockHarnesses {
  static const Set<String> supported = {'claude-code', 'grok', 'codex'};

  static bool covers(String? harness) => harness != null && supported.contains(harness);
}
