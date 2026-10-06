import 'package:equatable/equatable.dart';

class MuxNotification extends Equatable {
  const MuxNotification({
    required this.id,
    required this.sessionId,
    required this.type,
    required this.title,
    required this.body,
    required this.quiet,
  });

  final String id;
  final String sessionId;
  final String type;
  final String title;
  final String body;
  final bool quiet;

  static MuxNotification? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    return MuxNotification(
      id: id,
      sessionId: raw['sessionId'] as String? ?? '',
      type: raw['type'] as String? ?? '',
      title: raw['title'] as String? ?? '',
      body: raw['body'] as String? ?? '',
      quiet: raw['quiet'] as bool? ?? false,
    );
  }

  @override
  List<Object?> get props => [id, sessionId, type, title, body, quiet];
}
