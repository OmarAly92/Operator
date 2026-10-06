import 'package:flutter/material.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_backdrop.dart';
import 'package:operator_mobile/core/widgets/glass/lab/glass_lab_launch.dart';
import 'package:operator_mobile/core/widgets/main_widgets/global_appbar.dart';

sealed class LabNavigationScenes {
  static const Rect nativeTabBar = Rect.fromLTWH(20, 791, 362, 62);

  static final Map<String, Widget Function(GlassLabLaunch launch)> scenes = {
    'tabbar.rest': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'tabbar.press': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'tabbar.drag': (launch) => _TabBarScene(backdrop: launch.backdrop),
    'navbar.inline': (launch) => _InlineNavScene(backdrop: launch.backdrop),
  };
}

class _TabBarScene extends StatefulWidget {
  const _TabBarScene({required this.backdrop});

  final String backdrop;

  @override
  State<_TabBarScene> createState() => _TabBarSceneState();
}

class _TabBarSceneState extends State<_TabBarScene> {
  var _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: GlassLabBackdrop(id: widget.backdrop)),
        Positioned.fromRect(
          rect: LabNavigationScenes.nativeTabBar,
          child: GlassTabBar(
            items: const [
              GlassTabItem(icon: Icons.layers, label: 'Agents'),
              GlassTabItem(icon: Icons.call_merge, label: 'PRs'),
              GlassTabItem(icon: Icons.settings, label: 'Settings'),
              GlassTabItem(icon: Icons.search, label: 'Search'),
            ],
            selectedIndex: _selected,
            onSelected: (index) => setState(() => _selected = index),
          ),
        ),
      ],
    );
  }
}

class _InlineNavScene extends StatelessWidget {
  const _InlineNavScene({required this.backdrop});

  final String backdrop;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: Colors.transparent,
      appBar: GlobalAppbar.sub(
        titleText: 'Agents',
        actions: [
          GlassButton.icon(icon: Icons.notifications_none_rounded, onPressed: () {}),
          GlassButton.icon(icon: Icons.more_horiz_rounded, onPressed: () {}),
        ],
      ),
      body: GlassLabBackdrop(id: backdrop),
    );
  }
}
