import 'package:gl_volition/gl_volition_web.dart';
import 'package:web/web.dart' as web;

import 'game.dart';

Future<void> main() async {
  final canvas =
      web.document.getElementById('viewport') as web.HTMLCanvasElement;
  final runner = await WebEngineHost.mount(
    canvas,
    enableHotState: true,
    registerSpecs: registerPrismPulseSpecs,
    initialScene: buildPrismPulseScene(),
  );
  runner?.start();
}
