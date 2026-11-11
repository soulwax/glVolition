part of '../../engine.dart';

/// Component managing dialogue conversation state on a GameObject (NPC, interactable, narrator) (E37).
class DialogueComponent extends Behaviour {
  final talk.DialogueGraph graph;
  final bool autoStart;
  final double typewriterSpeed;
  final talk.VariableStore variables;

  late final talk.DialogueRunner runner;

  void Function(talk.DialogueNode node)? onNodeEnter;
  void Function()? onDialogueComplete;

  DialogueComponent({
    required this.graph,
    this.autoStart = false,
    this.typewriterSpeed = 40.0,
    talk.VariableStore? variables,
    this.onNodeEnter,
    this.onDialogueComplete,
  }) : variables = variables ?? talk.VariableStore() {
    runner = talk.DialogueRunner(
      graph: graph,
      variables: this.variables,
      typewriterSpeed: typewriterSpeed,
      onNodeEnter: (node) => onNodeEnter?.call(node),
      onDialogueComplete: () => onDialogueComplete?.call(),
    );
  }

  bool get isRunning => runner.isRunning;
  bool get isComplete => runner.isComplete;
  String get speaker => runner.currentNode?.speaker ?? '';
  String get text => runner.displayedText;
  List<talk.DialogueChoice> get choices => runner.availableChoices;

  @override
  void start() {
    if (autoStart) {
      runner.start();
    }
  }

  @override
  void update() {
    if (runner.isRunning) {
      runner.update(time.deltaTime);
    }
  }

  void startDialogue([String? entryNodeId]) => runner.start(entryNodeId);
  void advance() => runner.advance();
  void selectChoice(int index) => runner.selectChoice(index);
}

/// Central Quest Management component tracking active, completed and failed quests (E37).
class QuestManagerComponent extends Component {
  final talk.QuestTracker tracker;

  QuestManagerComponent({talk.VariableStore? variables})
      : tracker = talk.QuestTracker(variables: variables);

  talk.VariableStore get variables => tracker.variables;
  List<talk.Quest> get activeQuests => tracker.activeQuests;
  List<talk.Quest> get completedQuests => tracker.completedQuests;

  void registerQuest(talk.Quest quest) => tracker.registerQuest(quest);
  void startQuest(String id) => tracker.startQuest(id);
  void advanceObjective(String questId, String objectiveId, [int amount = 1]) =>
      tracker.advanceObjective(questId, objectiveId, amount);
  void completeQuest(String id) => tracker.completeQuest(id);
  void failQuest(String id) => tracker.failQuest(id);
  talk.Quest? getQuest(String id) => tracker.getQuest(id);
}

/// Immediate-mode dialogue UI renderer utilizing `package:voxui` (E37).
class DialogueUI {
  /// Renders active [runner] conversation as an immediate-mode dialogue box.
  static void render(
    VoxUiContext ctx,
    talk.DialogueRunner runner, {
    double x = 40.0,
    double y = 300.0,
    double width = 500.0,
    double height = 160.0,
  }) {
    if (!runner.isRunning) return;

    final node = runner.currentNode;
    if (node == null) return;

    final title = node.speaker.isNotEmpty ? node.speaker : 'Dialogue';
    if (!ctx.beginWindow(title, x: x, y: y, width: width, height: height)) {
      ctx.endWindow();
      return;
    }

    // Speech text
    ctx.text(runner.displayedText);
    ctx.spacing(8.0);

    // Branching choices or advance prompt
    if (runner.isTypewriterComplete) {
      final choices = runner.availableChoices;
      if (choices.isNotEmpty) {
        for (int i = 0; i < choices.length; i++) {
          if (ctx.button('${i + 1}. ${choices[i].text}', height: 22.0)) {
            runner.selectChoice(i);
            break;
          }
        }
      } else {
        if (ctx.button('Continue >', width: 100.0, height: 22.0)) {
          runner.advance();
        }
      }
    } else {
      if (ctx.button('Skip >>', width: 80.0, height: 20.0)) {
        runner.completeTypewriter();
      }
    }

    ctx.endWindow();
  }
}
