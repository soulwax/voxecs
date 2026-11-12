<p align="center">
  <img src="assets/logo.svg" width="88" alt="voxecs logo"/>
</p>

# voxecs

A high-performance sparse-set Entity Component System (ECS) for Dart, inspired by EnTT.

`voxecs` delivers fast iteration speeds, contiguous memory packing, $O(1)$ operations, and $O(\min(N_1, N_2))$ multi-component query joins without code generation.

## Features

- **Generational Entity Handles**: Safe entity recycling with version checks to prevent use-after-free bugs.
- **Sparse-Set Storage**: Components stored contiguously in dense arrays for maximum CPU cache locality, with $O(1)$ indexed lookup.
- **Swap-and-Pop Deletions**: $O(1)$ component removals without shifting arrays or leaving fragmented gaps.
- **EnTT-Style Optimal Multi-Joins**: `view2<T1, T2>()` and `view3<T1, T2, T3>()` automatically iterate the smallest component pool and test membership in others, yielding optimal join performance.
- **Zero Codegen**: Pure Dart, no `build_runner` or reflection required.

## Usage

```dart
import 'package:voxecs/voxecs.dart';

class Position {
  double x, y;
  Position(this.x, this.y);
}

class Velocity {
  double vx, vy;
  Velocity(this.vx, this.vy);
}

void main() {
  final reg = Registry();

  // Create entity and attach components
  final entity = reg.create();
  reg.assign(entity, Position(0, 0));
  reg.assign(entity, Velocity(1.5, 2.0));

  // Multi-component join iteration
  for (final (e, pos, vel) in reg.view2<Position, Velocity>()) {
    pos.x += vel.vx;
    pos.y += vel.vy;
  }

  // Safe destruction
  reg.destroy(entity);
}
```

## Benchmark

Processes 10,000 entities across multi-component views in < 15ms on Dart VM.

## License

MIT
