import 'package:equatable/equatable.dart';

class ProjectBranchModel extends Equatable {
  const ProjectBranchModel({this.name, this.checkedOutAt, this.isMainCheckout});

  final String? name;
  final String? checkedOutAt;
  final bool? isMainCheckout;

  factory ProjectBranchModel.fromJson(Map<String, dynamic> json) => ProjectBranchModel(
    name: json['name'] as String?,
    checkedOutAt: json['checkedOutAt'] as String?,
    isMainCheckout: json['isMainCheckout'] as bool?,
  );

  bool get isBusy => checkedOutAt != null && checkedOutAt!.isNotEmpty;

  @override
  List<Object?> get props => [name, checkedOutAt, isMainCheckout];
}
