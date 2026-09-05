import 'package:equatable/equatable.dart';

class SessionCommandResultModel extends Equatable {
  final String? state;
  final List<String>? models;

  const SessionCommandResultModel({this.state, this.models});

  factory SessionCommandResultModel.fromJson(Map<String, dynamic> json) => SessionCommandResultModel(
    state: json['state'] as String?,
    models: (json['models'] as List?)?.map((e) => e as String).toList(),
  );

  @override
  List<Object?> get props => [state, models];
}
