import 'package:equatable/equatable.dart';

class SendSessionMessageParams extends Equatable {
  final String message;

  const SendSessionMessageParams({required this.message});

  Map<String, dynamic> toJson() => {'message': message};

  @override
  List<Object?> get props => [message];
}
