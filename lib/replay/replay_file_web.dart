import 'replay.dart';

/// Web: browsers have no file system to write to. Replays still record in
/// memory (Replay.toJson); saving is native only for now.
String? saveReplayFile(Replay replay) => null;
