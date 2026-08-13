import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/spawn/presentation/spawn_screen/ui/widgets/spawn_body.dart';

class SpawnScreen extends StatelessWidget {
  const SpawnScreen({super.key});

  @override
  Widget build(BuildContext context) => const AppScaffold(
    appBar: GlobalAppbar.sub(titleText: 'Spawn agent'),
    body: SpawnBody(),
  );
}
