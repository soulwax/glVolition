/// UICanvas controls, focus traversal, voxui layout & EngineWorkbenchComponent tests.
library;

import 'package:gl_volition/gl_volition_native.dart';
import 'package:test/test.dart';

void main() {
  group('E4 — UICanvas Pointer Click Dispatch', () {
    test(
      'UICanvas dispatches UIButton click from ScriptedInput pointer events',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 360;
        final engine = Engine(host);

        var clicked = 0;
        final canvas = UICanvas(designWidth: 640, designHeight: 360);
        canvas.add(
          UIButton(
            label: 'START',
            anchor: UIAnchor.center,
            width: 120,
            height: 40,
            onPressed: () => clicked++,
          ),
        );
        engine.scene.createGameObject('HUD', components: [canvas]);

        // Press at center (320, 180)
        host.input
          ..pointerX = 320
          ..pointerY = 180
          ..pointerDown = true
          ..pointerPressed = true;
        engine.step(0.016);
        host.input.endFrame();
        expect(clicked, 0);

        // Release at center (320, 180)
        host.input
          ..pointerDown = false
          ..pointerReleased = true;
        engine.step(0.016);
        host.input.endFrame();
        expect(clicked, 1);
      },
    );
  });

  group('E8 — Modular UICanvas Controls (UIStack, UIToggle, UISlider)', () {
    test(
      'UIStack lays out UIToggle and UISlider and dispatches pointer interactions',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 360;
        final engine = Engine(host);

        final canvas = UICanvas(designWidth: 640, designHeight: 360);
        var toggledValue = false;
        var sliderValue = 0.0;

        final toggle = UIToggle(
          label: 'Mute',
          width: 20,
          height: 20,
          onChanged: (v) => toggledValue = v,
        );
        final slider = UISlider(
          width: 100,
          height: 12,
          min: 0,
          max: 100,
          value: 20,
          onChanged: (v) => sliderValue = v,
        );
        final stack = UIStack(
          anchor: UIAnchor.topLeft,
          x: 10,
          y: 10,
          padding: 4,
          spacing: 6,
          children: [toggle, slider],
        );
        canvas.add(stack);
        engine.scene.createGameObject('HUD', components: [canvas]);

        // Verify vertical layout coordinates
        stack.layout(canvasW: 640, canvasH: 360);
        expect(toggle.x, closeTo(14, 1e-5));
        expect(toggle.y, closeTo(14, 1e-5));
        expect(slider.x, closeTo(14, 1e-5));
        expect(slider.y, closeTo(40, 1e-5));

        // Click toggle at (20, 20)
        host.input
          ..pointerX = 20
          ..pointerY = 20
          ..pointerDown = true
          ..pointerPressed = true;
        engine.step(0.016);
        host.input.endFrame();
        expect(toggle.value, isTrue);
        expect(toggledValue, isTrue);

        // Drag slider to 75% at x = 14 + 75 = 89, y = 45
        host.input
          ..pointerX = 89
          ..pointerY = 45
          ..pointerDown = true
          ..pointerPressed = true;
        engine.step(0.016);
        host.input.endFrame();
        expect(sliderValue, closeTo(75.0, 1e-4));
      },
    );
  });

  group('E13 — UITextField Editing & Submission', () {
    test(
      'UITextField focuses on click, edits text on key presses, and fires onSubmitted on Enter',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 360;
        final engine = Engine(host);

        String? submittedText;
        final field = UITextField(
          anchor: UIAnchor.topLeft,
          x: 20,
          y: 20,
          width: 140,
          height: 24,
          onSubmitted: (t) => submittedText = t,
        );
        final canvas = UICanvas(designWidth: 640, designHeight: 360)
          ..add(field);
        engine.scene.createGameObject('UI', components: [canvas]);

        // Click inside UITextField to focus
        host.input
          ..pointerX = 40
          ..pointerY = 30
          ..pointerDown = true
          ..pointerPressed = true;
        engine.step(0.016);
        host.input.endFrame();
        expect(field.isFocused, isTrue);

        // Type 'H', 'i', '!', Backspace, 'Enter'
        host.input
          ..press('ShiftLeft')
          ..press('KeyH');
        engine.step(0.016);
        host.input
          ..release('ShiftLeft')
          ..release('KeyH')
          ..endFrame();

        host.input
          ..press('KeyI')
          ..press('Digit1');
        engine.step(0.016);
        host.input
          ..release('KeyI')
          ..release('Digit1')
          ..endFrame();
        expect(field.text, 'Hi1');

        host.input
          ..press('Backspace')
          ..press('Enter');
        engine.step(0.016);
        host.input
          ..release('Backspace')
          ..release('Enter')
          ..endFrame();

        expect(field.text, 'Hi');
        expect(submittedText, 'Hi');
      },
    );
  });

  group('E19 — UIImage SpriteBatch Rendering', () {
    test('UIImage renders into UICanvas SpriteBatch without crashing', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      engine.scene.createGameObject('UI', components: [canvas]);

      final img = canvas.add(
        UIImage(
          region: SpriteRegion.white,
          x: 10,
          y: 20,
          width: 64,
          height: 64,
          tintColor: 0xFF00FFFF,
          flipX: true,
        ),
      );

      expect(canvas.elements.contains(img), isTrue);

      // Stepping engine runs UICanvas.update and renders batch
      engine.step(0.016);
    });
  });

  group('E21 — UIDropdown Selection', () {
    test('UIDropdown toggles popup menu and selects items on click', () {
      final host = HeadlessHost();
      host.graphics
        ..viewportWidth = 640
        ..viewportHeight = 360;
      final engine = Engine(host);

      final canvas = UICanvas(designWidth: 640, designHeight: 360);
      engine.scene.createGameObject('UI', components: [canvas]);

      int selectedIdx = -1;
      String selectedVal = '';
      final dropdown = canvas.add(
        UIDropdown(
          options: ['Quality: Low', 'Quality: Medium', 'Quality: Ultra'],
          selectedIndex: 0,
          x: 10,
          y: 10,
          width: 140,
          height: 24,
          onSelected: (idx, val) {
            selectedIdx = idx;
            selectedVal = val;
          },
        ),
      );

      expect(dropdown.isOpen, isFalse);
      expect(dropdown.selectedOption, 'Quality: Low');

      // Click dropdown header (10, 10) to open
      final input = host.input;
      input
        ..pointerX = 20
        ..pointerY = 20
        ..pointerDown = true
        ..pointerPressed = true;
      engine.step(0.016);
      expect(dropdown.isOpen, isTrue);

      // Release pointer
      input
        ..pointerDown = false
        ..pointerPressed = false
        ..pointerReleased = true;
      engine.step(0.016);

      // Click on item 2 (Quality: Ultra):
      // header is [10..34]
      // item 0 is [34..58]
      // item 1 is [58..82]
      // item 2 is [82..106] -> y = 90
      input
        ..pointerX = 20
        ..pointerY = 90
        ..pointerDown = true
        ..pointerPressed = true
        ..pointerReleased = false;
      engine.step(0.016);

      expect(selectedIdx, 2);
      expect(selectedVal, 'Quality: Ultra');
      expect(dropdown.selectedOption, 'Quality: Ultra');
      expect(dropdown.isOpen, isFalse);
    });
  });

  group('E23 — UIButton Enabled & Disabled State', () {
    test(
      'UIButton enabled state controls hover/press interactions and disabled colors',
      () {
        final host = HeadlessHost();
        host.graphics
          ..viewportWidth = 640
          ..viewportHeight = 360;
        final engine = Engine(host);

        final canvas = UICanvas(designWidth: 640, designHeight: 360);
        engine.scene.createGameObject('UI', components: [canvas]);

        var clicked = false;
        final btn = canvas.add(
          UIButton(
            label: 'Submit',
            x: 10,
            y: 10,
            width: 100,
            height: 30,
            enabled: false,
            onPressed: () => clicked = true,
          ),
        );

        // Pointer click while disabled -> no click, no hover
        final input = host.input;
        input
          ..pointerX = 20
          ..pointerY = 20
          ..pointerDown = true
          ..pointerPressed = true;
        engine.step(0.016);
        expect(btn.isHovered, isFalse);
        expect(btn.isPressed, isFalse);
        expect(clicked, isFalse);

        // Enable button and click again -> succeeds
        btn.enabled = true;
        engine.step(0.016);
        expect(btn.isPressed, isTrue);

        input
          ..pointerDown = false
          ..pointerPressed = false
          ..pointerReleased = true;
        engine.step(0.016);
        expect(clicked, isTrue);
      },
    );
  });

  group('E26 — UICanvas Focus Navigation', () {
    test('UICanvas manages focus navigation and keyboard traversal', () {
      final host = HeadlessHost();
      final engine = Engine(host);

      var btn1Clicks = 0;
      var btn2Clicks = 0;
      final btn1 = UIButton(
        label: 'Btn1',
        width: 100,
        height: 30,
        onPressed: () => btn1Clicks++,
      );
      final btn2 = UIButton(
        label: 'Btn2',
        x: 120,
        width: 100,
        height: 30,
        onPressed: () => btn2Clicks++,
      );

      final canvas = UICanvas();
      canvas.add(btn1);
      canvas.add(btn2);
      engine.scene.createGameObject('UI', components: [canvas]);

      expect(canvas.focusedElement, isNull);

      // Tab -> focus first element (btn1)
      canvas.focusNext();
      expect(canvas.focusedElement, btn1);
      expect(btn1.isFocused, isTrue);
      expect(btn2.isFocused, isFalse);

      // Submit focused -> clicks btn1
      canvas.submitFocused();
      expect(btn1Clicks, 1);
      expect(btn2Clicks, 0);

      // Tab again -> focus btn2
      canvas.focusNext();
      expect(canvas.focusedElement, btn2);
      expect(btn1.isFocused, isFalse);
      expect(btn2.isFocused, isTrue);

      // Submit focused -> clicks btn2
      canvas.submitFocused();
      expect(btn1Clicks, 1);
      expect(btn2Clicks, 1);

      // Tab wraps around back to btn1
      canvas.focusNext();
      expect(canvas.focusedElement, btn1);

      // Shift+Tab navigates backwards to btn2
      canvas.focusPrevious();
      expect(canvas.focusedElement, btn2);
    });
  });

  group('E27 — voxui Immediate-Mode Layout & Sliders', () {
    test('voxui immediate-mode layout, sliders, and draw commands', () {
      final ui = VoxUiContext();
      // Window at (10, 10). Title(26) + pad(10) + text(17) + sep(8) => checkbox at y ~ 83..103.
      final input = VoxInput(
        mouseX: 50,
        mouseY: 90,
        wasMouseClicked: true,
        isMouseDown: true,
      );

      ui.beginFrame(input);
      final opened = ui.beginWindow(
        'Performance Diagnostics',
        x: 10,
        y: 10,
        width: 240,
        height: 160,
      );
      expect(opened, isTrue);

      ui.text('Frame Budget: 16.6ms');
      ui.separator();
      final wireframe = ui.checkbox('Show Colliders', false);
      expect(wireframe, isTrue);

      ui.endWindow();
      final dl = ui.endFrame();
      expect(dl.commands, isNotEmpty);
      expect(dl.commands.any((cmd) => cmd.text == 'Show Colliders'), isTrue);
    });
  });

  group('E96 — Cross-Platform VoxUiRenderer & EngineWorkbenchComponent', () {
    test(
      'EngineWorkbenchComponent renders DOM-free voxui hierarchy/inspector/profiler onto GlesDevice SpriteStage.overlay',
      () async {
        final device = GlesDevice();
        final runner = await NativeEngineHost.boot(
          device: device,
          width: 1280,
          height: 720,
          requestedProfile: QualityProfile.clean,
        );
        try {
          final camGo = runner.scene.createGameObject(
            'MainCamera',
            position: const Vec3(0, 2, 6),
          );
          camGo.transform.lookAt(Vec3.zero);
          camGo.addComponent(Camera());

          final crate = runner.scene.createGameObject(
            'SampleCrate',
            position: const Vec3(1.5, 0.5, 0.0),
          );
          final workbenchGo = runner.scene.createGameObject('Workbench');
          final wb = workbenchGo.addComponent(
            EngineWorkbenchComponent(visible: true),
          );
          workbenchGo.addComponent(DebugController());

          // Step & render on NativeEngineHost -> encodes voxui DrawList via VoxUiRenderer
          runner.renderFrame(1 / 60);
          expect(wb.lastDrawList, isNotNull);
          expect(wb.lastRenderedCommands, greaterThan(10));
          expect(wb.uiRenderer.lastBatchLength, greaterThan(10));

          // Click Inspector tab at (206.0, 64.0) via ScriptedInput -> switches activeTab
          runner.host.input
            ..pointerX = 206.0
            ..pointerY = 64.0
            ..pointerPressed = true
            ..pointerDown = true;
          runner.renderFrame(1 / 60);
          runner.host.input
            ..pointerPressed = false
            ..pointerReleased = true
            ..pointerDown = false;
          runner.renderFrame(1 / 60);
          expect(wb.activeTab, WorkbenchTab.inspector);

          // Select crate & switch to Profiler tab (328.0, 64.0)
          wb.selectedObject = crate;
          runner.host.input
            ..pointerX = 328.0
            ..pointerY = 64.0
            ..pointerPressed = true
            ..pointerDown = true
            ..pointerReleased = false;
          runner.renderFrame(1 / 60);
          runner.host.input
            ..pointerPressed = false
            ..pointerReleased = true
            ..pointerDown = false;
          runner.renderFrame(1 / 60);
          expect(wb.activeTab, WorkbenchTab.profiler);

          // Press F11 toggles visibility off -> encode emits 0 new commands
          runner.host.input.pointerReleased = false;
          runner.host.input.press('F11');
          runner.renderFrame(1 / 60);
          expect(wb.visible, isFalse);

          // ComponentRegistry round-trip
          final reg = ComponentRegistry.defaults();
          expect(reg.specByName('EngineWorkbenchComponent'), isNotNull);
          final json = reg.specFor(wb)!.toJson(wb);
          expect(json['toggleKeyCode'], 'F11');
          expect(json['activeTab'], 'profiler');
        } finally {
          runner.dispose();
        }
        expect(device.liveObjectCount, 0);
      },
    );
  });
}
