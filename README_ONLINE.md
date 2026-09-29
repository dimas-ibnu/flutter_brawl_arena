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
   field `expireAt` for collection groups `rooms`, `messages` and
   `queue`. Old rooms and abandoned queue tickets then delete themselves.

## 2. Give the app its Firebase settings

The Firebase config is **never committed**. The app reads it from
`--dart-define` values; without them it builds and runs with online off.

**Locally**: copy the template and fill in the values from the Firebase
console (Project settings > Your apps), or from a one-off
`flutterfire configure` run:

```bash
cp firebase.env.example.json firebase.env.json
```

`firebase.env.json` is git-ignored. Run or build with it:

```bash
flutter run --dart-define-from-file=firebase.env.json
```

| Key | Where to find it |
| --- | --- |
| `FIREBASE_PROJECT_ID` | Project settings > General |
| `FIREBASE_MESSAGING_SENDER_ID` | Project settings > Cloud Messaging (Sender ID) |
| `FIREBASE_STORAGE_BUCKET` | Project settings > General (optional) |
| `FIREBASE_ANDROID_API_KEY`, `FIREBASE_ANDROID_APP_ID` | Android app in Project settings |
| `FIREBASE_APPLE_API_KEY`, `FIREBASE_APPLE_APP_ID`, `FIREBASE_APPLE_BUNDLE_ID` | iOS app in Project settings (macOS uses the same) |
| `FIREBASE_WEB_API_KEY`, `FIREBASE_WEB_APP_ID`, `FIREBASE_WEB_AUTH_DOMAIN` | Web app in Project settings |

**In GitHub Actions**: save the whole `firebase.env.json` content as a
repository secret named `FIREBASE_ENV_JSON`, then:

```yaml
- name: Firebase settings
  run: echo '${{ secrets.FIREBASE_ENV_JSON }}' > firebase.env.json
- name: Build
  run: flutter build apk --release --dart-define-from-file=firebase.env.json
```

> These keys only identify the Firebase project; what protects the data is
> `firestore.rules`. Keeping them out of git is still good hygiene.

## 3. Play

1. Both players: **Play Online**, pick a fighter.
2. **Quick match**: tap it and wait; you are paired with the next player
   who is also searching (no code needed). The one who joined the queue
   later hosts.
3. **Private game**: one player taps **Host a private room** and shares the
   code; the other types it and taps **Join**.

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
