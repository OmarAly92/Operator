import 'package:equatable/equatable.dart';

class StagedAttachmentsModel extends Equatable {
  const StagedAttachmentsModel({this.sessionId, this.paths});

  final String? sessionId;
  final List<String>? paths;

  factory StagedAttachmentsModel.fromJson(Map<String, dynamic> json) => StagedAttachmentsModel(
    sessionId: json['sessionId'] as String?,
    paths: (json['paths'] as List<dynamic>?)?.whereType<String>().toList(),
  );

  @override
  List<Object?> get props => [sessionId, paths];
}
