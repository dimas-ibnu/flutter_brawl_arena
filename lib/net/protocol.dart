import 'dart:convert';
import 'dart:typed_data';

/// Packets exchanged by two online peers. Small binary messages, because
/// input packets go out every tick.
///
/// Every packet starts with a 1-byte type.
sealed class Packet {
  const Packet();

  static const int protocolVersion = 1;

  Uint8List encode();

  static Packet decode(Uint8List bytes) {
    final data = ByteData.sublistView(bytes);
    return switch (data.getUint8(0)) {
      InputPacket.type => InputPacket._decode(data),
      ChecksumPacket.type => ChecksumPacket._decode(data),
      HelloPacket.type => HelloPacket._decode(bytes),
      StartPacket.type => StartPacket._decode(bytes),
      PingPacket.type => PingPacket._decode(data),
      QuitPacket.type => const QuitPacket(),
      final t => throw FormatException('Unknown packet type $t'),
    };
  }
}

/// A run of one peer's inputs, starting at [startFrame]. Peers resend every
/// input the other side hasn't acknowledged yet, so a lost packet is covered
/// by the next one.
class InputPacket extends Packet {
  const InputPacket({
    required this.startFrame,
    required this.inputs,
    required this.ackFrame,
  });

  static const int type = 1;

  /// Most inputs in one packet (about 1 s at 60 ticks/s).
  static const int maxInputs = 64;

  final int startFrame;
  final List<int> inputs;

  /// The sender has every one of our inputs up to and including this frame
  /// (-1 = none yet).
  final int ackFrame;

  @override
  Uint8List encode() {
    final data = ByteData(1 + 4 + 4 + 1 + inputs.length * 2)
      ..setUint8(0, type)
      ..setInt32(1, startFrame)
      ..setInt32(5, ackFrame)
      ..setUint8(9, inputs.length);
    for (var i = 0; i < inputs.length; i++) {
      data.setUint16(10 + i * 2, inputs[i]);
    }
    return data.buffer.asUint8List();
  }

  static InputPacket _decode(ByteData d) {
    final count = d.getUint8(9);
    return InputPacket(
      startFrame: d.getInt32(1),
      ackFrame: d.getInt32(5),
      inputs: [for (var i = 0; i < count; i++) d.getUint16(10 + i * 2)],
    );
  }
}

/// The checksum of the sender's state at a frame both sides have confirmed.
/// A mismatch means the two games drifted apart (a desync).
class ChecksumPacket extends Packet {
  const ChecksumPacket({required this.frame, required this.checksum});

  static const int type = 2;

  final int frame;
  final int checksum;

  @override
  Uint8List encode() =>
      (ByteData(9)
            ..setUint8(0, type)
            ..setInt32(1, frame)
            ..setUint32(5, checksum))
          .buffer
          .asUint8List();

  static ChecksumPacket _decode(ByteData d) =>
      ChecksumPacket(frame: d.getInt32(1), checksum: d.getUint32(5));
}

sealed class _JsonPacket extends Packet {
  const _JsonPacket();

  int get packetType;
  Map<String, Object?> toJson();

  @override
  Uint8List encode() {
    final body = utf8.encode(jsonEncode(toJson()));
    return Uint8List(body.length + 1)
      ..[0] = packetType
      ..setRange(1, body.length + 1, body);
  }

  static Map<String, dynamic> body(Uint8List bytes) =>
      jsonDecode(utf8.decode(bytes.sublist(1))) as Map<String, dynamic>;
}

/// First message from each side: who I am and what I picked.
class HelloPacket extends _JsonPacket {
  const HelloPacket({
    required this.fighterId,
    required this.skinId,
    this.rules = 0,
    this.version = Packet.protocolVersion,
  });

  /// Fingerprint of the game rules and fighter data (see
  /// rules_fingerprint.dart). Must match, or the match would desync.
  final int rules;

  static const int type = 3;

  final int version;
  final String fighterId;
  final String skinId;

  @override
  int get packetType => type;

  @override
  Map<String, Object?> toJson() => {
    'version': version,
    'fighter': fighterId,
    'skin': skinId,
    'rules': rules,
  };

  static HelloPacket _decode(Uint8List bytes) {
    final j = _JsonPacket.body(bytes);
    return HelloPacket(
      version: j['version'] as int,
      fighterId: j['fighter'] as String,
      skinId: j['skin'] as String,
      rules: j['rules'] as int? ?? 0,
    );
  }
}

/// Sent by the host once both sides said hello: the match settings. The
/// host is slot 0, the guest slot 1.
class StartPacket extends _JsonPacket {
  const StartPacket({
    required this.seed,
    required this.fighterIds,
    required this.skinIds,
    required this.paletteId,
  });

  static const int type = 4;

  final int seed;
  final List<String> fighterIds;
  final List<String> skinIds;
  final String paletteId;

  @override
  int get packetType => type;

  @override
  Map<String, Object?> toJson() => {
    'seed': seed,
    'fighters': fighterIds,
    'skins': skinIds,
    'palette': paletteId,
  };

  static StartPacket _decode(Uint8List bytes) {
    final j = _JsonPacket.body(bytes);
    return StartPacket(
      seed: j['seed'] as int,
      fighterIds: [for (final f in j['fighters'] as List) f as String],
      skinIds: [for (final s in j['skins'] as List) s as String],
      paletteId: j['palette'] as String,
    );
  }
}

/// Round-trip time measurement. [reply] = false asks, true answers.
class PingPacket extends Packet {
  const PingPacket({required this.id, required this.reply});

  static const int type = 5;

  final int id;
  final bool reply;

  @override
  Uint8List encode() =>
      (ByteData(6)
            ..setUint8(0, type)
            ..setInt32(1, id)
            ..setUint8(5, reply ? 1 : 0))
          .buffer
          .asUint8List();

  static PingPacket _decode(ByteData d) =>
      PingPacket(id: d.getInt32(1), reply: d.getUint8(5) == 1);
}

/// The other player left.
class QuitPacket extends Packet {
  const QuitPacket();

  static const int type = 6;

  @override
  Uint8List encode() => Uint8List.fromList([type]);
}
