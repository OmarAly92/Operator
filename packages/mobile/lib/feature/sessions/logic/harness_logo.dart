enum BackdropPolarity { neutral, needsDark, needsLight }

const Set<String> kLogoKeys = {
  'agy', 'aider', 'amp', 'auggie', 'autohand', 'claude-code', 'cline', 'codex',
  'continue', 'copilot', 'crush', 'cursor', 'devin', 'droid', 'goose', 'grok',
  'kilocode', 'kimi', 'kiro', 'muse', 'opencode', 'pi', 'qwen', 'vibe',
};

String logoKey(String? harness) => harness?.trim().toLowerCase() ?? '';

bool hasLogo(String? harness) => kLogoKeys.contains(logoKey(harness));

const Set<String> _needsDarkBackdrop = {'opencode', 'cursor', 'cline', 'continue', 'grok', 'copilot'};
const Set<String> _needsLightBackdrop = {'kilocode', 'goose', 'devin', 'droid', 'pi', 'kimi'};

BackdropPolarity backdropFor(String? harness) {
  final key = logoKey(harness);
  if (key.isEmpty) return BackdropPolarity.neutral;
  if (_needsDarkBackdrop.contains(key)) return BackdropPolarity.needsDark;
  if (_needsLightBackdrop.contains(key)) return BackdropPolarity.needsLight;
  return BackdropPolarity.neutral;
}

String harnessInitial(String? harness) {
  final key = harness?.trim();
  if (key == null || key.isEmpty) return '?';
  return key[0].toUpperCase();
}
