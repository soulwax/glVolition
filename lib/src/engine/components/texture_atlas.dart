part of '../../engine.dart';

/// Texture atlas packer, 9-slice sprite layout & bitmap/SDF font shaper (`voxatlas`) (E78-2).
final class TextureAtlasComponent extends Component {
  int pageWidth;
  int pageHeight;
  int padding;
  atlas.MaxRectsHeuristic heuristic;
  bool autoRepack;

  final List<atlas.AtlasSpriteInput> _inputs = [];
  final Map<int, TextureHandle> _pageTextures = {};
  final Map<String, atlas.BitmapFontLayout> _fonts = {};

  atlas.AtlasPackResult? _lastResult;
  bool _dirty = true;

  TextureAtlasComponent({
    this.pageWidth = 512,
    this.pageHeight = 512,
    this.padding = 2,
    this.heuristic = atlas.MaxRectsHeuristic.bestShortSideFit,
    this.autoRepack = true,
    List<atlas.AtlasSpriteInput> initialSprites = const [],
  }) {
    _inputs.addAll(initialSprites);
  }

  static final spec = ComponentSpec<TextureAtlasComponent>(
    'TextureAtlasComponent',
    TextureAtlasComponent.new,
    [
      Field.integer('pageWidth', (c) => c.pageWidth, (c, v) {
        c.pageWidth = math.max(16, v);
        c._dirty = true;
      }),
      Field.integer('pageHeight', (c) => c.pageHeight, (c, v) {
        c.pageHeight = math.max(16, v);
        c._dirty = true;
      }),
      Field.integer('padding', (c) => c.padding, (c, v) {
        c.padding = math.max(0, v);
        c._dirty = true;
      }),
      Field.enumValue<TextureAtlasComponent, atlas.MaxRectsHeuristic>(
        'heuristic',
        atlas.MaxRectsHeuristic.values,
        (c) => c.heuristic,
        (c, v) {
          c.heuristic = v;
          c._dirty = true;
        },
      ),
      Field.boolean('autoRepack', (c) => c.autoRepack, (c, v) => c.autoRepack = v),
    ],
  );

  List<atlas.AtlasSpriteInput> get registeredSprites =>
      List<atlas.AtlasSpriteInput>.unmodifiable(_inputs);

  void registerSprite(atlas.AtlasSpriteInput sprite) {
    _inputs.removeWhere((s) => s.id == sprite.id);
    _inputs.add(sprite);
    _dirty = true;
  }

  void registerFont(atlas.BitmapFontLayout font) {
    _fonts[font.fontFamily] = font;
  }

  atlas.BitmapFontLayout? fontByFamily(String family) => _fonts[family];

  void bindPageTexture(int pageIndex, TextureHandle texture) {
    _pageTextures[pageIndex] = texture;
  }

  void setHeuristic(atlas.MaxRectsHeuristic next) {
    if (heuristic != next) {
      heuristic = next;
      _dirty = true;
    }
  }

  void cycleNextHeuristic() {
    final vals = atlas.MaxRectsHeuristic.values;
    final nextIdx = (vals.indexOf(heuristic) + 1) % vals.length;
    setHeuristic(vals[nextIdx]);
  }

  void cycleNextPageSize() {
    const sizes = [128, 256, 512, 1024];
    final idx = sizes.indexOf(pageWidth);
    final next = sizes[(idx == -1 ? 0 : idx + 1) % sizes.length];
    pageWidth = next;
    pageHeight = next;
    _dirty = true;
  }

  void markDirty() => _dirty = true;

  atlas.AtlasPackResult repack() {
    final packer = atlas.MaxRectsAtlasPacker(
      pageWidth: math.max(16, pageWidth),
      pageHeight: math.max(16, pageHeight),
      padding: math.max(0, padding),
      heuristic: heuristic,
    );
    _lastResult = packer.pack(_inputs);
    _dirty = false;
    return _lastResult!;
  }

  atlas.AtlasPackResult get result {
    if (_lastResult == null || (_dirty && autoRepack)) {
      return repack();
    }
    return _lastResult!;
  }

  atlas.AtlasSpriteEntry? lookupEntry(String id) => result.lookup(id);

  SpriteRegion? spriteRegionFor(String id) {
    final entry = lookupEntry(id);
    if (entry == null) return null;
    return SpriteRegion(
      texture: _pageTextures[entry.pageIndex],
      width: entry.width.toDouble(),
      height: entry.height.toDouble(),
      u0: entry.uvMinX,
      v0: entry.uvMinY,
      u1: entry.uvMaxX,
      v1: entry.uvMaxY,
    );
  }

  List<atlas.NineSliceQuad> sliceQuadsFor(
    String id, {
    required double destX,
    required double destY,
    required double destW,
    required double destH,
    double borderScale = 1.0,
  }) {
    final entry = lookupEntry(id);
    if (entry == null) return const [];
    return entry.sliceQuads(
      destX: destX,
      destY: destY,
      destW: destW,
      destH: destH,
      borderScale: borderScale,
    );
  }

  List<atlas.PositionedGlyph> layoutFontText(
    String fontFamily,
    String text, {
    double startX = 0.0,
    double startY = 0.0,
    double scale = 1.0,
    double? maxWidth,
  }) {
    final font = _fonts[fontFamily];
    if (font == null) return const [];
    return font.layoutText(
      text,
      atlas: result,
      startX: startX,
      startY: startY,
      scale: scale,
      maxWidth: maxWidth,
    );
  }
}

/// Persistent UI state for [AtlasPackerInspectorUI.render].
final class AtlasPackerInspectorUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` texture atlas packing & fill-efficiency inspector (E78-2).
final class AtlasPackerInspectorUI {
  static bool _drawButton(
    VoxUiContext ui,
    AtlasPackerInspectorUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked = hovered && state.activeButtonId == id && inp.wasMouseReleased;
    if (inp.wasMouseReleased && state.activeButtonId == id) {
      state.activeButtonId = null;
    }

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      bg,
      cornerRadius: ui.style.frameRounding,
    );
    dl.addRectOutline(
      rect.x,
      rect.y,
      rect.width,
      rect.height,
      ui.style.windowBorder,
      cornerRadius: ui.style.frameRounding,
    );
    final textW = label.length * (ui.style.fontSize * 0.6);
    dl.addText(
      label,
      rect.x + math.max(4.0, (rect.width - textW) * 0.5),
      rect.y + (rect.height - ui.style.fontSize) * 0.5,
      color: ui.style.text,
      size: ui.style.fontSize,
    );
    return clicked;
  }

  static void render(
    VoxUiContext ui,
    TextureAtlasComponent atlasComp, {
    AtlasPackerInspectorUiState? state,
    String title = 'Texture Atlas Packer',
    double x = 20.0,
    double y = 20.0,
    double width = 395.0,
    double height = 245.0,
  }) {
    final uiState = state ?? AtlasPackerInspectorUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final res = atlasComp.result;
    ui.labelValue(
      'Page Size / Pad',
      '${atlasComp.pageWidth}x${atlasComp.pageHeight} | ${atlasComp.padding}px',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Heuristic',
      atlasComp.heuristic.name,
      valueColor: VoxColor.yellow,
    );
    ui.labelValue(
      'Packed / Pages',
      '${res.packedCount}/${atlasComp.registeredSprites.length} | ${res.pageCount} pg (${res.unpackedIds.length} overflow)',
      valueColor: res.unpackedIds.isEmpty ? VoxColor.green : VoxColor.red,
    );
    ui.labelValue(
      'Fill Efficiency',
      '${(res.averageFillEfficiency * 100.0).toStringAsFixed(1)}%',
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 92.0;
    final repackRect = VoxRect(x + pad, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'atlas_repack', 'Repack', repackRect)) {
      atlasComp.repack();
    }

    final heurRect = VoxRect(repackRect.right + 8.0, barY, 86.0, 22.0);
    if (_drawButton(ui, uiState, 'atlas_heur', 'Heuristic', heurRect)) {
      atlasComp.cycleNextHeuristic();
      atlasComp.repack();
    }

    final padRect = VoxRect(heurRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'atlas_pad', 'Pad +1px', padRect)) {
      atlasComp.padding = (atlasComp.padding + 1) % 9;
      atlasComp.repack();
    }

    final sizeRect = VoxRect(padRect.right + 8.0, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'atlas_size', 'Next Size', sizeRect)) {
      atlasComp.cycleNextPageSize();
      atlasComp.repack();
    }

    ui.endWindow();
  }
}
