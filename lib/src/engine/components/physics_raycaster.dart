part of '../../engine.dart';

/// Data payload delivered to [Behaviour] pointer event callbacks (`onPointerEnter`,
/// `onPointerExit`, `onPointerDown`, `onPointerUp`, `onPointerClick`) when
/// interacting with 3D colliders (E16-1).
final class PointerRaycastHit {
  final GameObject gameObject;
  final Collider collider;
  final Vec3 point;
  final double distance;
  final Vec2 pointerPosition;

  const PointerRaycastHit({
    required this.gameObject,
    required this.collider,
    required this.point,
    required this.distance,
    required this.pointerPosition,
  });
}

/// Casts world-space rays through the pointer each frame, dispatching Unity-style
/// 3D pointer events ([Behaviour.onPointerEnter], [Behaviour.onPointerExit],
/// [Behaviour.onPointerDown], [Behaviour.onPointerUp], [Behaviour.onPointerClick])
/// to colliders on hit [GameObject]s (E16-1).
final class PhysicsRaycaster extends Behaviour {
  int layerMask;
  double maxDistance;
  bool includeTriggers;

  GameObject? _currentHovered;
  Collider? _currentCollider;
  Vec3? _lastHitPoint;
  double _lastDistance = 0.0;
  GameObject? _pressedObject;
  Collider? _pressedCollider;

  PhysicsRaycaster({
    this.layerMask = -1,
    this.maxDistance = double.infinity,
    this.includeTriggers = true,
  });

  static final spec = ComponentSpec<PhysicsRaycaster>(
    'PhysicsRaycaster',
    PhysicsRaycaster.new,
    [
      Field.integer('layerMask', (r) => r.layerMask, (r, v) => r.layerMask = v),
      Field.number(
        'maxDistance',
        (r) => r.maxDistance,
        (r, v) => r.maxDistance = v,
      ),
      Field.boolean(
        'includeTriggers',
        (r) => r.includeTriggers,
        (r, v) => r.includeTriggers = v,
      ),
    ],
  );

  GameObject? get currentHovered => _currentHovered;
  GameObject? get currentPressed => _pressedObject;

  @override
  void update() {
    final cam = getComponent<Camera>() ?? Camera.of(scene);
    if (cam == null) return;

    final rawInput = engine.host.input;
    final px = rawInput.pointerX;
    final py = rawInput.pointerY;
    final ray = cam.screenPointToRay(px, py);
    if (ray == null) return;

    final hit = scene.physics.raycast(
      ray,
      maxDistance: maxDistance,
      layerMask: layerMask,
      includeTriggers: includeTriggers,
    );

    final hitGo = hit?.gameObject;
    final hitCollider = hit?.collider;
    final hitPoint = hit?.point ?? Vec3.zero;
    final hitDistance = hit?.distance ?? 0.0;
    final pointerPos = Vec2(px, py);

    // Hover transitions
    if (hitGo != _currentHovered) {
      if (_currentHovered != null &&
          !_currentHovered!.isDestroyed &&
          _currentCollider != null) {
        final exitHit = PointerRaycastHit(
          gameObject: _currentHovered!,
          collider: _currentCollider!,
          point: _lastHitPoint ?? Vec3.zero,
          distance: _lastDistance,
          pointerPosition: pointerPos,
        );
        _notifyBehaviors(_currentHovered!, (b) => b.onPointerExit(exitHit));
      }

      if (hitGo != null && hitCollider != null) {
        final enterHit = PointerRaycastHit(
          gameObject: hitGo,
          collider: hitCollider,
          point: hitPoint,
          distance: hitDistance,
          pointerPosition: pointerPos,
        );
        _notifyBehaviors(hitGo, (b) => b.onPointerEnter(enterHit));
      }

      _currentHovered = hitGo;
      _currentCollider = hitCollider;
      _lastHitPoint = hitPoint;
      _lastDistance = hitDistance;
    } else if (hitGo != null) {
      _lastHitPoint = hitPoint;
      _lastDistance = hitDistance;
    }

    // Pointer press / down
    if (rawInput.pointerPressed) {
      _pressedObject = hitGo;
      _pressedCollider = hitCollider;
      if (hitGo != null && hitCollider != null) {
        final downHit = PointerRaycastHit(
          gameObject: hitGo,
          collider: hitCollider,
          point: hitPoint,
          distance: hitDistance,
          pointerPosition: pointerPos,
        );
        _notifyBehaviors(hitGo, (b) => b.onPointerDown(downHit));
      }
    }

    // Pointer release / up / click
    if (rawInput.pointerReleased) {
      if (_pressedObject != null &&
          !_pressedObject!.isDestroyed &&
          _pressedCollider != null) {
        final upHit = PointerRaycastHit(
          gameObject: _pressedObject!,
          collider: _pressedCollider!,
          point: hitPoint,
          distance: hitDistance,
          pointerPosition: pointerPos,
        );
        _notifyBehaviors(_pressedObject!, (b) => b.onPointerUp(upHit));

        if (identical(_pressedObject, hitGo)) {
          final clickHit = PointerRaycastHit(
            gameObject: hitGo!,
            collider: hitCollider!,
            point: hitPoint,
            distance: hitDistance,
            pointerPosition: pointerPos,
          );
          _notifyBehaviors(hitGo, (b) => b.onPointerClick(clickHit));
        }
      }
      _pressedObject = null;
      _pressedCollider = null;
    }
  }

  void _notifyBehaviors(GameObject go, void Function(Behaviour b) action) {
    for (final comp in List.of(go._components)) {
      if (comp is Behaviour && comp._active && !comp._destroyRequested) {
        scene._guard(() => action(comp));
      }
    }
  }

  @override
  void onDisable() {
    if (_currentHovered != null &&
        !_currentHovered!.isDestroyed &&
        _currentCollider != null) {
      final exitHit = PointerRaycastHit(
        gameObject: _currentHovered!,
        collider: _currentCollider!,
        point: _lastHitPoint ?? Vec3.zero,
        distance: _lastDistance,
        pointerPosition: Vec2.zero,
      );
      _notifyBehaviors(_currentHovered!, (b) => b.onPointerExit(exitHit));
    }
    _currentHovered = null;
    _currentCollider = null;
    _pressedObject = null;
    _pressedCollider = null;
  }
}
