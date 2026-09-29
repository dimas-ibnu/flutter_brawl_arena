import 'dart:async';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/cosmetics_store.dart';
import '../data/roster.dart';
import '../game/sounds.dart';
import '../net/lobby.dart';
import '../net/matchmaking.dart';
import '../net/net_match.dart';
import '../net/online_service.dart';
import '../net/protocol.dart';
import '../net/rollback_session.dart';
import '../net/signaling.dart';
import '../net/transport.dart';
import '../net/webrtc_transport.dart';
import '../sim/defs.dart';
import '../sim/match_simulation.dart';
import '../sim/rules_fingerprint.dart';
import 'game_screen.dart';
import 'theme.dart';

/// Host a room (share the code) or join one, then agree on the match and
/// start it. The host is slot 0, the guest slot 1.
class OnlineLobbyScreen extends StatefulWidget {
  const OnlineLobbyScreen({
    super.key,
    required this.service,
    required this.player,
    required this.roster,
    required this.cosmetics,
    required this.sounds,
    required this.showTouchControls,
  });

  final OnlineService service;
  final RosterEntry player;
  final List<RosterEntry> roster;
  final CosmeticsStore cosmetics;
  final GameSounds sounds;
  final bool showTouchControls;

  @override
  State<OnlineLobbyScreen> createState() => _OnlineLobbyScreenState();
}

enum _Phase { choose, searching, hosting, joining, handshake, failed }

class _OnlineLobbyScreenState extends State<OnlineLobbyScreen> {
  _Phase _phase = _Phase.choose;
  String? _roomCode;
  String _status = '';
  final _codeField = TextEditingController();
  Timer? _timer;
  Transport? _transport;
  bool _started = false;

  @override
  void dispose() {
    _cancelSearch = true;
    _stopHosting();
    _timer?.cancel();
    if (!_started) _transport?.close();
    _codeField.dispose();
    super.dispose();
  }

  void _fail(Object error) {
    debugPrint('Online error: $error');
    if (!mounted) return;
    setState(() {
      _phase = _Phase.failed;
      _status = friendlyOnlineError(error);
    });
  }

  bool _cancelSearch = false;
  Duration _waited = Duration.zero;

  /// Quick match: queue up and play whoever else is waiting.
  Future<void> _quickMatch() async {
    _cancelSearch = false;
    setState(() {
      _phase = _Phase.searching;
      _waited = Duration.zero;
      _status = 'Looking for an opponent…';
    });
    try {
      final (transport, isHost) = await widget.service.quickMatch(
        cancelled: () => _cancelSearch,
        onWaiting: (d) {
          if (mounted) setState(() => _waited = d);
        },
        onFound: () {
          if (mounted) setState(() => _status = 'Opponent found! Connecting…');
        },
      );
      _handshake(transport, isHost: isHost);
    } on MatchmakingCancelled {
      if (mounted) {
        setState(() {
          _phase = _Phase.choose;
          _status = '';
        });
      }
    } catch (e) {
      _fail(e);
    }
  }

  /// Completed to close a room nobody has joined yet.
  Completer<void>? _hostCancel;

  void _stopHosting() {
    final c = _hostCancel;
    if (c != null && !c.isCompleted) c.complete();
  }

  Future<void> _host() async {
    final cancel = _hostCancel = Completer<void>();
    setState(() {
      _phase = _Phase.hosting;
      _status = 'Creating a room…';
    });
    try {
      final t = await widget.service.host(
        cancel: cancel.future,
        onCode: (code) {
          if (!mounted) return;
          setState(() {
            _roomCode = code;
            _status = 'Waiting for the other player to join…';
          });
        },
      );
      _handshake(t, isHost: true);
    } on ConnectCancelled {
      if (mounted) {
        setState(() {
          _phase = _Phase.choose;
          _status = '';
          _roomCode = null;
        });
      }
    } catch (e) {
      _fail(e);
    }
  }

  Future<void> _join() async {
    final code = _codeField.text.trim().toUpperCase();
    if (code.length != 5) {
      setState(() => _status = 'Room codes have 5 letters');
      return;
    }
    setState(() {
      _phase = _Phase.joining;
      _status = 'Joining room $code…';
    });
    try {
      final t = await widget.service.join(code);
      _handshake(t, isHost: false);
    } catch (e) {
      _fail(e);
    }
  }

  void _handshake(Transport transport, {required bool isHost}) {
    if (!mounted) {
      transport.close();
      return;
    }
    _transport = transport;
    setState(() {
      _phase = _Phase.handshake;
      _status = 'Connected! Getting ready…';
    });
    final mySkin = widget.cosmetics.equippedSkin(widget.player.id);
    final lobby = LobbyHandshake(
      transport: transport,
      isHost: isHost,
      hello: HelloPacket(
        fighterId: widget.player.id,
        skinId: mySkin.id,
        rules: rulesFingerprint(
          MatchSimulation(
            stage: StageDef.flatArena,
            fighterDefs: [for (final e in widget.roster) e.def],
          ),
          [for (final e in widget.roster) e.def],
        ),
      ),
      makeStart: (guest) => StartPacket(
        seed: math.Random().nextInt(1 << 31) + 1,
        fighterIds: [widget.player.id, guest.fighterId],
        skinIds: [mySkin.id, guest.skinId],
        paletteId: widget.cosmetics.equippedPalette.id,
      ),
    );
    var waited = 0;
    _timer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      lobby.tick();
      if (lobby.error != null) {
        timer.cancel();
        _fail(lobby.error!);
      } else if (lobby.start != null) {
        timer.cancel();
        _startMatch(transport, lobby.start!, isHost: isHost);
      } else if (++waited > 20 * 60) {
        timer.cancel();
        _fail('the other player did not answer');
      }
    });
  }

  RosterEntry _entry(String id) => widget.roster.firstWhere(
    (e) => e.id == id,
    orElse: () => throw StateError('Unknown fighter "$id"'),
  );

  void _startMatch(
    Transport transport,
    StartPacket start, {
    required bool isHost,
  }) {
    final localSlot = isHost ? 0 : 1;
    final RosterEntry host;
    final RosterEntry guest;
    try {
      host = _entry(start.fighterIds[0]);
      guest = _entry(start.fighterIds[1]);
    } catch (e) {
      _fail(e);
      return;
    }
    final sim = MatchSimulation(
      stage: StageDef.flatArena,
      fighterDefs: [host.def, guest.def],
    );
    final match = NetMatch(
      session: RollbackSession(
        sim: sim,
        seed: start.seed,
        localSlot: localSlot,
      ),
      transport: transport,
      resendUntilHeard: isHost ? start : null,
    );
    final catalog = widget.cosmetics.catalog;
    final me = isHost ? host : guest;
    final them = isHost ? guest : host;
    _started = true;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(
          player: me,
          opponent: them,
          seed: start.seed,
          sounds: widget.sounds,
          showTouchControls: widget.showTouchControls,
          playerSkin: catalog.skin(me.id, start.skinIds[localSlot]),
          opponentSkin: catalog.skin(them.id, start.skinIds[1 - localSlot]),
          palette: catalog.palette(start.paletteId),
          localSlot: localSlot,
          online: match,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.arrow_back),
                      ),
                      Expanded(
                        child: Text(
                          'Play online as ${widget.player.name}',
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ..._body(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _body() {
    switch (_phase) {
      case _Phase.choose:
        return [
          FilledButton.icon(
            key: const Key('quick-match'),
            onPressed: _quickMatch,
            icon: const Icon(Icons.bolt),
            label: const Text('Quick match'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Play the next person who is searching',
            style: TextStyle(color: BrawlColors.muted),
          ),
          const SizedBox(height: 20),
          const Divider(),
          const Text(
            'Play with a friend',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('host'),
            onPressed: _host,
            icon: const Icon(Icons.add),
            label: const Text('Host a private room'),
          ),
          const SizedBox(height: 12),
          const Text(
            'or join with a code',
            style: TextStyle(color: BrawlColors.muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('code'),
                  controller: _codeField,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 5,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp('[a-zA-Z]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Room code',
                    counterText: '',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _join(),
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                key: const Key('join'),
                onPressed: _join,
                child: const Text('Join'),
              ),
            ],
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(_status, style: const TextStyle(color: BrawlColors.muted)),
          ],
        ];
      case _Phase.searching:
        final secs = _waited.inSeconds;
        return [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            '${secs ~/ 60}:${(secs % 60).toString().padLeft(2, '0')}',
            key: const Key('search-time'),
            style: const TextStyle(color: BrawlColors.muted),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            key: const Key('cancel-search'),
            onPressed: () {
              _cancelSearch = true;
              setState(() => _status = 'Cancelling…');
            },
            child: const Text('Cancel'),
          ),
        ];
      case _Phase.hosting || _Phase.joining || _Phase.handshake:
        return [
          if (_roomCode != null && _phase == _Phase.hosting) ...[
            const Text('Room code', style: TextStyle(color: BrawlColors.muted)),
            SelectableText(
              _roomCode!,
              key: const Key('room-code'),
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.w900,
                letterSpacing: 10,
                color: BrawlColors.accent,
              ),
            ),
            TextButton.icon(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: _roomCode!)),
              icon: const Icon(Icons.copy),
              label: const Text('Copy'),
            ),
            const SizedBox(height: 12),
          ],
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(_status, textAlign: TextAlign.center),
          if (_phase == _Phase.hosting) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('cancel-host'),
              onPressed: _stopHosting,
              child: const Text('Cancel'),
            ),
          ],
        ];
      case _Phase.failed:
        return [
          const Icon(Icons.wifi_off, size: 40),
          const SizedBox(height: 8),
          Text(_status, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => setState(() {
              _phase = _Phase.choose;
              _status = '';
              _roomCode = null;
            }),
            child: const Text('Try again'),
          ),
        ];
    }
  }
}

/// Short, readable text for online errors (the full error goes to the log).
String friendlyOnlineError(Object error) {
  if (error is RoomNotFound || error is RoomFull) return error.toString();
  if (error is String) return 'Could not connect: $error';
  if (error is FirebaseException) {
    final auth = error.plugin == 'firebase_auth';
    return switch (error.code) {
      'operation-not-allowed' ||
      'admin-restricted-operation' ||
      'internal-error' when auth =>
        'Online sign-in is off. In the Firebase console, enable '
            'Authentication > Sign-in method > Anonymous.',
      'network-request-failed' || 'unavailable' =>
        'No internet connection. Check your network and try again.',
      'permission-denied' =>
        'The database refused the request. Publish firestore.rules in the '
            'Firebase console (Firestore > Rules).',
      'not-found' || 'failed-precondition' =>
        'The online database is not set up. Create the Firestore database '
            'in the Firebase console.',
      _ => 'Could not connect (${error.code}). Try again in a moment.',
    };
  }
  if (error is TimeoutException) {
    return 'The other player could not be reached. Try again, or check '
        'that both of you are online.';
  }
  return 'Could not connect. Try again in a moment.';
}
