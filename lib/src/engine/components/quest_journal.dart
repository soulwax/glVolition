part of '../../engine.dart';

/// Scene quest DAG & faction reputation log component with [EngineHost.storage] persistence (`voxquest`) (E69-2).
final class QuestLogComponent extends Behaviour {
  String storageKey;
  bool autoSave;

  final quest.QuestTracker tracker;

  QuestLogComponent({
    this.storageKey = 'voxquest_log',
    this.autoSave = false,
    quest.QuestTracker? tracker,
  }) : tracker = tracker ?? quest.QuestTracker();

  static final spec = ComponentSpec<QuestLogComponent>(
    'QuestLogComponent',
    QuestLogComponent.new,
    [
      Field.text('storageKey', (q) => q.storageKey, (q, v) => q.storageKey = v),
      Field.boolean('autoSave', (q) => q.autoSave, (q, v) => q.autoSave = v),
    ],
  );

  quest.FactionReputationMatrix get factions => tracker.factions;

  void registerFaction(quest.FactionDef def) => tracker.factions.registerFaction(def);

  void registerQuest(quest.QuestDef def) => tracker.registerQuest(def);

  quest.QuestInstance? getQuest(String questId) => tracker.getQuest(questId);

  List<quest.QuestInstance> get allQuests => tracker.allQuests;
  List<quest.QuestInstance> get availableQuests => tracker.availableQuests;
  List<quest.QuestInstance> get activeQuests => tracker.activeQuests;
  List<quest.QuestInstance> get completedQuests => tracker.completedQuests;

  bool acceptQuest(String questId) {
    final ok = tracker.acceptQuest(questId);
    if (ok && autoSave) saveToStorage();
    return ok;
  }

  List<String> recordProgress({
    required String targetTag,
    quest.QuestObjectiveKind? kind,
    int amount = 1,
    String? questId,
  }) {
    final progressed = tracker.recordProgress(
      targetTag: targetTag,
      kind: kind,
      amount: amount,
      questId: questId,
    );
    if (progressed.isNotEmpty && autoSave) saveToStorage();
    return progressed;
  }

  bool chooseBranch(String questId, String choiceId) {
    final ok = tracker.chooseBranch(questId, choiceId);
    if (ok && autoSave) saveToStorage();
    return ok;
  }

  bool failQuest(String questId) {
    final ok = tracker.failQuest(questId);
    if (ok && autoSave) saveToStorage();
    return ok;
  }

  void saveToStorage([String? keyOverride]) {
    if (!isAttached) return;
    engine.host.storage.write(
      keyOverride ?? storageKey,
      jsonEncode(tracker.toJson()),
    );
  }

  bool loadFromStorage([String? keyOverride]) {
    if (!isAttached) return false;
    final raw = engine.host.storage.read(keyOverride ?? storageKey);
    if (raw == null || raw.isEmpty) return false;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return false;
    tracker.loadFromJson(Map<String, Object?>.from(decoded));
    return true;
  }
}

/// Persistent UI interaction state for [QuestJournalUI.render].
final class QuestJournalUiState {
  String? activeButtonId;
}

/// Immediate-mode `voxui` quest journal & faction reputation monitor (E69-2).
final class QuestJournalUI {
  static bool _drawButton(
    VoxUiContext ui,
    QuestJournalUiState state,
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
    if (inp.wasMouseReleased && state.activeButtonId == id) state.activeButtonId = null;

    final bg = pressed
        ? ui.style.buttonActive
        : (hovered ? ui.style.buttonHover : ui.style.buttonBg);
    dl.addRectFilled(rect.x, rect.y, rect.width, rect.height, bg, cornerRadius: ui.style.frameRounding);
    dl.addRectOutline(rect.x, rect.y, rect.width, rect.height, ui.style.windowBorder, cornerRadius: ui.style.frameRounding);
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
    QuestLogComponent journal, {
    QuestJournalUiState? state,
    String title = 'Quest Journal',
    double x = 20.0,
    double y = 20.0,
    double width = 360.0,
    double height = 240.0,
  }) {
    final uiState = state ?? QuestJournalUiState();
    if (!ui.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ui.endWindow();
      return;
    }

    final pad = ui.style.windowPadding;
    final active = journal.activeQuests;
    final available = journal.availableQuests;
    final completed = journal.completedQuests;

    ui.labelValue(
      'Active Quests',
      '${active.length}',
      valueColor: VoxColor.cyan,
    );
    ui.labelValue(
      'Available / Done',
      '${available.length} / ${completed.length}',
      valueColor: VoxColor.green,
    );
    final currentHeadline = active.isNotEmpty
        ? '${active.first.def.title} (${active.first.currentStage?.title ?? "-"})'
        : (available.isNotEmpty ? 'Ready: ${available.first.def.title}' : 'None');
    ui.labelValue(
      'Tracked',
      currentHeadline,
      valueColor: VoxColor.yellow,
    );

    final fids = journal.factions.factionIds;
    final factionSummary = fids.isNotEmpty
        ? '${fids.first}: ${journal.factions.getRank(fids.first).name}'
        : '0 tracked';
    ui.labelValue(
      'Faction Standing',
      factionSummary,
      valueColor: VoxColor.lightGray,
    );

    final barY = y + ui.style.titleBarHeight + pad + 90.0;
    final acceptRect = VoxRect(x + pad, barY, 94.0, 22.0);
    if (_drawButton(ui, uiState, 'qst_accept', 'Accept Next', acceptRect)) {
      if (available.isNotEmpty) {
        journal.acceptQuest(available.first.def.id);
      }
    }

    final saveRect = VoxRect(acceptRect.right + 8.0, barY, 82.0, 22.0);
    if (_drawButton(ui, uiState, 'qst_save', 'Save Log', saveRect)) {
      journal.saveToStorage();
    }

    final loadRect = VoxRect(saveRect.right + 8.0, barY, 72.0, 22.0);
    if (_drawButton(ui, uiState, 'qst_load', 'Reload', loadRect)) {
      journal.loadFromStorage();
    }

    ui.endWindow();
  }
}
