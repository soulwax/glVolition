import 'dart:math' as math;

import 'package:gl_volition/gl_volition.dart';
import 'package:test/test.dart';

import '../example/pixel_rocket/game.dart';

void main() {
  group('Pixel Rocket on package:rocket', () {
    test('launches from title, steers, boosts, collides with crystals/fuel/meteors, and saves best score', () {
      final host = HeadlessHost();
      final engine = Engine(host);
      engine.time.fixedDeltaTime = 0.02;
      final hud = NullRocketHud();

      final director = buildPixelRocketScene(
        engine,
        hud: hud,
        random: math.Random(42),
      );
      expect(director.phase, GamePhase.title);
      expect(hud.messageVisible, isTrue);

      // Press Space to launch.
      host.input.press('Space');
      engine.step(0.02);
      host.input.endFrame();
      host.input.release('Space');
      expect(director.phase, GamePhase.playing);
      expect(hud.messageVisible, isFalse);

      // Steer right and up while boosting for 10 fixed steps (0.2s).
      host.input
        ..press('KeyD')
        ..press('KeyW')
        ..press('ShiftLeft');
      for (var i = 0; i < 10; i++) {
        engine.step(0.02);
        host.input.endFrame();
      }
      expect(director.ship.logicalPos.x, greaterThan(0.5));
      expect(director.ship.logicalPos.y, greaterThan(0.5));
      expect(director.boosting, isTrue);
      expect(director.fuel, lessThan(100));

      host.input
        ..release('KeyD')
        ..release('KeyW')
        ..release('ShiftLeft');

      // Place a crystal directly on the ship and step once: trigger fires.
      final crystal = director.bodies.firstWhere((b) => b.kind == BodyKind.crystal);
      crystal.transform.localPosition = director.ship.logicalPos;
      final scoreBefore = director.score;
      engine.step(0.02);
      expect(director.score, greaterThanOrEqualTo(scoreBefore + 250));
      expect(crystal.consumed, isTrue);

      // Place a fuel canister on the ship and verify fuel refills.
      director.fuel = 40;
      final canister = director.bodies.firstWhere((b) => b.kind == BodyKind.fuel);
      canister.transform.localPosition = director.ship.logicalPos;
      engine.step(0.02);
      expect(director.fuel, greaterThan(60));
      expect(canister.consumed, isTrue);

      // Toggle PS1 retro mode with KeyP.
      host.input.press('KeyP');
      engine.step(0.02);
      host.input.endFrame();
      host.input.release('KeyP');
      expect(director.retro, isTrue);

      // Hit 3 meteors (clearing invulnerability between hits) to trigger game over.
      final meteors = director.bodies.where((b) => b.kind == BodyKind.meteor).take(3).toList();
      for (var i = 0; i < 3; i++) {
        director.invulnerable = 0;
        meteors[i].transform.localPosition = director.ship.logicalPos;
        engine.step(0.02);
      }
      expect(director.shields, 0);
      expect(director.phase, GamePhase.over);
      expect(hud.lastTitle, 'SHIP DESTROYED');
      expect(host.graphics.shakeTrauma, greaterThan(1.0));
      expect(host.storage.read('pixelrocket.best'), '${director.best}');
    });
  });
}
