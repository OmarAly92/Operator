import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/core/utils/haptics.dart';
import 'package:operator_mobile/core/utils/service_locator.dart';
import 'package:operator_mobile/core/widgets/main_widgets/settings_group.dart';
import 'package:operator_mobile/core/widgets/motion/disclosure.dart';
import 'package:operator_mobile/feature/terminal/data/data_source/recent_photos_data_source.dart';
import 'package:operator_mobile/feature/terminal/data/model/recent_photo_model.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/recent_photos_cubit.dart';
import 'package:operator_mobile/feature/terminal/presentation/terminal_screen/logic/terminal_cubit.dart';

class RecentPhotosRow extends StatelessWidget {
  const RecentPhotosRow({super.key});

  static const Key rowKey = ValueKey('recent-photos-row');
  static const Key stripKey = ValueKey('recent-photos-strip');
  static const Key manageKey = ValueKey('recent-photos-manage');
  static const double thumbSize = 72;

  @override
  Widget build(BuildContext context) => BlocProvider<RecentPhotosCubit>(
    create: (_) => RecentPhotosCubit(sl<RecentPhotosDataSource>()),
    child: const _RecentPhotosView(),
  );
}

class _RecentPhotosView extends StatelessWidget {
  const _RecentPhotosView();

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return BlocBuilder<RecentPhotosCubit, RecentPhotosState>(
      builder: (context, state) {
        final cubit = context.read<RecentPhotosCubit>();
        final denied = state.access == PhotoAccess.denied;
        return SettingsGroup(
          children: [
            SettingsRow(
              key: RecentPhotosRow.rowKey,
              icon: denied ? Icons.lock_outline_rounded : Icons.photo_outlined,
              label: denied ? 'Allow photo access' : 'Show recent photos',
              trailing: denied
                  ? Icon(Icons.open_in_new_rounded, size: 16, color: skin.textFaint)
                  : DisclosureChevron(expanded: state.expanded, color: skin.textFaint),
              onTap: () {
                Haptics.tap();
                unawaited(denied ? cubit.openSettings() : cubit.toggle());
              },
            ),
            Disclosure(
              expanded: state.expanded,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [
                    SizedBox(
                      key: RecentPhotosRow.stripKey,
                      height: RecentPhotosRow.thumbSize,
                      child: state.loading
                          ? Center(child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: skin.accent)))
                          : ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: state.photos.length,
                              separatorBuilder: (_, _) => const SizedBox(width: 8),
                              itemBuilder: (context, index) => _RecentPhotoThumb(photo: state.photos[index]),
                            ),
                    ),
                    if (state.access == PhotoAccess.limited)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: RecentPhotosRow.manageKey,
                          onPressed: () => unawaited(cubit.manageLimited()),
                          child: Text('Manage', style: AppTextStyle.style13Medium.copyWith(color: skin.accentText)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecentPhotoThumb extends StatelessWidget {
  const _RecentPhotoThumb({required this.photo});

  final RecentPhotoModel photo;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final id = photo.id ?? '';
    final thumbnail = photo.thumbnail;
    return BlocBuilder<TerminalCubit, TerminalState>(
      builder: (context, _) {
        final terminal = context.read<TerminalCubit>();
        final selected = terminal.hasAttachment(recentPhotoAttachmentId(id));
        return Semantics(
          button: true,
          selected: selected,
          label: 'Recent photo',
          child: GestureDetector(
            key: ValueKey('recent-photo-$id'),
            behavior: HitTestBehavior.opaque,
            onTap: () => unawaited(_toggle(context, terminal, id, selected)),
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: thumbnail == null
                      ? Container(width: RecentPhotosRow.thumbSize, height: RecentPhotosRow.thumbSize, color: skin.bgElevated)
                      : Image.memory(
                          thumbnail,
                          width: RecentPhotosRow.thumbSize,
                          height: RecentPhotosRow.thumbSize,
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          errorBuilder: (_, _, _) => Container(
                            width: RecentPhotosRow.thumbSize,
                            height: RecentPhotosRow.thumbSize,
                            color: skin.bgElevated,
                          ),
                        ),
                ),
                if (selected)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: Icon(Icons.check_circle_rounded, size: 20, color: skin.accent),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Future<void> _toggle(BuildContext context, TerminalCubit terminal, String id, bool selected) async {
  Haptics.select();
  if (selected) {
    terminal.removeAttachment(recentPhotoAttachmentId(id));
    return;
  }
  final attachment = await context.read<RecentPhotosCubit>().load(id);
  if (attachment == null) {
    terminal.showAttachmentNotice("That photo couldn't be loaded.");
    return;
  }
  terminal.toggleAttachment(attachment);
}
