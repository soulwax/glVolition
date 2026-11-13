part of '../../engine.dart';

/// Drives queued crafting/smelting production, tech tree research, and conveyor transport (`voxcraft`) (E61-2).
final class FactoryProducerComponent extends Behaviour {
  int maxActiveSlots;
  double speedMultiplier;
  double powerGridScale;
  bool paused;

  final Map<String, craft.FactoryRecipe> recipes = {};
  final craft.TechTreeSolver techTree = craft.TechTreeSolver();
  final craft.ConveyorNetwork conveyors = craft.ConveyorNetwork();
  craft.ProductionQueue? _queue;
  int? _configuredSlots;

  FactoryProducerComponent({
    this.maxActiveSlots = 2,
    this.speedMultiplier = 1.0,
    this.powerGridScale = 1.0,
    this.paused = false,
  });

  static final spec = ComponentSpec<FactoryProducerComponent>(
    'FactoryProducerComponent',
    FactoryProducerComponent.new,
    [
      Field.integer(
        'maxActiveSlots',
        (f) => f.maxActiveSlots,
        (f, v) => f.maxActiveSlots = v,
      ),
      Field.number(
        'speedMultiplier',
        (f) => f.speedMultiplier,
        (f, v) => f.speedMultiplier = v,
      ),
      Field.number(
        'powerGridScale',
        (f) => f.powerGridScale,
        (f, v) => f.powerGridScale = v,
      ),
      Field.boolean('paused', (f) => f.paused, (f, v) => f.paused = v),
    ],
  );

  craft.ProductionQueue _ensureQueue() {
    if (_queue == null || _configuredSlots != maxActiveSlots) {
      final prev = _queue;
      final q = craft.ProductionQueue(
        maxActiveSlots: math.max(1, maxActiveSlots),
        baseSpeedMultiplier: speedMultiplier,
      );
      if (prev != null) {
        q.inventory.addAll(prev.inventory);
      }
      _queue = q;
      _configuredSlots = maxActiveSlots;
    }
    _queue!.baseSpeedMultiplier = speedMultiplier;
    return _queue!;
  }

  craft.ProductionQueue get queue => _ensureQueue();
  int get queuedJobCount => _ensureQueue().jobs.length;
  int get completedBatches => _ensureQueue().totalCompletedBatches;
  double get powerConsumedKwh => _ensureQueue().totalPowerConsumedKwh;
  double amountOf(String resourceId) => _ensureQueue().amountOf(resourceId);

  void registerRecipe(craft.FactoryRecipe recipe) {
    recipes[recipe.id] = recipe;
  }

  void depositResource(String resourceId, double amount) =>
      _ensureQueue().deposit(resourceId, amount);

  bool enqueueRecipe(String recipeId, {int batches = 1}) {
    final recipe = recipes[recipeId];
    if (recipe == null) return false;
    return _ensureQueue().enqueue(recipe, batches: batches, techTree: techTree);
  }

  /// Advances production, research, and conveyor transport explicitly by [dt] seconds.
  void simulateSeconds(double dt) {
    if (dt <= 0.0) return;
    techTree.stepResearch(dt);
    _ensureQueue().step(
      dt,
      recipes: recipes,
      techTree: techTree,
      powerGridScale: powerGridScale,
    );
    conveyors.tick(dt);
  }

  @override
  void update() {
    if (paused) return;
    simulateSeconds(time.deltaTime);
  }
}

/// Simulates a dynamic commodity market with scarcity elasticity & equilibrium reversion (`voxcraft`) (E61-2).
final class DynamicMarketComponent extends Behaviour {
  bool autoTick;
  int maxHistorySamples;
  double priceTickScale;

  craft.DynamicMarketBook? _book;

  DynamicMarketComponent({
    this.autoTick = true,
    this.maxHistorySamples = 32,
    this.priceTickScale = 1.0,
  });

  static final spec = ComponentSpec<DynamicMarketComponent>(
    'DynamicMarketComponent',
    DynamicMarketComponent.new,
    [
      Field.boolean('autoTick', (m) => m.autoTick, (m, v) => m.autoTick = v),
      Field.integer(
        'maxHistorySamples',
        (m) => m.maxHistorySamples,
        (m, v) => m.maxHistorySamples = v,
      ),
      Field.number(
        'priceTickScale',
        (m) => m.priceTickScale,
        (m, v) => m.priceTickScale = v,
      ),
    ],
  );

  craft.DynamicMarketBook get book => _book ??= craft.DynamicMarketBook(
    maxHistorySamples: math.max(2, maxHistorySamples),
  );

  void registerCommodity(
    craft.MarketCommoditySpec spec, {
    double? initialStock,
  }) => book.registerCommodity(spec, initialStock: initialStock);

  craft.MarketTradeReceipt buy(String commodityId, double quantity) =>
      book.buy(commodityId, quantity);

  craft.MarketTradeReceipt sell(String commodityId, double quantity) =>
      book.sell(commodityId, quantity);

  double priceOf(String commodityId) => book.priceOf(commodityId);
  double stockOf(String commodityId) => book.stockOf(commodityId);

  @override
  void update() {
    if (autoTick && time.deltaTime > 0.0) {
      book.tick(time.deltaTime * priceTickScale);
    }
  }
}

/// Persistent UI interaction state for [EconomyFactoryUI.render].
final class EconomyFactoryUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` factory pipeline, tech bonus & dynamic market panel (E61-2).
final class EconomyFactoryUI {
  static bool _drawButton(
    VoxUiContext ui,
    EconomyFactoryUiState state,
    String id,
    String label,
    VoxRect rect,
  ) {
    final inp = ui.input;
    final dl = ui.drawList;
    final hovered = rect.contains(inp.mouseX, inp.mouseY);
    if (hovered && inp.wasMouseClicked) state.activeButtonId = id;
    final pressed = hovered && state.activeButtonId == id && inp.isMouseDown;
    final clicked =
        hovered && state.activeButtonId == id && inp.wasMouseReleased;
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
    FactoryProducerComponent factory, {
    DynamicMarketComponent? market,
    String? primaryCommodityId,
    EconomyFactoryUiState? state,
    String title = 'Factory & Economy',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? EconomyFactoryUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final commodityKey =
        primaryCommodityId ??
        (market != null && market.book.listings.isNotEmpty
            ? market.book.listings.keys.first
            : null);

    ui.labelValue(
      'Queue / Done',
      '${factory.queuedJobCount} jobs / ${factory.completedBatches}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Speed / Tech',
      '${(factory.speedMultiplier * factory.techTree.totalSpeedMultiplier).toStringAsFixed(2)}x / ${factory.techTree.unlockedIds.length} techs',
      valueColor: VoxColor.green,
    );
    ui.labelValue(
      'Belts / Status',
      '${factory.conveyors.totalDelivered} items / ${factory.paused ? "PAUSED" : "RUN"}',
      valueColor: VoxColor.lightGray,
    );
    ui.labelValue(
      'Market Spot',
      commodityKey != null && market != null
          ? '$commodityKey @ ${market.priceOf(commodityKey).toStringAsFixed(1)}'
          : 'No Market',
      valueColor: VoxColor.yellow,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final stepRect = VoxRect(x + pad, barY, 84.0, 22.0);
    if (_drawButton(ui, uiState, 'fac_step', 'Step +1s', stepRect)) {
      factory.simulateSeconds(1.0);
    }

    final pauseRect = VoxRect(stepRect.right + 8.0, barY, 80.0, 22.0);
    if (_drawButton(
      ui,
      uiState,
      'fac_pause',
      factory.paused ? 'Resume' : 'Pause',
      pauseRect,
    )) {
      factory.paused = !factory.paused;
    }

    if (market != null && commodityKey != null) {
      final buyRect = VoxRect(pauseRect.right + 8.0, barY, 84.0, 22.0);
      if (_drawButton(ui, uiState, 'fac_buy', 'Buy 10', buyRect)) {
        market.buy(commodityKey, 10.0);
      }
    }

    ui.endWindow();
  }
}
