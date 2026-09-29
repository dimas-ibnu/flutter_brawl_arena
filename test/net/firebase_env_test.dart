import 'package:brawl_arena/net/firebase_env.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no settings means online stays off', () {
    // Tests run without --dart-define values.
    expect(firebaseOptions, isNull);
    expect(optionsFor(TargetPlatform.android), isNull);
  });

  FirebaseOptionsLike? build(TargetPlatform p) {
    final o = optionsFor(
      p,
      projectId: 'proj',
      senderId: '123',
      androidApiKey: 'a-key',
      androidAppId: 'a-app',
      appleApiKey: 'i-key',
      appleAppId: 'i-app',
      appleBundleId: 'com.example.app',
    );
    return o == null ? null : (o.apiKey, o.appId, o.projectId, o.iosBundleId);
  }

  test('each platform gets its own key and app id', () {
    expect(build(TargetPlatform.android), ('a-key', 'a-app', 'proj', null));
    expect(build(TargetPlatform.iOS), (
      'i-key',
      'i-app',
      'proj',
      'com.example.app',
    ));
    expect(build(TargetPlatform.macOS)?.$1, 'i-key');
  });

  test('unsupported platforms and partial settings give no options', () {
    expect(build(TargetPlatform.windows), isNull);
    expect(
      optionsFor(TargetPlatform.android, projectId: 'p', senderId: '1'),
      isNull,
    );
  });
}

typedef FirebaseOptionsLike = (String, String, String, String?);
