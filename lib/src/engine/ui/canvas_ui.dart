part of '../../engine.dart';

/// Anchor preset on a [UICanvas] design rectangle.
enum UIAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Base class for elements rendered by a [UICanvas].
sealed class UIElement {
  UIAnchor anchor;
  double x;
  double y;
  double width;
  double height;
  bool visible;

  UIElement({
    this.anchor = UIAnchor.topLeft,
    this.x = 0,
    this.y = 0,
    this.width = 0,
    this.height = 0,
    this.visible = true,
  });

  /// Resolves the top-left corner `(rx, ry)` of this element inside a canvas of
  /// `(canvasW, canvasH)`.
  (double, double) resolveTopLeft(double canvasW, double canvasH) {
    final (ax, ay) = switch (anchor) {
      UIAnchor.topLeft => (0.0, 0.0),
      UIAnchor.topCenter => (canvasW * 0.5 - width * 0.5, 0.0),
      UIAnchor.topRight => (canvasW - width, 0.0),
      UIAnchor.centerLeft => (0.0, canvasH * 0.5 - height * 0.5),
      UIAnchor.center => (canvasW * 0.5 - width * 0.5, canvasH * 0.5 - height * 0.5),
      UIAnchor.centerRight => (canvasW - width, canvasH * 0.5 - height * 0.5),
      UIAnchor.bottomLeft => (0.0, canvasH - height),
      UIAnchor.bottomCenter => (canvasW * 0.5 - width * 0.5, canvasH - height),
      UIAnchor.bottomRight => (canvasW - width, canvasH - height),
    };
    return (ax + x, ay + y);
  }

  bool containsPoint(double px, double py, double canvasW, double canvasH) {
    if (!visible) return false;
    final (rx, ry) = resolveTopLeft(canvasW, canvasH);
    return px >= rx && px <= rx + width && py >= ry && py <= ry + height;
  }
}

final class UIPanel extends UIElement {
  int fillColor;
  int? borderColor;
  double borderThickness;

  UIPanel({
    super.anchor,
    super.x,
    super.y,
    required super.width,
    required super.height,
    this.fillColor = 0x0A0816B8,
    this.borderColor,
    this.borderThickness = 1,
    super.visible,
  });
}

final class UILabel extends UIElement {
  String text;
  double scale;
  int color;
  double alignX;

  UILabel({
    required this.text,
    super.anchor,
    super.x,
    super.y,
    this.scale = 1,
    this.color = 0xFFFFFFFF,
    this.alignX = 0,
    super.visible,
  });
}

final class UIProgressBar extends UIElement {
  double value;
  int backgroundColor;
  int fillColor;
  int? lowFillColor;
  double lowThreshold;
  int? borderColor;

  UIProgressBar({
    super.anchor,
    super.x,
    super.y,
    required super.width,
    required super.height,
    this.value = 1.0,
    this.backgroundColor = 0x00000066,
    this.fillColor = 0x4DFFA6FF,
    this.lowFillColor = 0xFF5A5AFF,
    this.lowThreshold = 0.25,
    this.borderColor = 0x8F88B8FF,
    super.visible,
  });
}

final class UIButton extends UIElement {
  String label;
  void Function()? onPressed;
  int normalColor;
  int hoverColor;
  int pressedColor;
  int textColor;
  double textScale;

  bool isHovered = false;
  bool isPressed = false;

  UIButton({
    required this.label,
    super.anchor,
    super.x,
    super.y,
    required super.width,
    required super.height,
    this.onPressed,
    this.normalColor = 0x1E1B2EFF,
    this.hoverColor = 0x322D4DFF,
    this.pressedColor = 0xFFB347FF,
    this.textColor = 0xFFFFFFFF,
    this.textScale = 1,
    super.visible,
  });
}

/// DOM-free in-canvas UI overlay rendered on `SpriteStage.overlay` (E4-4).
final class UICanvas extends Behaviour {
  final double designWidth;
  final double designHeight;
  BitmapFont? font;
  final List<UIElement> elements = [];

  late final Camera2D _camera = Camera2D(
    designWidth: designWidth,
    designHeight: designHeight,
  )..x = designWidth * 0.5
   ..y = designHeight * 0.5;

  final SpriteBatch _batch = SpriteBatch(
    initialCapacity: 512,
    debugLabel: 'canvas_ui',
  );

  UICanvas({
    this.designWidth = 640,
    this.designHeight = 360,
    this.font,
  });

  T add<T extends UIElement>(T element) {
    elements.add(element);
    return element;
  }

  /// Converts a drawing-buffer pointer coordinate `(pointerX, pointerY)` into
  /// this canvas's `(0..designWidth, 0..designHeight)` space.
  Vec2 pointerToCanvas(double pointerX, double pointerY) {
    final vw = engine.graphics.viewportWidth;
    final vh = engine.graphics.viewportHeight;
    if (vw <= 0 || vh <= 0) return Vec2(pointerX, pointerY);
    _camera
      ..setViewport(vw, vh)
      ..x = designWidth * 0.5
      ..y = designHeight * 0.5;
    return _camera.screenToWorld(pointerX, pointerY);
  }

  @override
  void update() {
    final raw = engine.host.input;
    final pt = pointerToCanvas(raw.pointerX, raw.pointerY);
    for (final el in List.of(elements)) {
      if (el is UIButton) {
        final hit = el.containsPoint(pt.x, pt.y, designWidth, designHeight);
        el.isHovered = hit;
        if (hit && raw.pointerPressed) {
          el.isPressed = true;
        }
        if (el.isPressed && raw.pointerReleased) {
          el.isPressed = false;
          if (hit) el.onPressed?.call();
        }
        if (!raw.pointerDown) {
          el.isPressed = false;
        }
      }
    }
  }

  void _encode(RenderEncoder encoder, int viewportWidth, int viewportHeight) {
    if (viewportWidth > 0 && viewportHeight > 0) {
      _camera.setViewport(viewportWidth, viewportHeight);
    }
    _camera
      ..x = designWidth * 0.5
      ..y = designHeight * 0.5;
    _batch.clear();

    for (final el in elements) {
      if (!el.visible) continue;
      final (rx, ry) = el.resolveTopLeft(designWidth, designHeight);
      switch (el) {
        case UIPanel p:
          _batch.drawRect(rx, ry, p.width, p.height, color: p.fillColor);
          if (p.borderColor != null) {
            _drawBorder(rx, ry, p.width, p.height, p.borderThickness, p.borderColor!);
          }
        case UILabel l:
          font?.draw(
            _batch,
            l.text,
            rx,
            ry,
            scale: l.scale,
            alignX: l.alignX,
            color: l.color,
          );
        case UIProgressBar bar:
          _batch.drawRect(rx, ry, bar.width, bar.height, color: bar.backgroundColor);
          final frac = bar.value.clamp(0.0, 1.0);
          final fillCol = (bar.lowFillColor != null && frac <= bar.lowThreshold)
              ? bar.lowFillColor!
              : bar.fillColor;
          if (frac > 0) {
            _batch.drawRect(rx, ry, bar.width * frac, bar.height, color: fillCol);
          }
          if (bar.borderColor != null) {
            _drawBorder(rx, ry, bar.width, bar.height, 1, bar.borderColor!);
          }
        case UIButton btn:
          final bg = btn.isPressed
              ? btn.pressedColor
              : (btn.isHovered ? btn.hoverColor : btn.normalColor);
          _batch.drawRect(rx, ry, btn.width, btn.height, color: bg);
          final f = font;
          if (f != null && btn.label.isNotEmpty) {
            f.draw(
              _batch,
              btn.label,
              rx + btn.width * 0.5,
              ry + (btn.height - f.lineHeight * btn.textScale) * 0.5,
              scale: btn.textScale,
              alignX: 0.5,
              color: btn.textColor,
            );
          }
      }
    }

    encoder.drawSprites(_batch, _camera, stage: SpriteStage.overlay);
  }

  void _drawBorder(double x, double y, double w, double h, double t, int color) {
    _batch
      ..drawRect(x, y, w, t, color: color)
      ..drawRect(x, y + h - t, w, t, color: color)
      ..drawRect(x, y, t, h, color: color)
      ..drawRect(x + w - t, y, t, h, color: color);
  }

  @override
  void _onEnableInternal() => scene._uiCanvases.add(this);

  @override
  void _onDisableInternal() => scene._uiCanvases.remove(this);
}
