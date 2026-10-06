import 'package:equatable/equatable.dart';

class StopSessionTaskParams extends Equatable {
  final String sessionId;
  final String taskId;

  const StopSessionTaskParams({required this.sessionId, required this.taskId});

  @override
  List<Object?> get props => [sessionId, taskId];
}
