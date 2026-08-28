import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/home_shell.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/helpers/result/result.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_empty_state.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_chrome.dart';
import 'package:operator_mobile/feature/chat/logic/conversation_errors.dart';
import 'package:operator_mobile/feature/chat/logic/timeline_model.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/logic/chat_cubit.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_composer.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_meta_bar.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/chat_settings_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_banners.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_map_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/conversation_menu_sheet.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/inline_banner.dart';
import 'package:operator_mobile/feature/chat/presentation/chat_screen/ui/widgets/live_turn_bar.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/terminal/data/model/params/open_session_shell_params.dart';
import 'package:operator_mobile/feature/terminal/data/repository/terminal_repository.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/interface_switch_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_overlay.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/ui/widgets/interface_switch_sheet.dart';

class ChatBody extends StatefulWidget {
  const ChatBody({super.key, this.projectId, this.previewUrl});

  final String? projectId;
  final String? previewUrl;

  @override
  State<ChatBody> createState() => ChatBodyState();
}

class ChatBodyState extends State<ChatBody> with WidgetsBindingObserver {
  bool _openingShell = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      context.read<ChatCubit>().onResumed();
    }
  }

  void openSettings() {
    final cubit = context.read<ChatCubit>();
    final snapshot = cubit.snapshot;
    if (snapshot == null) return;
    showChatSettingsSheet(
      context,
      snapshot: snapshot,
      models: cubit.models,
      options: cubit.configOptions,
      disabled:
          snapshot.controllerState == 'stopped' ||
          cubit.pendingActions.contains(ConversationAction.settings) ||
          cubit.pendingActions.contains(ConversationAction.config),
      error:
          cubit.actionErrors[ConversationAction.settings] ??
          cubit.actionErrors[ConversationAction.config],
      onSettings: cubit.chooseSettings,
      onOption: cubit.setConfigOption,
    );
  }

  Future<void> openMenu() async {
    final cubit = context.read<ChatCubit>();
    final snapshot = cubit.snapshot;
    if (snapshot == null) return;

    final result = await showConversationMenuSheet(
      context,
      snapshot: snapshot,
      compactSupported:
          snapshot.can('compaction') &&
          !conversationActionUnsupported(
            'compact',
            cubit.actionCodes[ConversationAction.compact],
          ),
      mcpReloadSupported:
          snapshot.can('mcp_reload') &&
          !conversationActionUnsupported(
            'mcp',
            cubit.actionCodes[ConversationAction.mcp],
          ),
      compacting: cubit.pendingActions.contains(ConversationAction.compact),
      mcpReloading: cubit.pendingActions.contains(ConversationAction.mcp),
      openingShell: _openingShell,
      interfaceSupported: context.read<InterfaceSwitchCubit>().supported,
    );
    if (!mounted || result == null) return;

    switch (result.action) {
      case ConversationMenuAction.map:
        await showConversationMapSheet(
          context,
          markers: conversationMarkers(snapshot),
        );
      case ConversationMenuAction.pullRequests:
        final projectId = widget.projectId;
        if (projectId != null) {
          sl<SessionsCubit>().setActiveProject(projectId);
        }
        HomeShell.selectedTab.value = 2;
        if (mounted) Navigator.of(context).pop();
      case ConversationMenuAction.settings:
        openSettings();
      case ConversationMenuAction.compact:
        await cubit.compact();
      case ConversationMenuAction.reloadMcp:
        await cubit.reloadMcp();
      case ConversationMenuAction.rename:
        final title = result.title;
        if (title != null) await cubit.rename(title);
      case ConversationMenuAction.worktreeShell:
        await _openShell();
      case ConversationMenuAction.terminalUi:
        await _switchToTerminal();
      case ConversationMenuAction.preview:
        Navigator.of(context).pushNamed(
          RoutesStrings.preview,
          arguments: {
            'sessionId': cubit.sessionId,
            'title': snapshot.title ?? 'Preview',
            'previewUrl': widget.previewUrl,
          },
        );
    }
  }

  Future<void> _openShell() async {
    final projectId = widget.projectId;
    final sessionId = context.read<ChatCubit>().sessionId;
    if (projectId == null) {
      context.showSnackBar(
        'This session has no project, so it has no worktree shell.',
      );
      return;
    }
    if (_openingShell) return;
    setState(() => _openingShell = true);
    final result = await sl<TerminalRepository>().openSessionShell(
      OpenSessionShellParams(projectId: projectId, sessionId: sessionId),
    );
    if (!mounted) return;
    setState(() => _openingShell = false);
    result.when(
      onSuccess: (response) {
        final shell = response.data;
        final handleId = shell?.handleId;
        if (handleId == null) {
          context.showSnackBar(
            'Could not open shell: the daemon returned no handle.',
          );
          return;
        }
        Navigator.of(context).pushNamed(
          RoutesStrings.terminal,
          arguments: {
            'args': TerminalArgs(
              id: handleId,
              sessionId: sessionId,
              projectId: projectId,
              title: shell?.title ?? 'Worktree shell',
              shellOnly: true,
            ),
          },
        );
      },
      onFailure: (failure) =>
          context.showSnackBar('Could not open shell: ${failure.message}'),
    );
  }

  Future<void> _switchToTerminal() async {
    final switchCubit = context.read<InterfaceSwitchCubit>();
    if (!switchCubit.supported) {
      context.showSnackBar(
        switchCubit.reason ??
            'This agent has not declared a compatible native conversation handoff.',
      );
      return;
    }
    final choice = await showInterfaceSwitchSheet(
      context,
      targetLabel: 'Terminal UI',
      waitingOnInput:
          context.read<ChatCubit>().snapshot?.hasTurnInFlight ?? false,
      sourceLabel: 'Chat',
    );
    if (choice == null || !mounted) return;
    await switchCubit.start(
      'tui',
      choice == InterfaceSwitchChoice.drain ? 'drain' : 'interrupt',
    );
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;

    return BlocBuilder<ChatCubit, ChatState>(
      buildWhen: (previous, current) =>
          current is ChatInitialState || current is ChatReadyState,
      builder: (context, state) {
        final cubit = context.read<ChatCubit>();
        final snapshot = cubit.snapshot;

        if (cubit.loading && snapshot == null) {
          return Center(child: CircularProgressIndicator(color: skin.blue));
        }

        final unavailable = cubit.unavailable;
        if (unavailable != null) {
          return AppEmptyState(
            icon: Icons.warning_amber_rounded,
            title: 'Conversation unavailable',
            message: '${unavailable.message}\n\nThe worktree is untouched.',
            action: PrimaryButton(
              text: _openingShell ? 'Opening…' : 'Open worktree shell',
              onPressed: _openingShell ? null : _openShell,
            ),
          );
        }

        if (snapshot == null) {
          return AppEmptyState(
            icon: Icons.warning_amber_rounded,
            title: 'Could not load conversation',
            message: cubit.error ?? 'The daemon did not return a conversation.',
            action: PrimaryButton(text: 'Retry', onPressed: cubit.refresh),
          );
        }

        final quota = quotaWarning(
          primaryUsedPercent: snapshot.rateLimits?.primaryUsedPercent,
          secondaryUsedPercent: snapshot.rateLimits?.secondaryUsedPercent,
          primaryResetsInSeconds: snapshot.rateLimits?.primaryResetsInSeconds,
          secondaryResetsInSeconds:
              snapshot.rateLimits?.secondaryResetsInSeconds,
          planLabel: snapshot.rateLimits?.planLabel,
        );
        final rolledBack = snapshot.turns
            .where((turn) => turn.rolledBack == true)
            .length;
        final compactSupported =
            snapshot.can('compaction') &&
            !conversationActionUnsupported(
              'compact',
              cubit.actionCodes[ConversationAction.compact],
            );
        final mcpReloadSupported =
            snapshot.can('mcp_reload') &&
            !conversationActionUnsupported(
              'mcp',
              cubit.actionCodes[ConversationAction.mcp],
            );
        final activeTurn = snapshot.activeTurn;

        return Stack(
          children: [
            Positioned.fill(
              child: Column(
                children: [
                  ChatMetaBar(
                    snapshot: snapshot,
                    refreshing: cubit.refreshing,
                    compacting: cubit.pendingActions.contains(
                      ConversationAction.compact,
                    ),
                    onRefresh: cubit.refresh,
                    onCompact: compactSupported ? cubit.compact : null,
                    compactDisabled:
                        snapshot.hasTurnInFlight ||
                        snapshot.controllerState == 'stopped' ||
                        cubit.pendingActions.contains(
                          ConversationAction.compact,
                        ),
                  ),
                  ConversationBanners(
                    snapshot: snapshot,
                    resuming: false,
                    mcpReloading: cubit.pendingActions.contains(
                      ConversationAction.mcp,
                    ),
                    mcpReloadSupported: mcpReloadSupported,
                    mcpError: cubit.actionErrors[ConversationAction.mcp],
                    onResume: cubit.resumeAgent,
                    onReloadMcp: cubit.reloadMcp,
                    onOpenShell: _openShell,
                  ),
                  if (cubit.error != null)
                    InlineBanner(
                      tone: BannerTone.danger,
                      icon: Icons.wifi_off,
                      text: cubit.error!,
                      action: 'Retry',
                      onPressed: cubit.refresh,
                    ),
                  if (quota != null)
                    InlineBanner(
                      tone: quota.severity == Severity.critical
                          ? BannerTone.danger
                          : BannerTone.warning,
                      icon: Icons.warning_amber_rounded,
                      text:
                          '${quota.percent}% of the'
                          '${quota.planLabel == null ? '' : ' ${quota.planLabel}'} account quota is used'
                          '${resetLabel(quota.resetsInSeconds) == null ? '' : '; resets in ${resetLabel(quota.resetsInSeconds)}'}. '
                          '${quota.severity == Severity.critical ? 'Turns may start failing for reasons unrelated to your request.' : 'Turns will stop when the limit is reached.'}',
                    ),
                  if (cubit.actionError != null)
                    InlineBanner(
                      tone: BannerTone.danger,
                      icon: Icons.error_outline,
                      text: cubit.actionError!,
                    ),
                  if (rolledBack > 0)
                    InlineBanner(
                      tone: BannerTone.muted,
                      icon: Icons.settings_backup_restore,
                      text:
                          '$rolledBack ${rolledBack == 1 ? 'turn was' : 'turns were'} rolled back. '
                          'The agent no longer remembers ${rolledBack == 1 ? 'it' : 'them'}.',
                    ),
                  for (final pending in cubit.pendingSends)
                    if (pending.failed)
                      InlineBanner(
                        tone: BannerTone.danger,
                        icon: Icons.send_outlined,
                        text:
                            'Message not sent: ${pending.error ?? 'Delivery failed'}',
                        action: 'Retry',
                        secondary: 'Discard',
                        onPressed: () => cubit.retrySend(pending.id),
                        onSecondary: () => cubit.discardSend(pending.id),
                      ),
                  const Expanded(child: SizedBox.shrink()),
                  if (activeTurn != null)
                    LiveTurnBar(
                      snapshot: snapshot,
                      startedAt: activeTurn.startedAt ?? activeTurn.requestedAt,
                      stopping: cubit.pendingActions.contains(
                        ConversationAction.interrupt,
                      ),
                      onInterrupt: cubit.interrupt,
                    ),
                  ChatComposer(
                    sessionId: cubit.sessionId,
                    snapshot: snapshot,
                    skills: cubit.skills,
                    filePaths: cubit.workspace.paths ?? const [],
                    filePathsTruncated: cubit.workspace.truncated ?? false,
                    configOptions: cubit.configOptions,
                    steerUnavailable: conversationActionUnsupported(
                      'steer',
                      cubit.actionCodes[ConversationAction.steer],
                    ),
                    pending: cubit.pendingSends.any(
                      (pending) => !pending.failed,
                    ),
                    error: cubit.actionErrors[ConversationAction.steer],
                    onSend: (text, {attachments, resources}) => cubit.send(
                      text,
                      attachments: attachments,
                      resources: resources,
                    ),
                    onSteer: cubit.steer,
                    onInterrupt: cubit.interrupt,
                    onOpenSettings: openSettings,
                  ),
                ],
              ),
            ),
            BlocBuilder<InterfaceSwitchCubit, InterfaceSwitchState>(
              buildWhen: (previous, current) =>
                  current is InterfaceSwitchReadyState,
              builder: (context, _) =>
                  context.read<InterfaceSwitchCubit>().active
                  ? const Positioned.fill(
                      child: InterfaceSwitchOverlay(
                        sourceLabel: 'chat',
                        targetLabel: 'Terminal UI',
                      ),
                    )
                  : const Positioned.fill(child: SizedBox.shrink()),
            ),
          ],
        );
      },
    );
  }
}
