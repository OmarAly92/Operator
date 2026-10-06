import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/utils/app_constants.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_container.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/core/widgets/sheet/app_sheet.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

Future<void> showRePairSheet(BuildContext context) {
  final name = context.read<ConnectionCubit>().state.desktopName ?? 'your desktop';
  return showAppSheet<void>(
    context: context,
    scope: (sheetContext, sheet) => BlocProvider<ManualConnectCubit>(
      create: (_) => sl<ManualConnectCubit>(param1: ManualConnectMode.rePair),
      child: sheet,
    ),
    page: AppSheetPage(
      title: 'Re-pair $name',
      subtitle: 'Your desktop changed its password. Enter the new one from Settings › Connect Mobile, '
          'or scan the code again.',
      closeable: true,
      rows: (context, query) => const [RePairForm()],
    ),
  );
}

class RePairForm extends StatelessWidget {
  const RePairForm({super.key});

  static const Key hostKey = ValueKey('re-pair-host');
  static const Key reconnectKey = ValueKey('re-pair-reconnect');
  static const Key scanKey = ValueKey('re-pair-scan');

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final cubit = context.read<ManualConnectCubit>();
    return BlocListener<ManualConnectCubit, ManualConnectState>(
      listener: (context, state) {
        if (state is ConnectSuccessState) {
          Haptics.success();
          Navigator.of(context).pop();
        }
        if (state is ConnectFailureState) Haptics.warning();
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppContainer(
            key: hostKey,
            backgroundColor: skin.bgElevated,
            borderRadius: BorderRadius.circular(AppConstants.radiusCard),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.computer, size: 18, color: skin.textSecondary),
                const HorizontalSpace(10),
                Expanded(
                  child: AppText(
                    cubit.hostController.text,
                    style: AppTextStyle.mono12Regular.copyWith(color: skin.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const VerticalSpace(14),
          AppTextField(controller: cubit.passwordController, label: 'PASSWORD', obscureText: true),
          const VerticalSpace(14),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is ConnectFailureState || current is ConnectLoadingState,
            builder: (context, state) => state is ConnectFailureState
                ? Padding(padding: const EdgeInsets.only(bottom: 14), child: ConnectionFailureBanner(copy: state.copy))
                : const SizedBox.shrink(),
          ),
          BlocBuilder<ManualConnectCubit, ManualConnectState>(
            buildWhen: (previous, current) => current is ConnectLoadingState || current is ConnectFailureState,
            builder: (context, state) => PrimaryButton.expand(
              key: reconnectKey,
              text: 'Reconnect',
              isLoading: state is ConnectLoadingState,
              onPressed: () => cubit.connect(Theme.of(context).platform),
            ),
          ),
          const VerticalSpace(6),
          TextButton(
            key: scanKey,
            onPressed: () {
              final navigator = Navigator.of(context);
              navigator.pop();
              navigator.pushNamed(RoutesStrings.pairingScan);
            },
            child: AppText('Scan the code instead', style: AppTextStyle.style13p5Medium.copyWith(color: skin.accentText)),
          ),
        ],
      ),
    );
  }
}
