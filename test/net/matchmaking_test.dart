import 'package:brawl_arena/net/matchmaking.dart';
import 'package:flutter_test/flutter_test.dart';

/// A room is just its code here; the real app opens Firestore signaling.
class _Rooms {
  var created = 0;
  final discarded = <String>[];
  Future<String> create() async => 'ROOM${created++}';
}

Matchmaker<String> _player(
  MemoryQueue q,
  String id,
  _Rooms rooms, {
  DateTime Function()? clock,
}) => Matchmaker<String>(
  queue: q,
  ownerId: id,
  createRoom: rooms.create,
  roomCode: (r) => r,
  discardRoom: (r) async => rooms.discarded.add(r),
  pollEvery: const Duration(milliseconds: 5),
  clock: clock,
);

void main() {
  test('two players in the queue get paired into the same room', () async {
    final q = MemoryQueue();
    final rooms = _Rooms();
    final first = _player(q, 'alice', rooms).find(cancelled: () => false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final second = await _player(q, 'bob', rooms).find(cancelled: () => false);
    final a = await first;

    expect(second.isHost, isTrue, reason: 'the newer player claims');
    expect(a.isHost, isFalse);
    expect(a.roomCode, second.roomCode);
    expect(q.tickets, isEmpty, reason: 'tickets are cleaned up');
  });

  test(
    'players who start at the same moment still pair exactly once',
    () async {
      final q = MemoryQueue();
      final rooms = _Rooms();
      final results = await Future.wait([
        _player(q, 'alice', rooms).find(cancelled: () => false),
        _player(q, 'bob', rooms).find(cancelled: () => false),
      ]);
      expect(results.where((p) => p.isHost).length, 1);
      expect(results[0].roomCode, results[1].roomCode);
    },
  );

  test('four players make two separate pairs', () async {
    final q = MemoryQueue();
    final rooms = _Rooms();
    final results = await Future.wait([
      for (final name in ['a', 'b', 'c', 'd'])
        _player(q, name, rooms).find(cancelled: () => false),
    ]);
    final byRoom = <String, List<bool>>{};
    for (final p in results) {
      byRoom.putIfAbsent(p.roomCode, () => []).add(p.isHost);
    }
    expect(byRoom.length, 2);
    for (final pair in byRoom.values) {
      expect(pair..sort((x, y) => x ? 1 : -1), [false, true]);
    }
  });

  test('a ticket whose owner stopped responding is skipped', () async {
    var now = DateTime(2026, 1, 1, 12);
    final q = MemoryQueue(clock: () => now);
    final rooms = _Rooms();
    await q.enqueue('ghost'); // never sends a heartbeat
    now = now.add(const Duration(minutes: 2));

    var cancel = false;
    final searching = _player(
      q,
      'alice',
      rooms,
      clock: () => now,
    ).find(cancelled: () => cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(rooms.created, 0, reason: 'did not pair with the ghost');
    cancel = true;
    await expectLater(searching, throwsA(isA<MatchmakingCancelled>()));
  });

  test('cancelling leaves the queue', () async {
    final q = MemoryQueue();
    var cancel = false;
    final searching = _player(
      q,
      'alice',
      _Rooms(),
    ).find(cancelled: () => cancel);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(q.tickets, hasLength(1));
    cancel = true;
    await expectLater(searching, throwsA(isA<MatchmakingCancelled>()));
    expect(q.tickets, isEmpty);
  });

  test('you never get paired with yourself on another device', () async {
    final q = MemoryQueue();
    await q.enqueue('alice'); // alice's other session
    var cancel = false;
    final rooms = _Rooms();
    final searching = _player(q, 'alice', rooms).find(cancelled: () => cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(rooms.created, 0);
    cancel = true;
    await expectLater(searching, throwsA(isA<MatchmakingCancelled>()));
  });

  test('a failed claim throws away the room it opened', () async {
    final q = MemoryQueue();
    final rooms = _Rooms();
    final old = await q.enqueue('carol');
    // Carol gets taken by someone else right before our claim lands.
    final racing = _RacingQueue(q, steal: old.id);
    final m = Matchmaker<String>(
      queue: racing,
      ownerId: 'alice',
      createRoom: rooms.create,
      roomCode: (r) => r,
      discardRoom: (r) async => rooms.discarded.add(r),
      pollEvery: const Duration(milliseconds: 5),
    );
    var cancel = false;
    final searching = m.find(cancelled: () => cancel);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    cancel = true;
    await expectLater(searching, throwsA(isA<MatchmakingCancelled>()));
    expect(rooms.discarded, isNotEmpty);
  });
}

/// Marks [steal] as matched by someone else just before any claim.
class _RacingQueue implements MatchmakingQueue {
  _RacingQueue(this.inner, {required this.steal});

  final MemoryQueue inner;
  final String steal;

  @override
  Future<bool> claim({
    required String candidateId,
    required String ownId,
    required String room,
  }) async {
    final t = inner.tickets[steal];
    if (t != null) {
      inner.tickets[steal] = QueueTicket(
        id: t.id,
        ownerId: t.ownerId,
        createdAt: t.createdAt,
        lastSeen: t.lastSeen,
        state: 'matched',
        room: 'OTHER',
      );
    }
    return inner.claim(candidateId: candidateId, ownId: ownId, room: room);
  }

  @override
  Future<QueueTicket> enqueue(String ownerId) => inner.enqueue(ownerId);
  @override
  Future<QueueTicket?> get(String id) => inner.get(id);
  @override
  Future<List<QueueTicket>> waiting() => inner.waiting();
  @override
  Future<void> heartbeat(String id) => inner.heartbeat(id);
  @override
  Future<void> remove(String id) => inner.remove(id);
}
