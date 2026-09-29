import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_env.dart';
import 'firestore_queue.dart';
import 'matchmaking.dart';

import 'signaling.dart';
import 'transport.dart';
import 'webrtc_transport.dart';

/// Entry point for internet play: Firebase sign-in, room codes, and the
/// WebRTC connection.
class OnlineService {
  OnlineService._();

  static OnlineService? _instance;

  /// Null when Firebase failed to start (see README_ONLINE.md).
  static OnlineService? get instance => _instance;

  /// Call once at startup. Returns false (and online stays off) when this
  /// build has no Firebase settings (see firebase_env.dart).
  static Future<bool> init() async {
    final options = firebaseOptions;
    if (options == null) {
      debugPrint(
        'Online play is off: build with '
        '--dart-define-from-file=firebase.env.json',
      );
      return false;
    }
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      _instance = OnlineService._();
      return true;
    } catch (e) {
      debugPrint('Online play is off: Firebase is not configured ($e)');
      return false;
    }
  }

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// Anonymous sign-in, so the database rules can require a signed-in user.
  Future<void> _signIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
  }

  /// Creates a room. [onCode] gets the code to share; the future completes
  /// when a guest has joined and the connection is open.
  Future<Transport> host({required void Function(String code) onCode}) async {
    await _signIn();
    final signaling = await FirestoreSignaling.host(_db);
    onCode(signaling.roomCode);
    try {
      return await WebRtcTransport.connect(
        signaling: signaling,
        isHost: true,
        timeout: const Duration(minutes: 10),
      );
    } finally {
      await signaling.close();
    }
  }

  /// Quick match: waits in the queue until paired with another player, then
  /// connects. Returns the connection and whether we host (slot 0).
  /// Throws [MatchmakingCancelled] once [cancelled] returns true.
  Future<(Transport, bool)> quickMatch({
    required bool Function() cancelled,
    void Function(Duration waited)? onWaiting,
    void Function()? onFound,
  }) async {
    await _signIn();
    final matchmaker = Matchmaker<FirestoreSignaling>(
      queue: FirestoreQueue(_db),
      ownerId: FirebaseAuth.instance.currentUser!.uid,
      createRoom: () => FirestoreSignaling.host(_db),
      roomCode: (room) => room.roomCode,
      discardRoom: (room) => room.close(),
    );
    final pairing = await matchmaker.find(
      cancelled: cancelled,
      onWaiting: onWaiting,
    );
    onFound?.call();

    if (pairing.isHost) {
      final signaling = pairing.hostRoom!;
      try {
        final t = await WebRtcTransport.connect(
          signaling: signaling,
          isHost: true,
          timeout: const Duration(seconds: 25),
        );
        return (t as Transport, true);
      } finally {
        await signaling.close();
      }
    }

    // Guest: the host's room already exists; retry briefly in case our
    // read races its creation.
    for (var attempt = 0; ; attempt++) {
      try {
        return (await join(pairing.roomCode), false);
      } on RoomNotFound {
        if (attempt >= 3) rethrow;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
  }

  /// Joins the room with [code]. Throws [RoomNotFound] or [RoomFull].
  Future<Transport> join(String code) async {
    await _signIn();
    final signaling = await FirestoreSignaling.join(_db, code);
    try {
      return await WebRtcTransport.connect(signaling: signaling, isHost: false);
    } finally {
      await signaling.close();
    }
  }
}
