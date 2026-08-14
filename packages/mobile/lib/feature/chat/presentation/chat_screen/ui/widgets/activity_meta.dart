import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/app_skin.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_item_model.dart';

const Set<String> _readCommands = {
  'cat',
  'sed',
  'nl',
  'head',
  'tail',
  'bat',
  'less',
  'more',
  'wc',
  'jq',
};
const Set<String> _searchCommands = {
  'rg',
  'grep',
  'find',
  'fd',
  'ls',
  'tree',
  'glob',
  'ag',
};

class ActivityMeta {
  const ActivityMeta({required this.icon, required this.color, this.prefix});

  final IconData icon;
  final String? prefix;
  final Color Function(AppSkin skin) color;
}

ActivityMeta activityMeta(ConversationActivityModel activity) {
  switch (activity.activityKind) {
    case 'command':
      return ActivityMeta(
        icon: Icons.terminal,
        color: (skin) =>
            activity.status == 'failed' ? skin.red : skin.textTertiary,
      );
    case 'file_change':
      return ActivityMeta(
        icon: Icons.edit_outlined,
        prefix: 'Changed',
        color: (skin) => skin.blue,
      );
    case 'mcp_tool':
      return ActivityMeta(
        icon: Icons.build_outlined,
        prefix: activity.detail?.server != null
            ? '${activity.detail!.server} ·'
            : 'MCP ·',
        color: (skin) => skin.purple,
      );
    case 'auto_review':
      return ActivityMeta(
        icon: Icons.shield_outlined,
        prefix: 'Reviewed',
        color: (skin) => skin.green,
      );
    default:
      return ActivityMeta(
        icon: Icons.bolt_outlined,
        color: (skin) => skin.textTertiary,
      );
  }
}

String summarizeActivities(List<ConversationActivityModel> activities) {
  var reads = 0;
  var searches = 0;
  var versionControl = 0;
  var commands = 0;
  var tools = 0;
  var reviews = 0;
  var plans = 0;

  for (final activity in activities) {
    switch (activity.activityKind) {
      case 'mcp_tool':
        tools++;
        continue;
      case 'auto_review':
        reviews++;
        continue;
      case 'plan':
        plans++;
        continue;
    }
    switch (_commandCategory(
      activity.detail?.command ?? activity.summary ?? '',
    )) {
      case 'read':
        reads++;
      case 'search':
        searches++;
      case 'vcs':
        versionControl++;
      default:
        commands++;
    }
  }

  final parts = <String>[
    if (reads > 0) '$reads ${reads == 1 ? 'file' : 'files'}',
    if (searches > 0) '$searches ${searches == 1 ? 'search' : 'searches'}',
    if (versionControl > 0)
      '$versionControl git ${versionControl == 1 ? 'check' : 'checks'}',
    if (commands > 0) '$commands ${commands == 1 ? 'command' : 'commands'}',
    if (tools > 0) '$tools tool ${tools == 1 ? 'call' : 'calls'}',
    if (reviews > 0) '$reviews auto-${reviews == 1 ? 'decision' : 'decisions'}',
    if (plans > 0) 'updated plan',
  ];

  final verb = reads > 0 || searches > 0 ? 'Explored' : 'Ran';
  return '$verb ${parts.isEmpty ? '${activities.length} steps' : parts.join(', ')}';
}

String _commandCategory(String text) {
  final head = text.trim().split(RegExp(r'\s+')).first;
  final binary = head.substring(head.lastIndexOf('/') + 1);
  if (_readCommands.contains(binary)) return 'read';
  if (_searchCommands.contains(binary)) return 'search';
  if (binary == 'git' || binary == 'gh') return 'vcs';
  return 'run';
}
