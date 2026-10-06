import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/spawn/data/model/project_branch_model.dart';

class ProjectBranchesModel extends Equatable {
  const ProjectBranchesModel({this.current, this.branches});

  final String? current;
  final List<ProjectBranchModel>? branches;

  factory ProjectBranchesModel.fromJson(Map<String, dynamic> json) {
    final raw = json['branches'];
    return ProjectBranchesModel(
      current: json['current'] as String?,
      branches: raw is List
          ? raw.whereType<Map<String, dynamic>>().map(ProjectBranchModel.fromJson).toList()
          : null,
    );
  }

  @override
  List<Object?> get props => [current, branches];
}
