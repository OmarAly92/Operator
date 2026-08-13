import 'package:equatable/equatable.dart';

class OperatorSettingsModel extends Equatable {
  const OperatorSettingsModel({this.defaultSessionMode = 'chat', this.chatHarnesses = const []});

  final String defaultSessionMode;
  final List<String> chatHarnesses;

  factory OperatorSettingsModel.fromJson(Map<String, dynamic> json) => OperatorSettingsModel(
    defaultSessionMode: json['defaultSessionMode'] == 'tui' ? 'tui' : 'chat',
    chatHarnesses: (json['chatHarnesses'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
  );

  @override
  List<Object?> get props => [defaultSessionMode, chatHarnesses];
}
