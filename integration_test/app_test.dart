import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:ema_app/app_state.dart';
import 'package:ema_app/main.dart' as app;
import 'package:ema_app/models/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('enable sampling, answer a test prompt, see it in history', (tester) async {
    // Don't await: on a fresh simulator main() blocks on the iOS permission dialog.
    app.main();
    for (var i = 0; i < 15; i++) { await tester.pump(const Duration(milliseconds: 200)); }
    final state = AppState.instance;

    // Home renders
    expect(find.text('EMA Sampler'), findsOneWidget);

    // Enable sampling -> prompts scheduled with the OS
    await tester.tap(find.byType(Switch));
    for (var i = 0; i < 15; i++) { await tester.pump(const Duration(milliseconds: 200)); }
    final pending = await state.db.pendingAfter(DateTime.now());
    expect(pending.length, greaterThan(0));
    final osPending = await state.notifications.pendingIds();
    if (osPending.isEmpty) {
      debugPrint('WARN: no OS pending requests (notification permission not granted on this simulator)');
    } else {
      expect(osPending.length, pending.length);
    }
    // All within the active window and between min/max apart
    final s = await state.settingsStore.loadSettings();
    for (var i = 1; i < pending.length; i++) {
      final gap = pending[i].scheduledAt.difference(pending[i - 1].scheduledAt).inMinutes;
      final m = pending[i].scheduledAt.hour * 60 + pending[i].scheduledAt.minute;
      expect(m >= s.windowStart.minutes && m < s.windowEnd.minutes, isTrue, reason: 'in window');
      expect(gap >= s.minIntervalMinutes - 1, isTrue, reason: 'gap $gap >= min');
    }

    // Send a test prompt and open its survey
    await tester.tap(find.text('Send test prompt now'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Quick survey'), findsOneWidget);
    expect(find.text('What are you doing right now?'), findsOneWidget);

    // Choose "Other" + type detail, move slider, submit
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Testing the app');
    await tester.drag(find.byType(Slider), const Offset(200, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    for (var i = 0; i < 20; i++) { await tester.pump(const Duration(milliseconds: 200)); }

    final answered = await state.db.byStatus(PromptStatus.answered);
    expect(answered.length, 1);
    final qs = await state.settingsStore.loadQuestions();
    expect(answered.first.answers[qs[0].id], 'Other: Testing the app');
    expect(answered.first.answers[qs[1].id], isA<num>());
    expect(answered.first.openedAt, isNotNull);
    expect(answered.first.submittedAt, isNotNull);

    // Home shows the count; history shows the row
    expect(find.textContaining('1 answered'), findsOneWidget);
    await tester.tap(find.textContaining('1 answered'));
    for (var i = 0; i < 10; i++) { await tester.pump(const Duration(milliseconds: 200)); }
    expect(find.text('History'), findsOneWidget);
    expect(find.textContaining('answered'), findsWidgets);

    // Expiry: a stale pending prompt becomes "expired" and is queued for upload
    final stale = PromptRecord(id: 999999, uid: 'stale', scheduledAt: DateTime.now().subtract(const Duration(hours: 2)));
    await state.db.insert(stale);
    await state.scheduler.expireStale();
    expect((await state.db.byId(999999))!.status, PromptStatus.expired);
    expect((await state.db.needingUpload()).map((p) => p.uid), contains('stale'));
  });
}
