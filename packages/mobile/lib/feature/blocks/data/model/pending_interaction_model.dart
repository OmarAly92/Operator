import 'package:equatable/equatable.dart';

class PendingInteractionModel extends Equatable {
  final String? id;
  final String? kind;
  final String? toolName;
  final String? toolInput;
  final List<String>? lines;

  const PendingInteractionModel({this.id, this.kind, this.toolName, this.toolInput, this.lines});

  factory PendingInteractionModel.fromJson(Map<String, dynamic> json) => PendingInteractionModel(
    id: json['id'] as String?,
    kind: json['kind'] as String?,
    toolName: json['toolName'] as String?,
    toolInput: json['toolInput'] as String?,
    lines: (json['lines'] as List?)?.map((e) => e as String).toList(),
  );

  static List<PendingInteractionModel> listFromJson(Map<String, dynamic> json) =>
      (json['interactions'] as List<dynamic>? ?? [])
          .map((item) => PendingInteractionModel.fromJson(item as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [id, kind, toolName, toolInput, lines];
}
