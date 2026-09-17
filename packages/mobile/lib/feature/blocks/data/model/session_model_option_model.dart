import 'package:equatable/equatable.dart';

class SessionModelOptionModel extends Equatable {
  final String? label;
  final String? description;
  final bool? current;

  const SessionModelOptionModel({this.label, this.description, this.current});

  factory SessionModelOptionModel.fromJson(Map<String, dynamic> json) => SessionModelOptionModel(
    label: json['label'] as String?,
    description: json['description'] as String?,
    current: json['current'] as bool?,
  );

  static List<SessionModelOptionModel> listFromJson(Map<String, dynamic> json) =>
      (json['models'] as List<dynamic>? ?? [])
          .map((item) => SessionModelOptionModel.fromJson(item as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [label, description, current];
}
