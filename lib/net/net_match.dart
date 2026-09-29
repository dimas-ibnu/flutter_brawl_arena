import '../sim/game_state.dart';
import '../sim/input_frame.dart';
import 'protocol.dart';
import 'rollback_session.dart';
import 'transport.dart';

/// One peer of an online match: a [RollbackSession] talking to the other
/// peer through a [Transport]. Call [tick] once per game tick with this
/// player's input.
class NetMatch {
  NetMatch({
    required this.session,
    required this.transport,
    this.resendUntilHeard,
  });

  /// Host: the start packet, resent until the guest's first input arrives
  /// (the first copy may have been lost).
  Packet? resendUntilHeard;
  bool _heardInput = false;

  final RollbackSession session;
  final Transport transport;

  /// The opponent has all of our inputs up to this frame.
  int _remoteAck = -1;
  int _lastChecksumSent = -1;
  int _ticks = 0;
  final Map<int, int> _pingSentAt = {};

  /// Round-trip time in ticks (smoothed), or null before the first ping.
  double? rttTicks;

  /// Ticks since anything arrived from the opponent.
  int ticksSinceHeard = 0;

  bool remoteQuit = false;

  GameState get state => session.state;
  bool get desynced => session.desyncFrame != null;

  /// Receives, simulates one frame (unless stalled), and sends.
  bool tick(InputFrame local) {
    _ticks++;
    ticksSinceHeard++;
    for (final bytes in transport.poll()) {
      ticksSinceHeard = 0;
      try {
        _handle(Packet.decode(bytes));
      } on FormatException {
        // Ignore garbage rather than crash the match.
      }
    }

    final advanced = session.tick(local);

    // Resend every input the opponent hasn't acknowledged, so one lost
    // packet never loses an input.
    final from = _remoteAck + 1;
    transport.send(
      InputPacket(
        startFrame: from,
        inputs: session.localInputs(from, max: InputPacket.maxInputs),
        ackFrame: session.confirmedRemoteFrame,
      ).encode(),
    );

    for (final MapEntry(key: f, value: sum)
        in session.confirmedChecksums.entries) {
      if (f > _lastChecksumSent) {
        transport.send(ChecksumPacket(frame: f, checksum: sum).encode());
        _lastChecksumSent = f;
      }
    }

    final start = resendUntilHeard;
    if (start != null && !_heardInput && _ticks % 10 == 1) {
      transport.send(start.encode());
    }

    if (_ticks % 30 == 0) {
      _pingSentAt[_ticks] = _ticks;
      transport.send(PingPacket(id: _ticks, reply: false).encode());
    }
    return advanced;
  }

  void _handle(Packet p) {
    switch (p) {
      case InputPacket():
        _heardInput = true;
        session.addRemoteInputs(p.startFrame, p.inputs);
        if (p.ackFrame > _remoteAck) {
          _remoteAck = p.ackFrame;
          session.forgetLocalBefore(_remoteAck + 1);
        }
      case ChecksumPacket():
        session.addRemoteChecksum(p.frame, p.checksum);
      case PingPacket(reply: false):
        transport.send(PingPacket(id: p.id, reply: true).encode());
      case PingPacket(reply: true):
        final sentAt = _pingSentAt.remove(p.id);
        if (sentAt != null) {
          final rtt = (_ticks - sentAt).toDouble();
          rttTicks = rttTicks == null ? rtt : rttTicks! * 0.8 + rtt * 0.2;
        }
      case QuitPacket():
        remoteQuit = true;
      case HelloPacket() || StartPacket():
        break; // lobby messages, handled before the match starts
    }
  }

  void quit() {
    transport.send(const QuitPacket().encode());
    transport.close();
  }
}
