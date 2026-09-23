import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/logic/phone_alerts_cubit.dart';

class PhoneAlertsGroup extends StatelessWidget {
  const PhoneAlertsGroup({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.watch<PhoneAlertsCubit>();
    final state = cubit.state;
    final enabled = state.status?.enabled == true;
    final claimed = state.status?.claimed == true;

    return SettingsGroup(
      title: 'Phone alerts',
      footer: _statusLine(state),
      children: [
        SettingsRow(
          icon: Icons.notifications_active_outlined,
          label: 'Get ntfy',
          onTap: () => launchUrl(Uri.parse(kNtfyAppStoreUrl), mode: LaunchMode.externalApplication),
        ),
        SettingsRow(
          icon: Icons.qr_code,
          label: 'Subscribe on this phone',
          loading: state.busy,
          disabled: !enabled,
          value: !enabled
              ? 'Turn on Connect Mobile on the desktop first'
              : state.copiedTopic
              ? 'Topic copied — in ntfy, tap + and paste it'
              : null,
          onTap: enabled ? () => cubit.subscribe() : null,
        ),
        SettingsRow(
          icon: Icons.send_outlined,
          label: 'Send test alert',
          loading: state.busy,
          disabled: !(enabled && claimed),
          onTap: (enabled && claimed) ? () => cubit.sendTest() : null,
        ),
      ],
    );
  }

  String _statusLine(PhoneAlertsState state) {
    if (state.error.isNotEmpty) {
      return state.error;
    }
    if (state.status?.enabled != true) {
      return 'Off — Connect Mobile is off on the desktop';
    }
    if (state.status?.claimed != true) {
      return 'Not subscribed yet';
    }
    final lastDelivery = state.lastTest ?? state.status?.lastDelivery;
    if (lastDelivery?.ok == false) {
      return 'Last alert failed: ${lastDelivery?.error ?? 'unknown error'}';
    }
    return 'On — alerts arrive through ntfy when Operator is closed';
  }
}
