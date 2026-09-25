import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/blocks/data/model/background_task_model.dart';

class StopSessionTaskResultModel extends Equatable {
  final BackgroundTaskModel? task;
  final bool? confirmed;

  const StopSessionTaskResultModel({this.task, this.confirmed});

  factory StopSessionTaskResultModel.fromJson(Map<String, dynamic> json) {
    final task = json['task'];
    return StopSessionTaskResultModel(
      task: task is Map<String, dynamic> ? BackgroundTaskModel.fromJson(task) : null,
      confirmed: json['confirmed'] as bool?,
    );
  }

  @override
  List<Object?> get props => [task, confirmed];
}
