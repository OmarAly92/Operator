import 'package:equatable/equatable.dart';

class WorkspacePathsModel extends Equatable {
  final List<String>? paths;
  final bool? truncated;

  const WorkspacePathsModel({this.paths = const [], this.truncated = false});

  factory WorkspacePathsModel.fromJson(Map<String, dynamic> json) =>
      WorkspacePathsModel(
        paths: (json['files'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .where(
              (file) => file['status'] != 'deleted' && file['path'] is String,
            )
            .map((file) => file['path'] as String)
            .toList(),
        truncated: json['truncated'] == true,
      );

  @override
  List<Object?> get props => [paths, truncated];
}
