import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text_field.dart';
import 'package:operator_mobile/core/widgets/main_widgets/primary_button.dart';
import 'package:operator_mobile/core/widgets/main_widgets/space_widgets.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/connection_failure_banner.dart';

class ManualConnectBody extends StatelessWidget {
  const ManualConnectBody({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ManualConnectCubit>();
    return BlocListener<ManualConnectCubit, ManualConnectState>(
      listener: (context, state) {
        if (state is ConnectSuccessState) Haptics.success();
        if (state is ConnectFailureState) Haptics.warning();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppTextField(controller: cubit.hostController, label: 'HOST', keyboardType: TextInputType.url),
            const VerticalSpace(14),
            AppTextField(controller: cubit.portController, label: 'API PORT', keyboardType: TextInputType.number),
            const VerticalSpace(14),
            AppTextField(controller: cubit.passwordController, label: 'PASSWORD', obscureText: true),
            const VerticalSpace(14),
            BlocBuilder<ManualConnectCubit, ManualConnectState>(
              buildWhen: (previous, current) => current is SecureToggledState,
              builder: (context, state) => Row(
                children: [
                  Switch(value: cubit.secure, onChanged: cubit.setSecure, activeThumbColor: context.skin.accent),
                  const HorizontalSpace(8),
                  const AppText('Use TLS (https/wss)'),
                ],
              ),
            ),
            const VerticalSpace(20),
            BlocBuilder<ManualConnectCubit, ManualConnectState>(
              buildWhen: (previous, current) => current is ConnectFailureState,
              builder: (context, state) => state is ConnectFailureState
                  ? Padding(padding: const EdgeInsets.only(bottom: 16), child: ConnectionFailureBanner(copy: state.copy))
                  : const SizedBox.shrink(),
            ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: cubit.hostController,
              builder: (context, value, _) => BlocBuilder<ManualConnectCubit, ManualConnectState>(
                buildWhen: (previous, current) => current is ConnectLoadingState || current is ConnectFailureState,
                builder: (context, state) => PrimaryButton.expand(
                  text: 'Connect',
                  isLoading: state is ConnectLoadingState,
                  onPressed: value.text.trim().isEmpty ? null : () => cubit.connect(Theme.of(context).platform),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
