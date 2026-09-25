import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/pairing/data/model/desktop_model.dart';
import 'package:operator_mobile/feature/pairing/logic/relative_label.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connection_row.dart';

Future<void> showDesktopSwitcherSheet(BuildContext context) => showAppSheet<void>(
  context: context,
  scope: (sheetContext, sheet) => BlocProvider<ConnectionsCubit>(create: (_) => sl<ConnectionsCubit>(), child: sheet),
  page: AppSheetPage(
    title: 'Desktops',
    subtitle: 'Choose the desktop this phone drives.',
    closeable: true,
    rows: (context, query) => const [DesktopSwitcherList()],
  ),
);

class DesktopSwitcherList extends StatelessWidget {
  const DesktopSwitcherList({super.key});

  static const Key pairKey = ValueKey('desktop-switcher-pair');
  static const Key manageKey = ValueKey('desktop-switcher-manage');

  void _leaveTo(BuildContext context, String route, {Object? arguments}) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed(route, arguments: arguments);
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocConsumer<ConnectionsCubit, ConnectionsState>(
      listener: (context, state) {
        if (state is ConnectSuccessState) {
          Haptics.success();
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
        if (state is ConnectFailureState) Haptics.error();
      },
      builder: (context, state) {
        final cubit = context.read<ConnectionsCubit>();
        final now = DateTime.now();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cubit.desktops.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  color: skin.bgElevated,
                  borderRadius: BorderRadius.circular(AppConstants.radiusCard),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < cubit.desktops.length; i++) ...[
                      if (i > 0) Divider(color: skin.borderSubtle, height: 1),
                      _row(context, cubit, cubit.desktops[i], now),
                    ],
                  ],
                ),
              ),
            const VerticalSpace(12),
            _SheetAction(
              key: pairKey,
              icon: Icons.add,
              label: 'Pair another desktop',
              onTap: () => _leaveTo(context, RoutesStrings.onboarding, arguments: {'fromDesktops': true}),
            ),
            _SheetAction(
              key: manageKey,
              icon: Icons.tune_rounded,
              label: 'Manage desktops',
              onTap: () => _leaveTo(context, RoutesStrings.connections),
            ),
          ],
        );
      },
    );
  }

  Widget _row(BuildContext context, ConnectionsCubit cubit, DesktopModel desktop, DateTime now) {
    final id = desktop.id!;
    final error = cubit.errors[id];
    final active = desktop.isActive ?? false;
    return ConnectionRow(
      name: desktop.name ?? desktop.address,
      host: desktop.host ?? '',
      address: desktop.address,
      lastConnectedLabel: relativeLabel(desktop.lastConnectedAt, now),
      connecting: cubit.connectingId == id,
      active: active,
      activeDotKey: Key('switcher-active-$id'),
      error: error,
      onScanAgain: error?.isAuth ?? false ? () => _leaveTo(context, RoutesStrings.pairingScan) : null,
      onTap: active ? () => Navigator.of(context).pop() : () => cubit.connectTo(id, Theme.of(context).platform),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction({super.key, required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return AppContainer(
      onTap: onTap,
      margin: const EdgeInsets.symmetric(vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      backgroundColor: Colors.transparent,
      child: Row(
        children: [
          Icon(icon, size: 18, color: skin.accentText),
          const HorizontalSpace(10),
          AppText(label, style: AppTextStyle.style15Medium.copyWith(color: skin.accentText)),
        ],
      ),
    );
  }
}
