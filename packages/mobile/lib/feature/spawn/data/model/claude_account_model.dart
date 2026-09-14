import 'package:equatable/equatable.dart';

class ClaudeAccountModel extends Equatable {
  const ClaudeAccountModel({this.id, this.label, this.isDefault, this.loggedIn, this.subscriptionType});

  final String? id;
  final String? label;
  final bool? isDefault;
  final bool? loggedIn;
  final String? subscriptionType;

  factory ClaudeAccountModel.fromJson(Map<String, dynamic> json) {
    final status = json['status'] is Map<String, dynamic> ? json['status'] as Map<String, dynamic> : const <String, dynamic>{};
    return ClaudeAccountModel(
      id: json['id'] as String?,
      label: json['label'] as String?,
      isDefault: json['isDefault'] as bool?,
      loggedIn: status['loggedIn'] as bool?,
      subscriptionType: status['subscriptionType'] as String?,
    );
  }

  static List<ClaudeAccountModel> listFromJson(Map<String, dynamic> json) {
    final raw = json['accounts'];
    if (raw is! List) return const [];
    return raw.whereType<Map<String, dynamic>>().map(ClaudeAccountModel.fromJson).toList();
  }

  String get planLabel {
    if (loggedIn == false) return 'Not logged in';
    if (loggedIn != true) return 'Unknown';
    return switch (subscriptionType) {
      'max' => 'Max',
      'pro' => 'Pro',
      null || '' => 'Unknown',
      final other => other,
    };
  }

  String get displayLabel => '${label ?? id ?? ''} · $planLabel';

  @override
  List<Object?> get props => [id, label, isDefault, loggedIn, subscriptionType];
}
