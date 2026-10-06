import 'package:equatable/equatable.dart';

class SessionCommandResultModel extends Equatable {
  final String? state;
  final List<String>? models;
  final String? permissionMode;
  final bool? restarted;

  const SessionCommandResultModel({this.state, this.models, this.permissionMode, this.restarted});

  factory SessionCommandResultModel.fromJson(Map<String, dynamic> json) => SessionCommandResultModel(
    state: json['state'] as String?,
    models: (json['models'] as List?)?.map((e) => e as String).toList(),
    permissionMode: json['permissionMode'] as String?,
    restarted: json['restarted'] as bool?,
  );

  @override
  List<Object?> get props => [state, models, permissionMode, restarted];
}
