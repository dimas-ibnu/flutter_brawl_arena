import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Firebase settings come from `--dart-define`s, never from files in git.
///
/// Locally: `flutter run --dart-define-from-file=firebase.env.json`
/// (the file is git-ignored; copy firebase.env.example.json).
/// In CI: the same JSON is stored as a GitHub secret and written to
/// firebase.env.json before building (see README_ONLINE.md).
///
/// When the values are missing, [firebaseOptions] is null and the game runs
/// with online play turned off.
abstract final class FirebaseEnv {
  static const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
  static const messagingSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const storageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
  );
  static const androidApiKey = String.fromEnvironment(
    'FIREBASE_ANDROID_API_KEY',
  );
  static const androidAppId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
  static const appleApiKey = String.fromEnvironment('FIREBASE_APPLE_API_KEY');
  static const appleAppId = String.fromEnvironment('FIREBASE_APPLE_APP_ID');
  static const appleBundleId = String.fromEnvironment(
    'FIREBASE_APPLE_BUNDLE_ID',
  );
}

/// Options for the current platform, or null when not configured.
FirebaseOptions? get firebaseOptions => optionsFor(defaultTargetPlatform);

FirebaseOptions? optionsFor(
  TargetPlatform platform, {
  String projectId = FirebaseEnv.projectId,
  String senderId = FirebaseEnv.messagingSenderId,
  String bucket = FirebaseEnv.storageBucket,
  String androidApiKey = FirebaseEnv.androidApiKey,
  String androidAppId = FirebaseEnv.androidAppId,
  String appleApiKey = FirebaseEnv.appleApiKey,
  String appleAppId = FirebaseEnv.appleAppId,
  String appleBundleId = FirebaseEnv.appleBundleId,
}) {
  final (apiKey, appId) = switch (platform) {
    TargetPlatform.android => (androidApiKey, androidAppId),
    TargetPlatform.iOS || TargetPlatform.macOS => (appleApiKey, appleAppId),
    _ => ('', ''),
  };
  if (projectId.isEmpty ||
      senderId.isEmpty ||
      apiKey.isEmpty ||
      appId.isEmpty) {
    return null;
  }
  final apple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  return FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: senderId,
    projectId: projectId,
    storageBucket: bucket.isEmpty ? null : bucket,
    iosBundleId: apple && appleBundleId.isNotEmpty ? appleBundleId : null,
  );
}
