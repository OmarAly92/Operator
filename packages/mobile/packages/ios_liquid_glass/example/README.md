# ios_liquid_glass example

A plain Flutter app that uses only `ios_liquid_glass`. It shows the package works in a fresh project, and it is the glass lab's Flutter target.

## Run it

```bash
flutter run
```

The home screen lists every scene. Each one copies a scene of the native iOS 27 catalog point for point:
- regular glass at three sizes;
- clear glass with dimming;
- tinted glass and a prominent button;
- shapes;
- merging containers;
- the three scroll edge styles;
- the flip scene.

## Use the package in your own app

1. Add the dependency:

   ```yaml
   dependencies:
     ios_liquid_glass:
       path: <path to packages/ios_liquid_glass>
   ```

2. Put glass over content:

   ```dart
   import 'package:flutter/material.dart';
   import 'package:ios_liquid_glass/ios_liquid_glass.dart';

   class Demo extends StatelessWidget {
     const Demo({super.key});

     @override
     Widget build(BuildContext context) {
       return Stack(
         children: [
           Positioned.fill(child: Image.asset('assets/photo.jpg', fit: BoxFit.cover)),
           Center(
             child: GlassEffectContainer(
               child: Row(
                 mainAxisSize: MainAxisSize.min,
                 children: [
                   GlassEffect(
                     shape: const GlassShape.circle(),
                     child: const SizedBox.square(dimension: 56, child: GlassForeground(child: Icon(Icons.add))),
                   ),
                   const SizedBox(width: 12),
                   GlassEffect(
                     glass: Glass.regular.tint(const Color(0xFF1ACB64)),
                     child: const Padding(
                       padding: EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                       child: GlassForeground(child: Text('Run', style: TextStyle(fontSize: 17))),
                     ),
                   ),
                 ],
               ),
             ),
           ),
         ],
       );
     }
   }
   ```

3. On iOS, `pod install` runs automatically on the first build and adds the accessibility plugin.

## The lab hook

In debug builds, `lib/main.dart` looks for `Documents/glass_lab/launch.json`. If the file is there, the app opens that scene instead of the list and deletes the file. Its optional `material` map overrides material fields by name, which is how `lab.py tune` tries candidates. Release builds never read the file.
