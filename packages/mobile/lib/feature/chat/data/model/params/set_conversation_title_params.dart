import 'package:equatable/equatable.dart';

class SetConversationTitleParams extends Equatable {
  final String title;

  const SetConversationTitleParams({required this.title});

  Map<String, dynamic> toJson() => {'title': title};

  @override
  List<Object?> get props => [title];
}
