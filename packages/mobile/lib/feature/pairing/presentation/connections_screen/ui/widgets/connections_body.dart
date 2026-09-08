import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/saved_connection.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_form_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_menu_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connections_header.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/remove_connection_dialog.dart';

class ConnectionsBody extends StatelessWidget {
  const ConnectionsBody({super.key});

  Future<void> _openAddSheet(BuildContext context) async {
    final cubit = context.read<ConnectionsCubit>();
    final result = await showConnectionFormSheet(context);
    if (result == null) return;
    cubit.addConnection(name: result.name, address: result.address);
  }

  Future<void> _openEditSheet(BuildContext context, SavedConnection connection) async {
    final cubit = context.read<ConnectionsCubit>();
    final result = await showConnectionFormSheet(
      context,
      initialName: connection.name,
      initialAddress: connection.address,
    );
    if (result == null) return;
    cubit.updateConnection(connection.id, name: result.name, address: result.address);
  }

  Future<void> _openMenu(BuildContext context, SavedConnection connection) async {
    final cubit = context.read<ConnectionsCubit>();
    final action = await showConnectionMenuSheet(context, name: connection.name);
    if (!context.mounted || action == null) return;
    switch (action) {
      case ConnectionMenuAction.connect:
        cubit.connectTo(connection.id);
      case ConnectionMenuAction.edit:
        await _openEditSheet(context, connection);
      case ConnectionMenuAction.remove:
        final confirmed = await showRemoveConnectionDialog(context, name: connection.name);
        if (confirmed) cubit.removeConnection(connection.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<ConnectionsCubit>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            ConnectionsHeader(onAdd: () => _openAddSheet(context)),
            Expanded(
              child: BlocBuilder<ConnectionsCubit, ConnectionsState>(
                buildWhen: (previous, current) =>
                    current is ConnectionsInitialState ||
                    current is ConnectLoadingState ||
                    current is ConnectSuccessState ||
                    current is AddConnectionSuccessState ||
                    current is UpdateConnectionSuccessState ||
                    current is RemoveConnectionSuccessState,
                builder: (context, state) => SingleChildScrollView(
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
                        'Tap a desktop to connect. Saved pairings stay on this phone.',
                        style: AppTextStyle.style14Regular.copyWith(color: skin.textSecondary, height: 1.4),
                        maxLines: 2,
                      ),
                      const VerticalSpace(18),
                      if (cubit.connections.isNotEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: skin.bgSurface,
                            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                            border: Border.all(color: skin.borderDefault),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            children: [
                              for (var i = 0; i < cubit.connections.length; i++) ...[
                                if (i > 0) Divider(color: skin.borderSubtle, height: 1),
                                Builder(
                                  builder: (context) {
                                    final connection = cubit.connections[i];
                                    return ConnectionRow(
                                      name: connection.name,
                                      address: connection.address,
                                      lastConnectedLabel: connection.lastConnectedLabel,
                                      connecting: cubit.connectingId == connection.id,
                                      onTap: () => cubit.connectTo(connection.id),
                                      onMenuTap: () => _openMenu(context, connection),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      const VerticalSpace(20),
                      PrimaryButton(
                        text: 'Pair a new desktop',
                        textStyle: AppTextStyle.style16Medium.copyWith(color: skin.onAccent),
                        onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.pairingScan),
                      ),
                      _AddManuallyLink(onTap: () => _openAddSheet(context)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddManuallyLink extends StatelessWidget {
  const _AddManuallyLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return SizedBox(
      height: 44,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.edit, size: 16, color: skin.textTertiary),
              const HorizontalSpace(6),
              AppText('Add manually', style: AppTextStyle.style14SemiBold.copyWith(color: skin.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }
}
