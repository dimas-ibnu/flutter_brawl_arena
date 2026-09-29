import 'dart:io';

import 'replay.dart';

/// Native: writes to the system temp folder.
String? saveReplayFile(Replay replay) {
  final dir = Directory('${Directory.systemTemp.path}/brawl_replays')
    ..createSync(recursive: true);
  final file = File(
    '${dir.path}/replay_${DateTime.now().millisecondsSinceEpoch}.json',
  )..writeAsStringSync(replay.toJson());
  return file.path;
}
