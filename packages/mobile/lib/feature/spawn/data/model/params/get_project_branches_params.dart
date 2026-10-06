import 'package:equatable/equatable.dart';

class GetProjectBranchesParams extends Equatable {
  const GetProjectBranchesParams({required this.projectId});

  final String projectId;

  @override
  List<Object?> get props => [projectId];
}
