import 'dart:convert';

import 'package:operator_mobile/feature/blocks/logic/session_block.dart';
import 'package:operator_mobile/feature/chat/data/model/activity_detail_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_turn_model.dart';

class _SourceRow {
  _SourceRow({
    required this.item,
    required this.turnId,
    required this.sequence,
    required this.createdAt,
    required this.isRolledBack,
    required this.rolledBackTurnId,
    required this.rolledBackAt,
  });

  final ConversationItemModel item;
  final String? turnId;
  final int sequence;
  final String? createdAt;
  final bool isRolledBack;
  final String? rolledBackTurnId;
  final String? rolledBackAt;
}

class _CompactionInsertion {
  _CompactionInsertion({
    required this.compactedAt,
    required this.insertAfterSequence,
    required this.compactionSeq,
  });

  final String compactedAt;
  final int insertAfterSequence;
  final int compactionSeq;
}

List<SessionBlock> blocksFromConversation(ConversationSnapshotModel snapshot) {
  final rolledBackTurnIds = <String>{};
  final rolledBackAtByTurnId = <String, String>{};
  for (final turn in snapshot.turns) {
    if (turn.rolledBack == true) {
      rolledBackTurnIds.add(turn.id ?? '');
      if (turn.completedAt != null) {
        rolledBackAtByTurnId[turn.id ?? ''] = turn.completedAt!;
      } else if (turn.startedAt != null) {
        rolledBackAtByTurnId[turn.id ?? ''] = turn.startedAt!;
      } else if (turn.requestedAt != null) {
        rolledBackAtByTurnId[turn.id ?? ''] = turn.requestedAt!;
      }
    }
  }

  final activityById = <String, ConversationActivityModel>{};
  final rows = <_SourceRow>[];
  for (final item in snapshot.items) {
    final turnId = item.turnId;
    final isRolledBack = turnId != null && rolledBackTurnIds.contains(turnId);
    if (item is ConversationActivityModel && item.id != null) {
      activityById[item.id!] = item;
    }
    rows.add(
      _SourceRow(
        item: item,
        turnId: turnId,
        sequence: item.sequence ?? 0,
        createdAt: item.createdAt,
        isRolledBack: isRolledBack,
        rolledBackTurnId: isRolledBack ? turnId : null,
        rolledBackAt: isRolledBack ? rolledBackAtByTurnId[turnId] : null,
      ),
    );
  }

  final filteredRows = rows.where((row) => !row.isRolledBack).toList()
    ..sort((left, right) => left.sequence.compareTo(right.sequence));

  final rolledBackNotices = <_SourceRow>[];
  for (final turn in snapshot.turns) {
    if (turn.rolledBack != true) continue;
    final firstItem = snapshot.items.where((item) => item.turnId == turn.id).firstOrNull;
    rolledBackNotices.add(
      _SourceRow(
        item: firstItem ?? _syntheticItemForTurn(turn),
        turnId: turn.id,
        sequence: firstItem?.sequence ?? 0x7FFFFFFFFFFFFFFF,
        createdAt:
            rolledBackAtByTurnId[turn.id ?? ''] ??
            turn.requestedAt ??
            turn.startedAt,
        isRolledBack: false,
        rolledBackTurnId: turn.id,
        rolledBackAt: rolledBackAtByTurnId[turn.id ?? ''],
      ),
    );
  }

  final merged = <_SourceRow>[...filteredRows, ...rolledBackNotices]
    ..sort((left, right) => left.sequence.compareTo(right.sequence));

  final blocks = <SessionBlock>[];
  for (final row in merged) {
    if (row.rolledBackTurnId != null) {
      blocks.add(
        _buildRolledBackNotice(
          row.rolledBackTurnId!,
          row.rolledBackAt,
          row.createdAt,
          row.turnId,
        ),
      );
      continue;
    }
    blocks.add(_rowToBlock(row.item, row.turnId, row.createdAt, snapshot));
  }

  final insertion = _buildCompactionInsertion(snapshot, filteredRows);
  if (insertion == null) return _applyNesting(blocks, activityById);

  return _applyNesting(_insertCompaction(blocks, insertion), activityById);
}

SessionBlock _rowToBlock(
  ConversationItemModel item,
  String? turnId,
  String? createdAt,
  ConversationSnapshotModel snapshot,
) {
  if (item is ConversationMessageModel) {
    return _messageToBlock(item, turnId, createdAt);
  }
  if (item is ConversationActivityModel) {
    return _activityToBlock(item, turnId, createdAt, snapshot);
  }
  throw StateError('unknown item type: ${item.runtimeType}');
}

SessionBlock _messageToBlock(
  ConversationMessageModel message,
  String? turnId,
  String? createdAt,
) {
  if (message.role == 'user') {
    return SessionBlock(
      id: message.id ?? '',
      firstSeq: message.sequence ?? 0,
      lastSeq: message.sequence ?? 0,
      kind: BlockKind.prompt,
      status: BlockStatus.ok,
      turnId: turnId,
      title: 'Prompt',
      body: message.text ?? '',
      truncatedLines: 0,
      redacted: false,
      createdAt: createdAt,
    );
  }
  final status =
      message.streaming == true ? BlockStatus.running : BlockStatus.ok;
  return SessionBlock(
    id: message.id ?? '',
    firstSeq: message.sequence ?? 0,
    lastSeq: message.sequence ?? 0,
    kind: BlockKind.assistant,
    status: status,
    turnId: turnId,
    title: 'Assistant',
    body: message.text ?? '',
    truncatedLines: 0,
    redacted: false,
    createdAt: createdAt,
  );
}

SessionBlock _activityToBlock(
  ConversationActivityModel activity,
  String? turnId,
  String? createdAt,
  ConversationSnapshotModel snapshot,
) {
  final kind = activity.activityKind;
  final status = _mapActivityStatus(activity);
  final truncatedLines = _truncatedLinesFor(activity);

  switch (kind) {
    case 'reasoning':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.reasoning,
        status: status,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Reasoning',
        body: activity.detail?.text ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'command':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.tool,
        status: status,
        turnId: turnId,
        title: 'Shell',
        body: _commandBody(activity),
        detail: _buildShellDetail(activity),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'file_change':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.tool,
        status: status,
        turnId: turnId,
        title: 'File change',
        body: _fileChangeBody(activity),
        detail: _buildFileChangeDetail(activity),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'mcp_tool':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.tool,
        status: status,
        turnId: turnId,
        title: _mcpToolTitle(activity),
        body: _mcpToolBody(activity),
        detail: _buildMcpToolDetail(activity),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'plan':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.todo,
        status: status,
        turnId: turnId,
        title: 'Plan',
        body: _planBody(activity),
        detail: _buildPlanDetail(activity),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'approval':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.permission,
        status: _mapApprovalStatus(activity),
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Approval',
        body: activity.summary ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'user_input':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.permission,
        status: _mapUserInputStatus(activity),
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Input requested',
        body: activity.summary ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'auto_review':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.notice,
        status: BlockStatus.ok,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Notice',
        body: activity.summary ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'usage':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.notice,
        status: BlockStatus.ok,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Notice',
        body: '',
        detail: _buildUsageDetail(activity, snapshot),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'error':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.notice,
        status: BlockStatus.failed,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Notice',
        body: activity.summary ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    case 'system':
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.notice,
        status: status == BlockStatus.failed ? BlockStatus.failed : BlockStatus.ok,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Notice',
        body: activity.summary ?? '',
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );

    default:
      return SessionBlock(
        id: activity.id ?? '',
        firstSeq: activity.sequence ?? 0,
        lastSeq: activity.sequence ?? 0,
        kind: BlockKind.notice,
        status: BlockStatus.ok,
        turnId: turnId,
        title: (activity.summary != null && activity.summary!.isNotEmpty)
            ? activity.summary!
            : 'Notice',
        body: activity.summary ?? '',
        detail: UnknownBlockDetail(raw: activity.detail?.raw),
        truncatedLines: truncatedLines,
        redacted: false,
        createdAt: createdAt,
      );
  }
}

BlockStatus _mapActivityStatus(ConversationActivityModel activity) {
  final status = activity.status;
  if (status == 'running' || status == 'pending') return BlockStatus.running;
  if (status == 'failed' || status == 'cancelled') return BlockStatus.failed;
  return BlockStatus.ok;
}

BlockStatus _mapApprovalStatus(ConversationActivityModel activity) {
  final status = activity.status;
  if (status == 'resolved') return BlockStatus.ok;
  if (status == 'failed' || status == 'cancelled') return BlockStatus.failed;
  return BlockStatus.blocked;
}

BlockStatus _mapUserInputStatus(ConversationActivityModel activity) {
  final status = activity.status;
  if (status == 'resolved') return BlockStatus.ok;
  if (status == 'failed' || status == 'cancelled') return BlockStatus.failed;
  return BlockStatus.blocked;
}

int _truncatedLinesFor(ConversationActivityModel activity) {
  final detail = activity.detail;
  if (detail == null) return 0;
  if (detail.outputTruncated == true) return 1;
  if (detail.raw['textTruncated'] == true) return 1;
  return 0;
}

String _commandBody(ConversationActivityModel activity) {
  final output = activity.detail?.output;
  if (output == null) return '';
  return output.toString();
}

ShellBlockDetail _buildShellDetail(ConversationActivityModel activity) {
  final detail = activity.detail;
  return ShellBlockDetail(
    command: detail?.command,
    output: detail?.output == null ? null : detail!.output.toString(),
    exitCode: (detail?.raw['exitCode'] as num?)?.toInt(),
  );
}

String _fileChangeBody(ConversationActivityModel activity) {
  final files = activity.detail?.files;
  if (files is! List) return '';
  final objectFiles = files.whereType<Map<String, dynamic>>().toList();
  if (objectFiles.isEmpty) return '';
  return '${objectFiles.length} file${objectFiles.length == 1 ? '' : 's'} changed';
}

FileChangeBlockDetail _buildFileChangeDetail(ConversationActivityModel activity) {
  final detail = activity.detail;
  final files = detail?.files;
  List<BlockFileChange>? blockFiles;
  if (files is List) {
    blockFiles = files
        .whereType<Map<String, dynamic>>()
        .map((file) => BlockFileChange(
              path: file['path'] as String?,
              oldPath: file['oldPath'] as String?,
              status: file['status'] is String ? file['status'] as String : null,
              additions: (file['additions'] as num?)?.toInt(),
              deletions: (file['deletions'] as num?)?.toInt(),
            ))
        .toList();
  }
  final truncated = detail?.raw['patchOutputTruncated'] == true;
  return FileChangeBlockDetail(files: blockFiles, truncated: truncated);
}

String _mcpToolTitle(ConversationActivityModel activity) {
  final server = activity.detail?.server ?? '';
  final tool = activity.detail?.toolName ?? '';
  return '$server/$tool';
}

String _mcpToolBody(ConversationActivityModel activity) {
  final result = activity.detail?.result;
  if (result == null) return '';
  if (result is String) return result;
  try {
    return jsonEncode(result);
  } catch (_) {
    return result.toString();
  }
}

McpToolBlockDetail _buildMcpToolDetail(ConversationActivityModel activity) {
  final detail = activity.detail;
  return McpToolBlockDetail(
    server: detail?.server,
    tool: detail?.toolName,
    args: detail?.arguments,
    result: detail?.result == null
        ? null
        : (detail!.result is String
            ? detail.result as String
            : (() {
                try {
                  return jsonEncode(detail.result);
                } catch (_) {
                  return detail.result.toString();
                }
              })()),
  );
}

String _planBody(ConversationActivityModel activity) {
  final steps = activity.detail?.steps ?? const [];
  return '${steps.length} step${steps.length == 1 ? '' : 's'}';
}

PlanBlockDetail _buildPlanDetail(ConversationActivityModel activity) {
  final steps = activity.detail?.steps;
  return PlanBlockDetail(
    steps: steps
        ?.map((step) => BlockPlanStep(text: step.text, status: step.status))
        .toList(),
  );
}

UsageBlockDetail _buildUsageDetail(
  ConversationActivityModel activity,
  ConversationSnapshotModel snapshot,
) {
  final detail = activity.detail;
  final raw = detail?.raw;
  return UsageBlockDetail(
    contextUsed: snapshot.usage?.contextUsed,
    contextWindow: snapshot.usage?.contextWindow,
    inputTokens: (raw?['inputTokens'] as num?)?.toInt(),
    outputTokens: (raw?['outputTokens'] as num?)?.toInt(),
  );
}

_CompactionInsertion? _buildCompactionInsertion(
  ConversationSnapshotModel snapshot,
  List<_SourceRow> rows,
) {
  final compactedAt = snapshot.compactedAt;
  if (compactedAt == null || compactedAt.isEmpty) return null;

  var insertAfterSequence = -1;
  for (final row in rows) {
    if (row.createdAt != null && row.createdAt!.compareTo(compactedAt) <= 0) {
      insertAfterSequence = row.sequence;
    }
  }
  return _CompactionInsertion(
    compactedAt: compactedAt,
    insertAfterSequence: insertAfterSequence,
    compactionSeq: insertAfterSequence + 1,
  );
}

SessionBlock _buildCompactionBlock(
  String compactedAt,
  int compactionSeq,
) {
  return SessionBlock(
    id: 'compaction-1',
    firstSeq: compactionSeq,
    lastSeq: compactionSeq,
    kind: BlockKind.compaction,
    status: BlockStatus.ok,
    title: 'Compaction',
    body: '',
    detail: const CompactionBlockDetail(trigger: BlockCompactionTrigger.auto),
    truncatedLines: 0,
    redacted: false,
    createdAt: compactedAt,
  );
}

List<SessionBlock> _insertCompaction(
  List<SessionBlock> blocks,
  _CompactionInsertion insertion,
) {
  final result = <SessionBlock>[];
  for (final block in blocks) {
    if (block.firstSeq > insertion.insertAfterSequence) {
      result.add(_buildCompactionBlock(insertion.compactedAt, insertion.compactionSeq));
    }
    if (block.firstSeq > insertion.insertAfterSequence) {
      result.add(_shiftBlock(block, 1));
    } else {
      result.add(block);
    }
  }
  if (!blocks.any((b) => b.firstSeq > insertion.insertAfterSequence)) {
    result.add(_buildCompactionBlock(insertion.compactedAt, insertion.compactionSeq));
  }
  return result;
}

SessionBlock _shiftBlock(SessionBlock block, int delta) {
  return SessionBlock(
    id: block.id,
    firstSeq: block.firstSeq + delta,
    lastSeq: block.lastSeq + delta,
    kind: block.kind,
    status: block.status,
    turnId: block.turnId,
    title: block.title,
    body: block.body,
    detail: block.detail,
    toolName: block.toolName,
    errorType: block.errorType,
    truncatedLines: block.truncatedLines,
    redacted: block.redacted,
    createdAt: block.createdAt,
    children: block.children?.map((c) => _shiftBlock(c, delta)).toList(),
  );
}

List<SessionBlock> _applyNesting(
  List<SessionBlock> blocks,
  Map<String, ConversationActivityModel> activityById,
) {
  final blockByActivityId = <String, SessionBlock>{
    for (final block in blocks) block.id: block,
  };

  final mcpParentBlocks = <String, SessionBlock>{};
  for (final block in blocks) {
    final activity = activityById[block.id];
    if (activity == null) continue;
    if (activity.activityKind != 'mcp_tool') continue;
    if (activity.providerItemId != null && activity.providerItemId!.isNotEmpty) {
      mcpParentBlocks[activity.providerItemId!] = block;
    }
  }

  if (mcpParentBlocks.isEmpty) return blocks;

  final childIdsByParentId = <String, List<String>>{};
  for (final block in blocks) {
    final activity = activityById[block.id];
    if (activity == null) continue;
    final parentProviderItemId = activity.detail?.parentProviderItemId;
    if (parentProviderItemId == null || parentProviderItemId.isEmpty) continue;
    String? currentParent = parentProviderItemId;
    final visited = <String>{};
    while (currentParent != null) {
      if (visited.contains(currentParent)) break;
      visited.add(currentParent);
      final mcpParent = mcpParentBlocks[currentParent];
      if (mcpParent != null) {
        final list = childIdsByParentId[mcpParent.id] ?? <String>[];
        if (!list.contains(block.id)) list.add(block.id);
        childIdsByParentId[mcpParent.id] = list;
        break;
      }
      final childBlock = blockByActivityId[currentParent];
      if (childBlock == null) break;
      final childActivity = activityById[childBlock.id];
      if (childActivity == null) break;
      final next = childActivity.detail?.parentProviderItemId;
      if (next == null || next.isEmpty) break;
      currentParent = next;
    }
  }

  if (childIdsByParentId.isEmpty) return blocks;

  final flat = <SessionBlock>[];
  final emittedAsChild = <String>{};
  for (final block in blocks) {
    final childIds = childIdsByParentId[block.id];
    if (childIds == null) {
      if (!emittedAsChild.contains(block.id)) flat.add(block);
      continue;
    }
    final flattened = <SessionBlock>[];
    for (final childId in childIds) {
      final childBlock = blockByActivityId[childId];
      if (childBlock == null) continue;
      if (emittedAsChild.contains(childId)) continue;
      emittedAsChild.add(childId);
      flattened.add(childBlock);
    }
    final lastChildSeq = flattened.isNotEmpty ? flattened.last.lastSeq : block.lastSeq;
    flat.add(
      SessionBlock(
        id: block.id,
        firstSeq: block.firstSeq,
        lastSeq: lastChildSeq,
        kind: block.kind,
        status: block.status,
        turnId: block.turnId,
        title: block.title,
        body: block.body,
        detail: block.detail,
        toolName: block.toolName,
        errorType: block.errorType,
        truncatedLines: block.truncatedLines,
        redacted: block.redacted,
        createdAt: block.createdAt,
        children: flattened,
      ),
    );
  }

  return flat;
}

SessionBlock _buildRolledBackNotice(
  String turnId,
  String? rolledBackAt,
  String? createdAt,
  String? turnIdForBlock,
) {
  return SessionBlock(
    id: 'rolled-back-$turnId',
    firstSeq: 0x7FFFFFFFFFFFFFFF,
    lastSeq: 0x7FFFFFFFFFFFFFFF,
    kind: BlockKind.notice,
    status: BlockStatus.ok,
    turnId: turnIdForBlock,
    title: 'Rolled back',
    body: 'Rolled back: $turnId',
    truncatedLines: 0,
    redacted: false,
    createdAt: createdAt ?? rolledBackAt,
  );
}

ConversationItemModel _syntheticItemForTurn(ConversationTurnModel turn) {
  final timestamp = turn.startedAt ?? turn.requestedAt ?? turn.completedAt ?? '';
  return ConversationActivityModel(
    id: 'rolled-back-${turn.id}',
    turnId: turn.id,
    sequence: 0x7FFFFFFFFFFFFFFF,
    revision: 0,
    createdAt: timestamp,
    activityKind: 'system',
    status: 'completed',
    summary: '',
    detail: const ActivityDetailModel({}),
  );
}
