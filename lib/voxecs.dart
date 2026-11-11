/// High-performance sparse-set Entity Component System for Dart, inspired by EnTT.
///
/// Features cache-friendly packed memory layout, $O(1)$ additions and removals via
/// swap-and-pop, generational entity handles, and optimal multi-component query joins.
library voxecs;

/// Lightweight entity handle combining index and generational version.
final class Entity {
  final int index;
  final int version;

  const Entity(this.index, this.version);

  static const Entity nullEntity = Entity(0, 0);

  bool get isNull => index == 0 && version == 0;

  @override
  String toString() => 'Entity(idx: $index, ver: $version)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Entity &&
          runtimeType == other.runtimeType &&
          index == other.index &&
          version == other.version;

  @override
  int get hashCode => Object.hash(index, version);
}

/// Interface for component-agnostic operations on a sparse set.
abstract interface class ISparseSet {
  int get length;
  bool containsEntity(Entity entity);
  void removeEntity(Entity entity);
  void clear();
}

/// Packed contiguous storage and sparse index mapping for component [T].
final class SparseSet<T> implements ISparseSet {
  final List<Entity> _dense = [];
  final List<T> _components = [];
  final List<int> _sparse = [];

  static const int _tombstone = -1;

  @override
  int get length => _dense.length;

  List<Entity> get entities => _dense;
  List<T> get components => _components;

  void _ensureSparseCapacity(int index) {
    while (_sparse.length <= index) {
      _sparse.add(_tombstone);
    }
  }

  /// Inserts or assigns [component] to [entity] in $O(1)$ time.
  void assign(Entity entity, T component) {
    final idx = entity.index;
    _ensureSparseCapacity(idx);

    final denseIndex = _sparse[idx];
    if (denseIndex != _tombstone && denseIndex < _dense.length && _dense[denseIndex] == entity) {
      _components[denseIndex] = component;
      return;
    }

    final newDenseIndex = _dense.length;
    _dense.add(entity);
    _components.add(component);
    _sparse[idx] = newDenseIndex;
  }

  /// Removes component assigned to [entity] in $O(1)$ time using swap-and-pop.
  @override
  void removeEntity(Entity entity) {
    final idx = entity.index;
    if (idx >= _sparse.length) return;

    final denseIndex = _sparse[idx];
    if (denseIndex == _tombstone || denseIndex >= _dense.length || _dense[denseIndex] != entity) {
      return;
    }

    final lastIndex = _dense.length - 1;
    final lastEntity = _dense[lastIndex];
    final lastComponent = _components[lastIndex];

    // Move last element to the slot being removed
    _dense[denseIndex] = lastEntity;
    _components[denseIndex] = lastComponent;
    _sparse[lastEntity.index] = denseIndex;

    // Pop end
    _dense.removeLast();
    _components.removeLast();
    _sparse[idx] = _tombstone;
  }

  /// Checks if [entity] holds this component in $O(1)$ time.
  @override
  bool containsEntity(Entity entity) {
    final idx = entity.index;
    if (idx >= _sparse.length) return false;
    final denseIndex = _sparse[idx];
    return denseIndex != _tombstone &&
        denseIndex < _dense.length &&
        _dense[denseIndex] == entity;
  }

  /// Retrieves the component assigned to [entity] in $O(1)$ time.
  T get(Entity entity) {
    final idx = entity.index;
    if (idx >= _sparse.length) {
      throw StateError('Entity $entity not found in ${T.toString()} pool');
    }
    final denseIndex = _sparse[idx];
    if (denseIndex == _tombstone || denseIndex >= _dense.length || _dense[denseIndex] != entity) {
      throw StateError('Entity $entity has no component of type ${T.toString()}');
    }
    return _components[denseIndex];
  }

  /// Safely attempts to retrieve the component, returning `null` if absent.
  T? tryGet(Entity entity) {
    final idx = entity.index;
    if (idx >= _sparse.length) return null;
    final denseIndex = _sparse[idx];
    if (denseIndex == _tombstone || denseIndex >= _dense.length || _dense[denseIndex] != entity) {
      return null;
    }
    return _components[denseIndex];
  }

  @override
  void clear() {
    _dense.clear();
    _components.clear();
    _sparse.clear();
  }
}

/// Central registry managing entities, component pools, and view queries.
final class Registry {
  int _nextIndex = 1;
  final List<int> _versions = [0];
  final List<int> _freeIndices = [];
  final Map<Type, ISparseSet> _pools = {};

  /// Creates a new valid [Entity] handle.
  Entity create() {
    if (_freeIndices.isNotEmpty) {
      final recycledIndex = _freeIndices.removeLast();
      final ver = _versions[recycledIndex];
      return Entity(recycledIndex, ver);
    }

    final index = _nextIndex++;
    while (_versions.length <= index) {
      _versions.add(0);
    }
    _versions[index] = 1;
    return Entity(index, 1);
  }

  /// Checks if [entity] is alive and matches its current generation.
  bool valid(Entity entity) {
    final idx = entity.index;
    if (idx == 0 || idx >= _nextIndex) return false;
    return _versions[idx] == entity.version;
  }

  /// Destroys [entity], removing all its components and recycling its ID index.
  void destroy(Entity entity) {
    if (!valid(entity)) return;

    // Remove from all pools
    for (final pool in _pools.values) {
      pool.removeEntity(entity);
    }

    final idx = entity.index;
    _versions[idx] = (_versions[idx] + 1) & 0xFFFFFFFF;
    _freeIndices.add(idx);
  }

  SparseSet<T> _getPool<T>() {
    return _pools.putIfAbsent(T, () => SparseSet<T>()) as SparseSet<T>;
  }

  /// Assigns [component] to [entity].
  T assign<T>(Entity entity, T component) {
    if (!valid(entity)) throw StateError('Cannot assign component to invalid entity $entity');
    final pool = _getPool<T>();
    pool.assign(entity, component);
    return component;
  }

  /// Removes component of type [T] from [entity].
  void remove<T>(Entity entity) {
    final pool = _pools[T];
    if (pool != null) {
      pool.removeEntity(entity);
    }
  }

  /// Checks whether [entity] has component [T].
  bool has<T>(Entity entity) {
    if (!valid(entity)) return false;
    final pool = _pools[T];
    return pool != null && pool.containsEntity(entity);
  }

  /// Retrieves component [T] for [entity].
  T get<T>(Entity entity) {
    if (!valid(entity)) throw StateError('Cannot get component from invalid entity $entity');
    final pool = _pools[T];
    if (pool == null) throw StateError('No pool registered for type ${T.toString()}');
    return (pool as SparseSet<T>).get(entity);
  }

  /// Safely attempts to retrieve component [T] for [entity], returning `null` if absent.
  T? tryGet<T>(Entity entity) {
    if (!valid(entity)) return null;
    final pool = _pools[T];
    if (pool == null) return null;
    return (pool as SparseSet<T>).tryGet(entity);
  }

  /// High performance single-component view query.
  Iterable<(Entity, T)> view<T>() sync* {
    final pool = _pools[T];
    if (pool == null) return;
    final p = pool as SparseSet<T>;
    for (var i = 0; i < p.length; i++) {
      yield (p.entities[i], p.components[i]);
    }
  }

  /// Optimal dual-component view query ($O(\min(N_1, N_2))$ join).
  Iterable<(Entity, T1, T2)> view2<T1, T2>() sync* {
    final p1 = _pools[T1] as SparseSet<T1>?;
    final p2 = _pools[T2] as SparseSet<T2>?;
    if (p1 == null || p2 == null) return;

    if (p1.length <= p2.length) {
      for (var i = 0; i < p1.length; i++) {
        final e = p1.entities[i];
        final c2 = p2.tryGet(e);
        if (c2 != null) {
          yield (e, p1.components[i], c2);
        }
      }
    } else {
      for (var i = 0; i < p2.length; i++) {
        final e = p2.entities[i];
        final c1 = p1.tryGet(e);
        if (c1 != null) {
          yield (e, c1, p2.components[i]);
        }
      }
    }
  }

  /// Optimal triple-component view query.
  Iterable<(Entity, T1, T2, T3)> view3<T1, T2, T3>() sync* {
    final p1 = _pools[T1] as SparseSet<T1>?;
    final p2 = _pools[T2] as SparseSet<T2>?;
    final p3 = _pools[T3] as SparseSet<T3>?;
    if (p1 == null || p2 == null || p3 == null) return;

    // Pick smallest pool to iterate
    final minLen = mathMin(p1.length, mathMin(p2.length, p3.length));
    if (minLen == p1.length) {
      for (var i = 0; i < p1.length; i++) {
        final e = p1.entities[i];
        final c2 = p2.tryGet(e);
        if (c2 == null) continue;
        final c3 = p3.tryGet(e);
        if (c3 != null) yield (e, p1.components[i], c2, c3);
      }
    } else if (minLen == p2.length) {
      for (var i = 0; i < p2.length; i++) {
        final e = p2.entities[i];
        final c1 = p1.tryGet(e);
        if (c1 == null) continue;
        final c3 = p3.tryGet(e);
        if (c3 != null) yield (e, c1, p2.components[i], c3);
      }
    } else {
      for (var i = 0; i < p3.length; i++) {
        final e = p3.entities[i];
        final c1 = p1.tryGet(e);
        if (c1 == null) continue;
        final c2 = p2.tryGet(e);
        if (c2 != null) yield (e, c1, c2, p3.components[i]);
      }
    }
  }

  /// Clears all entities and component pools.
  void clear() {
    _nextIndex = 1;
    _versions.fillRange(0, _versions.length, 0);
    _freeIndices.clear();
    for (final pool in _pools.values) {
      pool.clear();
    }
    _pools.clear();
  }
}

int mathMin(int a, int b) => a < b ? a : b;
