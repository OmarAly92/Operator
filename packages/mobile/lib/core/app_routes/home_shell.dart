import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_routes/routes_strings.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/widgets/glass/glass_button.dart';
import 'package:operator_mobile/core/widgets/glass/glass_metrics.dart';
import 'package:operator_mobile/core/widgets/glass/glass_tab_bar.dart';
import 'package:operator_mobile/core/widgets/glass/scroll_edge_effect.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  static final List<ScrollController> _controllers = List<ScrollController>.generate(
    3,
    (_) => ScrollController(),
  );

  static ScrollController controllerFor(int tab) => _controllers[tab];

  static const Key spawnButtonKey = ValueKey('home-shell-spawn');

  static const List<GlassTabItem> tabs = [
    GlassTabItem(icon: Icons.auto_awesome_motion_outlined, label: 'Agents'),
    GlassTabItem(icon: Icons.call_merge_outlined, label: 'PRs'),
    GlassTabItem(icon: Icons.settings_outlined, label: 'Settings'),
  ];

  static double contentBottomInset(double safeBottom) =>
      math.max(safeBottom, GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final List<ValueNotifier<double>> _bottomVisibility = List<ValueNotifier<double>>.generate(
    HomeShell.tabs.length,
    (_) => ValueNotifier<double>(0),
  );

  @override
  void initState() {
    super.initState();
    HomeShell.selectedTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    HomeShell.selectedTab.removeListener(_onTabChanged);
    for (final notifier in _bottomVisibility) {
      notifier.dispose();
    }
    super.dispose();
  }

  Widget _tracked(int tab, Widget child) => NotificationListener<Notification>(
        onNotification: (notification) {
          final metrics = switch (notification) {
            ScrollNotification(:final metrics, depth: 0) => metrics,
            ScrollMetricsNotification(:final metrics, depth: 0) => metrics,
            _ => null,
          };
          if (metrics != null && metrics.axis == Axis.vertical) {
            _bottomVisibility[tab].value = ScrollEdgeEffect.bottomVisibility(metrics);
          }
          return false;
        },
        child: child,
      );

  void _onTabChanged() => setState(() {});

  void _select(int next) {
    if (next == HomeShell.selectedTab.value) {
      final controller = HomeShell.controllerFor(next);
      if (controller.hasClients && controller.offset > 0) {
        controller.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }
    HomeShell.selectedTab.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    final media = MediaQuery.of(context);
    final selected = HomeShell.selectedTab.value;
    final bottomInset = HomeShell.contentBottomInset(media.padding.bottom);
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery(
              data: media.copyWith(padding: media.padding.copyWith(bottom: bottomInset)),
              child: IndexedStack(
                index: selected,
                children: [
                  _tracked(0, const SessionsScreen()),
                  _tracked(1, const PullRequestsScreen()),
                  _tracked(2, SettingsScreen(onOpenBoard: () => HomeShell.selectedTab.value = 0)),
                ],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _bottomVisibility[selected],
              builder: (context, visibility, _) => ScrollEdgeEffect(
                edge: ScrollEdge.bottom,
                height: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.bottomEdgeFadeExtent,
                visibility: visibility,
              ),
            ),
          ),
          if (selected == 0)
            Positioned(
              right: GlassMetrics.primaryButtonInset,
              bottom: GlassMetrics.tabBarBottomInset + GlassMetrics.tabBarHeight + GlassMetrics.primaryButtonBottomGap,
              child: GlassButton.icon(
                key: HomeShell.spawnButtonKey,
                icon: Icons.add,
                semanticLabel: 'Spawn agent',
                prominent: true,
                onPressed: () => Navigator.of(context).pushNamed(RoutesStrings.spawn),
              ),
            ),
          Positioned(
            left: GlassMetrics.tabBarSideInset,
            right: GlassMetrics.tabBarSideInset,
            bottom: GlassMetrics.tabBarBottomInset,
            child: GlassTabBar(items: HomeShell.tabs, selectedIndex: selected, onSelected: _select),
          ),
        ],
      ),
    );
  }
}
