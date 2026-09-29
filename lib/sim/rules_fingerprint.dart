import 'defs.dart';
import 'match_simulation.dart';

/// Bump when the simulation code changes how a match plays, even if no
/// data changed (new rule, different formula).
const int simulationVersion = 1;

/// A 32-bit fingerprint of everything that decides how a match plays:
/// [simulationVersion], the match rules, the stage and every fighter's
/// numbers and moves. Two devices can only play online if these match;
/// otherwise the same inputs give different results (a desync).
int rulesFingerprint(MatchSimulation sim, List<FighterDef> roster) {
  var h = 0x811C9DC5;
  void add(int v) {
    for (final w in [v & 0xFFFFFFFF, (v >> 32) & 0xFFFFFFFF]) {
      h = ((h ^ w) * 0x01000193) & 0xFFFFFFFF;
    }
  }

  add(simulationVersion);
  add(sim.startingStocks);
  add(sim.timeLimitTicks);
  add(sim.respawnInvincibleTicks);
  add(sim.respawnDelayTicks);
  add(MatchSimulation.hitstunPerKnockback.raw);
  add(MatchSimulation.hitFreezeMinKnockback.raw);
  add(MatchSimulation.maxHitFreeze);
  add(MatchSimulation.spawnEdgeMargin.raw);
  add(MatchSimulation.minSpawnDistance.raw);

  final s = sim.stage;
  for (final v in [
    s.groundLeft,
    s.groundRight,
    s.groundY,
    s.blastLeft,
    s.blastRight,
    s.blastTop,
    s.blastBottom,
    s.spawnY,
    ...s.spawnX,
  ]) {
    add(v.raw);
  }

  for (final d in roster) {
    for (final c in d.name.codeUnits) {
      add(c);
    }
    for (final v in [
      d.width,
      d.height,
      d.walkSpeed,
      d.groundAccel,
      d.airAccel,
      d.attackFriction,
      d.knockbackDrag,
      d.gravity,
      d.maxFallSpeed,
      d.jumpSpeed,
      d.airJumpSpeed,
      d.fastFallSpeed,
      d.dodgeSpeed,
    ]) {
      add(v.raw);
    }
    for (final v in [d.weight, d.airJumps, d.dodgeFrames, d.dodgeCooldown]) {
      add(v);
    }
    for (final kind in MoveKind.values) {
      final m = d.move(kind);
      for (final v in [
        m.startup,
        m.active,
        m.recovery,
        m.damage,
        m.launchAway ? 1 : 0,
        m.endsOnLanding ? 1 : 0,
      ]) {
        add(v);
      }
      for (final v in [
        m.baseKnockback,
        m.knockbackGrowth,
        m.launchX,
        m.launchY,
        m.forward,
        m.up,
        m.width,
        m.height,
        m.selfVx,
        m.selfVy,
      ]) {
        add(v.raw);
      }
    }
  }
  return h;
}
