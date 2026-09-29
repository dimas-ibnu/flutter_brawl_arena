import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/sounds.dart';
import 'ui/app.dart';

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

  final sounds = FlameSounds();
  final roster = await BrawlApp.loadRoster();
  final cosmetics = await BrawlApp.loadCosmetics(roster);
  try {
    await sounds.load();
  } catch (e) {
    debugPrint('Sound failed to load, playing silent: $e');
  }

  runApp(
    BrawlApp(
      roster: roster,
      cosmetics: cosmetics,
      sounds: sounds,
      showTouchControls: isPhone || _forceTouchControls,
    ),
  );
}
