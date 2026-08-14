import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/terminal/data/model/interface_transition_model.dart';

class InterfaceTransitionStatusModel extends Equatable {
  final bool? supported;
  final String? targetMode;
  final String? reasonCode;
  final String? reason;
  final InterfaceTransitionModel? transition;

  const InterfaceTransitionStatusModel({
    this.supported,
    this.targetMode,
    this.reasonCode,
    this.reason,
    this.transition,
  });

  factory InterfaceTransitionStatusModel.fromJson(Map<String, dynamic> json) {
    final transition = json['transition'];
    return InterfaceTransitionStatusModel(
      supported: json['supported'] as bool?,
      targetMode: json['targetMode'] as String?,
      reasonCode: json['reasonCode'] as String?,
      reason: json['reason'] as String?,
      transition: transition is Map<String, dynamic>
          ? InterfaceTransitionModel.fromJson(transition)
          : null,
    );
  }

  @override
  List<Object?> get props => [supported, targetMode, reasonCode, reason, transition];
}
