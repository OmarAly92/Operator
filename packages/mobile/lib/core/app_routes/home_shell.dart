import 'package:flutter/material.dart';
import 'package:operator_mobile/core/app_themes/colors/skin_scope.dart';
import 'package:operator_mobile/core/app_themes/text_style/app_text_style.dart';
import 'package:operator_mobile/feature/sessions/presentation/sessions_screen/ui/sessions_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final skin = context.skin;
    return Scaffold(
      backgroundColor: skin.bgBase,
      body: IndexedStack(
        index: _index,
        children: [
          const SessionsScreen(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
          const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (next) => setState(() => _index = next),
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
