import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/utils/extensions.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/logic/sessions_cubit.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/widgets/sessions_body.dart';

class SessionsScreen extends StatelessWidget {
  const SessionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<SessionsCubit, SessionsState>(
    listener: (context, state) {
      if (state is KillFailureState) context.showSnackBar('Kill failed: ${state.failure.message}');
      if (state is RestoreFailureState) context.showSnackBar('Restore failed: ${state.failure.message}');
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.main(titleText: 'Agents'),
      body: SessionsBody(),
    ),
  );
}
