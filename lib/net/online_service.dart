import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'firebase_env.dart';

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
