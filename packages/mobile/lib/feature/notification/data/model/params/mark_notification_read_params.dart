import 'package:equatable/equatable.dart';

class MarkNotificationReadParams extends Equatable {
  const MarkNotificationReadParams();

  Map<String, dynamic> toJson() => {'status': 'read'};

  @override
  List<Object?> get props => [];
}
