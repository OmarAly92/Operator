import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/widgets/loading_widget/app_loader.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_ink_well.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_scaffold.dart';
import 'package:operator_mobile/core/widgets/main_widgets/app_text.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';
import 'package:operator_mobile/feature/usage/data/model/usage_rollup_model.dart';
import 'package:operator_mobile/feature/usage/presentation/usage_screen/logic/usage_cubit.dart';

class UsageScreen extends StatefulWidget {
  const UsageScreen({super.key});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  @override
  void initState() {
    super.initState();
    context.read<UsageCubit>().load('day');
  }

  @override
  Widget build(BuildContext context) => AppScaffold(
    appBar: GlobalAppbar.sub(titleText: 'Token usage'),
    body: BlocBuilder<UsageCubit, UsageState>(
      builder: (context, state) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: _BucketToggle(
              bucket: state.bucket,
              onChanged: (bucket) => context.read<UsageCubit>().load(bucket),
            ),
          ),
          Expanded(child: _UsageBody(state: state)),
        ],
      ),
    ),
  );
}

class _BucketToggle extends StatelessWidget {
  const _BucketToggle({required this.bucket, required this.onChanged});

  final String bucket;
  final void Function(String bucket) onChanged;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: skin.bgSubtle,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'day', 'Day')),
          Expanded(child: _segment(context, 'week', 'Week')),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String value, String label) {
    final skin = context.skin;
    final selected = bucket == value;
    return AppInkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? skin.bgSurface : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: AppText(
          label,
          style: AppTextStyle.style13SemiBold.copyWith(
            color: selected ? skin.textPrimary : skin.textTertiary,
          ),
        ),
      ),
    );
  }
}

class _UsageBody extends StatelessWidget {
  const _UsageBody({required this.state});

  final UsageState state;

  @override
  Widget build(BuildContext context) {
    switch (state.status) {
      case UsageStatus.initial:
      case UsageStatus.loading:
        return const AppLoader.center();
      case UsageStatus.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: AppText(
              state.error ?? 'Could not load token usage.',
              style: AppTextStyle.style12Regular.copyWith(
                color: context.skin.attention,
              ),
              maxLines: 3,
              textAlign: TextAlign.center,
            ),
          ),
        );
      case UsageStatus.loaded:
        if (state.buckets.isEmpty) {
          return Center(
            child: AppText(
              'No usage recorded yet.',
              style: AppTextStyle.style12Regular.copyWith(
                color: context.skin.textTertiary,
              ),
            ),
          );
        }
        final buckets = state.buckets.reversed.toList();
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          itemCount: buckets.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _UsageBucketRow(bucket: buckets[index]),
        );
    }
  }
}

class _UsageBucketRow extends StatelessWidget {
  const _UsageBucketRow({required this.bucket});

  final UsageBucketModel bucket;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final input = bucket.inputTokens ?? 0;
    final output = bucket.outputTokens ?? 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: skin.bgSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: AppText(
              bucket.start ?? '—',
              style: AppTextStyle.style13SemiBold.copyWith(color: skin.textPrimary),
            ),
          ),
          AppText(
            '${_formatTokens(input)} in / ${_formatTokens(output)} out',
            style: AppTextStyle.style12Regular.copyWith(color: skin.textSecondary),
          ),
        ],
      ),
    );
  }

  String _formatTokens(int value) {
    if (value < 1000) return '$value';
    return '${(value / 1000).toStringAsFixed(1)}k';
  }
}
