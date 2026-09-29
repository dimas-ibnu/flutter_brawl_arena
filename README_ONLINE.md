# Online play setup

Online matches use **rollback netcode** over a **WebRTC** data channel
(peer to peer). **Firebase** is only used to sign in anonymously and to swap
connection details through a 5-letter room code.

Until Firebase is set up, the game runs normally and **Play Online** shows a
"not set up" message.

## 1. Create the Firebase project (once)

1. Go to <https://console.firebase.google.com> and create a project.
2. **Build > Authentication > Get started > Sign-in method**: enable
   **Anonymous**.
3. **Build > Firestore Database > Create database** (production mode, any
   region close to your players).
4. **Firestore > Rules**: paste the contents of [`firestore.rules`](firestore.rules)
   and publish.
5. Optional but recommended: **Firestore > TTL policies**, add a policy on
   field `expireAt` for collection group `rooms` and another for
   collection group `messages`. Old rooms then delete themselves.

## 2. Connect this app to the project

```bash
npm install -g firebase-tools
dart pub global activate flutterfire_cli
firebase login
flutterfire configure
```

In `flutterfire configure`, pick your project and the platforms `android`,
`ios` and `macos`. It adds `google-services.json` /
`GoogleService-Info.plist` and `lib/firebase_options.dart`.

Then rebuild the app (`flutter run`).

> If Firebase still fails to start on a platform, pass the generated options
> explicitly in `lib/net/online_service.dart`:
> `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`.

## 3. Play

1. Both players: **Play Online**, pick a fighter.
2. One player: **Host a room**, share the code.
3. The other: type the code, **Join**.

The host is player 1 (left panel), the guest player 2. Skins and the host's
stage palette carry over.

## Good to know

- **Lag**: inputs apply 2 frames late, and the game predicts the opponent
  up to 8 frames ahead, rolling back when it guessed wrong. Above about
  150 ms ping the game starts to stutter while it waits.
- **Strict networks**: the free Google STUN servers work on most home
  networks. Some mobile or office networks need a TURN relay; add one to
  `WebRtcTransport.iceServers` (e.g. a hosted TURN service or `coturn`).
- **Desync**: both sides compare a checksum every second. If they ever
  differ the match shows "Out of sync". That would be a bug; please report it
  with the seed.
- Online matches can't pause (the menu opens but the match keeps running)
  and can't restart; leave and host a new room.
