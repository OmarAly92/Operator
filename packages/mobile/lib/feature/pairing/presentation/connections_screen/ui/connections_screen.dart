import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<ConnectionsCubit, ConnectionsState>(
    listener: (context, state) {
      switch (state) {
        case ConnectSuccessState():
          Haptics.success();
          Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
        case ConnectFailureState():
          Haptics.error();
        case LastDesktopRemovedState():
          Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.onboarding, (_) => false);
        case ConnectionsInitialState():
        case DesktopsUpdatedState():
        case ConnectLoadingState():
          break;
      }
    },
    child: const AppScaffold(body: ConnectionsBody()),
  );
}
