import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/game_screen.dart';

/// Force the on-screen controls on desktop (mouse = one finger):
/// `flutter run -d macos --dart-define=TOUCH_CONTROLS=true`
const _forceTouchControls = bool.fromEnvironment('TOUCH_CONTROLS');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final isPhone =
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: GameScreen(showTouchControls: isPhone || _forceTouchControls),
    ),
  );
}
