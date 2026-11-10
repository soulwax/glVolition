import 'package:gl_volition/gl_volition_web.dart';
import 'package:web/web.dart' as web;

import 'game.dart';

void main() async {
  final canvas = web.document.querySelector('#game');
  if (canvas is! web.HTMLCanvasElement) return;
  final hud = DomRocketHud();

  final runner = await WebEngineHost.mount(
    canvas,
    requestedProfile: QualityProfile.clean,
    enableHotState: true,
    registerSpecs: registerPixelRocketSpecs,
  );
  if (runner == null) {
    hud.message('WebGL2 unavailable', 'This browser cannot run Pixel Rocket.');
    return;
  }

  hud.message('PIXEL ROCKET', 'loading assets…');
  final RocketDirector director;
  try {
    final visuals = await RocketVisualAssets.load(runner.engine.assets);
    director = buildPixelRocketScene(
      runner.engine,
      hud: hud,
      visuals: visuals,
    );
  } catch (e, s) {
    print('Pixel Rocket failed to load: $e\n$s');
    hud.message('LOAD FAILED', '$e');
    return;
  }

  if (Uri.base.queryParameters.containsKey('autostart')) {
    director.startGame();
  }
  runner.start();
}

final class DomRocketHud implements RocketHud {
  final web.Element? _score = web.document.querySelector('#score');
  final web.Element? _best = web.document.querySelector('#best');
  final web.Element? _speed = web.document.querySelector('#speed');
  final web.Element? _shields = web.document.querySelector('#shields');
  final web.HTMLElement? _fuel = web.document.querySelector('#fuel-fill') as web.HTMLElement?;
  final web.HTMLElement? _card = web.document.querySelector('#card') as web.HTMLElement?;
  final web.Element? _title = web.document.querySelector('#card-title');
  final web.Element? _body = web.document.querySelector('#card-body');
  final web.HTMLElement? _boost = web.document.querySelector('#boost') as web.HTMLElement?;

  String _last = '';

  @override
  void message(String title, String body, {int? best}) {
    _title?.textContent = title;
    _body?.textContent = body;
    if (best != null) _best?.textContent = 'BEST $best';
    _card?.classList.remove('hidden');
  }

  @override
  void hideMessage() => _card?.classList.add('hidden');

  @override
  void update({
    required int score,
    required double speed,
    required int shields,
    required double fuel,
    required bool boosting,
  }) {
    final key = '$score|${speed.round()}|$shields|${fuel.round()}|$boosting';
    if (key == _last) return;
    _last = key;
    _score?.textContent = '$score';
    _speed?.textContent = '${(speed * 36).round()} km/h';
    _shields?.textContent = '◆' * shields + '◇' * (3 - shields).clamp(0, 3);
    _fuel?.style.width = '${fuel.clamp(0, 100)}%';
    _fuel?.classList.toggle('low', fuel < 25);
    _boost?.classList.toggle('on', boosting);
  }
}
