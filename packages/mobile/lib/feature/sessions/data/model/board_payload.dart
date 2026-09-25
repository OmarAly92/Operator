import 'package:equatable/equatable.dart';

class BoardPayload extends Equatable {
  const BoardPayload({required this.sessions, this.projects, this.accounts});

  final Map<String, dynamic> sessions;
  final Map<String, dynamic>? projects;
  final Map<String, dynamic>? accounts;

  @override
  List<Object?> get props => [sessions, projects, accounts];
}
