import 'package:equatable/equatable.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';
import 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart'
    show groupConversationByTurn;

export 'package:operator_mobile/feature/blocks/logic/turn_grouping.dart'
    show ConversationGroup, groupConversationByTurn, readableConversationItems;

final RegExp _fence = RegExp(r'```[\s\S]*?```');
final RegExp _link = RegExp(r'\[([^\]]+)]\([^)]*\)');
final RegExp _marks = RegExp(r'[*_`#>~]+');
final RegExp _whitespaceRun = RegExp(r'\s+');

class ConversationMarker extends Equatable {
  const ConversationMarker({
    required this.key,
    required this.sequence,
    required this.title,
    this.detail,
    this.state,
  });

  final String key;
  final int sequence;
  final String title;
  final String? detail;
  final String? state;

  @override
  List<Object?> get props => [key, sequence, title, detail, state];
}

class ActivityNode {
  ActivityNode(this.activity);

  final ConversationActivityModel activity;
  final List<ActivityNode> children = [];
}

List<ConversationMarker> conversationMarkers(
  ConversationSnapshotModel snapshot,
) => groupConversationByTurn(snapshot).map((group) {
  ConversationMessageModel? human;
  ConversationMessageModel? assistant;
  ConversationActivityModel? activity;

  for (final item in group.items) {
    if (item is ConversationMessageModel &&
        item.role == 'user' &&
        item.origin == 'human') {
      human ??= item;
    }
    if (item is ConversationActivityModel) activity ??= item;
  }
  for (final item in group.items.reversed) {
    if (item is ConversationMessageModel &&
        item.role == 'assistant' &&
        (item.text?.trim().isNotEmpty ?? false)) {
      assistant = item;
      break;
    }
  }

  final title = _previewText(
    human?.text ??
        ((activity?.summary?.isNotEmpty ?? false)
            ? activity!.summary!
            : 'Conversation update'),
    120,
  );
  final detailSource = _firstTruthy([
    assistant?.text,
    activity?.detail?.text,
    activity?.summary,
  ]);
  final detail = detailSource == null ? null : _previewText(detailSource, 240);

  return ConversationMarker(
    key: group.key,
    sequence: group.anchor,
    title: title,
    detail: detail != null && detail.isNotEmpty && detail != title
        ? detail
        : null,
    state: group.turn?.state,
  );
}).toList();

bool canRollbackTurn(
  ConversationSnapshotModel snapshot,
  ConversationTurnModel turn,
) =>
    snapshot.can('rollback') &&
    !snapshot.hasTurnInFlight &&
    !turn.isInFlight &&
    (turn.providerTurnId?.isNotEmpty ?? false) &&
    turn.rolledBack != true;

bool activityStartsExpanded(ConversationActivityModel activity) {
  final detail = activity.detail;
  final liveBody =
      activity.status == 'running' &&
      (_isJavaScriptTruthy(detail?.output) ||
          _isJavaScriptTruthy(detail?.result) ||
          _isJavaScriptTruthy(detail?.raw['error']) ||
          _isJavaScriptTruthy(detail?.raw['patchOutput']));
  return activity.status == 'failed' || liveBody;
}

List<ActivityNode> activityHierarchy(
  List<ConversationActivityModel> activities,
) {
  final byProvider = <String, ActivityNode>{};
  final nodes = activities.map((activity) {
    final node = ActivityNode(activity);
    final providerItemId = activity.providerItemId;
    if (providerItemId != null && providerItemId.isNotEmpty) {
      byProvider[providerItemId] = node;
    }
    return node;
  }).toList();

  final roots = <ActivityNode>[];
  for (final node in nodes) {
    final parentId = node.activity.detail?.parentProviderItemId;
    final parent = parentId == null || parentId.isEmpty
        ? null
        : byProvider[parentId];
    if (parent != null && !_activityCycle(node, parent, byProvider)) {
      parent.children.add(node);
    } else {
      roots.add(node);
    }
  }
  return roots;
}

int countActivityNodes(List<ActivityNode> nodes) => nodes.fold(
  0,
  (count, node) => count + 1 + countActivityNodes(node.children),
);

bool activityNodesRunning(List<ActivityNode> nodes) => nodes.any(
  (node) =>
      node.activity.status == 'running' || activityNodesRunning(node.children),
);

bool _activityCycle(
  ActivityNode node,
  ActivityNode parent,
  Map<String, ActivityNode> byProvider,
) {
  final visited = <ActivityNode>{node};
  ActivityNode? current = parent;
  while (current != null) {
    if (visited.contains(current)) return true;
    visited.add(current);
    final parentId = current.activity.detail?.parentProviderItemId;
    current = parentId == null || parentId.isEmpty
        ? null
        : byProvider[parentId];
  }
  return false;
}

String _previewText(String value, int limit) {
  final plain = value
      .replaceAll(_fence, ' code sample ')
      .replaceAllMapped(_link, (match) => match.group(1)!)
      .replaceAll(_marks, ' ')
      .replaceAll(_whitespaceRun, ' ')
      .trim();
  return plain.length > limit
      ? '${plain.substring(0, limit - 1).trimRight()}…'
      : plain;
}

String? _firstTruthy(List<String?> values) {
  for (final value in values) {
    if (_isJavaScriptTruthy(value)) return value;
  }
  return null;
}

bool _isJavaScriptTruthy(dynamic value) {
  if (value == null || value == false) return false;
  if (value is String) return value.isNotEmpty;
  if (value is num) return value != 0 && !value.isNaN;
  return true;
}
