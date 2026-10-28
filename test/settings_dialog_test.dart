import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snapdock/capture/capture_service.dart';
import 'package:snapdock/l10n/app_localizations.dart';
import 'package:snapdock/settings/app_settings.dart';
import 'package:snapdock/settings/capture_settings.dart';
import 'package:snapdock/settings/settings_dialog.dart';
import 'package:snapdock/theme/app_theme.dart';

void main() {
  testWidgets('docked 480x480 window: no overflow, chips switch sections', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(480, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = await AppSettings.load();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('art.zoomon.snapdock/capture'), (call) async => null);
    final capture = await CaptureSettings.load(CaptureService());
    await tester.pumpWidget(AppSettingsScope(
      settings: app,
      child: MaterialApp(
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ko'),
        home: Builder(
          builder: (context) => TextButton(onPressed: () => showCaptureSettingsDialog(context, capture), child: const Text('open')),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(ChoiceChip), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, '언어'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(app.locale, const Locale('en'));
    expect(tester.takeException(), isNull);
  });
}
