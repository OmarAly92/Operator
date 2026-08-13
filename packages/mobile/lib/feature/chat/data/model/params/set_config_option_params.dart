import 'package:equatable/equatable.dart';

class SetConfigOptionParams extends Equatable {
  final String optionId;
  final String? value;
  final bool? enabled;

  const SetConfigOptionParams({
    required this.optionId,
    this.value,
    this.enabled,
  });

  Map<String, dynamic> toJson() =>
      enabled != null ? {'enabled': enabled} : {'value': value};

  @override
  List<Object?> get props => [optionId, value, enabled];
}
