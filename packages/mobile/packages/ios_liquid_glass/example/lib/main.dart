import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'lab/glass_lab_launch.dart';
import 'lab/glass_lab_registry.dart';
import 'lab/glass_lab_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final launch = kDebugMode ? await GlassLabLaunch.load() : null;
  runApp(ExampleApp(launch: launch));
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.launch});

  final GlassLabLaunch? launch;

  @override
  Widget build(BuildContext context) {
    final launch = this.launch;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.light),
      darkTheme: ThemeData(brightness: Brightness.dark),
      home: launch != null ? GlassLabScreen(launch: launch) : const SceneIndex(),
    );
  }
}

class SceneIndex extends StatelessWidget {
  const SceneIndex({super.key});

  @override
  Widget build(BuildContext context) {
    final ids = GlassLabRegistry.scenes.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('ios_liquid_glass')),
      body: ListView(
        children: [
          for (final id in ids)
            ListTile(
              title: Text(id),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => GlassLabScreen(launch: GlassLabLaunch(scene: id))),
              ),
            ),
        ],
      ),
    );
  }
}
