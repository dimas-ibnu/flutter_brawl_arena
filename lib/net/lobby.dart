import 'protocol.dart';
import 'transport.dart';

/// Agrees on match settings once two peers are connected.
///
/// Both sides keep sending [HelloPacket] (packets can be lost) until they
/// hear the other. The host then builds the [StartPacket] (seed, fighters,
/// skins, stage) and sends it; the guest starts when it arrives. The host is
/// slot 0, the guest slot 1. Call [tick] about 60 times per second.
class LobbyHandshake {
  LobbyHandshake({
    required this.transport,
    required this.isHost,
    required this.hello,
    this.makeStart,
  }) : assert(!isHost || makeStart != null, 'the host builds the start');

  final Transport transport;
  final bool isHost;
  final HelloPacket hello;

  /// Host only: builds the match settings from the guest's hello.
  final StartPacket Function(HelloPacket guest)? makeStart;

  HelloPacket? remoteHello;

  /// The agreed settings; the match can start once this is set.
  StartPacket? start;

  /// Set when the handshake can't work (e.g. different game versions).
  String? error;

  int _ticks = 0;

  bool get done => start != null || error != null;

  void tick() {
    for (final bytes in transport.poll()) {
      final Packet p;
      try {
        p = Packet.decode(bytes);
      } on FormatException {
        continue;
      }
      switch (p) {
        case HelloPacket():
          if (p.version != Packet.protocolVersion) {
            error = 'The other player has a different game version';
          }
          remoteHello = p;
        case StartPacket() when !isHost:
          start = p;
        default:
          break; // game packets can arrive early; the match handles them
      }
    }
    if (error != null) return;
    final agreed = start;
    if (agreed != null) {
      // Host: keep offering the start until the match takes over (and
      // NetMatch keeps resending it). Guest: nothing left to do.
      if (isHost && _ticks++ % 15 == 0) transport.send(agreed.encode());
      return;
    }

    if (_ticks++ % 15 == 0) transport.send(hello.encode());
    if (isHost && remoteHello != null) {
      final settings = makeStart!(remoteHello!);
      start = settings;
      transport.send(settings.encode());
    }
  }
}
