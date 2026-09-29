import 'package:cloud_firestore/cloud_firestore.dart';

import 'matchmaking.dart';

/// The quick-match queue in Firestore: `queue/{ticketId}` holds
/// `{owner, state, room?, createdAt, lastSeen, expireAt}`.
///
/// No composite index is needed: [waiting] filters on `state` only and the
/// matchmaker sorts on the client.
class FirestoreQueue implements MatchmakingQueue {
  FirestoreQueue(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _queue =>
      _db.collection('queue');

  static Timestamp _expiry() =>
      Timestamp.fromDate(DateTime.now().add(const Duration(minutes: 10)));

  static QueueTicket _ticket(DocumentSnapshot<Map<String, dynamic>> d) {
    final j = d.data()!;
    return QueueTicket(
      id: d.id,
      ownerId: j['owner'] as String,
      createdAt: (j['createdAt'] as Timestamp).toDate(),
      lastSeen: (j['lastSeen'] as Timestamp).toDate(),
      state: j['state'] as String,
      room: j['room'] as String?,
    );
  }

  @override
  Future<QueueTicket> enqueue(String ownerId) async {
    final now = Timestamp.now();
    final ref = await _queue.add({
      'owner': ownerId,
      'state': 'waiting',
      'createdAt': now,
      'lastSeen': now,
      'expireAt': _expiry(),
    });
    return _ticket(await ref.get());
  }

  @override
  Future<QueueTicket?> get(String id) async {
    final d = await _queue.doc(id).get();
    return d.exists ? _ticket(d) : null;
  }

  @override
  Future<List<QueueTicket>> waiting() async {
    final snap = await _queue
        .where('state', isEqualTo: 'waiting')
        .limit(25)
        .get();
    return [for (final d in snap.docs) _ticket(d)];
  }

  @override
  Future<bool> claim({
    required String candidateId,
    required String ownId,
    required String room,
  }) async {
    try {
      return await _db.runTransaction((tx) async {
        final candidate = await tx.get(_queue.doc(candidateId));
        final own = await tx.get(_queue.doc(ownId));
        if (!candidate.exists || !own.exists) return false;
        if (candidate.data()!['state'] != 'waiting' ||
            own.data()!['state'] != 'waiting') {
          return false;
        }
        tx.update(candidate.reference, {'state': 'matched', 'room': room});
        tx.update(own.reference, {'state': 'hosting'});
        return true;
      });
    } on FirebaseException {
      return false; // lost a race; the matchmaker tries again
    }
  }

  @override
  Future<void> heartbeat(String id) async {
    try {
      await _queue.doc(id).update({
        'lastSeen': Timestamp.now(),
        'expireAt': _expiry(),
      });
    } on FirebaseException {
      // Ticket gone (claimed and removed, or expired): the loop re-checks.
    }
  }

  @override
  Future<void> remove(String id) async {
    try {
      await _queue.doc(id).delete();
    } on FirebaseException {
      // Already gone.
    }
  }
}
