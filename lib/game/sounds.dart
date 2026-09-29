import 'package:flame_audio/flame_audio.dart';
import 'package:flutter/foundation.dart';

enum Sfx {
  hitLight('hit_light.wav'),
  hitHeavy('hit_heavy.wav'),
  ko('ko.wav'),
  jump('jump.wav'),
  dodge('dodge.wav'),
  uiClick('ui_click.wav');

  const Sfx(this.file);
  final String file;
}

/// Sound effects and music. The game only talks to this interface, so tests
/// run with [SilentSounds] and never touch the audio plugin.
abstract class GameSounds {
  /// On = everything is silent. Toggled from the pause menu.
  ValueNotifier<bool> get muted;

  void play(Sfx sfx);
  void startMusic();
  void stopMusic();
}

class SilentSounds implements GameSounds {
  @override
  final ValueNotifier<bool> muted = ValueNotifier(false);

  @override
  void play(Sfx sfx) {}

  @override
  void startMusic() {}

  @override
  void stopMusic() {}
}

/// Plays the files in assets/audio/ (placeholders made by
/// tool/make_placeholder_sounds.py; replace them with real audio anytime).
class FlameSounds implements GameSounds {
  FlameSounds() {
    muted.addListener(() {
      if (muted.value) {
        FlameAudio.bgm.stop();
      } else if (_musicWanted) {
        FlameAudio.bgm.play(_music, volume: 0.3);
      }
    });
  }

  static const _music = 'music_flat_arena.wav';

  @override
  final ValueNotifier<bool> muted = ValueNotifier(false);
  bool _musicWanted = false;

  Future<void> load() async {
    FlameAudio.bgm.initialize();
    await FlameAudio.audioCache.loadAll([
      for (final s in Sfx.values) s.file,
      _music,
    ]);
  }

  @override
  void play(Sfx sfx) {
    if (!muted.value) FlameAudio.play(sfx.file, volume: 0.7);
  }

  @override
  void startMusic() {
    _musicWanted = true;
    if (!muted.value) FlameAudio.bgm.play(_music, volume: 0.3);
  }

  @override
  void stopMusic() {
    _musicWanted = false;
    FlameAudio.bgm.stop();
  }
}
