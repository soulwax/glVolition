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

/// Interactive boolean checkbox/switch rendered by a [UICanvas] (E8-3).
final class UIToggle extends UIElement {
  String label;
  bool value;
  void Function(bool value)? onChanged;
  int boxColor;
  int activeColor;
  int borderColor;
  int textColor;
  double textScale;

  bool isHovered = false;

  UIToggle({
    this.label = '',
    this.value = false,
    super.anchor,
    super.x,
    super.y,
    super.width = 16,
    super.height = 16,
    this.onChanged,
    this.boxColor = 0x181526FF,
    this.activeColor = 0x4DFFAAFF,
    this.borderColor = 0x8F88B8FF,
    this.textColor = 0xFFFFFFFF,
    this.textScale = 1,
    super.visible,
  });
}

/// Interactive horizontal value slider rendered by a [UICanvas] (E8-3).
final class UISlider extends UIElement {
  double value;
  double min;
  double max;
  void Function(double value)? onChanged;
  int trackColor;
  int fillColor;
  int thumbColor;
  int? borderColor;

  bool isDragging = false;

  UISlider({
    super.anchor,
    super.x,
    super.y,
    required super.width,
    super.height = 12,
    this.value = 0.5,
    this.min = 0.0,
    this.max = 1.0,
    this.onChanged,
    this.trackColor = 0x141220E6,
    this.fillColor = 0x5CE1E6FF,
    this.thumbColor = 0xFFFFFFFF,
    this.borderColor = 0x7A749EFF,
    super.visible,
  });

  double get normalized =>
      max > min ? ((value - min) / (max - min)).clamp(0.0, 1.0) : 0.0;

  void setFromNormalized(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final next = min + (max - min) * clamped;
    if ((next - value).abs() > 1e-6) {
      value = next;
      onChanged?.call(value);
    }
  }
}

enum UIStackAxis { vertical, horizontal }

/// Auto-layout stack container that positions child [UIElement]s sequentially
/// with [spacing] and [padding] (E8-3).
final class UIStack extends UIElement {
  UIStackAxis axis;
  double spacing;
  double padding;
  int? backgroundColor;
  int? borderColor;
  final List<UIElement> children = [];

  UIStack({
    this.axis = UIStackAxis.vertical,
    this.spacing = 4,
    this.padding = 6,
    this.backgroundColor,
    this.borderColor,
    super.anchor,
    super.x,
    super.y,
    super.width = 120,
    super.height = 80,
    super.visible,
    List<UIElement> children = const [],
  }) {
    this.children.addAll(children);
    layout();
  }

  T add<T extends UIElement>(T child) {
    children.add(child);
    layout();
    return child;
  }

  /// Recomputes each child's `(anchor, x, y)` so they flow along [axis] inside
  /// this stack's resolved rectangle, and updates this stack's `width`/`height`
  /// to fit its children.
  void layout({double canvasW = 640, double canvasH = 360}) {
    var cursor = padding;
    var maxCross = 0.0;
    for (final child in children) {
      if (!child.visible) continue;
      if (axis == UIStackAxis.vertical) {
        cursor += child.height + spacing;
        if (child.width > maxCross) maxCross = child.width;
      } else {
        cursor += child.width + spacing;
        if (child.height > maxCross) maxCross = child.height;
      }
    }
    final totalMain = children.where((c) => c.visible).isEmpty
        ? padding * 2
        : cursor - spacing + padding;
    if (axis == UIStackAxis.vertical) {
      if (maxCross + padding * 2 > width) width = maxCross + padding * 2;
      height = totalMain;
    } else {
      width = totalMain;
      if (maxCross + padding * 2 > height) height = maxCross + padding * 2;
    }

    final (rx, ry) = resolveTopLeft(canvasW, canvasH);
    var offset = padding;
    for (final child in children) {
      if (!child.visible) continue;
      child.anchor = UIAnchor.topLeft;
      if (axis == UIStackAxis.vertical) {
        child
          ..x = rx + padding
          ..y = ry + offset;
        offset += child.height + spacing;
      } else {
        child
          ..x = rx + offset
          ..y = ry + padding;
        offset += child.width + spacing;
      }
    }
  }
}

/// DOM-free in-canvas UI overlay rendered on `SpriteStage.overlay` (E4-4).
final class UICanvas extends Behaviour {
  double designWidth;
  double designHeight;
  BitmapFont? font;
  final List<UIElement> elements = [];

  static final spec = ComponentSpec<UICanvas>(
    'UICanvas',
    UICanvas.new,
    [
      Field.number('designWidth', (c) => c.designWidth, (c, v) => c.designWidth = v),
      Field.number('designHeight', (c) => c.designHeight, (c, v) => c.designHeight = v),
    ],
  );

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
      _updateElement(el, pt, raw);
    }
  }

  void _updateElement(UIElement el, Vec2 pt, Input raw) {
    if (!el.visible) return;
    switch (el) {
      case UIStack stack:
        stack.layout(canvasW: designWidth, canvasH: designHeight);
        for (final child in List.of(stack.children)) {
          _updateElement(child, pt, raw);
        }
      case UIButton btn:
        final hit = btn.containsPoint(pt.x, pt.y, designWidth, designHeight);
        btn.isHovered = hit;
        if (hit && raw.pointerPressed) {
          btn.isPressed = true;
        }
        if (btn.isPressed && raw.pointerReleased) {
          btn.isPressed = false;
          if (hit) btn.onPressed?.call();
        }
        if (!raw.pointerDown) {
          btn.isPressed = false;
        }
      case UIToggle toggle:
        final hit = toggle.containsPoint(pt.x, pt.y, designWidth, designHeight);
        toggle.isHovered = hit;
        if (hit && raw.pointerPressed) {
          toggle.value = !toggle.value;
          toggle.onChanged?.call(toggle.value);
        }
      case UISlider slider:
        final hit = slider.containsPoint(pt.x, pt.y, designWidth, designHeight);
        if (hit && raw.pointerPressed) {
          slider.isDragging = true;
        }
        if (!raw.pointerDown) {
          slider.isDragging = false;
        }
        if (slider.isDragging || (hit && raw.pointerPressed)) {
          final (rx, _) = slider.resolveTopLeft(designWidth, designHeight);
          final t = slider.width > 0 ? (pt.x - rx) / slider.width : 0.0;
          slider.setFromNormalized(t);
        }
      case UIPanel() || UILabel() || UIProgressBar():
        break;
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
      _drawElement(el);
    }

    encoder.drawSprites(_batch, _camera, stage: SpriteStage.overlay);
  }

  void _drawElement(UIElement el) {
    if (!el.visible) return;
    final (rx, ry) = el.resolveTopLeft(designWidth, designHeight);
    switch (el) {
      case UIStack stack:
        stack.layout(canvasW: designWidth, canvasH: designHeight);
        final (sx, sy) = stack.resolveTopLeft(designWidth, designHeight);
        if (stack.backgroundColor != null) {
          _batch.drawRect(sx, sy, stack.width, stack.height, color: stack.backgroundColor!);
        }
        if (stack.borderColor != null) {
          _drawBorder(sx, sy, stack.width, stack.height, 1, stack.borderColor!);
        }
        for (final child in stack.children) {
          _drawElement(child);
        }
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
      case UIToggle toggle:
        _batch.drawRect(rx, ry, toggle.height, toggle.height, color: toggle.boxColor);
        _drawBorder(rx, ry, toggle.height, toggle.height, 1, toggle.borderColor);
        if (toggle.value) {
          final inset = math.max(2.0, toggle.height * 0.22);
          _batch.drawRect(
            rx + inset,
            ry + inset,
            toggle.height - inset * 2,
            toggle.height - inset * 2,
            color: toggle.activeColor,
          );
        }
        final f = font;
        if (f != null && toggle.label.isNotEmpty) {
          f.draw(
            _batch,
            toggle.label,
            rx + toggle.height + 5,
            ry + (toggle.height - f.lineHeight * toggle.textScale) * 0.5,
            scale: toggle.textScale,
            color: toggle.textColor,
          );
        }
      case UISlider slider:
        _batch.drawRect(rx, ry, slider.width, slider.height, color: slider.trackColor);
        final frac = slider.normalized;
        if (frac > 0) {
          _batch.drawRect(rx, ry, slider.width * frac, slider.height, color: slider.fillColor);
        }
        if (slider.borderColor != null) {
          _drawBorder(rx, ry, slider.width, slider.height, 1, slider.borderColor!);
        }
        final thumbW = math.max(4.0, slider.height * 0.5);
        final thumbX = rx + (slider.width - thumbW) * frac;
        _batch.drawRect(thumbX, ry - 1, thumbW, slider.height + 2, color: slider.thumbColor);
    }
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
