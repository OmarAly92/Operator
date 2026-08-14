import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/orchestrator/presentation/orchestrator_screen/ui/orchestrator_screen.dart';
import 'package:operator_mobile/feature/pull_request/presentation/pull_requests_screen/ui/pull_requests_screen.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';
import 'package:operator_mobile/feature/settings/presentation/settings_screen/ui/settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  static final ValueNotifier<int> selectedTab = ValueNotifier<int>(0);

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  @override
  void initState() {
    super.initState();
    HomeShell.selectedTab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    HomeShell.selectedTab.removeListener(_onTabChanged);
    super.dispose();
  }

  void _onTabChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: IndexedStack(
        index: HomeShell.selectedTab.value,
        children: [
          const SessionsScreen(),
          OrchestratorScreen(onOpenBoard: () => HomeShell.selectedTab.value = 0),
          const PullRequestsScreen(),
          SettingsScreen(onOpenBoard: () => HomeShell.selectedTab.value = 0),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: HomeShell.selectedTab.value,
        onTap: (next) => HomeShell.selectedTab.value = next,
        type: BottomNavigationBarType.fixed,
        backgroundColor: skin.bgSurface,
        selectedItemColor: skin.blue,
        unselectedItemColor: skin.textTertiary,
        selectedLabelStyle: AppTextStyle.style11SemiBold,
        unselectedLabelStyle: AppTextStyle.style11SemiBold,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.auto_awesome_motion_outlined), label: 'Agents'),
          BottomNavigationBarItem(icon: Icon(Icons.hub_outlined), label: 'Orchestrator'),
          BottomNavigationBarItem(icon: Icon(Icons.merge_outlined), label: 'PRs'),
          BottomNavigationBarItem(icon: Icon(Icons.settings_outlined), label: 'Settings'),
        ],
      ),
    );
  }
}
