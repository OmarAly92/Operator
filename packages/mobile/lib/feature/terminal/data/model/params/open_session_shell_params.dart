import 'package:equatable/equatable.dart';

class OpenSessionShellParams extends Equatable {
  final String projectId;
  final String sessionId;

  const OpenSessionShellParams({required this.projectId, required this.sessionId});

  Map<String, dynamic> toJson() => {'projectId': projectId, 'sessionId': sessionId};

  @override
  List<Object?> get props => [projectId, sessionId];
}
