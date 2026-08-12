import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/logic/pairing_scan_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/pairing_scan_screen/ui/widgets/pairing_scan_body.dart';

class PairingScanScreen extends StatelessWidget {
  const PairingScanScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<PairingScanCubit, PairingScanState>(
    listener: (context, state) {
      if (state is! VerifySuccessState) return;
      final fromOnboarding = context.read<PairingScanCubit>().fromOnboarding;
      if (fromOnboarding) {
        Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
      } else {
        Navigator.of(context).pop();
      }
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.sub(titleText: 'Scan pairing code'),
      body: PairingScanBody(),
    ),
  );
}
