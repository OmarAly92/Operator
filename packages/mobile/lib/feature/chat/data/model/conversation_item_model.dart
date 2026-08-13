import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';

sealed class ConversationItemModel extends Equatable {
  final String? id;
  final String? turnId;
  final int? sequence;
  final int? revision;
  final String? createdAt;

  const ConversationItemModel({
    this.id,
    this.turnId,
    this.sequence,
    this.revision,
    this.createdAt,
  });

  String get itemKey;
}

final class ConversationMessageModel extends ConversationItemModel {
  final String? role;
  final String? origin;
  final String? text;
  final bool? streaming;
  final String? delivery;
  final String? senderLabel;

  const ConversationMessageModel({
    super.id,
    super.turnId,
    super.sequence,
    super.revision,
    super.createdAt,
    this.role,
    this.origin,
    this.text,
    this.streaming,
    this.delivery,
    this.senderLabel,
  });

  factory ConversationMessageModel.fromJson(Map<String, dynamic> json) =>
      ConversationMessageModel(
        id: json['id'] as String?,
        turnId: json['turnId'] as String?,
        sequence: (json['sequence'] as num?)?.toInt(),
        revision: (json['revision'] as num?)?.toInt(),
        createdAt: json['createdAt'] as String?,
        role: json['role'] as String?,
        origin: json['origin'] as String?,
        text: json['text'] as String?,
        streaming: json['streaming'] as bool?,
        delivery: json['delivery'] as String?,
        senderLabel: json['senderLabel'] as String?,
      );

  @override
  String get itemKey => 'message:${id ?? ''}';

  @override
  List<Object?> get props => [
    id,
    turnId,
    sequence,
    revision,
    createdAt,
    role,
    origin,
    text,
    streaming,
    delivery,
    senderLabel,
  ];
}

final class ConversationActivityModel extends ConversationItemModel {
  final String? activityKind;
  final String? status;
  final String? summary;
  final ActivityDetailModel? detail;
  final String? requestId;
  final String? providerItemId;
  final List<DecisionOptionModel>? decisions;

  const ConversationActivityModel({
    super.id,
    super.turnId,
    super.sequence,
    super.revision,
    super.createdAt,
    this.activityKind,
    this.status,
    this.summary,
    this.detail,
    this.requestId,
    this.providerItemId,
    this.decisions,
  });

  factory ConversationActivityModel.fromJson(Map<String, dynamic> json) {
    final detail = json['detail'];
    final parsed = detail is Map<String, dynamic>
        ? ActivityDetailModel.fromJson(detail)
        : null;
    return ConversationActivityModel(
      id: json['id'] as String?,
      turnId: json['turnId'] as String?,
      sequence: (json['sequence'] as num?)?.toInt(),
      revision: (json['revision'] as num?)?.toInt(),
      createdAt: json['createdAt'] as String?,
      activityKind: json['activityKind'] as String?,
      status: json['status'] as String?,
      summary: json['summary'] as String?,
      detail: parsed,
      requestId: json['requestId'] as String?,
      providerItemId: json['providerItemId'] as String?,
      decisions: parsed?.decisions,
    );
  }

  bool get isPending => status == 'pending';

  @override
  String get itemKey => 'activity:${id ?? ''}';

  @override
  List<Object?> get props => [
    id,
    turnId,
    sequence,
    revision,
    createdAt,
    activityKind,
    status,
    summary,
    detail,
    requestId,
    providerItemId,
    decisions,
  ];
}
