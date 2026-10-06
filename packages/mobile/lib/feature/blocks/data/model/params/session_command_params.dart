import 'package:equatable/equatable.dart';

class SessionCommandParams extends Equatable {
  final String command;
  final String? model;
  final String? mode;

  const SessionCommandParams({required this.command, this.model, this.mode});

  Map<String, dynamic> toJson() => {
    'command': command,
    if (model != null) 'model': model,
    if (mode != null) 'mode': mode,
  };

  @override
  List<Object?> get props => [command, model, mode];
}
