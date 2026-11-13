part of '../../engine.dart';

/// Integrates [rule.StatusContainer], [rule.CooldownTracker], damage shields,
/// and [StatsComponent] stat synchronization onto a [GameObject].
final class StatusEffectComponent extends Behaviour {
  final rule.StatusContainer statuses = rule.StatusContainer();
  final rule.CooldownTracker cooldowns = rule.CooldownTracker();
  final rule.CombatDefenseProfile defense;

  double currentHp;
  double maxHp;
  void Function(rule.StatusTickEvent tick, double finalHpDamage, double healed)?
  onTickApplied;
  void Function(rule.CombatResult result)? onDamaged;
  void Function()? onDefeated;

  late final Object _statusModifierSource = Object();

  StatusEffectComponent({
    this.maxHp = 100.0,
    double? currentHp,
    double armor = 0.0,
    double dodgeChance = 0.0,
    double blockChance = 0.0,
    double blockReduction = 0.5,
    Map<String, double>? resistances,
    this.onTickApplied,
    this.onDamaged,
    this.onDefeated,
  }) : currentHp = currentHp ?? maxHp,
       defense = rule.CombatDefenseProfile(
         armor: armor,
         dodgeChance: dodgeChance,
         blockChance: blockChance,
         blockReduction: blockReduction,
         resistances: resistances,
       ) {
    defense.statusContainer = statuses;
    statuses.onChanged = _syncStatsModifiers;
    statuses.onTick = _handleTick;
  }

  bool get isAlive => currentHp > 0.0;
  bool get isStunned => statuses.isStunned;

  rule.ActiveStatus? applyStatus(
    rule.StatusEffectDef def, {
    Object? sourceId,
    int initialStacks = 1,
  }) => statuses.apply(def, sourceId: sourceId, initialStacks: initialStacks);

  int dispelByTag(String tag, {int? maxCount}) =>
      statuses.dispelByTag(tag, maxCount: maxCount);

  /// Evaluates [packet] against active armor (base + sibling [StatsComponent] armor),
  /// elemental resistances, dodge/block, and status shields, deducting final HP loss.
  rule.CombatResult takeDamage(
    rule.DamagePacket packet, {
    math.Random? rng,
    bool? forceCrit,
    bool? forceDodge,
    bool? forceBlock,
  }) {
    final siblingStats = isAttached ? getComponent<StatsComponent>() : null;
    if (siblingStats != null && siblingStats.stats.getStat('armor') != null) {
      defense.armor = siblingStats.getValue('armor');
    }

    final result = rule.CombatResolver.resolve(
      packet,
      defense,
      rng: rng,
      forceCrit: forceCrit,
      forceDodge: forceDodge,
      forceBlock: forceBlock,
    );

    if (result.finalDamage > 0.0) {
      currentHp = math.max(0.0, currentHp - result.finalDamage);
    }
    onDamaged?.call(result);
    if (currentHp <= 0.0) {
      onDefeated?.call();
    }
    return result;
  }

  double heal(double amount) {
    if (amount <= 0.0) return 0.0;
    final prev = currentHp;
    currentHp = math.min(maxHp, currentHp + amount);
    return currentHp - prev;
  }

  void _handleTick(rule.StatusTickEvent tick) {
    var dealt = 0.0;
    if (tick.damage > 0.0) {
      final res = takeDamage(
        rule.DamagePacket(
          baseAmount: tick.damage,
          damageType: tick.damageType,
          sourceId: tick.status.sourceId,
          canDodge: false,
          canBlock: false,
        ),
        forceCrit: false,
        forceDodge: false,
        forceBlock: false,
      );
      dealt = res.finalDamage;
    }
    final healed = tick.heal > 0.0 ? heal(tick.heal) : 0.0;
    onTickApplied?.call(tick, dealt, healed);
  }

  void _syncStatsModifiers() {
    if (!isAttached) return;
    final statsComp = getComponent<StatsComponent>();
    if (statsComp == null) return;

    statsComp.removeModifiersFromSource(_statusModifierSource);
    final bonuses = statuses.aggregateStatBonuses();
    for (final entry in bonuses.entries) {
      final statName = entry.key;
      final b = entry.value;
      if (b.flat != 0.0) {
        statsComp.addModifier(
          items.StatModifier(
            statName: statName,
            value: b.flat,
            type: items.StatModifierType.flat,
            source: _statusModifierSource,
          ),
        );
      }
      if (b.percentAdd != 0.0) {
        statsComp.addModifier(
          items.StatModifier(
            statName: statName,
            value: b.percentAdd,
            type: items.StatModifierType.percentAdd,
            source: _statusModifierSource,
          ),
        );
      }
      if ((b.percentMult - 1.0).abs() > 1e-6) {
        statsComp.addModifier(
          items.StatModifier(
            statName: statName,
            value: b.percentMult - 1.0,
            type: items.StatModifierType.percentMult,
            source: _statusModifierSource,
          ),
        );
      }
    }
  }

  @override
  void awake() {
    final statsComp = isAttached ? getComponent<StatsComponent>() : null;
    if (statsComp != null &&
        defense.armor != 0.0 &&
        statsComp.stats.getStat('armor') == null) {
      statsComp.setBase('armor', defense.armor);
    }
    _syncStatsModifiers();
  }

  @override
  void update() {
    final dt = time.deltaTime;
    statuses.step(dt);
    cooldowns.step(dt);
  }
}

/// Manages turn order across combatants in a tactical encounter scene.
final class TurnEncounterComponent extends Component {
  final rule.TurnScheduler scheduler;
  final Map<String, StatusEffectComponent> _statusLinks = {};

  void Function(rule.CombatantSlot actor)? onTurnStarted;

  TurnEncounterComponent({
    rule.TurnMode mode = rule.TurnMode.speedGauge,
    double ctThreshold = 100.0,
    int initiativeDie = 20,
    int? seed,
    this.onTurnStarted,
  }) : scheduler = rule.TurnScheduler(
         mode: mode,
         ctThreshold: ctThreshold,
         initiativeDie: initiativeDie,
         seed: seed,
       );

  void registerParticipant(
    rule.CombatantSlot slot, {
    StatusEffectComponent? statusComponent,
  }) {
    scheduler.addCombatant(slot);
    if (statusComponent != null) {
      _statusLinks[slot.id] = statusComponent;
    }
  }

  void syncParticipantStates() {
    for (final entry in _statusLinks.entries) {
      final slot = scheduler.getCombatant(entry.key);
      if (slot == null) continue;
      slot.isAlive = entry.value.isAlive;
      slot.canAct = !entry.value.isStunned;
    }
  }

  rule.CombatantSlot? advanceTurn() {
    syncParticipantStates();
    final actor = scheduler.advanceNext();
    if (actor != null) {
      onTurnStarted?.call(actor);
    }
    return actor;
  }

  List<rule.CombatantSlot> previewOrder([int count = 6]) {
    syncParticipantStates();
    return scheduler.previewOrder(count);
  }
}

/// Immediate-mode `voxui` combat HUD showing HP/Shield bars, active buff/debuff
/// badges, ability cooldowns, and predicted turn timeline.
final class CombatHudUI {
  static void render(
    VoxUiContext ui,
    StatusEffectComponent actor, {
    TurnEncounterComponent? encounter,
    List<String> abilities = const [],
    String title = 'Combat Status',
    double x = 20.0,
    double y = 20.0,
    double width = 300.0,
    double height = 220.0,
  }) {
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final hpFrac = actor.maxHp <= 0
        ? 0.0
        : (actor.currentHp / actor.maxHp).clamp(0.0, 1.0);
    final prevGrab = ui.style.sliderGrab;
    ui.style.sliderGrab = const VoxColor(210, 60, 65, 255);
    ui.progressBar(
      hpFrac,
      overlay: 'HP ${actor.currentHp.round()}/${actor.maxHp.round()}',
    );
    ui.style.sliderGrab = prevGrab;

    if (actor.statuses.totalShield > 0.0) {
      ui.labelValue(
        'Shield',
        actor.statuses.totalShield.toStringAsFixed(0),
        valueColor: VoxColor.cyan,
      );
    }

    if (actor.statuses.active.isNotEmpty) {
      ui.text('Effects:', color: VoxColor.lightGray);
      for (final st in actor.statuses.active) {
        final durLabel = st.isPermanent
            ? 'INF'
            : '${st.remainingDuration.toStringAsFixed(1)}s';
        final stacksLabel = st.stacks > 1 ? ' x${st.stacks}' : '';
        ui.labelValue(
          '${st.def.name}$stacksLabel',
          durLabel,
          valueColor: VoxColor.yellow,
        );
      }
    }

    for (final ab in abilities) {
      final ready = actor.cooldowns.isReady(ab);
      ui.style.sliderGrab = ready ? VoxColor.green : VoxColor.blue;
      ui.progressBar(
        actor.cooldowns.progress(ab),
        overlay: ready
            ? '$ab: READY'
            : '$ab (${actor.cooldowns.remaining(ab).toStringAsFixed(1)}s)',
      );
      ui.style.sliderGrab = prevGrab;
    }

    if (encounter != null) {
      final upcoming = encounter.previewOrder(4);
      if (upcoming.isNotEmpty) {
        ui.separator();
        ui.text(
          'Next Turns: ${upcoming.map((s) => s.name).join(" -> ")}',
          color: VoxColor.cyan,
        );
      }
    }

    ui.endWindow();
  }
}
