import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/logic/composer_suggestions.dart';

class ChatModelModel extends Equatable {
  final String? id;
  final String? displayName;
  final String? description;
  final bool? isDefault;
  final List<String>? efforts;
  final String? defaultEffort;

  const ChatModelModel({
    this.id = '',
    this.displayName = '',
    this.description,
    this.isDefault = false,
    this.efforts = const [],
    this.defaultEffort,
  });

  factory ChatModelModel.fromJson(Map<String, dynamic> json) => ChatModelModel(
    id: json['id'] as String? ?? '',
    displayName: json['displayName'] as String? ?? json['id'] as String? ?? '',
    description: json['description'] as String?,
    isDefault: json['default'] == true,
    efforts: (json['efforts'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    defaultEffort: json['defaultEffort'] as String?,
  );

  @override
  List<Object?> get props => [
    id,
    displayName,
    description,
    isDefault,
    efforts,
    defaultEffort,
  ];
}

class ChatConfigChoiceModel extends Equatable {
  final String? value;
  final String? name;
  final String? description;
  final String? group;
  final String? groupName;

  const ChatConfigChoiceModel({
    this.value = '',
    this.name = '',
    this.description,
    this.group,
    this.groupName,
  });

  factory ChatConfigChoiceModel.fromJson(Map<String, dynamic> json) =>
      ChatConfigChoiceModel(
        value: json['value'] as String? ?? '',
        name: json['name'] as String? ?? json['value'] as String? ?? '',
        description: json['description'] as String?,
        group: json['group'] as String?,
        groupName: json['groupName'] as String?,
      );

  @override
  List<Object?> get props => [value, name, description, group, groupName];
}

class ChatConfigOptionModel extends Equatable {
  final String? id;
  final String? name;
  final String? description;
  final String? category;
  final String? type;
  final String? currentValue;
  final bool? currentBoolean;
  final List<ChatConfigChoiceModel>? choices;

  const ChatConfigOptionModel({
    this.id = '',
    this.name = '',
    this.description,
    this.category,
    this.type = 'select',
    this.currentValue,
    this.currentBoolean,
    this.choices = const [],
  });

  factory ChatConfigOptionModel.fromJson(Map<String, dynamic> json) =>
      ChatConfigOptionModel(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? json['id'] as String? ?? '',
        description: json['description'] as String?,
        category: json['category'] as String?,
        type: json['type'] as String? ?? 'select',
        currentValue: json['currentValue'] as String?,
        currentBoolean: json['currentBoolean'] as bool?,
        choices: (json['choices'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ChatConfigChoiceModel.fromJson)
            .toList(),
      );

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    category,
    type,
    currentValue,
    currentBoolean,
    choices,
  ];
}

class ChatSkillModel extends Equatable implements SuggestibleSkill {
  @override
  final String name;
  @override
  final String displayName;
  @override
  final String? description;
  @override
  final String? inputHint;
  @override
  final String? source;

  const ChatSkillModel({
    required this.name,
    required this.displayName,
    this.description,
    this.inputHint,
    this.source,
  });

  factory ChatSkillModel.fromJson(Map<String, dynamic> json) => ChatSkillModel(
    name: json['name'] as String? ?? '',
    displayName:
        json['displayName'] as String? ?? json['name'] as String? ?? '',
    description: json['description'] as String?,
    inputHint: json['inputHint'] as String?,
    source: json['source'] as String?,
  );

  @override
  List<Object?> get props => [
    name,
    displayName,
    description,
    inputHint,
    source,
  ];
}
