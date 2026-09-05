import 'package:equatable/equatable.dart';

class SessionCommandParams extends Equatable {
  final String command;
  final String? model;

  const SessionCommandParams({required this.command, this.model});

  Map<String, dynamic> toJson() => {
    'command': command,
    if (model != null) 'model': model,
  };

  @override
  List<Object?> get props => [command, model];
}
