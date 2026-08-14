import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/logic/manual_connect_cubit.dart';
import 'package:operator_mobile/feature/pairing/presentation/manual_connect_screen/ui/widgets/manual_connect_body.dart';

class ManualConnectScreen extends StatelessWidget {
  const ManualConnectScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocListener<ManualConnectCubit, ManualConnectState>(
    listener: (context, state) {
      if (state is ConnectSuccessState) Navigator.of(context).pop<bool>(true);
    },
    child: const AppScaffold(
      appBar: GlobalAppbar.sub(titleText: 'Connect manually'),
      body: ManualConnectBody(),
    ),
  );
}
