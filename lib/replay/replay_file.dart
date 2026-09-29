import 'replay.dart';
import 'replay_file_io.dart'
    if (dart.library.js_interop) 'replay_file_web.dart'
    as impl;

/// Saves [replay] for later, where the platform allows it. Returns a
/// description of where it went (a file path), or null if not supported.
String? saveReplayFile(Replay replay) => impl.saveReplayFile(replay);
