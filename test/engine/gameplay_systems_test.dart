/// Example game loops, dialogue, quests, inventory, combat, cutscenes, economy & circuits.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

import '../../example/dungeon_2d/game.dart';
import '../../example/island_3d/game.dart';
import '../../example/procession/game.dart';

void main() {
  group('E5 — Example Game Full Gameplay Loops', () {
    test(
      'Dungeon2D (Lantern), Procession, and Island3D (Tidewatch) full gameplay loops',
      () {
        // 1. Lantern (Dungeon2D): collect mote, light both braziers, unlock portal
        final host = HeadlessHost();
        final engine = Engine(host, initialScene: buildDungeon2DScene());

        host.input.press('KeyD');
        for (var i = 0; i < 90; i++) {
          engine.step(0.02);
        }
        host.input.release('KeyD');
        host.input.endFrame();

        final explorer = engine.scene.findObjectOfType<DungeonExplorer>()!;
        expect(explorer.motesCollected, 1);
        expect(explorer.braziersLit, 2);
        expect(explorer.portalUnlocked, isTrue);

        // Move down to portal at (208, 112)
        host.input.press('KeyS');
        for (var i = 0; i < 45; i++) {
          engine.step(0.02);
        }
        host.input.release('KeyS');
        host.input.endFrame();
        expect(explorer.levelCompleted, isTrue);

        // 2. Procession: recruit 3 villagers, repel swarm with torch, deliver to Sanctuary
        engine.loadScene(buildProcessionScene());
        final leader = engine.scene.findObjectOfType<LeaderBehaviour>()!;
        final swarm = engine.scene.findObjectOfType<SwarmEnemyBehaviour>()!;
        final initialSwarmDist =
            (swarm.transform.localPosition - leader.transform.localPosition)
                .length;
        engine.step(0.05);
        final afterSwarmDist =
            (swarm.transform.localPosition - leader.transform.localPosition)
                .length;
        expect(afterSwarmDist, greaterThan(initialSwarmDist));

        host.input.press('KeyD');
        for (var i = 0; i < 140; i++) {
          engine.step(0.02);
        }
        host.input.release('KeyD');
        host.input.endFrame();
        expect(leader.deliveredCount, 3);

        // 3. Tidewatch (Island3D): guide ship with lighthouse beam or launch flare, test reef wreck
        engine.loadScene(buildIsland3DScene());
        final lighthouse = engine.scene
            .findObjectOfType<LighthouseBehaviour>()!;
        final skiffAgent = engine.scene.findObjectOfType<ShipAgentBehaviour>()!;
        final harbour = engine.scene.findObjectOfType<HarbourDirector>()!;

        // Launch a flare so the ship stays guided along its full route into harbour
        harbour.launchFlareAt(skiffAgent.transform.position);
        expect(harbour.flaresLaunched, 1);

        for (var i = 0; i < 40; i++) {
          lighthouse.aimPoint = skiffAgent.transform.localPosition;
          engine.step(0.1);
        }
        expect(skiffAgent.dockedSafely, isTrue);

        // Verify unguided ship wrecks on reef when lighthouse aims away and no flare is active
        engine.loadScene(buildIsland3DScene());
        final unguidedLighthouse = engine.scene
            .findObjectOfType<LighthouseBehaviour>()!;
        unguidedLighthouse.aimPoint = const Vec3(-100, 0, -100);
        final unguidedShip = engine.scene
            .findObjectOfType<ShipAgentBehaviour>()!;
        for (var i = 0; i < 30; i++) {
          engine.step(0.1);
        }
        expect(unguidedShip.wreckedOnReef, isTrue);
      },
    );
  });

  group('E37 — Dialogue, QuestManager & DialogueUI', () {
    test(
      'E37: DialogueComponent advances conversation and handles player choices',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final graph = DialogueGraph(
          entryNodeId: 'intro',
          initialNodes: [
            const DialogueNode(
              id: 'intro',
              speaker: 'Captain',
              text: 'Ready for departure, Commander?',
              choices: [
                DialogueChoice(text: 'Launch now', targetNodeId: 'launch'),
                DialogueChoice(text: 'Hold on', targetNodeId: 'hold'),
              ],
            ),
            const DialogueNode(
              id: 'launch',
              speaker: 'Captain',
              text: 'Engines engaged!',
            ),
            const DialogueNode(
              id: 'hold',
              speaker: 'Captain',
              text: 'Standing by.',
            ),
          ],
        );

        final npc = engine.scene.createGameObject('CaptainGo');
        final dialogue = npc.addComponent(
          DialogueComponent(graph: graph, autoStart: true),
        );

        engine.step(0.05);

        expect(dialogue.isRunning, isTrue);
        expect(dialogue.speaker, equals('Captain'));
        expect(dialogue.choices.length, equals(2));

        // Choose 'Launch now' (index 0)
        dialogue.selectChoice(0);
        expect(dialogue.runner.currentNode?.id, equals('launch'));

        // Advance to end
        dialogue.advance(); // finish typewriter
        dialogue.advance(); // completes dialogue
        expect(dialogue.isComplete, isTrue);
      },
    );

    test(
      'E37: QuestManagerComponent registers and advances quest objectives',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final questGo = engine.scene.createGameObject('QuestManagerGo');
        final questMgr = questGo.addComponent(QuestManagerComponent());

        final quest = Quest(
          id: 'repair_thrusters',
          title: 'Fix Thruster Assembly',
          description: 'Collect 2 titanium plates to patch the thruster.',
          objectives: [
            QuestObjective(
              id: 'plates',
              description: 'Titanium Plates',
              targetCount: 2,
            ),
          ],
        );

        questMgr.registerQuest(quest);
        questMgr.startQuest('repair_thrusters');

        expect(questMgr.activeQuests.length, equals(1));
        expect(
          questMgr.variables.getString('quest_repair_thrusters_status'),
          equals('active'),
        );

        // Complete objective
        questMgr.advanceObjective('repair_thrusters', 'plates', 2);
        expect(quest.isCompleted, isTrue);
        expect(questMgr.completedQuests.length, equals(1));
        expect(
          questMgr.variables.getString('quest_repair_thrusters_status'),
          equals('completed'),
        );
      },
    );

    test(
      'E37: DialogueUI renders immediate-mode dialogue box with choices',
      () {
        final graph = DialogueGraph(
          entryNodeId: 'talk',
          initialNodes: [
            const DialogueNode(
              id: 'talk',
              speaker: 'Navigator',
              text: 'Jump coordinates locked.',
              choices: [
                DialogueChoice(text: 'Engage hyperdrive', targetNodeId: 'jump'),
              ],
            ),
            const DialogueNode(
              id: 'jump',
              speaker: 'Navigator',
              text: 'Jumping now!',
            ),
          ],
        );

        final runner = DialogueRunner(graph: graph, typewriterSpeed: 0.0);
        runner.start();

        final ui = VoxUiContext();
        final input = VoxInput();
        ui.beginFrame(input);

        DialogueUI.render(ui, runner);

        final dl = ui.endFrame();

        // Should have recorded dialogue window commands
        expect(dl.commands, isNotEmpty);
        final hasNavigator = dl.commands.any(
          (cmd) => cmd.type == DrawCmdType.text && cmd.text == 'Navigator',
        );
        expect(hasNavigator, isTrue);

        final hasChoiceText = dl.commands.any(
          (cmd) =>
              cmd.type == DrawCmdType.text &&
              cmd.text?.contains('Engage hyperdrive') == true,
        );
        expect(hasChoiceText, isTrue);
      },
    );
  });

  group('E41 — InventoryComponent & StatsComponent', () {
    test(
      'E41: InventoryComponent & StatsComponent handle spatial equip swaps, stat buffs & storage persistence',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final greatsword = ItemDefinition(
          id: 'greatsword',
          name: 'Titanium Greatsword',
          gridWidth: 2,
          gridHeight: 3,
          rarity: ItemRarity.legendary,
          equipSlot: 'MainHand',
          equipModifiers: [
            StatModifier(statName: 'attack', value: 30.0),
            StatModifier(
              statName: 'attack',
              value: 0.2,
              type: StatModifierType.percentAdd,
            ),
          ],
        );
        const healingCell = ItemDefinition(
          id: 'medkit',
          name: 'Nano Medkit',
          maxStack: 5,
          rarity: ItemRarity.rare,
        );

        final reg = ItemRegistry()..registerAll([greatsword, healingCell]);

        final statsComp = StatsComponent({'attack': 10.0});
        final invComp = InventoryComponent(gridWidth: 5, gridHeight: 4);
        engine.scene.createGameObject(
          'Player',
          components: [invComp, statsComp],
        );

        final swordStack = ItemStack(greatsword);
        final medStack = ItemStack(healingCell, quantity: 3);
        expect(invComp.addItem(swordStack), equals(0));
        expect(invComp.addItem(medStack), equals(0));

        // Equip greatsword from grid -> base 10 + 30 = 40, * 1.2 = 48.0 attack
        expect(invComp.equipFromInventory('MainHand', swordStack), isTrue);
        expect(statsComp.getValue('attack'), closeTo(48.0, 1e-4));
        expect(invComp.grid.countById('greatsword'), equals(0));

        // Unequip back to inventory -> returns to base 10.0
        expect(invComp.unequipToInventory('MainHand'), isTrue);
        expect(statsComp.getValue('attack'), closeTo(10.0, 1e-4));
        expect(invComp.grid.countById('greatsword'), equals(1));

        // Save & restore inventory grid via host.storage
        invComp.saveToStorage('hero_bag');
        invComp.grid.clear();
        expect(invComp.grid.countById('medkit'), equals(0));
        expect(invComp.loadFromStorage(reg, 'hero_bag'), isTrue);
        expect(invComp.grid.countById('medkit'), equals(3));

        // Render InventoryUI using voxui
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        InventoryUI.render(ui, invComp);
        final dl = ui.endFrame();
        expect(
          dl.commands.any(
            (c) =>
                c.type == DrawCmdType.text && c.text == 'Titanium Greatsword',
          ),
          isTrue,
        );
        expect(
          dl.commands.any((c) => c.type == DrawCmdType.text && c.text == 'x3'),
          isTrue,
        );
      },
    );
  });

  group('E43 — FlowGraphComponent & FlowGraphUI', () {
    test(
      'E43: FlowGraphComponent drives GameObject transforms, delays & signals in scene loop',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final g = FlowGraph(
          name: 'MoverGraph',
          registry: EngineFlowNodes.createRegistry(),
        );
        final onUpdate = g.addNode('event.update');
        final mulSpeed = g.addNode('math.mul', inputs: {'b': 10.0});
        final makeDelta = g.addNode('vec.make3');
        final translate = g.addNode('engine.translate');

        g.connect(onUpdate.id, 'out', translate.id, 'in');
        g.connect(onUpdate.id, 'dt', mulSpeed.id, 'a');
        g.connect(mulSpeed.id, 'result', makeDelta.id, 'x');
        g.connect(makeDelta.id, 'vec', translate.id, 'delta');

        // Also test latent delay -> signal -> deactivate
        final onEvt = g.addNode(
          'event.custom',
          properties: {'event': 'DeactivateSoon'},
        );
        final delay = g.addNode('flow.delay', inputs: {'seconds': 0.2});
        final emit = g.addNode(
          'signal.emit',
          inputs: {'payload': 42},
          properties: {'signal': 'done'},
        );
        final deactivate = g.addNode(
          'engine.setActive',
          inputs: {'active': false},
        );

        g.connect(onEvt.id, 'out', delay.id, 'in');
        g.connect(delay.id, 'completed', emit.id, 'in');
        g.connect(emit.id, 'out', deactivate.id, 'in');

        final signals = <(String, Object?)>[];
        final flowComp = FlowGraphComponent(
          g,
          onSignal: (sig, payload) => signals.add((sig, payload)),
        );
        final go = engine.scene.createGameObject('Bot', components: [flowComp]);

        // 4 frames * 0.05s * 10.0 speed = 2.0m along X
        for (int i = 0; i < 4; i++) {
          engine.step(0.05);
        }
        expect(go.transform.position.x, closeTo(2.0, 1e-4));

        // Trigger custom latent event
        flowComp.triggerEvent('DeactivateSoon');
        expect(go.activeSelf, isTrue);
        engine.step(0.1);
        expect(signals, isEmpty);
        engine.step(0.12);
        expect(signals, [('done', 42)]);
        expect(go.activeSelf, isFalse);
      },
    );

    test(
      'E43: FlowGraphUI renders node canvas, wire preview and interactive pin linking via voxui',
      () {
        final g = FlowGraph();
        final src = g.addNode(
          'math.constFloat',
          x: 40.0,
          y: 40.0,
          properties: {'value': 7.0},
        );
        final dst = g.addNode('math.add', x: 260.0, y: 40.0);

        final ui = VoxUiContext();
        final state = FlowGraphUiState();

        // Compute exact canvas offset matching FlowGraphUI.render(x: 20, y: 20)
        final canvasX = 20.0 + 6.0;
        final canvasY = 20.0 + ui.style.titleBarHeight + 4.0;
        final outPinX = canvasX + src.x + 170.0 - 10.0;
        final outPinY = canvasY + src.y + 22.0 + 12.0;
        final inPinX = canvasX + dst.x + 10.0;
        final inPinY = canvasY + dst.y + 22.0 + 12.0;

        // Frame 1: click output pin on src node
        ui.beginFrame(
          VoxInput(
            mouseX: outPinX,
            mouseY: outPinY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        FlowGraphUI.render(
          ui,
          g,
          state: state,
          x: 20,
          y: 20,
          width: 620,
          height: 400,
        );
        final cmds1 = ui.endFrame();
        expect(state.linkingFromNodeId, src.id);
        expect(
          cmds1.commands.where((c) => c.type == DrawCmdType.line),
          isNotEmpty,
        );

        // Frame 2: drag across canvas
        ui.beginFrame(
          VoxInput(
            mouseX: (outPinX + inPinX) * 0.5,
            mouseY: outPinY,
            isMouseDown: true,
          ),
        );
        FlowGraphUI.render(
          ui,
          g,
          state: state,
          x: 20,
          y: 20,
          width: 620,
          height: 400,
        );
        ui.endFrame();

        // Frame 3: release over input pin on dst node -> connects link cleanly
        ui.beginFrame(
          VoxInput(mouseX: inPinX, mouseY: inPinY, wasMouseReleased: true),
        );
        FlowGraphUI.render(
          ui,
          g,
          state: state,
          x: 20,
          y: 20,
          width: 620,
          height: 400,
        );
        ui.endFrame();

        expect(g.links.length, 1);
        expect(g.links.first.fromNodeId, src.id);
        expect(g.links.first.toNodeId, dst.id);
        expect(
          DataflowEvaluator(g).evaluateOutput(dst.id, 'result'),
          closeTo(7.0, 1e-6),
        );
      },
    );
  });

  group('E45 — StatusEffect, TurnEncounter & CombatHudUI', () {
    test(
      'E45: StatusEffectComponent syncs buffs with StatsComponent, ticks DoTs, absorbs damage & cooldowns',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final stats = StatsComponent({'attack': 20.0, 'armor': 20.0});
        final combat = StatusEffectComponent(maxHp: 100.0);
        engine.scene.createGameObject('Paladin', components: [stats, combat]);

        const warcry = StatusEffectDef(
          id: 'warcry',
          name: 'Warcry',
          duration: 2.0,
          maxStacks: 2,
          stackPolicy: StatusStackPolicy.stackIntensity,
          statBonuses: {
            'attack': StatBonusSpec(flat: 5.0),
            'armor': StatBonusSpec(flat: 40.0),
          },
          absorbShieldAmount: 15.0,
        );
        const burn = StatusEffectDef(
          id: 'burn',
          name: 'Burn',
          duration: 1.5,
          tickInterval: 0.5,
          damagePerTick: 10.0,
          damageType: DamageTypes.fire,
        );

        // Apply 2 stacks -> +10 attack (total 30), +80 armor (total 100), 30 shield
        combat.applyStatus(warcry);
        combat.applyStatus(warcry);
        expect(stats.getValue('attack'), closeTo(30.0, 1e-4));
        expect(stats.getValue('armor'), closeTo(100.0, 1e-4));
        expect(combat.statuses.totalShield, closeTo(30.0, 1e-4));

        // Take 40 physical damage: 100 armor gives 50% mitigation -> 20 dmg, fully absorbed by 30 shield!
        final hitRes = combat.takeDamage(
          const DamagePacket(baseAmount: 40.0),
          forceCrit: false,
          forceDodge: false,
          forceBlock: false,
        );
        expect(hitRes.absorbedByShield, closeTo(20.0, 1e-4));
        expect(hitRes.finalDamage, closeTo(0.0, 1e-4));
        expect(combat.statuses.totalShield, closeTo(10.0, 1e-4));

        // Cooldown tracking + DoT burn over 1.0s (2 ticks * 10 fire = 20 dmg -> 10 shield + 10 HP lost)
        combat.cooldowns.start('slash', 1.0);
        expect(combat.cooldowns.isReady('slash'), isFalse);

        combat.applyStatus(burn);
        for (int i = 0; i < 10; i++) {
          engine.step(0.1);
        }
        expect(combat.currentHp, closeTo(90.0, 1e-3));
        expect(combat.cooldowns.isReady('slash'), isTrue);

        // Advance remaining 1.1s so warcry (2.0s total) expires and cleans up StatsComponent modifiers
        for (int i = 0; i < 11; i++) {
          engine.step(0.1);
        }
        expect(combat.statuses.hasStatus('warcry'), isFalse);
        expect(stats.getValue('attack'), closeTo(20.0, 1e-4));
        expect(stats.getValue('armor'), closeTo(20.0, 1e-4));
      },
    );

    test(
      'E45: TurnEncounterComponent syncs stun state & CombatHudUI renders buffs/turn bar via voxui',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final heroStatus = StatusEffectComponent(maxHp: 120.0, currentHp: 85.0);
        final orcStatus = StatusEffectComponent(maxHp: 80.0);
        final encounter = TurnEncounterComponent(mode: TurnMode.speedGauge);

        engine.scene.createGameObject('Hero', components: [heroStatus]);
        engine.scene.createGameObject('Orc', components: [orcStatus]);
        engine.scene.createGameObject('Encounter', components: [encounter]);

        encounter.registerParticipant(
          CombatantSlot(id: 'hero', name: 'Hero', speed: 25.0),
          statusComponent: heroStatus,
        );
        encounter.registerParticipant(
          CombatantSlot(id: 'orc', name: 'Orc', speed: 20.0),
          statusComponent: orcStatus,
        );

        // Stun orc -> Hero gets back-to-back turns
        orcStatus.applyStatus(
          const StatusEffectDef(
            id: 'stun',
            name: 'Stunned',
            duration: 2.0,
            stopsTurnAction: true,
          ),
        );
        expect(encounter.advanceTurn()!.id, 'hero');
        expect(encounter.advanceTurn()!.id, 'hero');

        heroStatus.cooldowns.start('Fireball', 4.0);
        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        CombatHudUI.render(
          ui,
          heroStatus,
          encounter: encounter,
          abilities: const ['Fireball'],
        );
        final drawList = ui.endFrame();
        expect(
          drawList.commands.where(
            (c) => c.text != null && c.text!.contains('Next Turns'),
          ),
          isNotEmpty,
        );
        expect(
          drawList.commands.where(
            (c) => c.text != null && c.text!.contains('HP 85/120'),
          ),
          isNotEmpty,
        );
      },
    );
  });

  group('E46 — CutsceneDirector & TimelineSequencerUI', () {
    test(
      'E46: CutsceneDirectorComponent animates transforms, toggles active camera shots, subtitles & cues',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final hero = engine.scene.createGameObject('Hero');
        final wideCam = Camera();
        final closeCam = Camera();
        engine.scene.createGameObject('WideCam', components: [wideCam]);
        engine.scene.createGameObject('CloseCam', components: [closeCam]);

        final eventsFired = <String>[];
        final audioCuesFired = <String>[];
        var completed = false;

        final director = CutsceneDirectorComponent(
          duration: 2.0,
          onEvent: (m) => eventsFired.add(m.name),
          onCompleted: () => completed = true,
        );
        director.bindPosition('hero_pos', hero)
          ..addKey(0.0, const SeqVec3(0, 0, 0))
          ..addKey(2.0, const SeqVec3(10, 0, 0));
        director.bindCameras('cams', {'Wide': wideCam, 'Close': closeCam})
          ..addShot(0.0, 1.0, 'Wide')
          ..addShot(1.0, 2.0, 'Close');
        director
            .bindSubtitles('subs')
            .addClip(0.5, 1.8, 'Captain', 'All units advance!');
        director
            .bindAudioCues(
              'sfx',
              onTriggerCue: (cue) => audioCuesFired.add(cue.clipKey),
            )
            .addCue(0.25, 'sfx/horn.wav', duration: 0.5);
        director.sequence.addTrack(
          EventTrack(id: 'cues')..addEvent(1.5, 'spawnWave'),
        );

        engine.scene.createGameObject(
          'CutsceneDirector',
          components: [director],
        );
        director.play(fromStart: true);

        // Step to t = 0.3
        for (int i = 0; i < 3; i++) {
          engine.step(0.1);
        }
        expect(hero.transform.position.x, closeTo(1.5, 1e-3));
        expect(wideCam.isActiveAndEnabled, isTrue);
        expect(closeCam.isActiveAndEnabled, isFalse);
        expect(audioCuesFired, ['sfx/horn.wav']);
        expect(director.activeSubtitle, isNull);

        // Step to t = 1.2
        for (int i = 0; i < 9; i++) {
          engine.step(0.1);
        }
        expect(hero.transform.position.x, closeTo(6.0, 1e-3));
        expect(wideCam.isActiveAndEnabled, isFalse);
        expect(closeCam.isActiveAndEnabled, isTrue);
        expect(director.activeSubtitle?.speaker, 'Captain');

        // Step to completion at t = 2.0+
        for (int i = 0; i < 9; i++) {
          engine.step(0.1);
        }
        expect(eventsFired, ['spawnWave']);
        expect(completed, isTrue);
        expect(director.isPlaying, isFalse);
        expect(hero.transform.position.x, closeTo(10.0, 1e-3));
      },
    );

    test(
      'E46: TimelineSequencerUI renders tracks, toggles transport Play & scrubs playhead via voxui',
      () {
        final posTrack = ValueTrack.vec3(id: 'pos')
          ..addKey(0.0, const SeqVec3(0, 0, 0))
          ..addKey(4.0, const SeqVec3(8, 0, 0));
        final camTrack = CameraCutTrack(id: 'cams')
          ..addShot(0.0, 4.0, 'MainCam');

        final sequence = TimelineSequence(duration: 4.0)
          ..addTrack(posTrack)
          ..addTrack(camTrack);

        final ui = VoxUiContext();
        final state = TimelineSequencerUiState();

        // Compute exact button/ruler coordinates matching TimelineSequencerUI.render(x: 20, y: 20, width: 560)
        final playBtnX = 20.0 + ui.style.windowPadding + 20.0;
        final playBtnY =
            20.0 + ui.style.titleBarHeight + ui.style.windowPadding + 10.0;

        // Press & release Play button
        ui.beginFrame(
          VoxInput(
            mouseX: playBtnX,
            mouseY: playBtnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        TimelineSequencerUI.render(
          ui,
          sequence,
          state: state,
          subtitlePreview: 'Ready!',
          x: 20,
          y: 20,
          width: 560,
          height: 280,
        );
        ui.endFrame();

        ui.beginFrame(
          VoxInput(mouseX: playBtnX, mouseY: playBtnY, wasMouseReleased: true),
        );
        TimelineSequencerUI.render(
          ui,
          sequence,
          state: state,
          subtitlePreview: 'Ready!',
          x: 20,
          y: 20,
          width: 560,
          height: 280,
        );
        ui.endFrame();
        expect(sequence.isPlaying, isTrue);

        // Scrub to 50% of ruler (rulerX = 20 + 10 + 132 = 162, rulerW = 560 - 20 - 132 = 408)
        final rulerMidX = 162.0 + 408.0 * 0.5;
        final rulerMidY =
            20.0 +
            ui.style.titleBarHeight +
            ui.style.windowPadding +
            30.0 +
            10.0;
        ui.beginFrame(
          VoxInput(
            mouseX: rulerMidX,
            mouseY: rulerMidY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        TimelineSequencerUI.render(
          ui,
          sequence,
          state: state,
          subtitlePreview: 'Ready!',
          x: 20,
          y: 20,
          width: 560,
          height: 280,
        );
        final dl = ui.endFrame();

        expect(sequence.currentTime, closeTo(2.0, 1e-3));
        expect(posTrack.evaluate(sequence.currentTime), const SeqVec3(4, 0, 0));
        expect(
          dl.commands.any((c) => c.type == DrawCmdType.circleFilled),
          isTrue,
        );
        expect(
          dl.commands.any(
            (c) => c.type == DrawCmdType.text && c.text == 'Ready!',
          ),
          isTrue,
        );
      },
    );
  });

  group('E47 — ProgressionStatsComponent & Achievements', () {
    test(
      'E47: ProgressionStatsComponent tracks combos, unlocks composable achievements & persists storage',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);

        final stats = ProgressionStatsComponent(
          comboDecayDuration: 1.0,
          comboMultiplierStep: 0.5,
          toastDisplayDuration: 2.0,
        );
        stats.registerAchievements([
          const AchievementDef(
            id: 'chain5',
            title: 'Combo Apprentice',
            description: 'Reach a 5-hit combo',
            points: 15,
            condition: MetricThresholdCondition('best_combo', 5),
          ),
          const AchievementDef(
            id: 'ace_pilot',
            title: 'Ace Pilot',
            description: 'Defeat 3 bosses and reach combo rank C',
            points: 40,
            condition: AllOfConditions([
              EventCountCondition('boss_down', requiredCount: 3),
              MetricThresholdCondition('best_combo', 5),
            ]),
          ),
        ]);
        engine.scene.createGameObject('GameStats', components: [stats]);

        // Hit 5 times -> hits best_combo == 5 -> unlocks 'chain5'
        for (int i = 0; i < 5; i++) {
          stats.registerComboHit(basePoints: 100.0);
        }
        expect(stats.combo.rank, ComboRank.c);
        expect(stats.combo.multiplier, closeTo(3.0, 1e-6));
        expect(stats.achievements.isUnlocked('chain5'), isTrue);
        expect(stats.achievements.isUnlocked('ace_pilot'), isFalse);

        // Step once so active toast dequeues, render HUD & submit leaderboard score
        engine.step(0.1);
        expect(stats.activeToast?.id, 'chain5');
        stats.submitScore(
          'arcade',
          playerId: 'p1',
          displayName: 'Nova',
          score: stats.combo.totalScore,
        );

        final ui = VoxUiContext();
        ui.beginFrame(VoxInput());
        AchievementsHudUI.render(ui, stats, leaderboardId: 'arcade');
        final drawList = ui.endFrame();
        expect(
          drawList.commands.any(
            (c) =>
                c.text != null &&
                c.text!.contains('UNLOCKED: Combo Apprentice'),
          ),
          isTrue,
        );
        expect(
          drawList.commands.any(
            (c) => c.text != null && c.text!.contains('#1 Nova'),
          ),
          isTrue,
        );

        // Emit 3 boss events -> unlocks 'ace_pilot'
        for (int i = 0; i < 3; i++) {
          stats.emitEvent('boss_down');
        }
        expect(stats.achievements.isUnlocked('ace_pilot'), isTrue);

        // Decay combo after 1.1s (Time.maximumDeltaTime clamps single steps to 0.1s)
        for (int i = 0; i < 10; i++) {
          engine.step(0.1);
        }
        expect(stats.combo.count, 0);

        // Persist & reload into fresh engine sharing host storage
        stats.saveToStorage('profile_e47');
        final engine2 = Engine(host);
        final stats2 = ProgressionStatsComponent();
        stats2.registerAchievements(stats.achievements.all.map((a) => a.def));
        engine2.scene.createGameObject('GameStats2', components: [stats2]);
        expect(stats2.loadFromStorage('profile_e47'), isTrue);
        expect(stats2.achievements.isUnlocked('ace_pilot'), isTrue);
        expect(stats2.leaderboards['arcade']!.top().single.displayName, 'Nova');
      },
    );
  });

  group('E61 — Production Pipelines, Conveyors & Dynamic Economy (voxcraft)', () {
    test(
      'FactoryProducerComponent, DynamicMarketComponent & EconomyFactoryUI run production, belts & market trades',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        const alloyRecipe = FactoryRecipe(
          id: 'alloy',
          name: 'Titanium Alloy',
          inputs: [CraftResourceAmount('ore', 2.0)],
          outputs: [CraftResourceAmount('alloy', 1.0)],
          byproducts: [CraftResourceAmount('slag', 0.5)],
          craftDurationSeconds: 1.0,
        );

        final factory =
            FactoryProducerComponent(maxActiveSlots: 1, speedMultiplier: 1.0)
              ..registerRecipe(alloyRecipe)
              ..depositResource('ore', 10.0)
              ..enqueueRecipe('alloy', batches: 4);
        factory.techTree
          ..addNode(
            const TechNodeDef(
              id: 'fast_smelt',
              name: 'Fast Smelt',
              bonus: TechBonusEffect(recipeSpeedBonus: 1.0),
            ),
          )
          ..unlockImmediate('fast_smelt');

        factory.conveyors
          ..addNode(
            ConveyorNode(id: 'mine', kind: ConveyorNodeKind.producer)
              ..deposit('ore', 6.0),
          )
          ..addNode(ConveyorNode(id: 'bin', kind: ConveyorNodeKind.consumer))
          ..connect(
            id: 'c1',
            fromNodeId: 'mine',
            toNodeId: 'bin',
            itemsPerSecond: 10.0,
            lengthMeters: 0.5,
            beltSpeedMps: 5.0,
          );

        final market = DynamicMarketComponent()
          ..registerCommodity(
            const MarketCommoditySpec(
              id: 'alloy',
              name: 'Titanium Alloy',
              basePrice: 50.0,
              equilibriumStock: 40.0,
              elasticity: 0.75,
            ),
          );

        scene.createGameObject('IndustrialHub', components: [factory, market]);

        // Run 20 x 0.1s frames (= 2.0s; at 2x speed completes all 4 x 1.0s alloy batches!).
        for (var i = 0; i < 20; i++) {
          engine.step(0.1);
        }

        expect(factory.completedBatches, 4);
        expect(factory.amountOf('alloy'), closeTo(4.0, 1e-4));
        expect(factory.amountOf('slag'), closeTo(2.0, 1e-4));
        expect(
          factory.conveyors.nodes['bin']!.amountOf('ore'),
          greaterThanOrEqualTo(4.0),
        );

        final spotBefore = market.priceOf('alloy');
        // Click 'Buy 10' at x=250, y=156 in EconomyFactoryUI.
        final ui = VoxUiContext();
        final uiState = EconomyFactoryUiState();
        const buyX = 250.0;
        const btnY = 156.0;
        ui.beginFrame(
          VoxInput(
            mouseX: buyX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        EconomyFactoryUI.render(
          ui,
          factory,
          market: market,
          primaryCommodityId: 'alloy',
          state: uiState,
        );
        ui.endFrame();

        ui.beginFrame(
          VoxInput(
            mouseX: buyX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        EconomyFactoryUI.render(
          ui,
          factory,
          market: market,
          primaryCommodityId: 'alloy',
          state: uiState,
        );
        ui.endFrame();

        ui.beginFrame(VoxInput());
        EconomyFactoryUI.render(
          ui,
          factory,
          market: market,
          primaryCommodityId: 'alloy',
          state: uiState,
        );
        final drawList = ui.endFrame();

        expect(market.priceOf('alloy'), greaterThan(spotBefore));
        expect(
          drawList.commands.any(
            (c) => (c.text?.startsWith('alloy @ ') ?? false),
          ),
          isTrue,
        );

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('FactoryProducerComponent'), isNotNull);
        expect(reg.specByName('DynamicMarketComponent'), isNotNull);
        final json = reg.specFor(factory)!.toJson(factory);
        expect(json['maxActiveSlots'], 1);
      },
    );
  });

  group('E62 — Modular Snap-Grid Construction & Blueprints (voxbuild)', () {
    test(
      'ConstructionPlannerComponent snaps sockets, spawns colliders, captures/stamps blueprints & renders BuilderInspectorUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        const floorDef = BuildPieceDef(
          id: 'floor',
          name: 'Wood Deck',
          halfExtents: BuildVec3(1.0, 0.1, 1.0),
          providesFoundationSupport: true,
          costs: [BuildCostItem('wood', 4.0)],
          sockets: [
            BuildSocket(
              id: 'wall_north',
              socketType: 'wall_base',
              localPosition: BuildVec3(0.0, 0.1, -1.0),
              localForward: BuildVec3(0.0, 0.0, -1.0),
            ),
          ],
        );
        const wallDef = BuildPieceDef(
          id: 'wall',
          name: 'Stone Wall',
          halfExtents: BuildVec3(1.0, 1.0, 0.15),
          requiresGrounded: true,
          costs: [BuildCostItem('stone', 6.0)],
          sockets: [
            BuildSocket(
              id: 'bottom',
              socketType: 'wall_base',
              localPosition: BuildVec3(0.0, -1.0, 0.0),
              localForward: BuildVec3(0.0, 0.0, 1.0),
            ),
          ],
        );

        final planner =
            scene
                .createGameObject('BuilderRig')
                .addComponent(
                  ConstructionPlannerComponent(
                    gridSize: 2.0,
                    socketSnapRadius: 1.5,
                  ),
                )
              ..registerPieceDef(floorDef)
              ..registerPieceDef(wallDef);

        planner.activeDefId = 'floor';
        final fObj = planner.placeAt(const Vec3(0.1, 0.05, 0.2));
        expect(fObj, isNotNull);
        expect(fObj!.getComponent<BoxCollider>(), isNotNull);
        expect(fObj.getComponent<BlueprintPieceComponent>()!.defId, 'floor');

        planner.activeDefId = 'wall';
        final cand = planner.previewAt(const Vec3(0.0, 0.15, -1.05));
        expect(cand.isValid, isTrue);
        expect(cand.snappedToSocketId, 'wall_north');
        final wObj = planner.placeAt(const Vec3(0.0, 0.15, -1.05));
        expect(wObj, isNotNull);
        expect(planner.placedCount, 2);
        expect(planner.totalStructureCost['wood'], closeTo(4.0, 1e-6));
        expect(planner.totalStructureCost['stone'], closeTo(6.0, 1e-6));

        final bp = planner.captureBlueprint('WatchBay', origin: Vec3.zero);
        final stamped = planner.stampBlueprint(
          bp,
          const Vec3(10.0, 0.0, 0.0),
          yawSteps: 1,
        );
        expect(stamped.length, 2);
        expect(planner.placedCount, 4);

        // Click 'Rot +90' (x=150, y=156) and 'Undo' (x=232, y=156) via BuilderInspectorUI.
        final ui = VoxUiContext();
        final uiState = BuilderInspectorUiState();
        const rotX = 150.0;
        const undoX = 232.0;
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: rotX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        BuilderInspectorUI.render(ui, planner, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: rotX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        BuilderInspectorUI.render(ui, planner, state: uiState);
        ui.endFrame();
        expect(planner.activeYawSteps, 1);

        ui.beginFrame(
          VoxInput(
            mouseX: undoX,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        BuilderInspectorUI.render(ui, planner, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: undoX,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        BuilderInspectorUI.render(ui, planner, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        BuilderInspectorUI.render(ui, planner, state: uiState);
        final drawList = ui.endFrame();

        expect(planner.placedCount, 3);
        expect(drawList.commands.any((c) => c.text == 'wall / 90deg'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('BlueprintPieceComponent'), isNotNull);
        expect(reg.specByName('ConstructionPlannerComponent'), isNotNull);
        final json = reg.specFor(planner)!.toJson(planner);
        expect(json['gridSize'], 2.0);
      },
    );
  });

  group('E66 — Digital Logic Circuits & Clock Propagation (voxcircuit)', () {
    test(
      'LogicCircuitComponent propagates gates & clocked flip-flops, syncs bound lamps & renders CircuitDebuggerUI',
      () {
        final engine = Engine(HeadlessHost());
        final scene = engine.scene;

        final lampGo = scene.createGameObject(
          'OutputLamp',
          components: [
            MeshRenderer(meshData: Primitives.cube(size: 1.0)),
            Light(intensity: 0.0),
          ],
        );

        final circuit =
            scene
                .createGameObject('CircuitBoard')
                .addComponent(LogicCircuitComponent(tickHz: 20.0))
              ..addGate(CircuitGateDef.input('sw_a'))
              ..addGate(CircuitGateDef.input('sw_b'))
              ..addGate(CircuitGateDef.gate('gate_and', CircuitGateKind.and))
              ..addGate(CircuitGateDef.lamp('lamp_out'))
              ..addGate(CircuitGateDef.clock('clk', halfPeriodTicks: 1))
              ..addGate(
                CircuitGateDef.gate(
                  'dff',
                  CircuitGateKind.dFlipFlop,
                  inputCount: 3,
                  outputCount: 2,
                ),
              )
              ..connect('sw_a', 0, 'gate_and', 0)
              ..connect('sw_b', 0, 'gate_and', 1)
              ..connect('gate_and', 0, 'lamp_out', 0)
              ..connect('clk', 0, 'dff', 1)
              ..connect('dff', 1, 'dff', 0)
              ..bindLampObject('lamp_out', lampGo);

        circuit.setInput('sw_a', true);
        circuit.setInput('sw_b', false);
        engine.step(0.05);
        engine.step(0.05); // 2 ticks at 20 Hz
        expect(circuit.readOutput('lamp_out'), isFalse);
        expect(lampGo.getComponent<Light>()!.intensity, closeTo(0.0, 1e-6));
        expect(circuit.readOutput('dff', pinIndex: 0), isTrue);

        circuit.toggleInput('sw_b');
        engine.step(0.05);
        engine.step(0.05); // propagates AND -> lamp_out
        expect(circuit.readOutput('lamp_out'), isTrue);
        expect(lampGo.getComponent<Light>()!.intensity, greaterThan(1.0));
        expect(lampGo.getComponent<Light>()!.color.g, greaterThan(0.8));

        // Click 'Step +4' (x=152, y=156) and 'Pause' (x=236, y=156) in CircuitDebuggerUI
        final ui = VoxUiContext();
        final uiState = CircuitDebuggerUiState();
        final ticksBefore = circuit.tickCount;
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 152.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        CircuitDebuggerUI.render(ui, circuit, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 152.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        CircuitDebuggerUI.render(ui, circuit, state: uiState);
        ui.endFrame();
        expect(circuit.tickCount, ticksBefore + 4);

        ui.beginFrame(
          VoxInput(
            mouseX: 236.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        CircuitDebuggerUI.render(ui, circuit, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 236.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        CircuitDebuggerUI.render(ui, circuit, state: uiState);
        ui.endFrame();

        ui.beginFrame(VoxInput());
        CircuitDebuggerUI.render(ui, circuit, state: uiState);
        final drawList = ui.endFrame();

        expect(circuit.paused, isTrue);
        expect(drawList.commands.any((c) => c.text == 'PAUSED'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('LogicCircuitComponent'), isNotNull);
        final json = reg.specFor(circuit)!.toJson(circuit);
        expect(json['tickHz'], 20.0);
        expect(json['paused'], isTrue);
      },
    );
  });

  group('E69 — Branching Quest DAGs & Faction Matrix (voxquest)', () {
    test(
      'QuestLogComponent drives branching quests, saves/loads via engine.host.storage & renders QuestJournalUI',
      () {
        final host = HeadlessHost();
        final engine = Engine(host);
        final scene = engine.scene;

        final journal = scene
            .createGameObject('PlayerJournal')
            .addComponent(QuestLogComponent(storageKey: 'campaign_save_01'));
        journal
          ..registerFaction(
            const FactionDef(
              id: 'keepers',
              displayName: 'Lantern Keepers',
              relations: {'brigands': -0.75},
            ),
          )
          ..registerFaction(
            const FactionDef(id: 'brigands', displayName: 'Iron Brigands'),
          )
          ..registerQuest(
            const QuestDef(
              id: 'q_beacon',
              title: 'Relight the Beacon',
              entryStageId: 's_fork',
              stages: [
                QuestStageDef(
                  id: 's_fork',
                  title: 'Approach Ruins',
                  branchChoices: {
                    'help_keepers': 's_oil',
                    'raid_convoy': 's_sabotage',
                  },
                ),
                QuestStageDef(
                  id: 's_oil',
                  title: 'Collect Oil Flasks',
                  mutuallyExclusiveWithStages: ['s_sabotage'],
                  objectives: [
                    QuestObjectiveDef.allOf(
                      id: 'obj_prep',
                      description: 'Reach tower with 2 oil flasks',
                      children: [
                        QuestObjectiveDef.location(
                          id: 'c_loc',
                          description: 'Tower Spire',
                          targetTag: 'spire',
                        ),
                        QuestObjectiveDef.deliver(
                          id: 'c_oil',
                          description: 'Oil Flasks',
                          targetTag: 'oil_flask',
                          requiredCount: 2,
                        ),
                      ],
                    ),
                  ],
                  factionRewards: {'keepers': 35.0},
                ),
                QuestStageDef(
                  id: 's_sabotage',
                  title: 'Siphon Fuel',
                  mutuallyExclusiveWithStages: ['s_oil'],
                  objectives: [
                    QuestObjectiveDef.location(
                      id: 'c_camp',
                      description: 'Brigand Camp',
                      targetTag: 'camp',
                    ),
                  ],
                ),
              ],
            ),
          );

        // Click 'Accept Next' (x=77, y=156) in QuestJournalUI
        final ui = VoxUiContext();
        final uiState = QuestJournalUiState();
        const btnY = 156.0;

        ui.beginFrame(
          VoxInput(
            mouseX: 77.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 77.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();
        expect(journal.activeQuests.length, 1);

        expect(journal.chooseBranch('q_beacon', 'help_keepers'), isTrue);
        expect(
          journal.getQuest('q_beacon')!.isBranchLocked('s_sabotage'),
          isTrue,
        );
        journal.recordProgress(
          targetTag: 'oil_flask',
          kind: QuestObjectiveKind.deliver,
          amount: 1,
        );

        // Click 'Save Log' (x=173, y=156) in QuestJournalUI
        ui.beginFrame(
          VoxInput(
            mouseX: 173.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 173.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();
        expect(host.storage.read('campaign_save_01'), isNotNull);

        // Advance then reload old snapshot via UI 'Reload' (x=258, y=156)
        journal.recordProgress(
          targetTag: 'spire',
          kind: QuestObjectiveKind.location,
        );
        expect(
          journal
              .getQuest('q_beacon')!
              .activeObjectives['obj_prep']!
              .children[0]
              .completed,
          isTrue,
        );

        ui.beginFrame(
          VoxInput(
            mouseX: 258.0,
            mouseY: btnY,
            isMouseDown: true,
            wasMouseClicked: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();
        ui.beginFrame(
          VoxInput(
            mouseX: 258.0,
            mouseY: btnY,
            isMouseDown: false,
            wasMouseReleased: true,
          ),
        );
        QuestJournalUI.render(ui, journal, state: uiState);
        ui.endFrame();

        expect(
          journal
              .getQuest('q_beacon')!
              .activeObjectives['obj_prep']!
              .children[0]
              .completed,
          isFalse,
        );
        journal.recordProgress(
          targetTag: 'spire',
          kind: QuestObjectiveKind.location,
        );
        journal.recordProgress(
          targetTag: 'oil_flask',
          kind: QuestObjectiveKind.deliver,
          amount: 1,
        );
        expect(journal.getQuest('q_beacon')!.isCompleted, isTrue);
        expect(journal.factions.getRank('keepers'), FactionRank.friendly);
        expect(journal.factions.isHostile('brigands'), isTrue);

        ui.beginFrame(VoxInput());
        QuestJournalUI.render(ui, journal, state: uiState);
        final drawList = ui.endFrame();
        expect(drawList.commands.any((c) => c.text == '0 / 1'), isTrue);

        final reg = ComponentRegistry.defaults();
        expect(reg.specByName('QuestLogComponent'), isNotNull);
        final json = reg.specFor(journal)!.toJson(journal);
        expect(json['storageKey'], 'campaign_save_01');
      },
    );
  });
}
