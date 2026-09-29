import 'dart:convert';

import '../sim/defs.dart';
import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';

/// Everything needed to play a match again, tick for tick: the seed, which
/// fighters were picked, and every tick's inputs. Because the simulation is
/// deterministic, replaying these inputs rebuilds the exact same match; the
/// stored checksum proves it.
///
/// Also the base for later work: the bot is tuned from recorded matches, and
/// online PvP sends exactly these per-tick inputs over the network.
class Replay {
  Replay({
    required this.seed,
    required this.fighterIds,
    required this.stage,
    List<List<int>>? ticks,
    this.finalChecksum,
  }) : ticks = ticks ?? [];

  static const int formatVersion = 1;

  final int seed;
  final List<String> fighterIds;
  final String stage;

  /// Input bits per tick, one entry per fighter slot.
  final List<List<int>> ticks;

  /// Checksum of the state after the last tick, when the match was recorded.
  int? finalChecksum;

  void record(List<InputFrame> inputs) =>
      ticks.add([for (final i in inputs) i.bits]);

  /// Plays every tick on a fresh state and returns the final state.
  GameState play(MatchSimulation sim) {
    final state = sim.initialState(seed: seed);
    for (final tick in ticks) {
      sim.step(state, [for (final bits in tick) InputFrame(bits)]);
    }
    return state;
  }

  /// True when replaying gives the checksum stored at recording time.
  bool verify(MatchSimulation sim) =>
      finalChecksum != null && play(sim).checksum() == finalChecksum;

  String toJson() => jsonEncode({
    'version': formatVersion,
    'seed': seed,
    'stage': stage,
    'fighters': fighterIds,
    'finalChecksum': finalChecksum,
    'ticks': ticks,
  });

  factory Replay.fromJson(String json) {
    final j = jsonDecode(json) as Map<String, dynamic>;
    final version = j['version'];
    if (version != formatVersion) {
      throw FormatException('Unsupported replay version $version');
    }
    return Replay(
      seed: j['seed'] as int,
      stage: j['stage'] as String,
      fighterIds: [for (final f in j['fighters'] as List) f as String],
      finalChecksum: j['finalChecksum'] as int?,
      ticks: [
        for (final t in j['ticks'] as List)
          [for (final bits in t as List) bits as int],
      ],
    );
  }

  /// Builds the simulation this replay was recorded with.
  static MatchSimulation simulationFor(
    Replay replay,
    Map<String, FighterDef> fighters,
  ) => MatchSimulation(
    stage: StageDef.flatArena,
    fighterDefs: [for (final id in replay.fighterIds) fighters[id]!],
  );
}
