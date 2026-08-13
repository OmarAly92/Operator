import 'package:equatable/equatable.dart';

class InputChoice extends Equatable {
  const InputChoice({
    required this.value,
    required this.label,
    this.description,
  });

  final String value;
  final String label;
  final String? description;

  @override
  List<Object?> get props => [value, label, description];
}

abstract class ElicitationProperty {
  String? get type;
  String? get title;
  String? get description;
  dynamic get defaultValue;
  List<dynamic>? get enumValues;
  List<InputChoice>? get oneOf;
  List<InputChoice>? get itemsAnyOf;
  num? get minimum;
  num? get maximum;
  int? get minLength;
  int? get maxLength;
}

dynamic initialInputValue(ElicitationProperty property) {
  if (property.defaultValue != null) return property.defaultValue;
  if (property.type == 'array') return <dynamic>[];
  if (property.type == 'boolean') return false;
  return '';
}

List<InputChoice> inputOptions(ElicitationProperty property) {
  final candidates = property.oneOf ?? property.itemsAnyOf;
  if (candidates != null && candidates.isNotEmpty) return candidates;
  return (property.enumValues ?? const [])
      .whereType<String>()
      .map((value) => InputChoice(value: value, label: value))
      .toList();
}

List<String> toggleInputValue(List<dynamic> values, String value) {
  final strings = values.whereType<String>().toList();
  return strings.contains(value)
      ? strings.where((item) => item != value).toList()
      : [...strings, value];
}

List<String> missingRequiredInputs(
  List<String>? required,
  Map<String, dynamic> values,
) => (required ?? const []).where((name) {
  final value = values[name];
  return value == null || value == '' || (value is List && value.isEmpty);
}).toList();

String? validateInput(ElicitationProperty property, dynamic value) {
  if (value is String) {
    final minLength = property.minLength;
    final maxLength = property.maxLength;
    if (minLength != null && value.length < minLength) {
      return 'must be at least $minLength characters';
    }
    if (maxLength != null && value.length > maxLength) {
      return 'must be at most $maxLength characters';
    }
  }
  if ((property.type == 'number' || property.type == 'integer') &&
      value is num) {
    if (!value.isFinite) return 'must be a number';
    if (property.type == 'integer' && value != value.roundToDouble()) {
      return 'must be a whole number';
    }
    final minimum = property.minimum;
    final maximum = property.maximum;
    if (minimum != null && value < minimum) {
      return 'must be at least ${_number(minimum)}';
    }
    if (maximum != null && value > maximum) {
      return 'must be at most ${_number(maximum)}';
    }
  }
  return null;
}

String humanizeInputName(String value) {
  final spaced = value.replaceAll('_', ' ');
  return spaced.isEmpty
      ? spaced
      : spaced[0].toUpperCase() + spaced.substring(1);
}

Uri? safeHttpUrl(dynamic value) {
  if (value is! String) return null;
  final url = Uri.tryParse(value);
  if (url == null || !url.hasScheme || url.host.isEmpty) return null;
  return url.scheme == 'https' || url.scheme == 'http' ? url : null;
}

String _number(num value) =>
    value == value.roundToDouble() ? '${value.toInt()}' : '$value';
