import 'package:equatable/equatable.dart';

class Replicated<T> extends Equatable {
  const Replicated({required this.value, required this.fetchedAt});

  final T value;
  final DateTime fetchedAt;

  @override
  List<Object?> get props => [value, fetchedAt];
}
