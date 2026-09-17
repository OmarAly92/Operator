import 'package:equatable/equatable.dart';

class SlashCommandModel extends Equatable {
  final String? name;
  final String? description;
  final String? source;
  final bool? interactive;

  const SlashCommandModel({this.name, this.description, this.source, this.interactive});

  factory SlashCommandModel.fromJson(Map<String, dynamic> json) => SlashCommandModel(
    name: json['name'] as String?,
    description: json['description'] as String?,
    source: json['source'] as String?,
    interactive: json['interactive'] as bool?,
  );

  static List<SlashCommandModel> listFromJson(Map<String, dynamic> json) =>
      (json['commands'] as List<dynamic>? ?? [])
          .map((item) => SlashCommandModel.fromJson(item as Map<String, dynamic>))
          .toList();

  @override
  List<Object?> get props => [name, description, source, interactive];
}
