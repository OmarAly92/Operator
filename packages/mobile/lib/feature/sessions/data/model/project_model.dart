import 'package:equatable/equatable.dart';

const Set<String> _knownKinds = {'single_repo', 'workspace', 'scratch'};

class ProjectModel extends Equatable {
  const ProjectModel({this.id, this.name, this.kind, this.sessionPrefix});

  final String? id;
  final String? name;
  final String? kind;
  final String? sessionPrefix;

  factory ProjectModel.fromJson(Map<String, dynamic> json) {
    final rawKind = json['kind'];
    return ProjectModel(
      id: json['id'] as String?,
      name: json['name'] as String?,
      kind: rawKind is String && _knownKinds.contains(rawKind) ? rawKind : null,
      sessionPrefix: json['sessionPrefix'] as String?,
    );
  }

  @override
  List<Object?> get props => [id, name, kind, sessionPrefix];
}
