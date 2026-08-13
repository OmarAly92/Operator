import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/logic/pull_request_cubit.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/widgets/pull_requests_body.dart';

class PullRequestsScreen extends StatelessWidget {
  const PullRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) => sl<PullRequestCubit>(),
    child: Scaffold(
      backgroundColor: context.skin.bgBase,
      appBar: const GlobalAppbar.main(titleText: 'Pull Requests'),
      body: const PullRequestsBody(),
    ),
  );
}
