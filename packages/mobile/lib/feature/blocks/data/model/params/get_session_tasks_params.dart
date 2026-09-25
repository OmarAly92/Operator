import 'package:equatable/equatable.dart';

class GetSessionTasksParams extends Equatable {
  final String sessionId;

  const GetSessionTasksParams({required this.sessionId});

  @override
  List<Object?> get props => [sessionId];
}
