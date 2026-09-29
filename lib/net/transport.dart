import 'dart:math' as math;
import 'dart:typed_data';

/// Sends and receives raw packets to one other peer. Unreliable and
/// unordered, like UDP: the rollback layer copes with loss by resending.
abstract class Transport {
  void send(Uint8List packet);

  /// Packets received since the last call.
  List<Uint8List> poll();

  void close();
}

/// Two in-memory transports wired together, with made-up network trouble:
/// delay and jitter in ticks, and a loss rate. Used by tests and for trying
/// the netcode without a network. Call [advance] once per tick.
class FakeNetwork {
  FakeNetwork({
    this.delayTicks = 0,
    this.jitterTicks = 0,
    this.lossPercent = 0,
    int seed = 1,
  }) : _rng = math.Random(seed) {
    a = _FakeEnd(this, 0);
    b = _FakeEnd(this, 1);
  }

  final int delayTicks;
  final int jitterTicks;
  final int lossPercent;
  final math.Random _rng;
  int _now = 0;

  late final Transport a;
  late final Transport b;

  final _inFlight = [<(int, Uint8List)>[], <(int, Uint8List)>[]];

  /// Packets sent / dropped so far.
  int sent = 0;
  int dropped = 0;

  void advance() => _now++;

  void _send(int toEnd, Uint8List packet) {
    sent++;
    if (_rng.nextInt(100) < lossPercent) {
      dropped++;
      return;
    }
    final jitter = jitterTicks == 0 ? 0 : _rng.nextInt(jitterTicks + 1);
    _inFlight[toEnd].add((
      _now + delayTicks + jitter,
      Uint8List.fromList(packet),
    ));
  }

  List<Uint8List> _poll(int end) {
    final ready = [
      for (final (at, p) in _inFlight[end])
        if (at <= _now) p,
    ];
    _inFlight[end].removeWhere((e) => e.$1 <= _now);
    return ready;
  }
}

class _FakeEnd implements Transport {
  _FakeEnd(this._net, this._end);

  final FakeNetwork _net;
  final int _end;

  @override
  void send(Uint8List packet) => _net._send(1 - _end, packet);

  @override
  List<Uint8List> poll() => _net._poll(_end);

  @override
  void close() {}
}
