part of '../../engine.dart';

/// Holds RPG character attributes and evaluates additive/multiplicative [items.StatModifier] stacks.
final class StatsComponent extends Component {
  final items.StatBlock stats;

  StatsComponent([Map<String, double>? initialBaseStats])
    : stats = items.StatBlock(initialBaseStats);

  double getValue(String statName, {double fallback = 0.0}) =>
      stats.getValue(statName, fallback: fallback);

  void setBase(String statName, double value) => stats.setBase(statName, value);

  void addModifier(items.StatModifier mod) => stats.addModifier(mod);

  int removeModifiersFromSource(Object source) =>
      stats.removeModifiersFromSource(source);

  @override
  void awake() {
    // Sync any equipment already equipped on a sibling InventoryComponent added beforehand
    final inv = getComponent<InventoryComponent>();
    if (inv != null) {
      for (final slot in inv.equipment.slotNames) {
        final equipped = inv.equipment.getEquipped(slot);
        if (equipped != null) {
          for (final mod in equipped.definition.equipModifiers) {
            stats.addModifier(mod, overrideSource: equipped);
          }
        }
      }
    }
  }
}

/// Manages a spatial 2D grid inventory and named equipment slots on a [GameObject].
final class InventoryComponent extends Component {
  final items.GridInventory grid;
  items.EquipmentSlots? _equipment;
  final List<String> slotNames;
  final items.StatBlock? _explicitStats;

  InventoryComponent({
    int gridWidth = 8,
    int gridHeight = 6,
    double? maxWeight,
    this.slotNames = const [
      'Head',
      'Chest',
      'Legs',
      'Boots',
      'MainHand',
      'OffHand',
      'Accessory',
    ],
    items.StatBlock? stats,
  }) : grid = items.GridInventory(
         width: gridWidth,
         height: gridHeight,
         maxWeight: maxWeight,
       ),
       _explicitStats = stats;

  items.EquipmentSlots get equipment {
    if (_equipment != null) return _equipment!;
    final resolvedStats =
        _explicitStats ??
        (isAttached ? getComponent<StatsComponent>()?.stats : null);
    _equipment = items.EquipmentSlots(
      slotNames: slotNames,
      stats: resolvedStats,
    );
    return _equipment!;
  }

  @override
  void awake() {
    // Re-bind equipment slots with sibling StatsComponent if available and previously unbound
    if (_equipment == null || _equipment!.stats == null) {
      final resolvedStats =
          _explicitStats ?? getComponent<StatsComponent>()?.stats;
      if (resolvedStats != null) {
        final prev = _equipment;
        final next = items.EquipmentSlots(
          slotNames: slotNames,
          stats: resolvedStats,
        );
        if (prev != null) {
          for (final s in slotNames) {
            final item = prev.getEquipped(s);
            if (item != null) next.equip(s, item);
          }
        }
        _equipment = next;
      }
    }
  }

  /// Adds [stack] to the spatial grid (auto-stacking & rotating as needed). Returns unplaced remainder.
  int addItem(items.ItemStack stack) => grid.addItem(stack);

  /// Moves [stack] from the grid into [slotName], returning any swapped item back to the grid.
  bool equipFromInventory(String slotName, items.ItemStack stack) {
    if (!equipment.canEquip(slotName, stack)) return false;

    final existingEntry = grid.items.cast<items.PlacedItem?>().firstWhere(
      (e) => identical(e!.stack, stack),
      orElse: () => null,
    );
    if (existingEntry == null) return false;

    final origX = existingEntry.x;
    final origY = existingEntry.y;
    final origRot = stack.rotated;

    grid.removeItem(stack);
    final res = equipment.equip(slotName, stack);
    if (!res.equipped) {
      grid.placeAt(stack, origX, origY, rotated: origRot);
      return false;
    }

    if (res.previousItem != null) {
      final rem = grid.addItem(res.previousItem!);
      if (rem > 0) {
        // Displaced item doesn't fit back -> roll back swap cleanly
        equipment.unequip(slotName);
        equipment.equip(slotName, res.previousItem!);
        grid.placeAt(stack, origX, origY, rotated: origRot);
        return false;
      }
    }
    return true;
  }

  /// Unequips whatever is in [slotName] back into the spatial grid.
  bool unequipToInventory(String slotName) {
    final current = equipment.getEquipped(slotName);
    if (current == null) return false;
    final free = grid.findFreeSlot(current);
    if (free == null || !grid.fitsWeight(current.totalWeight)) return false;

    equipment.unequip(slotName);
    grid.addItem(current);
    return true;
  }

  /// Saves spatial grid contents to host storage.
  void saveToStorage([String key = 'voxitem_inventory']) {
    if (!isAttached) return;
    engine.host.storage.write(key, jsonEncode(grid.toJson()));
  }

  /// Loads spatial grid contents from host storage.
  bool loadFromStorage(
    items.ItemRegistry registry, [
    String key = 'voxitem_inventory',
  ]) {
    if (!isAttached) return false;
    final raw = engine.host.storage.read(key);
    if (raw == null || raw.isEmpty) return false;
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    grid.loadJson(decoded, registry);
    return true;
  }
}

/// Immediate-mode `voxui` renderer for spatial grid inventories with rarity tints & quantity badges.
final class InventoryUI {
  static VoxColor _rarityColor(items.ItemRarity rarity) {
    switch (rarity) {
      case items.ItemRarity.common:
        return const VoxColor(90, 96, 110, 220);
      case items.ItemRarity.uncommon:
        return const VoxColor(45, 130, 65, 230);
      case items.ItemRarity.rare:
        return const VoxColor(50, 115, 210, 230);
      case items.ItemRarity.epic:
        return const VoxColor(145, 65, 200, 235);
      case items.ItemRarity.legendary:
        return const VoxColor(215, 145, 35, 240);
      case items.ItemRarity.unique:
        return const VoxColor(185, 65, 50, 240);
    }
  }

  static void render(
    VoxUiContext ui,
    InventoryComponent inv, {
    String title = 'Inventory',
    double x = 40.0,
    double y = 40.0,
    double cellSize = 36.0,
  }) {
    final grid = inv.grid;
    final winW = grid.width * cellSize + 24.0;
    final winH = grid.height * cellSize + 64.0;

    if (!ui.beginWindow(title, x: x, y: y, width: winW, height: winH)) {
      ui.endWindow();
      return;
    }

    final originX = x + 12.0;
    final originY = y + 36.0;
    final dl = ui.drawList;

    // Draw background grid slots
    for (int gy = 0; gy < grid.height; gy++) {
      for (int gx = 0; gx < grid.width; gx++) {
        final cx = originX + gx * cellSize;
        final cy = originY + gy * cellSize;
        dl.addRectFilled(
          cx + 1,
          cy + 1,
          cellSize - 2,
          cellSize - 2,
          const VoxColor(26, 28, 34, 240),
        );
        dl.addRectOutline(
          cx + 1,
          cy + 1,
          cellSize - 2,
          cellSize - 2,
          const VoxColor(55, 60, 72, 255),
        );
      }
    }

    // Draw placed items spanning their grid footprint
    for (final entry in grid.items) {
      final ix = originX + entry.x * cellSize + 2;
      final iy = originY + entry.y * cellSize + 2;
      final iw = entry.width * cellSize - 4;
      final ih = entry.height * cellSize - 4;

      final tint = _rarityColor(entry.stack.definition.rarity);
      dl.addRectFilled(ix, iy, iw, ih, tint, cornerRadius: 3.0);
      dl.addRectOutline(
        ix,
        iy,
        iw,
        ih,
        VoxColor.white.withAlpha(140),
        cornerRadius: 3.0,
      );

      dl.addText(
        entry.stack.definition.name,
        ix + 4,
        iy + 4,
        color: VoxColor.white,
        size: 11.0,
      );

      if (entry.stack.quantity > 1) {
        dl.addText(
          'x${entry.stack.quantity}',
          ix + iw - 22,
          iy + ih - 14,
          color: VoxColor.yellow,
          size: 11.0,
        );
      }
    }

    ui.text('Weight: ${grid.totalWeight.toStringAsFixed(1)} kg');
    ui.endWindow();
  }
}
