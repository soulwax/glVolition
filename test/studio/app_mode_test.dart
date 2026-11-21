/// S8-C / S8-D test: Verifies standalone Studio app launch selection, MRU
/// recent projects list, and all 5 project templates (`empty`, `2d`, `3d`,
/// `multiplayer`, `showcase`) including all-6-family coverage in Showcase.
library;

import 'package:gl_volition/src/studio/studio.dart';
import 'package:test/test.dart';

void main() {
  group('S8-C / S8-D — App Mode Launcher & Project Templates / Showcase', () {
    test(
      'StudioAppLauncherModel selects native webview -> browser app -> browser tab',
      () {
        expect(
          StudioAppLauncherModel.selectLaunchMode(
            hasWebView2OrNativeWrapper: true,
            hasChromiumBrowser: true,
            appModeRequested: true,
          ),
          equals(StudioWindowLaunchMode.nativeWebView),
        );
        expect(
          StudioAppLauncherModel.selectLaunchMode(
            hasWebView2OrNativeWrapper: false,
            hasChromiumBrowser: true,
            appModeRequested: true,
          ),
          equals(StudioWindowLaunchMode.browserAppMode),
        );
        expect(
          StudioAppLauncherModel.selectLaunchMode(
            hasWebView2OrNativeWrapper: true,
            hasChromiumBrowser: true,
            appModeRequested: false,
          ),
          equals(StudioWindowLaunchMode.browserTab),
        );

        final launcher = StudioAppLauncherModel(maxRecent: 2);
        launcher.recordOpened('Alpha', '/p/alpha', 100);
        launcher.recordOpened('Beta', '/p/beta', 200);
        launcher.recordOpened('Alpha', '/p/alpha', 300);
        expect(launcher.recentProjects.first.name, equals('Alpha'));
        expect(launcher.recentProjects, hasLength(2));
      },
    );

    test(
      'all 5 templates generate valid GUID projects and Showcase covers all 6 families',
      () async {
        for (final template in StudioProjectTemplate.values) {
          final fs = MemoryProjectFileSystem();
          final db = await StudioProjectTemplateGenerator.generate(
            fs: fs,
            projectName: 'Demo_${template.name}',
            template: template,
          );
          expect(await fs.exists(kProjectManifestFilename), isTrue);
          expect(
            db.getByPath('assets/scenes/main.scene.json'),
            isNotNull,
            reason:
                'Template $template must create a GUID-tracked startup scene',
          );
        }
        expect(
          StudioProjectTemplateGenerator.showcaseFamilyCoverage,
          hasLength(6),
        );
      },
    );
  });
}
