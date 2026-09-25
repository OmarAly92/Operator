import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/connection/connection_cubit.dart';
import 'package:operator_mobile/core/error_handling/connection_error.dart';
import 'package:operator_mobile/core/error_handling/failures/failure.dart';
import 'package:operator_mobile/core/widgets/connection/connection_error_state.dart';
import 'package:operator_mobile/feature/pairing/presentation/re_pair_sheet/ui/re_pair_sheet.dart';

class BoardError extends StatelessWidget {
  const BoardError({super.key, required this.failure, required this.onRetry});

  final Failure failure;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final connection = context.watch<ConnectionCubit>();
    final config = connection.config;
    return ConnectionErrorState(
      reason: classifyConnectionFailure(failure.statusCode),
      host: config?.host ?? '',
      port: config?.httpPort ?? '',
      desktopName: connection.state.desktopName,
      onRetry: () => unawaited(onRetry()),
      onSwitchDesktop: () => Navigator.of(context).pushNamed(RoutesStrings.connections),
      onRePair: () => showRePairSheet(context),
    );
  }
}
