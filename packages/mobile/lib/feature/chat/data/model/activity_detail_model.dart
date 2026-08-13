import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/logic/elicitation_model.dart';

const Set<String> _diffStatuses = {'added', 'modified', 'deleted', 'renamed'};

class DecisionOptionModel extends Equatable {
  final String? id;
  final String? label;

  const DecisionOptionModel({this.id, this.label});

  @override
  List<Object?> get props => [id, label];
}

class PlanStepModel extends Equatable {
  final String? text;
  final String? status;

  const PlanStepModel({this.text, this.status});

  factory PlanStepModel.fromJson(Map<String, dynamic> json) => PlanStepModel(
    text: json['text'] as String?,
    status: json['status'] as String?,
  );

  static List<PlanStepModel> listFrom(dynamic value) => value is List
      ? value
            .whereType<Map<String, dynamic>>()
            .map(PlanStepModel.fromJson)
            .toList()
      : const [];

  @override
  List<Object?> get props => [text, status];
}

class DiffFileModel extends Equatable {
  final String? path;
  final String? oldPath;
  final String? status;
  final int? additions;
  final int? deletions;
  final String? patch;
  final bool? patchTruncated;

  const DiffFileModel({
    this.path,
    this.oldPath,
    this.status,
    this.additions,
    this.deletions,
    this.patch,
    this.patchTruncated,
  });

  factory DiffFileModel.fromJson(Map<String, dynamic> json) {
    final status = json['status'];
    return DiffFileModel(
      path: json['path'] as String?,
      oldPath: json['oldPath'] as String?,
      status: status is String && _diffStatuses.contains(status)
          ? status
          : 'modified',
      additions: (json['additions'] as num?)?.toInt(),
      deletions: (json['deletions'] as num?)?.toInt(),
      patch: json['patch'] as String?,
      patchTruncated: json['patchTruncated'] as bool?,
    );
  }

  static List<DiffFileModel> listFrom(dynamic value) => value is List
      ? value
            .whereType<Map<String, dynamic>>()
            .where((file) => file['path'] is String)
            .map(DiffFileModel.fromJson)
            .toList()
      : const [];

  @override
  List<Object?> get props => [
    path,
    oldPath,
    status,
    additions,
    deletions,
    patch,
    patchTruncated,
  ];
}

class InputPropertyModel extends Equatable implements ElicitationProperty {
  @override
  final String? type;
  @override
  final String? title;
  @override
  final String? description;
  @override
  final dynamic defaultValue;
  @override
  final bool hasDefaultValue;
  @override
  final List<dynamic>? enumValues;
  @override
  final List<InputChoice>? oneOf;
  @override
  final List<InputChoice>? itemsAnyOf;
  @override
  final num? minimum;
  @override
  final num? maximum;
  @override
  final int? minLength;
  @override
  final int? maxLength;

  const InputPropertyModel({
    this.type,
    this.title,
    this.description,
    this.defaultValue,
    this.hasDefaultValue = false,
    this.enumValues,
    this.oneOf,
    this.itemsAnyOf,
    this.minimum,
    this.maximum,
    this.minLength,
    this.maxLength,
  });

  factory InputPropertyModel.fromJson(Map<String, dynamic> json) =>
      InputPropertyModel(
        type: json['type'] as String?,
        title: json['title'] as String?,
        description: json['description'] as String?,
        defaultValue: json['default'],
        hasDefaultValue: json.containsKey('default'),
        enumValues: json['enum'] as List<dynamic>?,
        oneOf: _choices(json['oneOf']),
        itemsAnyOf: _choices(
          (json['items'] as Map<String, dynamic>?)?['anyOf'],
        ),
        minimum: json['minimum'] as num?,
        maximum: json['maximum'] as num?,
        minLength: (json['minLength'] as num?)?.toInt(),
        maxLength: (json['maxLength'] as num?)?.toInt(),
      );

  static List<InputChoice>? _choices(dynamic value) {
    if (value is! List) return null;
    final choices = value
        .whereType<Map<String, dynamic>>()
        .where((candidate) => candidate['const'] is String)
        .map(
          (candidate) => InputChoice(
            value: candidate['const'] as String,
            label:
                candidate['title'] is String &&
                    (candidate['title'] as String).isNotEmpty
                ? candidate['title'] as String
                : candidate['const'] as String,
            description: candidate['description'] as String?,
          ),
        )
        .toList();
    return choices.isEmpty ? null : choices;
  }

  @override
  List<Object?> get props => [
    type,
    title,
    description,
    defaultValue,
    hasDefaultValue,
    enumValues,
    oneOf,
    itemsAnyOf,
    minimum,
    maximum,
    minLength,
    maxLength,
  ];
}

class InputSchemaModel extends Equatable {
  final String? title;
  final String? description;
  final List<String> required;
  final Map<String, InputPropertyModel> properties;

  const InputSchemaModel({
    this.title,
    this.description,
    this.required = const [],
    this.properties = const {},
  });

  factory InputSchemaModel.fromJson(
    Map<String, dynamic> json,
  ) => InputSchemaModel(
    title: json['title'] as String?,
    description: json['description'] as String?,
    required: (json['required'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(),
    properties: {
      for (final entry
          in (json['properties'] as Map<String, dynamic>? ?? const {}).entries)
        if (entry.value is Map<String, dynamic>)
          entry.key: InputPropertyModel.fromJson(
            entry.value as Map<String, dynamic>,
          ),
    },
  );

  @override
  List<Object?> get props => [title, description, required, properties];
}

class ActivityDetailModel extends Equatable {
  final Map<String, dynamic> raw;

  const ActivityDetailModel(this.raw);

  factory ActivityDetailModel.fromJson(Map<String, dynamic> json) =>
      ActivityDetailModel(json);

  String? get text => raw['text'] as String?;
  String? get command => raw['command'] as String?;
  String? get cwd => raw['cwd'] as String?;
  dynamic get output => raw['output'];
  String? get outputSource => raw['outputSource'] as String?;
  bool? get outputMayBePartial => raw['outputMayBePartial'] as bool?;
  bool? get outputTruncated => raw['outputTruncated'] as bool?;
  String? get reason => raw['reason'] as String?;
  String? get terminalInput => raw['terminalInput'] as String?;
  bool? get terminalInputTruncated => raw['terminalInputTruncated'] as bool?;
  String? get parentProviderItemId => raw['parentProviderItemId'] as String?;
  dynamic get files => raw['files'];
  String? get patchOutput => raw['patchOutput'] as String?;
  bool? get patchOutputTruncated => raw['patchOutputTruncated'] as bool?;
  String? get server => raw['server'] as String?;
  String? get toolName => raw['toolName'] as String?;
  String? get namespace => raw['namespace'] as String?;
  dynamic get arguments => raw['arguments'];
  dynamic get result => raw['result'];
  String? get error => raw['error'] as String?;
  bool? get success => raw['success'] as bool?;
  String? get progress => raw['progress'] as String?;
  bool? get progressTruncated => raw['progressTruncated'] as bool?;
  String? get riskLevel => raw['riskLevel'] as String?;
  String? get rationale => raw['rationale'] as String?;
  String? get decisionSource => raw['decisionSource'] as String?;
  String? get status => raw['status'] as String?;
  String? get host => raw['host'] as String?;
  String? get event => raw['event'] as String?;
  String? get fromModel => raw['fromModel'] as String?;
  String? get toModel => raw['toModel'] as String?;
  String? get explanation => raw['explanation'] as String?;
  List<PlanStepModel> get steps => PlanStepModel.listFrom(raw['steps']);
  int? get tokensAfter => (raw['tokensAfter'] as num?)?.toInt();
  int? get tokensReclaimed => (raw['tokensReclaimed'] as num?)?.toInt();
  int? get contextWindow => (raw['contextWindow'] as num?)?.toInt();
  String? get inputMode => raw['inputMode'] as String?;
  String? get message => raw['message'] as String?;
  String? get url => raw['url'] as String?;

  InputSchemaModel? get schema {
    final value = raw['schema'];
    return value is Map<String, dynamic>
        ? InputSchemaModel.fromJson(value)
        : null;
  }

  List<DecisionOptionModel>? get decisions {
    final value = raw['decisions'];
    if (value is! List) return null;
    final decisions = value
        .whereType<Map<String, dynamic>>()
        .where(
          (option) =>
              option['id'] is String && (option['id'] as String).isNotEmpty,
        )
        .map(
          (option) => DecisionOptionModel(
            id: option['id'] as String,
            label:
                option['label'] is String &&
                    (option['label'] as String).isNotEmpty
                ? option['label'] as String
                : option['id'] as String,
          ),
        )
        .toList();
    return decisions.isEmpty ? null : decisions;
  }

  @override
  List<Object?> get props => [raw];
}
