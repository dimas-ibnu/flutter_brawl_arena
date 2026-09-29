import 'dart:async';

import 'package:brawl_arena/net/signaling.dart';
import 'package:brawl_arena/ui/online_lobby_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('anonymous sign-in turned off points to the console setting', () {
    final e = FirebaseException(
      plugin: 'firebase_auth',
      code: 'internal-error',
    );
    expect(friendlyOnlineError(e), contains('Anonymous'));
  });

  test('database problems point to Firestore', () {
    expect(
      friendlyOnlineError(
        FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'),
      ),
      contains('firestore.rules'),
    );
    expect(
      friendlyOnlineError(
        FirebaseException(plugin: 'cloud_firestore', code: 'not-found'),
      ),
      contains('Create the Firestore database'),
    );
  });

  test('room, network and timeout errors read clearly', () {
    expect(friendlyOnlineError(RoomNotFound('ABCDE')), contains('ABCDE'));
    expect(
      friendlyOnlineError(
        FirebaseException(
          plugin: 'firebase_auth',
          code: 'network-request-failed',
        ),
      ),
      contains('internet'),
    );
    expect(friendlyOnlineError(TimeoutException('x')), contains('reached'));
    expect(friendlyOnlineError(Exception('boom')), isNot(contains('boom')));
  });
}
