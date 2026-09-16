import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/logic/relative_label.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connections_header.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/remove_connection_dialog.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/rename_desktop_sheet.dart';

class ConnectionsBody extends StatelessWidget {
  const ConnectionsBody({super.key});

  void _pairAnother(BuildContext context) {
    Navigator.of(context).pushNamed(RoutesStrings.onboarding, arguments: {'fromDesktops': true});
  }

  Future<void> _openMenu(BuildContext context, DesktopModel desktop) async {
    final cubit = context.read<ConnectionsCubit>();
    final id = desktop.id!;
    final title = desktop.name ?? desktop.address;
    final action = await showConnectionMenuSheet(context, name: title);
    if (!context.mounted || action == null) return;
    switch (action) {
      case ConnectionMenuAction.rename:
        final name = await showRenameDesktopSheet(context, initialName: title);
        if (name == null || name.isEmpty) return;
        await cubit.rename(id, name);
      case ConnectionMenuAction.remove:
        final confirmed = await showRemoveConnectionDialog(context, name: title);
        if (confirmed) await cubit.remove(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            ConnectionsHeader(onAdd: () => _pairAnother(context)),
            Expanded(
              child: BlocBuilder<ConnectionsCubit, ConnectionsState>(
                builder: (context, state) {
                  final cubit = context.read<ConnectionsCubit>();
                  final desktops = cubit.desktops;
                  final now = DateTime.now();
                  return SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppText(
                          'Your desktops',
                          style: AppTextStyle.style24BoldDisplay.copyWith(
                            color: skin.textPrimary,
                            letterSpacing: -0.4,
                          ),
                          maxLines: 2,
                        ),
                        const VerticalSpace(8),
                        AppText(
                          'Tap a desktop to connect.',
                          style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary, height: 1.4),
                          maxLines: 2,
                        ),
                        const VerticalSpace(18),
                        if (desktops.isNotEmpty)
                          Container(
                            decoration: BoxDecoration(
                              color: skin.bgSurface,
                              borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                              border: Border.all(color: skin.borderDefault),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Column(
                              children: [
                                for (var i = 0; i < desktops.length; i++) ...[
                                  if (i > 0) Divider(color: skin.borderSubtle, height: 1),
                                  Builder(
                                    builder: (context) {
                                      final d = desktops[i];
                                      final id = d.id!;
                                      final error = cubit.errors[id];
                                      return ConnectionRow(
                                        name: d.name ?? d.address,
                                        host: d.host ?? '',
                                        address: d.address,
                                        lastConnectedLabel: relativeLabel(d.lastConnectedAt, now),
                                        connecting: cubit.connectingId == id,
                                        active: d.isActive ?? false,
                                        activeDotKey: Key('active-dot-$id'),
                                        error: error,
                                        onScanAgain: error?.isAuth ?? false
                                            ? () => Navigator.of(context).pushNamed(
                                                RoutesStrings.pairingScan,
                                                arguments: {'fromOnboarding': true},
                                              )
                                            : null,
                                        onTap: () => cubit.connectTo(id, Theme.of(context).platform),
                                        onMenuTap: () => _openMenu(context, d),
                                      );
                                    },
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const VerticalSpace(20),
                        PrimaryButton(
                          text: 'Pair another desktop',
                          textStyle: AppTextStyle.style16Medium.copyWith(color: skin.onAccent),
                          onPressed: () => _pairAnother(context),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
