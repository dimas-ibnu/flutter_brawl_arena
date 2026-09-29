import 'dart:async';

/// One player waiting in the quick-match queue.
class QueueTicket {
  const QueueTicket({
    required this.id,
    required this.ownerId,
    required this.createdAt,
    required this.lastSeen,
    required this.state,
    this.room,
  });

  final String id;
  final String ownerId;
  final DateTime createdAt;

  /// Refreshed by the owner every few seconds; old tickets are ignored.
  final DateTime lastSeen;

  /// 'waiting', 'matched' (someone claimed it; [room] says where to go) or
  /// 'hosting' (the owner claimed someone else).
  final String state;
  final String? room;

  /// Queue order: older first, ids break ties so every client agrees.
  bool isOlderThan(QueueTicket other) =>
      createdAt.isBefore(other.createdAt) ||
      (createdAt == other.createdAt && id.compareTo(other.id) < 0);
}

/// Storage for the queue. Firestore in the app (firestore_queue.dart),
/// [MemoryQueue] in tests.
abstract class MatchmakingQueue {
  Future<QueueTicket> enqueue(String ownerId);
  Future<QueueTicket?> get(String id);
  Future<List<QueueTicket>> waiting();

  /// Atomically: if both tickets are still waiting, mark [candidateId]
  /// matched with [room] and [ownId] hosting. Returns false otherwise.
  Future<bool> claim({
    required String candidateId,
    required String ownId,
    required String room,
  });

  Future<void> heartbeat(String id);
  Future<void> remove(String id);
}

/// Result of a quick match: which room to use and whether we host it.
class Pairing<R> {
  const Pairing.host(R this.hostRoom, this.roomCode) : isHost = true;
  const Pairing.guest(this.roomCode) : isHost = false, hostRoom = null;

  final bool isHost;
  final String roomCode;

  /// The host's open room (its signaling), ready for the guest to join.
  final R? hostRoom;
}

class MatchmakingCancelled implements Exception {
  @override
  String toString() => 'Search cancelled';
}

/// Pairs two players from the queue without a room code.
///
/// Everyone first joins the queue. Then, until paired, each player looks
/// for a waiting ticket OLDER than its own and claims the oldest one. Only
/// the newer player of a pair ever claims, so two players can't claim each
/// other at the same time, and the claim itself is one transaction. The
/// claimer hosts a room; the claimed player joins it as the guest.
class Matchmaker<R> {
  Matchmaker({
    required this.queue,
    required this.ownerId,
    required this.createRoom,
    required this.roomCode,
    required this.discardRoom,
    this.pollEvery = const Duration(seconds: 2),
    this.staleAfter = const Duration(seconds: 45),
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final MatchmakingQueue queue;
  final String ownerId;

  /// Host side: opens a room (e.g. Firestore signaling) before claiming.
  final Future<R> Function() createRoom;
  final String Function(R room) roomCode;
  final Future<void> Function(R room) discardRoom;

  final Duration pollEvery;
  final Duration staleAfter;
  final DateTime Function() _now;

  /// Searches until paired or [cancelled] returns true (then throws
  /// [MatchmakingCancelled]). [onWaiting] gets the time spent so far.
  Future<Pairing<R>> find({
    required bool Function() cancelled,
    void Function(Duration waited)? onWaiting,
  }) async {
    final started = _now();
    var mine = await queue.enqueue(ownerId);
    try {
      while (true) {
        if (cancelled()) throw MatchmakingCancelled();

        // Someone claimed us: join their room.
        final current = await queue.get(mine.id);
        if (current == null) {
          mine = await queue.enqueue(ownerId); // expired; queue again
          continue;
        }
        if (current.state == 'matched' && current.room != null) {
          return Pairing.guest(current.room!);
        }
        mine = current;

        final pairing = await _tryClaimOlder(mine);
        if (pairing != null) return pairing;

        await queue.heartbeat(mine.id);
        onWaiting?.call(_now().difference(started));
        await Future<void>.delayed(pollEvery);
      }
    } finally {
      await queue.remove(mine.id);
    }
  }

  Future<Pairing<R>?> _tryClaimOlder(QueueTicket mine) async {
    final now = _now();
    final older =
        (await queue.waiting())
            .where(
              (t) =>
                  t.id != mine.id &&
                  t.ownerId != ownerId &&
                  t.state == 'waiting' &&
                  now.difference(t.lastSeen) < staleAfter &&
                  t.isOlderThan(mine),
            )
            .toList()
          ..sort((a, b) => a.isOlderThan(b) ? -1 : 1);

    for (final candidate in older.take(3)) {
      final room = await createRoom();
      final claimed = await queue.claim(
        candidateId: candidate.id,
        ownId: mine.id,
        room: roomCode(room),
      );
      if (claimed) return Pairing.host(room, roomCode(room));
      await discardRoom(room);
      // Maybe we were just claimed ourselves; the main loop checks.
      final me = await queue.get(mine.id);
      if (me == null || me.state != 'waiting') return null;
    }
    return null;
  }
}

/// In-memory queue for tests (and for trying the flow without Firebase).
class MemoryQueue implements MatchmakingQueue {
  MemoryQueue({DateTime Function()? clock}) : _now = clock ?? DateTime.now;

  final DateTime Function() _now;
  final Map<String, QueueTicket> tickets = {};
  int _nextId = 0;

  @override
  Future<QueueTicket> enqueue(String ownerId) async {
    final now = _now();
    final t = QueueTicket(
      id: 't${_nextId++}',
      ownerId: ownerId,
      createdAt: now,
      lastSeen: now,
      state: 'waiting',
    );
    tickets[t.id] = t;
    return t;
  }

  @override
  Future<QueueTicket?> get(String id) async => tickets[id];

  @override
  Future<List<QueueTicket>> waiting() async => [
    for (final t in tickets.values)
      if (t.state == 'waiting') t,
  ];

  @override
  Future<bool> claim({
    required String candidateId,
    required String ownId,
    required String room,
  }) async {
    final c = tickets[candidateId];
    final me = tickets[ownId];
    if (c == null || me == null) return false;
    if (c.state != 'waiting' || me.state != 'waiting') return false;
    tickets[candidateId] = _with(c, state: 'matched', room: room);
    tickets[ownId] = _with(me, state: 'hosting');
    return true;
  }

  @override
  Future<void> heartbeat(String id) async {
    final t = tickets[id];
    if (t != null) tickets[id] = _with(t, lastSeen: _now());
  }

  @override
  Future<void> remove(String id) async => tickets.remove(id);

  static QueueTicket _with(
    QueueTicket t, {
    String? state,
    String? room,
    DateTime? lastSeen,
  }) => QueueTicket(
    id: t.id,
    ownerId: t.ownerId,
    createdAt: t.createdAt,
    lastSeen: lastSeen ?? t.lastSeen,
    state: state ?? t.state,
    room: room ?? t.room,
  );
}
