import 'package:test/test.dart';
import 'package:voxecs/voxecs.dart';

class Position {
  double x;
  double y;
  Position(this.x, this.y);
}

class Velocity {
  double vx;
  double vy;
  Velocity(this.vx, this.vy);
}

class Health {
  int hp;
  Health(this.hp);
}

void main() {
  group('voxecs - High-Performance Sparse-Set ECS Suite', () {
    test('Generational entity handles & recycling', () {
      final reg = Registry();

      final e1 = reg.create();
      expect(e1.index, equals(1));
      expect(e1.version, equals(1));
      expect(reg.valid(e1), isTrue);

      final e2 = reg.create();
      expect(e2.index, equals(2));
      expect(e2.version, equals(1));

      // Destroy e1 -> index 1 recycled with version 2
      reg.destroy(e1);
      expect(reg.valid(e1), isFalse);

      final e3 = reg.create();
      expect(e3.index, equals(1));
      expect(e3.version, equals(2));
      expect(reg.valid(e3), isTrue);

      // Stale handle e1 is strictly invalid
      expect(reg.valid(e1), isFalse);
    });

    test('Component assignment, retrieval, and swap-and-pop removal', () {
      final reg = Registry();

      final e1 = reg.create();
      final e2 = reg.create();
      final e3 = reg.create();

      reg.assign(e1, Position(10, 20));
      reg.assign(e2, Position(30, 40));
      reg.assign(e3, Position(50, 60));

      expect(reg.has<Position>(e1), isTrue);
      expect(reg.get<Position>(e1).x, equals(10));
      expect(reg.get<Position>(e2).x, equals(30));
      expect(reg.get<Position>(e3).x, equals(50));

      // Remove middle entity e2 (triggers swap-and-pop with e3)
      reg.remove<Position>(e2);
      expect(reg.has<Position>(e2), isFalse);
      expect(reg.tryGet<Position>(e2), isNull);

      // Remaining elements e1 and e3 remain fully valid and accessible
      expect(reg.has<Position>(e1), isTrue);
      expect(reg.get<Position>(e1).x, equals(10));
      expect(reg.has<Position>(e3), isTrue);
      expect(reg.get<Position>(e3).x, equals(50));
    });

    test('Single-component and multi-component view joins', () {
      final reg = Registry();

      // Entity A: Position + Velocity
      final a = reg.create();
      reg.assign(a, Position(1, 1));
      reg.assign(a, Velocity(2, 2));

      // Entity B: Position only
      final b = reg.create();
      reg.assign(b, Position(10, 10));

      // Entity C: Position + Velocity + Health
      final c = reg.create();
      reg.assign(c, Position(20, 20));
      reg.assign(c, Velocity(5, 5));
      reg.assign(c, Health(100));

      // Query single component: Position (all 3)
      final allPositions = reg.view<Position>().toList();
      expect(allPositions.length, equals(3));

      // Query dual component: Position + Velocity (A and C)
      final movingEntities = reg.view2<Position, Velocity>().toList();
      expect(movingEntities.length, equals(2));
      final movingIds = movingEntities.map((t) => t.$1).toSet();
      expect(movingIds, contains(a));
      expect(movingIds, contains(c));
      expect(movingIds, isNot(contains(b)));

      // Simulate physics movement loop
      for (final (_, pos, vel) in reg.view2<Position, Velocity>()) {
        pos.x += vel.vx;
        pos.y += vel.vy;
      }
      expect(reg.get<Position>(a).x, equals(3));
      expect(reg.get<Position>(c).x, equals(25));

      // Query triple component: Position + Velocity + Health (only C)
      final livingMoving = reg.view3<Position, Velocity, Health>().toList();
      expect(livingMoving.length, equals(1));
      expect(livingMoving.first.$1, equals(c));
    });

    test('Destroying entity cleans up all assigned components', () {
      final reg = Registry();
      final e = reg.create();
      reg.assign(e, Position(100, 200));
      reg.assign(e, Velocity(10, 20));

      expect(reg.has<Position>(e), isTrue);
      expect(reg.has<Velocity>(e), isTrue);

      reg.destroy(e);
      expect(reg.has<Position>(e), isFalse);
      expect(reg.has<Velocity>(e), isFalse);
      expect(reg.view<Position>().length, equals(0));
      expect(reg.view2<Position, Velocity>().length, equals(0));
    });

    test('High-volume benchmark: 10,000 entities processed in milliseconds', () {
      final reg = Registry();
      const count = 10000;

      for (var i = 0; i < count; i++) {
        final e = reg.create();
        reg.assign(e, Position(i.toDouble(), 0));
        if (i % 2 == 0) {
          reg.assign(e, Velocity(1.0, 1.0));
        }
      }

      var movingCount = 0;
      final sw = Stopwatch()..start();
      for (final (_, pos, vel) in reg.view2<Position, Velocity>()) {
        pos.x += vel.vx;
        movingCount++;
      }
      sw.stop();

      expect(movingCount, equals(5000));
      expect(sw.elapsedMilliseconds, lessThan(100)); // extremely fast memory iteration
    });
  });
}
