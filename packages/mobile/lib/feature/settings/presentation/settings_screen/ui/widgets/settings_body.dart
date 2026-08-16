import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/api/server_config_store.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/dark_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/light_skin.dart';
import 'package:operator_mobile/core/app_themes/colors/logic/skin_cubit.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/colors/theme_preference.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/utils/app_info.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/dialog/app_dialog.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/pickers/project_picker_sheet.dart';
import 'package:operator_mobile/core/widgets/pickers/theme_picker_sheet.dart';
import 'package:operator_mobile/feature/notification/logic/push_registrar.dart';
import 'package:operator_mobile/feature/notification/logic/push_status.dart';
import 'package:operator_mobile/feature/pull_request/logic/open_github.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_cubit.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/settings_state.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsBody extends StatefulWidget {
  const SettingsBody({super.key, required this.onOpenBoard});

  final VoidCallback onOpenBoard;

  @override
  State<SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<SettingsBody> {
  BuildInfo _buildInfo = const BuildInfo();
  PushStatus? _pushStatus;
  bool _pushBusy = false;

  @override
  void initState() {
    super.initState();
    _loadBuildInfo();
    _refreshPushStatus();
  }

  Future<void> _loadBuildInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _buildInfo = BuildInfo(version: info.version, build: info.buildNumber));
  }

  Future<void> _refreshPushStatus() async {
    final status = await sl<PushRegistrar>().status();
    if (!mounted) return;
    setState(() => _pushStatus = status);
  }

  Future<void> _togglePush(BuildContext context, bool next) async {
    final toggle = describePushToggle(_pushStatus, sl<ServerConfigStore>().current);
    if (toggle.blocked) {
      final open = await AppDialog.confirm(
        context,
        title: 'Notifications are blocked',
        message: 'Allow notifications for Operator in your system settings, then come back.',
        confirmLabel: 'Open settings',
        cancelLabel: 'Not now',
      );
      if (open) await openAppSettings();
      return;
    }

    setState(() => _pushBusy = true);
    final registrar = sl<PushRegistrar>();
    PushRegisterResult? result;
    if (!next) {
      await registrar.unregister();
      Haptics.tap();
    } else {
      result = await registrar.register(sl<ServerConfigStore>().current, ask: true);
      if (result is PushRegistered) {
        Haptics.success();
      } else {
        Haptics.error();
      }
    }
    if (!mounted) return;
    setState(() => _pushBusy = false);

    if (result is PushNotRegistered && context.mounted) {
      final described = describeRegisterFailure(
        result.reason,
        Theme.of(context).platform,
        statusCode: result.statusCode,
      );
      await AppDialog.confirm(
        context,
        title: described.title,
        message: described.message,
        confirmLabel: 'OK',
        cancelLabel: 'Close',
      );
    }
    await _refreshPushStatus();
  }

  Future<void> _openConnection(BuildContext context) async {
    await Navigator.of(context).pushNamed(RoutesStrings.pairingScan);
    if (mounted) setState(() {});
  }

  Future<void> _openProjectPicker(BuildContext context, SessionsCubit sessionsCubit) async {
    final selected = await showProjectPickerSheet(
      context,
      projects: sessionsCubit.projects,
      selected: sessionsCubit.activeProjectId,
    );
    if (selected == null || !context.mounted) return;
    sessionsCubit.setActiveProject(selected);
    widget.onOpenBoard();
  }

  Future<void> _openThemePicker(BuildContext context, SkinCubit skinCubit) async {
    final selected = await showThemePickerSheet(context, selected: skinCubit.skin.themeMode);
    if (selected == null) return;
    switch (selected) {
      case ThemeMode.system:
        skinCubit.setSystemSkin();
      case ThemeMode.light:
        skinCubit.setSkin(const LightSkin());
      case ThemeMode.dark:
        skinCubit.setSkin(const DarkSkin());
    }
  }

  void _reportProblem(BuildContext context) {
    final platform = Platform.operatingSystem;
    final osVersion = Platform.operatingSystemVersion;
    final body = bugReportBody(_buildInfo, platform, osVersion);
    final url = 'https://github.com/OmarAly92/operator/issues/new?body=${Uri.encodeComponent(body)}';
    openGitHub(url);
  }

  Future<void> _disconnect(BuildContext context) async {
    final confirmed = await AppDialog.confirm(
      context,
      title: 'Disconnect & forget server?',
      message: 'This clears the saved connection. You can pair again with a new QR code any time.',
      confirmLabel: 'Disconnect',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    await context.read<SettingsCubit>().forget();
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final sessionsCubit = context.watch<SessionsCubit>();
    final skinCubit = context.watch<SkinCubit>();
    final config = sl<ServerConfigStore>().current;

    return BlocConsumer<SettingsCubit, SettingsState>(
      listener: (context, state) {
        if (state is PingSuccessState) {
          Haptics.success();
        }
        if (state is PingFailureState) {
          Haptics.error();
        }
        if (state is ForgetSuccessState) {
          Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.onboarding, (_) => false);
        }
      },
      builder: (context, state) {
        String? testValue;
        Color? testValueColor;
        if (state is PingSuccessState) {
          final count = state.sessionCount;
          testValue = 'Connected — $count session${count == 1 ? '' : 's'}';
          testValueColor = skin.green;
        } else if (state is PingFailureState) {
          testValue = describeConnectionFailure(
            classifyConnectionFailure(state.failure.statusCode),
            host: config?.host ?? '',
            port: config?.httpPort ?? '',
            platform: Theme.of(context).platform,
          ).title;
          testValueColor = skin.red;
        }

        var activeProjectName = 'All projects';
        if (sessionsCubit.activeProjectId != kAllProjects) {
          for (final project in sessionsCubit.projects) {
            if (project.id == sessionsCubit.activeProjectId) {
              activeProjectName = project.name ?? project.id ?? 'All projects';
              break;
            }
          }
        }

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          children: [
            SettingsGroup(
              footer: "Your PC's Tailscale name / 100.x address, or its LAN IP on the same Wi-Fi.",
              children: [
                SettingsRow(
                  icon: Icons.dns_outlined,
                  label: 'Connect Operator',
                  value: config != null ? '${config.host}:${config.httpPort}' : 'Not connected',
                  leading: config != null
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(color: skin.green, shape: BoxShape.circle),
                        )
                      : null,
                  onTap: () => _openConnection(context),
                ),
                SettingsRow(
                  icon: Icons.wifi_tethering,
                  label: 'Test connection',
                  value: testValue,
                  valueColor: testValueColor,
                  loading: state is PingLoadingState,
                  disabled: config == null,
                  onTap: () => context.read<SettingsCubit>().testConnection(),
                ),
              ],
            ),
            const VerticalSpace(20),
            SettingsGroup(
              title: 'Projects',
              footer: 'Scopes the Agents and PRs tabs.',
              children: [
                SettingsRow(
                  icon: Icons.folder_outlined,
                  label: 'Active project',
                  value: activeProjectName,
                  onTap: () => _openProjectPicker(context, sessionsCubit),
                ),
              ],
            ),
            const VerticalSpace(20),
            SettingsGroup(
              children: [
                SettingsRow(
                  icon: Icons.palette_outlined,
                  label: 'Theme',
                  value: preferenceLabel(skinCubit.skin.themeMode),
                  onTap: () => _openThemePicker(context, skinCubit),
                ),
              ],
            ),
            const VerticalSpace(20),
            Builder(
              builder: (context) {
                final toggle = describePushToggle(_pushStatus, config);
                return SettingsGroup(
                  title: 'Notifications',
                  footer: toggle.footer,
                  children: [
                    SettingsToggle(
                      icon: Icons.notifications_none,
                      label: 'Agent notifications',
                      value: toggle.value,
                      disabled: toggle.disabled,
                      busy: _pushBusy,
                      onChanged: (next) => _togglePush(context, next),
                    ),
                    SettingsRow(
                      icon: Icons.history,
                      label: 'History',
                      onTap: () =>
                          Navigator.of(context).pushNamed(RoutesStrings.notifications),
                    ),
                  ],
                );
              },
            ),
            const VerticalSpace(20),
            SettingsGroup(
              children: [
                SettingsRow(icon: Icons.info_outline, label: 'Version', value: formatVersion(_buildInfo)),
                SettingsRow(
                  icon: Icons.bug_report_outlined,
                  label: 'Report a problem',
                  onTap: () => _reportProblem(context),
                ),
                SettingsRow(
                  icon: Icons.link_off,
                  label: 'Disconnect & forget server',
                  destructive: true,
                  onTap: () => _disconnect(context),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
