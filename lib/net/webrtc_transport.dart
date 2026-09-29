import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling.dart';
import 'transport.dart';

/// Game packets over a WebRTC data channel: peer to peer, through home
/// routers via STUN.
class WebRtcTransport implements Transport {
  WebRtcTransport._(this._pc, this._channel) {
    _channel.onMessage = (m) {
      if (m.isBinary) _incoming.add(m.binary);
    };
  }

  final RTCPeerConnection _pc;
  final RTCDataChannel _channel;
  final _incoming = <Uint8List>[];
  bool _closed = false;

  /// Public STUN servers let the two peers find each other's address.
  /// Players behind strict networks may also need a TURN relay (see the
  /// PRD, "Relay (TURN)").
  static const iceServers = {
    'iceServers': [
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ],
  };

  /// Unordered, and packets older than 150 ms are dropped instead of
  /// resent: the rollback layer resends inputs itself and only wants fresh
  /// data.
  static RTCDataChannelInit get _channelConfig => RTCDataChannelInit()
    ..ordered = false
    ..maxRetransmitTime = 150
    ..binaryType = 'binary';

  /// Connects to the other peer, exchanging setup messages over
  /// [signaling]. The host makes the offer; the guest answers.
  static Future<WebRtcTransport> connect({
    required Signaling signaling,
    required bool isHost,
    Duration timeout = const Duration(seconds: 30),
    Future<void>? cancel,
  }) async {
    final pc = await createPeerConnection(iceServers);
    final opened = Completer<RTCDataChannel>();

    void watch(RTCDataChannel ch) {
      if (ch.state == RTCDataChannelState.RTCDataChannelOpen &&
          !opened.isCompleted) {
        opened.complete(ch);
      }
      ch.onDataChannelState = (state) {
        if (state == RTCDataChannelState.RTCDataChannelOpen &&
            !opened.isCompleted) {
          opened.complete(ch);
        }
      };
    }

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      signaling.send(
        SignalMessage('candidate', {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        }),
      );
    };
    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed &&
          !opened.isCompleted) {
        opened.completeError(
          StateError('Could not connect to the other player'),
        );
      }
    };

    // Candidates can arrive before the remote description; hold them.
    final pending = <RTCIceCandidate>[];
    var haveRemote = false;
    final sub = signaling.messages.listen((m) async {
      switch (m.kind) {
        case 'offer' when !isHost:
          await pc.setRemoteDescription(
            RTCSessionDescription(m.data['sdp'] as String, 'offer'),
          );
          haveRemote = true;
          for (final c in pending) {
            await pc.addCandidate(c);
          }
          pending.clear();
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          await signaling.send(SignalMessage('answer', {'sdp': answer.sdp}));
        case 'answer' when isHost:
          await pc.setRemoteDescription(
            RTCSessionDescription(m.data['sdp'] as String, 'answer'),
          );
          haveRemote = true;
          for (final c in pending) {
            await pc.addCandidate(c);
          }
          pending.clear();
        case 'candidate':
          final c = RTCIceCandidate(
            m.data['candidate'] as String?,
            m.data['sdpMid'] as String?,
            m.data['sdpMLineIndex'] as int?,
          );
          haveRemote ? await pc.addCandidate(c) : pending.add(c);
      }
    });

    try {
      if (isHost) {
        watch(await pc.createDataChannel('game', _channelConfig));
        final offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await signaling.send(SignalMessage('offer', {'sdp': offer.sdp}));
      } else {
        pc.onDataChannel = watch;
      }
      final channel = await Future.any([
        opened.future,
        if (cancel != null)
          cancel.then<RTCDataChannel>((_) => throw ConnectCancelled()),
      ]).timeout(timeout);
      return WebRtcTransport._(pc, channel);
    } catch (_) {
      await pc.close();
      rethrow;
    } finally {
      await sub.cancel();
    }
  }

  @override
  void send(Uint8List packet) {
    if (_closed || _channel.state != RTCDataChannelState.RTCDataChannelOpen) {
      return;
    }
    _channel.send(RTCDataChannelMessage.fromBinary(packet));
  }

  @override
  List<Uint8List> poll() {
    if (_incoming.isEmpty) return const [];
    final out = List<Uint8List>.of(_incoming);
    _incoming.clear();
    return out;
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    // Let a final packet (e.g. "quit") go out before closing.
    Future<void>.delayed(const Duration(milliseconds: 200), () async {
      await _channel.close();
      await _pc.close();
    });
  }
}

/// The player left before the other side connected.
class ConnectCancelled implements Exception {
  @override
  String toString() => 'Cancelled';
}
