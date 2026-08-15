import 'package:equatable/equatable.dart';

class StartInterfaceTransitionParams extends Equatable {
  final String targetMode;
  final String policy;

  const StartInterfaceTransitionParams({required this.targetMode, required this.policy});

  Map<String, dynamic> toJson() => {'targetMode': targetMode, 'policy': policy};

  @override
  List<Object?> get props => [targetMode, policy];
}
