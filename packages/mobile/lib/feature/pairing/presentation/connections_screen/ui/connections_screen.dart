import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/logic/connections_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/connections_screen/ui/widgets/connections_body.dart';

class ConnectionsScreen extends StatelessWidget {
  const ConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<ConnectionsCubit, ConnectionsState>(
    listener: (context, state) {
      if (state is ConnectSuccessState) {
        Navigator.of(context).pushNamedAndRemoveUntil(RoutesStrings.sessions, (_) => false);
      }
    },
    child: const AppScaffold(body: ConnectionsBody()),
  );
}
