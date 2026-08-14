import 'package:flutter/material.dart';
import 'package:operator_mobile/feature/chat/data/model/conversation_snapshot_model.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart';

class ConversationBanners extends StatelessWidget {
  const ConversationBanners({
    super.key,
    required this.snapshot,
    required this.resuming,
    required this.mcpReloading,
    required this.mcpReloadSupported,
    required this.onResume,
    required this.onReloadMcp,
    this.mcpError,
  });

  final ConversationSnapshotModel snapshot;
  final bool resuming;
  final bool mcpReloading;
  final bool mcpReloadSupported;
  final String? mcpError;
  final VoidCallback onResume;
  final VoidCallback onReloadMcp;

  @override
  Widget build(BuildContext context) {
    final thread = snapshot.threadState;
    final broken = snapshot.brokenMcpServers;
    final signIn = _signInCommand(snapshot.harness);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (snapshot.account?.reauthRequiredAt != null)
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.key_outlined,
            text:
                '${snapshot.account!.reauthReason ?? 'The provider rejected this session\'s credentials.'} '
                '${signIn != null ? 'Run “$signIn” on the Operator host, then try again.' : 'Sign in with the agent\'s CLI on the Operator host, then try again.'} '
                'Operator holds no credentials of its own. The worktree is untouched.',
          ),
        if (snapshot.controllerState == 'stopped')
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.power_settings_new,
            text:
                snapshot.controllerError ?? 'The agent controller is stopped.',
            action: resuming ? 'Resuming…' : 'Resume agent',
            onPressed: resuming ? null : onResume,
          ),
        if (snapshot.controllerState == 'recovering' ||
            snapshot.controllerState == 'connecting')
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.autorenew,
            text: snapshot.controllerState == 'recovering'
                ? 'Reconnecting to the agent…'
                : 'Starting the agent controller…',
          ),
        if (thread?.status == 'system_error')
          InlineBanner(
            tone: BannerTone.danger,
            icon: Icons.warning_amber_rounded,
            text:
                'The provider reports an internal fault in this thread; Operator\'s connection may still be healthy. '
                'The conversation and worktree are kept.'
                '${thread!.waitingOn.isEmpty ? '' : ' Waiting on: ${thread.waitingOn.join(', ')}.'}',
          )
        else if (thread?.status == 'closed')
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.warning_amber_rounded,
            text:
                'The provider closed this thread. Operator kept its history, but the agent no longer holds it.'
                '${thread!.waitingOn.isEmpty ? '' : ' Waiting on: ${thread.waitingOn.join(', ')}.'}',
          ),
        if (broken.isNotEmpty)
          InlineBanner(
            tone: BannerTone.warning,
            icon: Icons.build_outlined,
            text:
                '${broken.map((server) => mcpServerFailureLabel(name: server.name ?? 'MCP server', failureReason: server.failureReason, error: server.error)).join(', ')}'
                ' did not start. The agent has none of their tools and will not say so—it works around them silently.'
                '${mcpError == null ? '' : ' Reload failed: $mcpError'}',
            action: mcpReloadSupported && !snapshot.hasTurnInFlight
                ? mcpReloading
                      ? 'Reloading…'
                      : 'Reload'
                : null,
            onPressed: mcpReloading ? null : onReloadMcp,
          ),
      ],
    );
  }

  String? _signInCommand(String? harness) => switch (harness) {
    'codex' => 'codex login',
    'claude-code' || 'claude' => 'claude auth login',
    _ => null,
  };
}
