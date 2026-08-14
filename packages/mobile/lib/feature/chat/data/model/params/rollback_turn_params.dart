import 'package:equatable/equatable.dart';

class RollbackTurnParams extends Equatable {
  final String turnId;

  const RollbackTurnParams({required this.turnId});

  Map<String, dynamic> toJson() => const {};

  @override
  List<Object?> get props => [turnId];
}
