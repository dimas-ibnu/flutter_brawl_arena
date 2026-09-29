import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

/// One connection-setup message (WebRTC offer, answer or network candidate)
/// from one side of a room to the other.
class SignalMessage {
  const SignalMessage(this.kind, this.data);

  /// 'offer', 'answer' or 'candidate'.
  final String kind;
  final Map<String, dynamic> data;
}

/// Carries [SignalMessage]s between host and guest until WebRTC connects.
/// After that, all game traffic goes peer to peer.
abstract class Signaling {
  String get roomCode;
  Stream<SignalMessage> get messages;
  Future<void> send(SignalMessage message);
  Future<void> close();
}

/// Room codes: 5 letters without look-alikes (no I, O, 0, 1).
String newRoomCode([math.Random? rng]) {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  final r = rng ?? math.Random.secure();
  return List.generate(5, (_) => letters[r.nextInt(letters.length)]).join();
}

/// Signaling through Firestore (PRD: Firebase for matchmaking and
/// signaling).
///
/// Layout: `rooms/{code}` holds `{state: 'open' | 'full', createdAt}`;
/// `rooms/{code}/messages` holds `{from: 'host' | 'guest', kind, data,
/// at}`. Each side listens to the other side's messages.
class FirestoreSignaling implements Signaling {
  FirestoreSignaling._(this._db, this.roomCode, this._isHost) {
    _sub = _room
        .collection('messages')
        .where('from', isEqualTo: _isHost ? 'guest' : 'host')
        .snapshots()
        .listen((snap) {
          for (final change in snap.docChanges) {
            if (change.type != DocumentChangeType.added) continue;
            final d = change.doc.data();
            if (d == null) continue;
            _messages.add(
              SignalMessage(
                d['kind'] as String,
                Map<String, dynamic>.from(d['data'] as Map),
              ),
            );
          }
        }, onError: _messages.addError);
  }

  final FirebaseFirestore _db;
  final bool _isHost;
  late final StreamSubscription<QuerySnapshot<Map<String, dynamic>>> _sub;
  final _messages = StreamController<SignalMessage>.broadcast();

  @override
  final String roomCode;

  DocumentReference<Map<String, dynamic>> get _room =>
      _db.collection('rooms').doc(roomCode);

  /// Creates a new open room with a fresh code.
  static Future<FirestoreSignaling> host(FirebaseFirestore db) async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = newRoomCode();
      final ref = db.collection('rooms').doc(code);
      final created = await db.runTransaction((tx) async {
        final existing = await tx.get(ref);
        if (existing.exists) return false;
        tx.set(ref, {
          'state': 'open',
          'createdAt': FieldValue.serverTimestamp(),
          'expireAt': _expiry(),
        });
        return true;
      });
      if (created) return FirestoreSignaling._(db, code, true);
    }
    throw StateError('Could not create a room, try again');
  }

  /// Joins an open room. Throws [RoomNotFound] or [RoomFull].
  static Future<FirestoreSignaling> join(
    FirebaseFirestore db,
    String code,
  ) async {
    final ref = db.collection('rooms').doc(code.toUpperCase());
    await db.runTransaction((tx) async {
      final room = await tx.get(ref);
      if (!room.exists) throw RoomNotFound(code);
      if (room.data()?['state'] != 'open') throw RoomFull(code);
      tx.update(ref, {'state': 'full'});
    });
    return FirestoreSignaling._(db, code.toUpperCase(), false);
  }

  @override
  Stream<SignalMessage> get messages => _messages.stream;

  @override
  Future<void> send(SignalMessage m) => _room.collection('messages').add({
    'from': _isHost ? 'host' : 'guest',
    'kind': m.kind,
    'data': m.data,
    'at': FieldValue.serverTimestamp(),
    'expireAt': _expiry(),
  });

  @override
  Future<void> close() async {
    await _sub.cancel();
    await _messages.close();
    // The host removes the room once the players are connected or gone.
    if (_isHost) {
      try {
        await _room.delete();
      } catch (_) {
        // Already gone or offline; rooms also expire (see firestore.rules).
      }
    }
  }
}

/// Rooms and their messages are deleted automatically an hour later by a
/// Firestore TTL policy on `expireAt` (see README_ONLINE.md).
Timestamp _expiry() =>
    Timestamp.fromDate(DateTime.now().add(const Duration(hours: 1)));

class RoomNotFound implements Exception {
  RoomNotFound(this.code);
  final String code;
  @override
  String toString() => 'No room with code $code';
}

class RoomFull implements Exception {
  RoomFull(this.code);
  final String code;
  @override
  String toString() => 'Room $code already has two players';
}
