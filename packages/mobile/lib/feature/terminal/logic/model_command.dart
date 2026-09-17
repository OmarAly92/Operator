final RegExp _kModelCommand = RegExp(r'^/model(?:\s+(\S+))?\s*$');

class ModelCommand {
  const ModelCommand({this.label});

  final String? label;
}

ModelCommand? parseModelCommand(String text) {
  final match = _kModelCommand.firstMatch(text.trim());
  if (match == null) return null;
  return ModelCommand(label: match.group(1));
}
