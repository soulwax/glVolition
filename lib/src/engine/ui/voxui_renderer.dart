part of '../../engine.dart';

/// Samples engine [Input] into a [VoxInput] snapshot each frame with optional
/// viewport-to-design coordinate scaling (E96-1).
final class VoxUiInputBridge {
  static const List<String> defaultTrackedKeys = [
    'F11',
    'F12',
    'Backquote',
    'Tab',
    'Enter',
    'Space',
    'ArrowUp',
    'ArrowDown',
    'ArrowLeft',
    'ArrowRight',
  ];

  double _prevPointerX = 0.0;
  double _prevPointerY = 0.0;
  bool _hasPrev = false;

  /// Resets the tracked previous pointer position so the next [sample] call
  /// reports zero mouse delta.
  void reset() {
    _prevPointerX = 0.0;
    _prevPointerY = 0.0;
    _hasPrev = false;
  }

  /// Samples [input] for the current frame and returns a [VoxInput] snapshot.
  ///
  /// When both `designWidth > 0 && viewportWidth > 0` (and likewise for height),
  /// pointer coordinates are scaled from viewport pixels into design-space
  /// coordinates; otherwise raw pixel coordinates are used.
  VoxInput sample(
    Input input, {
    int viewportWidth = 0,
    int viewportHeight = 0,
    double designWidth = 0.0,
    double designHeight = 0.0,
    Iterable<String> trackedKeys = defaultTrackedKeys,
  }) {
    final mx = (designWidth > 0.0 && viewportWidth > 0)
        ? input.pointerX * (designWidth / viewportWidth)
        : input.pointerX;
    final my = (designHeight > 0.0 && viewportHeight > 0)
        ? input.pointerY * (designHeight / viewportHeight)
        : input.pointerY;

    final dx = _hasPrev ? (mx - _prevPointerX) : 0.0;
    final dy = _hasPrev ? (my - _prevPointerY) : 0.0;
    _prevPointerX = mx;
    _prevPointerY = my;
    _hasPrev = true;

    final keysDown = <String>{};
    final keysPressed = <String>{};
    for (final key in trackedKeys) {
      if (input.isDown(key)) keysDown.add(key);
      if (input.wasPressed(key)) keysPressed.add(key);
    }

    return VoxInput(
      mouseX: mx,
      mouseY: my,
      mouseDeltaX: dx,
      mouseDeltaY: dy,
      isMouseDown: input.pointerDown,
      wasMouseClicked: input.pointerPressed,
      wasMouseReleased: input.pointerReleased,
      keysDown: keysDown,
      keysPressed: keysPressed,
    );
  }
}

/// Translates a `package:voxui` [DrawList] into a `SpriteStage.overlay`
/// [SpriteBatch] submitted through [RenderEncoder] (E96-1).
final class VoxUiRenderer {
  double designWidth;
  double designHeight;
  BitmapFont? font;

  late Camera2D _camera =
      Camera2D(
          designWidth: designWidth > 0.0 ? designWidth : 1280.0,
          designHeight: designHeight > 0.0 ? designHeight : 720.0,
          fit: ViewFit.contain,
        )
        ..x = designWidth * 0.5
        ..y = designHeight * 0.5;

  final SpriteBatch _batch = SpriteBatch(
    initialCapacity: 1024,
    sort: SpriteSort.none,
    debugLabel: 'voxui_overlay',
  );

  int _lastBatchLength = 0;

  VoxUiRenderer({
    this.designWidth = 1280.0,
    this.designHeight = 720.0,
    this.font,
  });

  /// Number of sprite quads emitted during the most recent [renderDrawList] call.
  int get lastBatchLength => _lastBatchLength;

  /// Underlying [SpriteBatch] populated by [renderDrawList].
  SpriteBatch get batch => _batch;

  /// Translates [drawList] commands into sprite quads and submits them to
  /// [encoder] on [SpriteStage.overlay].
  ///
  /// Returns the number of sprite quads rendered (`lastBatchLength`).
  int renderDrawList(
    DrawList drawList,
    RenderEncoder encoder, {
    required int viewportWidth,
    required int viewportHeight,
  }) {
    _batch.clear();

    final camW = designWidth > 0.0 ? designWidth : 1280.0;
    final camH = designHeight > 0.0 ? designHeight : 720.0;
    if (_camera.designWidth != camW || _camera.designHeight != camH) {
      _camera = Camera2D(
        designWidth: camW,
        designHeight: camH,
        fit: ViewFit.contain,
      );
    }
    if (viewportWidth > 0 && viewportHeight > 0) {
      _camera.setViewport(viewportWidth, viewportHeight);
    }
    _camera
      ..x = camW * 0.5
      ..y = camH * 0.5;

    final clipStack = <VoxRect>[];

    for (final cmd in drawList.commands) {
      switch (cmd.type) {
        case DrawCmdType.pushClip:
          final next = clipStack.isEmpty
              ? cmd.rect
              : clipStack.last.intersect(cmd.rect);
          clipStack.add(next);

        case DrawCmdType.popClip:
          if (clipStack.isNotEmpty) {
            clipStack.removeLast();
          }

        case DrawCmdType.rectFilled:
          final clip = _effectiveClip(clipStack, cmd.clipRect);
          final r = _clipRect(
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            clip,
          );
          if (r != null) {
            _batch.drawRect(
              r.x,
              r.y,
              r.width,
              r.height,
              color: cmd.color.toRgbaInt(),
            );
          }

        case DrawCmdType.rectOutline:
          final clip = _effectiveClip(clipStack, cmd.clipRect);
          _drawOutline(
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.thickness,
            cmd.color.toRgbaInt(),
            clip,
          );

        case DrawCmdType.line:
          final clip = _effectiveClip(clipStack, cmd.clipRect);
          final seg = _clipLine(cmd.rect.x, cmd.rect.y, cmd.x2, cmd.y2, clip);
          if (seg != null && cmd.thickness > 0.0) {
            final (x0, y0, x1, y1) = seg;
            final dx = x1 - x0;
            final dy = y1 - y0;
            final len = math.sqrt(dx * dx + dy * dy);
            if (len > 0.0) {
              _batch.draw(
                SpriteRegion.white,
                x0,
                y0,
                width: len,
                height: cmd.thickness,
                originX: 0.0,
                originY: 0.5,
                rotation: math.atan2(dy, dx),
                color: cmd.color.toRgbaInt(),
              );
            }
          }

        case DrawCmdType.circleFilled:
          final clip = _effectiveClip(clipStack, cmd.clipRect);
          _drawCircleOctagon(
            cmd.rect.x,
            cmd.rect.y,
            cmd.rect.width,
            cmd.rect.height,
            cmd.color.toRgbaInt(),
            clip,
          );

        case DrawCmdType.text:
          final text = cmd.text;
          if (text == null || text.isEmpty) break;
          final clip = _effectiveClip(clipStack, cmd.clipRect);
          final color = cmd.color.toRgbaInt();
          final f = font;
          if (f != null) {
            final scale = cmd.textSize / math.max(1.0, f.lineHeight);
            if (clip != null) {
              final lineCount = '\n'.allMatches(text).length + 1;
              final tw = f.measure(text, scale: scale);
              final th = lineCount * f.lineHeight * scale;
              if (_clipRect(cmd.rect.x, cmd.rect.y, tw, th, clip) == null) {
                break;
              }
            }
            f.draw(
              _batch,
              text,
              cmd.rect.x,
              cmd.rect.y,
              scale: scale,
              color: color,
            );
          } else {
            _drawMicroText(
              text,
              cmd.rect.x,
              cmd.rect.y,
              cmd.textSize,
              color,
              clip,
            );
          }
      }
    }

    _lastBatchLength = _batch.length;
    if (!_batch.isEmpty) {
      encoder.drawSprites(_batch, _camera, stage: SpriteStage.overlay);
    }
    return _lastBatchLength;
  }

  static VoxRect? _effectiveClip(List<VoxRect> stack, VoxRect? cmdClip) {
    final stackTop = stack.isEmpty ? null : stack.last;
    if (stackTop != null && cmdClip != null) {
      return stackTop.intersect(cmdClip);
    }
    return stackTop ?? cmdClip;
  }

  static VoxRect? _clipRect(
    double x,
    double y,
    double w,
    double h,
    VoxRect? clip,
  ) {
    if (w <= 0.0 || h <= 0.0) return null;
    if (clip == null) return VoxRect(x, y, w, h);
    final nx = math.max(x, clip.x);
    final ny = math.max(y, clip.y);
    final nr = math.min(x + w, clip.right);
    final nb = math.min(y + h, clip.bottom);
    final nw = nr - nx;
    final nh = nb - ny;
    if (nw <= 0.0 || nh <= 0.0) return null;
    return VoxRect(nx, ny, nw, nh);
  }

  static (double, double, double, double)? _clipLine(
    double x0,
    double y0,
    double x1,
    double y1,
    VoxRect? clip,
  ) {
    if (clip == null) return (x0, y0, x1, y1);
    if (clip.width <= 0.0 || clip.height <= 0.0) return null;
    final xmin = clip.x;
    final ymin = clip.y;
    final xmax = clip.right;
    final ymax = clip.bottom;
    final dx = x1 - x0;
    final dy = y1 - y0;
    var t0 = 0.0;
    var t1 = 1.0;

    bool clipEdge(double p, double q) {
      if (p == 0.0) return q >= 0.0;
      final r = q / p;
      if (p < 0.0) {
        if (r > t1) return false;
        if (r > t0) t0 = r;
      } else {
        if (r < t0) return false;
        if (r < t1) t1 = r;
      }
      return true;
    }

    if (!clipEdge(-dx, x0 - xmin)) return null;
    if (!clipEdge(dx, xmax - x0)) return null;
    if (!clipEdge(-dy, y0 - ymin)) return null;
    if (!clipEdge(dy, ymax - y0)) return null;

    return (x0 + t0 * dx, y0 + t0 * dy, x0 + t1 * dx, y0 + t1 * dy);
  }

  void _emitClippedRect(
    double x,
    double y,
    double w,
    double h,
    int color,
    VoxRect? clip,
  ) {
    final r = _clipRect(x, y, w, h, clip);
    if (r != null) {
      _batch.drawRect(r.x, r.y, r.width, r.height, color: color);
    }
  }

  void _drawOutline(
    double x,
    double y,
    double w,
    double h,
    double thickness,
    int color,
    VoxRect? clip,
  ) {
    if (w <= 0.0 || h <= 0.0 || thickness <= 0.0) return;
    final t = math.min(thickness, math.min(w, h) * 0.5);
    // Top and bottom strips
    _emitClippedRect(x, y, w, t, color, clip);
    _emitClippedRect(x, y + h - t, w, t, color, clip);
    // Left and right strips between top/bottom to avoid corner overdraw
    final sideH = h - t * 2.0;
    if (sideH > 0.0) {
      _emitClippedRect(x, y + t, t, sideH, color, clip);
      _emitClippedRect(x + w - t, y + t, t, sideH, color, clip);
    }
  }

  void _drawCircleOctagon(
    double x,
    double y,
    double w,
    double h,
    int color,
    VoxRect? clip,
  ) {
    if (w <= 0.0 || h <= 0.0) return;
    if (w < 3.0 || h < 3.0) {
      _emitClippedRect(x, y, w, h, color, clip);
      return;
    }
    const k = 0.4142135623730951; // sqrt(2) - 1
    final capW = w * k;
    final capH = (h * 0.5) * (1.0 - k);
    final midH = h - capH * 2.0;
    final capX = x + (w - capW) * 0.5;
    _emitClippedRect(capX, y, capW, capH, color, clip);
    if (midH > 0.0) {
      _emitClippedRect(x, y + capH, w, midH, color, clip);
    }
    _emitClippedRect(capX, y + h - capH, capW, capH, color, clip);
  }

  void _drawMicroText(
    String text,
    double x,
    double y,
    double textSize,
    int color,
    VoxRect? clip,
  ) {
    if (textSize <= 0.0) return;
    final px = textSize / 5.0;
    final stepX = px * 4.0;
    final stepY = px * 6.0;
    var penX = x;
    var penY = y;

    for (var i = 0; i < text.length; i++) {
      final code = text.codeUnitAt(i);
      if (code == 10) {
        penX = x;
        penY += stepY;
        continue;
      }
      if (code == 32) {
        penX += stepX;
        continue;
      }

      if (clip != null) {
        if (penY >= clip.bottom ||
            penY + px * 5.0 <= clip.y ||
            penX >= clip.right) {
          penX += stepX;
          continue;
        }
        if (penX + px * 3.0 <= clip.x) {
          penX += stepX;
          continue;
        }
      }

      final glyph = _lookupMicroGlyph(code);
      for (var row = 0; row < 5; row++) {
        final bits = (glyph >> ((4 - row) * 4)) & 0x7;
        if (bits == 0) continue;
        final ry = penY + row * px;
        switch (bits) {
          case 7: // ###
            _emitClippedRect(penX, ry, px * 3.0, px, color, clip);
          case 6: // ##.
            _emitClippedRect(penX, ry, px * 2.0, px, color, clip);
          case 3: // .##
            _emitClippedRect(penX + px, ry, px * 2.0, px, color, clip);
          case 5: // #.#
            _emitClippedRect(penX, ry, px, px, color, clip);
            _emitClippedRect(penX + px * 2.0, ry, px, px, color, clip);
          case 4: // #..
            _emitClippedRect(penX, ry, px, px, color, clip);
          case 2: // .#.
            _emitClippedRect(penX + px, ry, px, px, color, clip);
          case 1: // ..#
            _emitClippedRect(penX + px * 2.0, ry, px, px, color, clip);
        }
      }
      penX += stepX;
    }
  }

  static int _lookupMicroGlyph(int codeUnit) {
    final c = (codeUnit >= 97 && codeUnit <= 122) ? codeUnit - 32 : codeUnit;
    return _microGlyphs[c] ?? 0x75557;
  }

  /// 3x5 bitmap glyphs packed as 5 hex nibbles (top row in bits 16..18, bottom
  /// row in bits 0..2; bit 2 = left column, bit 0 = right column).
  static const Map<int, int> _microGlyphs = {
    33: 0x22202, // !
    34: 0x55000, // "
    35: 0x57575, // #
    36: 0x76237, // $
    37: 0x51245, // %
    38: 0x25253, // &
    39: 0x22000, // '
    40: 0x12221, // (
    41: 0x42224, // )
    42: 0x52725, // *
    43: 0x02720, // +
    44: 0x00024, // ,
    45: 0x00700, // -
    46: 0x00002, // .
    47: 0x11244, // /
    48: 0x75557, // 0
    49: 0x26227, // 1
    50: 0x71747, // 2
    51: 0x71717, // 3
    52: 0x55711, // 4
    53: 0x74717, // 5
    54: 0x74757, // 6
    55: 0x71122, // 7
    56: 0x75757, // 8
    57: 0x75717, // 9
    58: 0x02020, // :
    59: 0x02024, // ;
    60: 0x12421, // <
    61: 0x07070, // =
    62: 0x42124, // >
    63: 0x71202, // ?
    64: 0x75743, // @
    65: 0x25755, // A
    66: 0x65656, // B
    67: 0x74447, // C
    68: 0x65556, // D
    69: 0x74747, // E
    70: 0x74744, // F
    71: 0x74557, // G
    72: 0x55755, // H
    73: 0x72227, // I
    74: 0x11157, // J
    75: 0x55655, // K
    76: 0x44447, // L
    77: 0x57755, // M
    78: 0x56735, // N
    79: 0x25552, // O
    80: 0x65644, // P
    81: 0x25531, // Q
    82: 0x65655, // R
    83: 0x34216, // S
    84: 0x72222, // T
    85: 0x55557, // U
    86: 0x55552, // V
    87: 0x55775, // W
    88: 0x55255, // X
    89: 0x55222, // Y
    90: 0x71247, // Z
    91: 0x64446, // [
    92: 0x44211, // \
    93: 0x31113, // ]
    94: 0x25000, // ^
    95: 0x00007, // _
    96: 0x42000, // `
    123: 0x32423, // {
    124: 0x22222, // |
    125: 0x62126, // }
    126: 0x06300, // ~
  };
}
