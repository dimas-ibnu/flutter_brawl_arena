import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import '../sim/match_simulation.dart';

/// Rollback netcode for a 1v1 match (PRD Phase 3), in the style of GGPO.
///
/// Each peer runs the full simulation. Local input is applied [inputDelay]
/// frames late, which hides small network delays. The opponent's input is
/// *predicted* (repeat the last one we know) so the game never waits. When
/// the real input arrives and differs from the prediction, the session
/// restores the saved state from that frame and re-simulates up to now.
/// Because the simulation is deterministic, both peers end up with the same
/// state once every input is known; [confirmedChecksums] proves it.
class RollbackSession {
  RollbackSession({
    required this.sim,
    required int seed,
    required this.localSlot,
    this.inputDelay = 2,
    this.maxRollback = 8,
    this.checksumInterval = 60,
  }) : _state = sim.initialState(seed: seed) {
    assert(sim.fighterDefs.length == 2, 'rollback sessions are 1v1');
    for (var f = 0; f < inputDelay; f++) {
      _local[f] = 0;
    }
  }

  final MatchSimulation sim;
  final int localSlot;

  /// Frames between pressing a button and it taking effect.
  final int inputDelay;

  /// Most frames we may run ahead of the last confirmed remote input.
  /// Beyond that the session waits (stalls) for the opponent.
  final int maxRollback;

  /// A checksum is recorded for every frame that is a multiple of this.
  final int checksumInterval;

  int get remoteSlot => 1 - localSlot;

  GameState _state;

  /// Current (possibly predicted) state; draw this.
  GameState get state => _state;

  int _frame = 0;

  /// The next frame to simulate (= frames simulated so far).
  int get frame => _frame;

  final Map<int, int> _local = {};
  final Map<int, int> _remote = {};
  final Map<int, int> _usedRemote = {};
  final Map<int, GameState> _snapshots = {};
  int _confirmedRemote = -1;
  int? _rollbackTo;

  /// Highest frame for which we have every remote input (-1 = none).
  int get confirmedRemoteFrame => _confirmedRemote;

  /// Last frame that has a local input queued.
  int get lastLocalFrame => _frame + inputDelay - 1;

  /// Frames up to here are final on this peer: every input is known.
  int get confirmedFrame =>
      _confirmedRemote < _frame - 1 ? _confirmedRemote : _frame - 1;

  /// How often we had to go back, and how many frames we re-simulated.
  int rollbacks = 0;
  int rolledBackFrames = 0;

  /// Ticks that could not advance because the opponent was too far behind.
  int stalls = 0;

  /// Frame -> checksum of the state at the start of that frame, recorded
  /// once the frame is confirmed. Checksums are sent to the other peer.
  final Map<int, int> confirmedChecksums = {};
  int _nextChecksumFrame = 0;

  /// First frame where our checksum differed from the opponent's.
  int? desyncFrame;
  final Map<int, int> _remoteChecksums = {};

  bool get canAdvance => _frame - _confirmedRemote <= maxRollback;

  /// Local inputs for frames [from]..[lastLocalFrame], for sending.
  List<int> localInputs(int from, {int max = 64}) => [
    for (var f = from; f <= lastLocalFrame && f < from + max; f++)
      _local[f] ?? 0,
  ];

  /// Remote inputs arriving from the network (duplicates are ignored).
  void addRemoteInputs(int startFrame, List<int> inputs) {
    for (var i = 0; i < inputs.length; i++) {
      final f = startFrame + i;
      if (f <= _confirmedRemote || _remote.containsKey(f)) continue;
      _remote[f] = inputs[i];
      final used = _usedRemote[f];
      if (f < _frame && used != inputs[i]) {
        _rollbackTo = _rollbackTo == null || f < _rollbackTo! ? f : _rollbackTo;
      }
    }
    while (_remote.containsKey(_confirmedRemote + 1)) {
      _confirmedRemote++;
    }
  }

  void addRemoteChecksum(int frame, int checksum) {
    _remoteChecksums[frame] = checksum;
    _compareChecksums();
  }

  /// Runs one tick: corrects any misprediction, then (if not too far ahead)
  /// queues [local] and simulates one frame. Returns false when stalled.
  bool tick(InputFrame local) {
    _applyRollback();
    _recordChecksums();
    if (!canAdvance) {
      stalls++;
      return false;
    }
    _local[_frame + inputDelay] = local.bits;
    _step(_frame);
    _frame++;
    _recordChecksums();
    _prune();
    return true;
  }

  /// The best-known input for [slot] at [frame]: confirmed if we have it,
  /// otherwise the last confirmed remote input repeated (prediction).
  int _remoteFor(int frame) =>
      _remote[frame] ?? (_remote[_confirmedRemote] ?? 0);

  void _step(int f) {
    _snapshots[f] = _state.copy();
    final remote = _remoteFor(f);
    _usedRemote[f] = remote;
    final inputs = List.filled(2, InputFrame.none);
    inputs[localSlot] = InputFrame(_local[f] ?? 0);
    inputs[remoteSlot] = InputFrame(remote);
    sim.step(_state, inputs);
  }

  void _applyRollback() {
    final from = _rollbackTo;
    if (from == null) return;
    _rollbackTo = null;
    final snapshot = _snapshots[from];
    if (snapshot == null) {
      throw StateError('No snapshot for frame $from (rollback too deep)');
    }
    _state = snapshot.copy();
    for (var f = from; f < _frame; f++) {
      _step(f);
    }
    rollbacks++;
    rolledBackFrames += _frame - from;
  }

  // The state at the start of frame b is final once every frame before b
  // is confirmed and no correction is pending.
  void _recordChecksums() {
    if (_rollbackTo != null) return;
    while (_nextChecksumFrame <= confirmedFrame + 1) {
      final b = _nextChecksumFrame;
      final s = b == _frame ? _state : _snapshots[b];
      if (s == null) break;
      confirmedChecksums[b] = s.checksum();
      _nextChecksumFrame += checksumInterval;
    }
    _compareChecksums();
  }

  void _compareChecksums() {
    if (desyncFrame != null) return;
    for (final MapEntry(key: f, value: theirs) in _remoteChecksums.entries) {
      final mine = confirmedChecksums[f];
      if (mine != null && mine != theirs) {
        desyncFrame = f;
        return;
      }
    }
  }

  void _prune() {
    final keepFrom = confirmedFrame - maxRollback - 2;
    final checksumNeeded = _nextChecksumFrame;
    _snapshots.removeWhere((f, _) => f < keepFrom && f < checksumNeeded);
    _usedRemote.removeWhere((f, _) => f < keepFrom);
    _remote.removeWhere((f, _) => f < _confirmedRemote - 1);
    _remoteChecksums.removeWhere(
      (f, _) => confirmedChecksums.containsKey(f) && f < keepFrom,
    );
    // Local inputs go only once the opponent has them AND no rollback can
    // replay those frames any more.
    final localKeepFrom = _remoteHasLocalUpTo < keepFrom
        ? _remoteHasLocalUpTo
        : keepFrom;
    _local.removeWhere((f, _) => f < localKeepFrom);
  }

  int _remoteHasLocalUpTo = -1;

  /// The opponent has our inputs before [frame]. They are still kept for
  /// rollbacks and dropped later by [_prune].
  void forgetLocalBefore(int frame) {
    if (frame - 1 > _remoteHasLocalUpTo) _remoteHasLocalUpTo = frame - 1;
  }
}
